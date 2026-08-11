# emg_bridge_server.py
#
# NEW FILE — does not modify quick_calibration.py or hand_controller.py.
# Long-lived process spawned by the Node backend. Talks line-delimited JSON
# over stdin/stdout:
#   Node -> here:  {"command": "<name>", "payload": {...}}
#   here -> Node:  {"type": "<name>", "payload": {...}}
#
# Reuses the model, gesture table, preprocessing and Myo client base class
# from quick_calibration.py, and the servo driver from hand_controller.py,
# instead of duplicating that logic. Importing quick_calibration loads the
# model and instantiates HandController (which opens all fingers once, on
# import) exactly like running that script directly would.

import asyncio
import base64
import copy
import io
import json
import os
import sys
import time
import uuid

import numpy as np
import torch

import quick_calibration as qc  # noqa: E402  (side effects are intentional: loads model + HAND)

CALIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "calibrations")
os.makedirs(CALIB_DIR, exist_ok=True)

# Raw EMG arrives at ~200Hz (2 samples per BLE packet) and every sample is
# broadcast as its own "emg_data" event on /myo/stream - calibration needs
# that full rate to build the 150-sample/0.75s windows the model expects.
# The dashboard's live chart doesn't need (or want) 200 JSON messages a
# second though, so it gets its own throttled, pre-averaged feed here
# instead of downsampling on the frontend after already paying the parse
# cost for every raw message.
_PREVIEW_INTERVAL_SECONDS = 0.05
_preview_sums = [0.0] * 8
_preview_count = 0


def emit(event_type, payload=None):
    print(json.dumps({"type": event_type, "payload": payload if payload is not None else {}}), flush=True)


def log(message):
    print(f"[bridge] {message}", file=sys.stderr, flush=True)


# ── Myo client: same callbacks as quick_calibration.CalibrationClient, plus
#    it republishes every EMG sample as a bridge event for the live graph. ──
class BridgeClient(qc.myo.MyoClient):
    async def on_emg_data(self, emg):
        global _preview_count
        for sample in [emg.sample1, emg.sample2]:
            values = list(sample)
            qc.STATE.emg_buffer.append(values)
            emit("emg_data", {"channels": values})
            for i, v in enumerate(values):
                _preview_sums[i] += v
            _preview_count += 1

    async def on_imu_data(self, _):
        pass

    async def on_classifier_event(self, _):
        pass

    async def on_aggregated_data(self, _):
        pass

    async def on_emg_data_aggregated(self, _):
        pass

    async def on_fv_data(self, _):
        pass

    async def on_motion_event(self, _):
        pass


class Bridge:
    def __init__(self):
        self.client = None
        self.control_task = None
        self.control_running = False
        self.base_fc_state = copy.deepcopy(qc.model.fc[-1].state_dict())  # untouched baseline
        self.loaded_user_id = None

    # ── Myo lifecycle ──

    async def _verify_connected(self):
        """
        A held `self.client` reference doesn't mean the BLE link is still up -
        the Myo drops its connection on its own (inactivity sleep, range,
        etc.) without telling us. Ping it with a cheap read; if that fails,
        clear the stale reference so the next connect actually reconnects
        instead of confirming a dead session.
        """
        if self.client is None:
            return False
        try:
            await self.client.battery_level()
            return True
        except Exception as exc:  # noqa: BLE001
            log(f"Stale Myo connection detected, clearing: {exc}")
            self.client = None
            return False

    async def myo_connect(self, payload):
        if await self._verify_connected():
            emit("myo_connect_result", {"success": True, "already_connected": True})
            return
        log("Scanning for Myo armband...")
        self.client = await BridgeClient.with_device()
        await self.client.setup(
            classifier_mode=qc.ClassifierMode.DISABLED,
            emg_mode=qc.EMGMode.SEND_EMG,
            imu_mode=qc.IMUMode.SEND_DATA,
        )
        await self.client.start()
        log(f"Connected: {self.client.device.name}")
        emit("myo_connect_result", {"success": True, "deviceName": self.client.device.name})

    async def myo_disconnect(self, payload):
        await self._stop_control()
        if self.client is not None:
            try:
                await self.client.stop()
                await self.client.disconnect()
            except Exception as exc:  # noqa: BLE001
                log(f"Error during disconnect (clearing state anyway): {exc}")
            finally:
                self.client = None
        emit("myo_disconnect_result", {"success": True})

    async def myo_battery(self, payload):
        if self.client is None:
            emit("myo_battery_result", {"battery": None, "error": "not connected"})
            return
        try:
            battery = await self.client.battery_level()
            emit("myo_battery_result", {"battery": battery})
        except Exception as exc:  # noqa: BLE001
            self.client = None
            emit("myo_battery_result", {"battery": None, "error": str(exc)})

    async def myo_poweroff(self, payload):
        if self.client is None:
            emit("myo_poweroff_result", {"success": False, "error": "not connected"})
            return
        await self._stop_control()
        try:
            await self.client.deep_sleep()
            await self.client.disconnect()
        except Exception as exc:  # noqa: BLE001
            log(f"Error during poweroff (clearing state anyway): {exc}")
        finally:
            self.client = None
        emit("myo_poweroff_result", {"success": True})

    # ── Calibration: fine-tune on samples the frontend already collected
    #    and labeled during the guided calibration flow (via /myo/stream). ──

    async def fine_tune(self, payload):
        user_id = str(payload["userId"])
        samples = payload["samples"]

        by_gesture = {}
        for s in samples:
            by_gesture.setdefault(s["gesture"], []).append(s["channels"])

        all_x, all_y = [], []
        for gesture_name, rows in by_gesture.items():
            gesture_id = next((gid for gid, name in qc.GESTURE_NAMES.items() if name == gesture_name), None)
            if gesture_id is None:
                continue
            emg = np.array(rows, dtype=np.float32)
            j = 0
            while j + qc.WIN_SAMPLES <= len(emg):
                window = qc.preprocess(emg[j:j + qc.WIN_SAMPLES].copy())
                all_x.append(window.T.copy())
                all_y.append(gesture_id)
                j += qc.STEP

        if not all_x:
            emit("fine_tune_result", {"error": "not enough samples to form a training window"})
            return

        # Resume from this user's previous checkpoint if one exists, so the
        # new session improves on it rather than replacing it.
        checkpoint_path = os.path.join(CALIB_DIR, f"user_{user_id}.pt")
        if os.path.exists(checkpoint_path):
            qc.model.fc[-1].load_state_dict(torch.load(checkpoint_path, map_location=qc.DEVICE))
        else:
            qc.model.fc[-1].load_state_dict(self.base_fc_state)

        for param in qc.model.parameters():
            param.requires_grad = False
        for param in qc.model.fc[-1].parameters():
            param.requires_grad = True

        qc.model.train()
        x_tensor = torch.tensor(np.array(all_x), dtype=torch.float32).to(qc.DEVICE)
        y_tensor = torch.tensor(np.array(all_y), dtype=torch.long).to(qc.DEVICE)

        optimizer = torch.optim.Adam(filter(lambda p: p.requires_grad, qc.model.parameters()), lr=1e-3)
        criterion = torch.nn.CrossEntropyLoss()
        dataset = torch.utils.data.TensorDataset(x_tensor, y_tensor)
        loader = torch.utils.data.DataLoader(dataset, batch_size=32, shuffle=True)

        accuracy = 0.0
        for epoch in range(1, qc.FINETUNE_EPOCHS + 1):
            correct = total = 0
            for xb, yb in loader:
                optimizer.zero_grad()
                out = qc.model(xb)
                loss = criterion(out, yb)
                loss.backward()
                optimizer.step()
                correct += (out.argmax(1) == yb).sum().item()
                total += len(yb)
            accuracy = correct / total if total else 0.0

        qc.model.eval()
        self.loaded_user_id = user_id

        buf = io.BytesIO()
        torch.save(qc.model.fc[-1].state_dict(), buf)
        checkpoint_bytes = buf.getvalue()
        with open(checkpoint_path, "wb") as f:
            f.write(checkpoint_bytes)
        session_data_b64 = base64.b64encode(checkpoint_bytes).decode("ascii")

        emit("fine_tune_result", {"accuracy": accuracy, "sessionData": session_data_b64})

    def _ensure_user_model_loaded(self, user_id):
        user_id = str(user_id)
        if self.loaded_user_id == user_id:
            return
        checkpoint_path = os.path.join(CALIB_DIR, f"user_{user_id}.pt")
        if os.path.exists(checkpoint_path):
            qc.model.fc[-1].load_state_dict(torch.load(checkpoint_path, map_location=qc.DEVICE))
        else:
            qc.model.fc[-1].load_state_dict(self.base_fc_state)
        qc.model.eval()
        self.loaded_user_id = user_id

    # ── Real-time control: same gating logic as quick_calibration.realtime(),
    #    but emits structured prediction/servo events instead of printing. ──

    async def start_control(self, payload):
        if not await self._verify_connected():
            emit("start_control_result", {"success": False, "error": "Myo not connected"})
            return
        if self.control_running:
            emit("start_control_result", {"success": True, "already_running": True})
            return

        self._ensure_user_model_loaded(payload["userId"])
        self.control_running = True
        self.control_task = asyncio.create_task(self._control_loop())
        emit("start_control_result", {"success": True})

    async def stop_control(self, payload):
        await self._stop_control()
        emit("stop_control_result", {"success": True})

    async def _stop_control(self):
        self.control_running = False
        if self.control_task is not None:
            self.control_task.cancel()
            self.control_task = None

    async def _control_loop(self):
        pending_gesture = None
        pending_count = 0
        stable_gesture = None

        try:
            while self.control_running:
                await asyncio.sleep(qc.PREDICTION_INTERVAL)

                if len(qc.STATE.emg_buffer) < qc.WIN_SAMPLES:
                    continue

                window = np.array(qc.STATE.emg_buffer, dtype=np.float32)
                pred, conf = qc.predict(window)
                name = qc.GESTURE_NAMES[pred]

                if conf < qc.CONFIDENCE_THRESHOLD:
                    pending_gesture, pending_count = None, 0
                    continue

                if name == pending_gesture:
                    pending_count += 1
                else:
                    pending_gesture, pending_count = name, 1

                if pending_count < qc.STABLE_PREDICTIONS or stable_gesture == name:
                    continue

                stable_gesture = name
                prediction_id = str(uuid.uuid4())
                prediction_time = time.time()

                emit("prediction", {
                    "predictionId": prediction_id,
                    "gesture": name,
                    "confidence": conf,
                    "timestamp": _iso(prediction_time),
                })

                # HandController.set_gesture() is synchronous/blocking (it
                # sleeps between PWM pulses), so run it off the event loop.
                await asyncio.get_event_loop().run_in_executor(None, qc.HAND.set_gesture, name)

                emit("servo_event", {
                    "predictionId": prediction_id,
                    "command": name,
                    "userId": self.loaded_user_id,
                    "timestamp": _iso(time.time()),
                })
        except asyncio.CancelledError:
            pass

    # ── Command dispatch ──

    async def handle(self, command, payload):
        handler = {
            "myo_connect": self.myo_connect,
            "myo_disconnect": self.myo_disconnect,
            "myo_battery": self.myo_battery,
            "myo_poweroff": self.myo_poweroff,
            "fine_tune": self.fine_tune,
            "start_control": self.start_control,
            "stop_control": self.stop_control,
        }.get(command)

        if handler is None:
            log(f"Unknown command: {command}")
            return
        try:
            await handler(payload)
        except Exception as exc:  # noqa: BLE001
            log(f"Error handling {command}: {exc}")
            emit(f"{command}_result", {"error": str(exc)})


def _iso(unix_time):
    return time.strftime("%Y-%m-%dT%H:%M:%S", time.gmtime(unix_time)) + f".{int(unix_time % 1 * 1000):03d}Z"


async def read_commands(bridge):
    loop = asyncio.get_event_loop()
    while True:
        line = await loop.run_in_executor(None, sys.stdin.readline)
        if not line:
            break
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        asyncio.create_task(bridge.handle(msg.get("command"), msg.get("payload", {})))


async def emg_preview_loop():
    global _preview_count
    while True:
        await asyncio.sleep(_PREVIEW_INTERVAL_SECONDS)
        if _preview_count == 0:
            continue
        averaged = [s / _preview_count for s in _preview_sums]
        emit("emg_data_preview", {"channels": averaged})
        for i in range(len(_preview_sums)):
            _preview_sums[i] = 0.0
        _preview_count = 0


async def main():
    bridge = Bridge()
    log("Bridge ready")
    asyncio.create_task(emg_preview_loop())
    await read_commands(bridge)


if __name__ == "__main__":
    asyncio.run(main())
