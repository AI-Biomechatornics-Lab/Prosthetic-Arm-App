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
from collections import deque

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

# Arrival time of each sample currently in qc.STATE.emg_buffer, kept in
# lockstep with it (same maxlen, appended together) so that when a
# prediction fires we know exactly when the newest sample in that window
# arrived (the model had everything it used for that inference at that
# point). "When did the gesture start" is tracked separately in the control
# loop as the first detection of the winning candidate, not from this deque.
_emg_timestamps = deque(maxlen=qc.WIN_SAMPLES)

# Overrides of quick_calibration's realtime-control tuning (that file itself
# is never edited). Its STABLE_PREDICTIONS=1 confirms a gesture off a single
# confident inference, which is exactly what was flooding the log with a new
# "confirmed" entry on every brief flicker between similar gestures.
#
# A raw prediction *count* doesn't actually buy much stability at
# PREDICTION_INTERVAL=0.01s: even STABLE_PREDICTIONS=5 only demands 50ms of
# consistency, trivial for classifier noise to satisfy. MIN_STABLE_SECONDS
# requires the same class to keep winning for a real stretch of wall-clock
# time instead, decoupled from how fast the loop happens to poll.
MIN_STABLE_SECONDS = 0.2
# Per-gesture: once confirmed, that same gesture won't re-fire for this long
# (covers holding it, and flickering away and back).
DEBOUNCE_SECONDS = 1.5
# Global, across ALL gestures: caps how often ANY confirmation can fire at
# all, which is what actually stops rapid flapping between different
# gestures - the per-gesture debounce above does nothing for that case since
# each different name has its own independent timer.
#
# This also does double duty as the fix for stacked physical latency: the
# ServoDispatcher can't truly interrupt a movement already in progress
# (set_gesture() is a blocking call inside hand_controller.py, which can't be
# edited to add a cancellation point) - so a second gesture confirmed while
# the first is still moving doesn't replace it physically, it just waits its
# turn, and its measured physical latency includes however much of the
# first movement was still left. Keeping confirmations at least ~2s apart -
# roughly the worst-case single-gesture movement time (thumb's clearance
# sequence is the slowest at ~2.25s; fist/rest are now ~1s via the fast
# paths above) - means a second gesture is confirmed only once the hand has
# plausibly finished the first, so it essentially never has to wait at all.
GLOBAL_COOLDOWN_SECONDS = 2.0
DETECTING_EMIT_INTERVAL_SECONDS = 0.1
# quick_calibration.py's own CONFIDENCE_THRESHOLD (0.50) is barely above
# guessing for a 10-class model - a lot of the noisy log entries were
# confirmations in the 51-65% range. Raised as another lever against noise;
# lower it back here if it ends up rejecting real gestures too often.
CONFIDENCE_THRESHOLD = 0.65
# Wrist gestures tend to score lower confidence even when correct, but that
# same low-confidence band is also where most false positives land - so they
# get their own, higher bar instead of raising the threshold globally.
WRIST_GESTURES = {"wrist_rotate_out", "wrist_rotate_in"}
WRIST_CONFIDENCE_THRESHOLD = 0.75
# Bounds the BLE scan in myo_connect - see the comment there.
SCAN_TIMEOUT_SECONDS = 25
# Mechanically, closing to a fist is a transient midpoint while the hand
# moves between two single-finger gestures - the model reads that as a
# genuine "fist" command. Blackout windows are absolute-time deadlines
# (fist_blackout_until / single_finger_blackout_until in _control_loop), not
# a prediction count: at PREDICTION_INTERVAL=0.01s even 8 consecutive ticks
# is only 80ms, *less* strict than the normal 200ms stability window every
# other gesture needs - a count-based bar here doesn't actually buy any
# protection, so there's no fallback path at all: blacklisted means ignored,
# full stop, until the deadline passes.
SINGLE_FINGER_GESTURES = {"index", "middle", "ring", "pinky", "thumb"}
FIST_BLACKLIST_SECONDS = 4.0
FIST_TO_SINGLE_FINGER_BLACKLIST_SECONDS = 1.5
# Ignore predictions entirely for this long after Start - the model tends to
# fire a false wrist_rotate_out immediately, before the user's done anything.
WARMUP_SECONDS = 3


def _required_confidence(gesture_name):
    return WRIST_CONFIDENCE_THRESHOLD if gesture_name in WRIST_GESTURES else CONFIDENCE_THRESHOLD


def _rest_hand_fast():
    """
    HandController.set_gesture("rest") opens each finger one at a time
    (fast_open + recover_open per finger, sequentially) - measured ~7.6s
    end to end. Its own open_all() moves all 5 servos simultaneously in
    ~1s, but only set_gesture() updates current_gesture/busy bookkeeping.
    hand_controller.py can't be edited, but open_all() and those attributes
    are already public - calling it directly and replicating the small bit
    of bookkeeping set_gesture() would otherwise have done is not a
    modification to that file, just a different (already-supported) way of
    driving it.
    """
    if getattr(qc.HAND, "current_gesture", None) == "rest":
        return
    qc.HAND.busy = True
    try:
        qc.HAND.open_all()
        qc.HAND.current_gesture = "rest"
    finally:
        qc.HAND.busy = False


def _fist_hand_fast():
    """
    Same idea as _rest_hand_fast(): set_gesture("fist") closes index, middle,
    ring, pinky, then thumb one at a time (measured ~6s), because the
    mechanical comment there says thumb has to close LAST to avoid
    interfering with the other fingers. close_all() closes all 5
    simultaneously in ~1s instead.

    That thumb-last ordering is a real mechanical constraint the sequential
    path was written to respect, and close_all() doesn't - it's a public,
    already-exercised method (used in hand_controller.py's own
    test_fist_sequence()) but NOT one the normal control flow calls, unlike
    open_all() which every startup already runs. Watch the first few real
    fist confirmations after this deploys for any thumb interference; if the
    hand catches or binds, this needs reverting to the slow sequential path
    for fist specifically.
    """
    if getattr(qc.HAND, "current_gesture", None) == "fist":
        return
    qc.HAND.busy = True
    try:
        qc.HAND.close_all()
        qc.HAND.current_gesture = "fist"
    finally:
        qc.HAND.busy = False


class ServoDispatcher:
    """
    Decouples "a gesture was confirmed" from "the servo physically moved".
    HandController.set_gesture() is a blocking call (real PWM timing, ~1-2s)
    - previously the control loop awaited it inline, which meant the AI
    stopped inspecting new EMG windows for that whole stretch. Now the
    control loop just calls request() (instant) and moves on to the next
    prediction immediately; this class owns a single-slot "latest target"
    and a background task that keeps driving the hand towards whatever that
    target currently is. If a newer gesture gets confirmed while the hand is
    still mid-movement, it silently replaces the pending one instead of
    queuing - by the time the hand is free, only the most recent request
    still matters.
    """

    def __init__(self, on_dispatched, on_moved):
        self._on_dispatched = on_dispatched
        self._on_moved = on_moved
        self._target = None
        self._new_target = asyncio.Event()
        self._task = None

    def start(self):
        if self._task is None:
            self._task = asyncio.create_task(self._run())

    def stop(self):
        if self._task is not None:
            self._task.cancel()
            self._task = None
        self._target = None
        self._new_target.clear()

    def request(self, gesture_name, prediction_id):
        self._target = (gesture_name, prediction_id)
        dispatch_time = time.time()
        self._new_target.set()
        self._on_dispatched(gesture_name, prediction_id, dispatch_time)

    async def _run(self):
        loop = asyncio.get_event_loop()
        try:
            while True:
                await self._new_target.wait()
                self._new_target.clear()
                target = self._target
                if target is None:
                    continue
                gesture_name, prediction_id = target
                if gesture_name == "rest":
                    await loop.run_in_executor(None, _rest_hand_fast)
                elif gesture_name == "fist":
                    await loop.run_in_executor(None, _fist_hand_fast)
                else:
                    await loop.run_in_executor(None, qc.HAND.set_gesture, gesture_name)
                self._on_moved(gesture_name, prediction_id, time.time())
                # If request() landed again while we were mid-movement,
                # _new_target is already set, so the loop immediately picks
                # up whatever the newest target is - anything requested and
                # since-superseded in between is simply never dispatched.
        except asyncio.CancelledError:
            pass


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
            _emg_timestamps.append(time.time())
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
        self.servo_dispatcher = None

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
        # with_device()'s own retry loop never gives up on its own - it will
        # happily scan for minutes. Bound it so a missing/off/out-of-range
        # armband fails with a clear message instead of leaving the request
        # hanging indefinitely (which is what previously made a second,
        # overlapping connect attempt look tempting - and BlueZ flatly
        # rejects two concurrent scans).
        try:
            self.client = await asyncio.wait_for(BridgeClient.with_device(), timeout=SCAN_TIMEOUT_SECONDS)
        except asyncio.TimeoutError:
            emit("myo_connect_result", {
                "success": False,
                "error": "Myo not found - make sure it's powered on and nearby",
            })
            return

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

    async def revert_calibration(self, payload):
        """
        Called after Node deletes a calibration row: reconciles the on-disk
        checkpoint (and the in-memory model, if this user is currently
        loaded) to whatever session_data it says is now the most recent
        remaining one - or wipes the checkpoint back to the untouched base
        model if none are left.
        """
        user_id = str(payload["userId"])
        session_data_b64 = payload.get("sessionData")
        checkpoint_path = os.path.join(CALIB_DIR, f"user_{user_id}.pt")

        if session_data_b64:
            with open(checkpoint_path, "wb") as f:
                f.write(base64.b64decode(session_data_b64))
        elif os.path.exists(checkpoint_path):
            os.remove(checkpoint_path)

        if self.loaded_user_id == user_id:
            # Force _ensure_user_model_loaded to re-read from disk next time
            # control starts, rather than keep serving the stale in-memory
            # weights from the deleted session.
            self.loaded_user_id = None

        emit("revert_calibration_result", {"success": True})

    def _ensure_user_model_loaded(self, user_id):
        user_id = str(user_id)
        if self.loaded_user_id == user_id:
            log(f"MODEL: user {user_id} already loaded in memory, not reloading")
            return
        checkpoint_path = os.path.join(CALIB_DIR, f"user_{user_id}.pt")
        if os.path.exists(checkpoint_path):
            qc.model.fc[-1].load_state_dict(torch.load(checkpoint_path, map_location=qc.DEVICE))
            mtime = time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(os.path.getmtime(checkpoint_path)))
            log(f"MODEL: loaded calibrated checkpoint for user {user_id} from {checkpoint_path} (saved {mtime})")
        else:
            qc.model.fc[-1].load_state_dict(self.base_fc_state)
            log(f"MODEL: no checkpoint for user {user_id} at {checkpoint_path} - using uncalibrated base model")
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

        def on_dispatched(gesture_name, prediction_id, dispatch_time):
            emit("servo_dispatched", {
                "predictionId": prediction_id,
                "command": gesture_name,
                "userId": self.loaded_user_id,
                "timestamp": _iso(dispatch_time),
            })

        def on_moved(gesture_name, prediction_id, moved_time):
            emit("servo_moved", {
                "predictionId": prediction_id,
                "command": gesture_name,
                "userId": self.loaded_user_id,
                "timestamp": _iso(moved_time),
            })

        self.servo_dispatcher = ServoDispatcher(on_dispatched, on_moved)
        self.servo_dispatcher.start()

        self.control_running = True
        self.control_task = asyncio.create_task(self._control_loop())
        emit("start_control_result", {"success": True, "warmupSeconds": WARMUP_SECONDS})

    async def stop_control(self, payload):
        await self._stop_control()
        emit("stop_control_result", {"success": True})

    async def _stop_control(self):
        self.control_running = False
        if self.control_task is not None:
            self.control_task.cancel()
            self.control_task = None
        if self.servo_dispatcher is not None:
            self.servo_dispatcher.stop()
            self.servo_dispatcher = None

        # Release the hand back to rest instead of leaving it clenched on
        # whatever gesture was last commanded. _rest_hand_fast() is a no-op
        # if it's already at rest, and it's synchronous/blocking, so run it
        # off the event loop like the dispatcher does.
        await asyncio.get_event_loop().run_in_executor(None, _rest_hand_fast)

    async def _control_loop(self):
        control_started_at = time.time()
        emit("warmup", {"seconds": WARMUP_SECONDS})

        pending_gesture = None
        pending_start_time = None  # when this candidate gesture was FIRST detected, pre-confirmation
        stable_gesture = None
        last_confirmed_at = {}  # gesture name -> unix time it was last actually confirmed/sent
        last_confirmed_globally = 0.0  # unix time ANY gesture was last confirmed, regardless of which
        last_detecting_emit = 0.0
        fist_blackout_until = 0.0  # absolute unix time; fist is fully ignored until this passes
        single_finger_blackout_until = 0.0  # same, for single-finger gestures right after a fist

        try:
            while self.control_running:
                await asyncio.sleep(qc.PREDICTION_INTERVAL)

                if len(qc.STATE.emg_buffer) < qc.WIN_SAMPLES:
                    continue

                window = np.array(qc.STATE.emg_buffer, dtype=np.float32)
                data_received_time = _emg_timestamps[-1]  # newest sample - just before inference ran

                pred, conf = qc.predict(window)
                name = qc.GESTURE_NAMES[pred]
                now = time.time()

                if now - control_started_at < WARMUP_SECONDS:
                    continue

                # Blacklists take priority over everything else, including
                # confidence - a blacklisted gesture is treated as if it
                # weren't predicted at all, no fallback path to confirmation.
                if name == "fist" and now < fist_blackout_until:
                    log(f"BLACKLIST: fist rejected ({fist_blackout_until - now:.1f}s remaining)")
                    pending_gesture, pending_start_time = None, None
                    continue
                if (
                    name in SINGLE_FINGER_GESTURES
                    and name != "thumb"
                    and now < single_finger_blackout_until
                ):
                    log(f"BLACKLIST: {name} rejected ({single_finger_blackout_until - now:.1f}s remaining, post-fist)")
                    pending_gesture, pending_start_time = None, None
                    continue

                if conf < _required_confidence(name):
                    pending_gesture, pending_start_time = None, None
                    continue

                if name == pending_gesture:
                    pass  # still the same candidate - check how long it's held below
                else:
                    pending_gesture, pending_start_time = name, now
                    # Start the fist blackout the MOMENT a single-finger
                    # gesture becomes the pending candidate, not just once
                    # it's confirmed - the mechanical fist-midpoint tends to
                    # follow within a couple hundred ms of the hand starting
                    # to move, well before MIN_STABLE_SECONDS would confirm it.
                    if name in SINGLE_FINGER_GESTURES:
                        fist_blackout_until = max(fist_blackout_until, now + FIST_BLACKLIST_SECONDS)

                if now - pending_start_time < MIN_STABLE_SECONDS:
                    # Still accumulating confidence, not confirmed yet - let the
                    # UI show a subtle "detecting" hint without logging anything.
                    if now - last_detecting_emit >= DETECTING_EMIT_INTERVAL_SECONDS:
                        emit("detecting", {"gesture": name, "confidence": conf})
                        last_detecting_emit = now
                    continue

                # Confirmed candidate. Layered duplicate/noise suppression:
                # - still holding the exact same gesture as last confirmation -> skip.
                # - ANY gesture fired too recently -> skip (stops rapid flapping
                #   between different classes, which per-name checks can't catch).
                # - this specific gesture flickered away and came back within its
                #   own longer debounce window -> skip.
                if stable_gesture == name:
                    continue
                if now - last_confirmed_globally < GLOBAL_COOLDOWN_SECONDS:
                    continue
                if now - last_confirmed_at.get(name, 0) < DEBOUNCE_SECONDS:
                    continue

                stable_gesture = name
                last_confirmed_at[name] = now
                last_confirmed_globally = now
                if name in SINGLE_FINGER_GESTURES:
                    # Refresh on actual confirmation too, extending past
                    # whatever the detection-time trigger above already set.
                    fist_blackout_until = max(fist_blackout_until, now + FIST_BLACKLIST_SECONDS)
                if name == "fist":
                    single_finger_blackout_until = now + FIST_TO_SINGLE_FINGER_BLACKLIST_SECONDS
                prediction_id = str(uuid.uuid4())

                emit("prediction", {
                    "predictionId": prediction_id,
                    "gesture": name,
                    "confidence": conf,
                    "gestureStartTime": _iso(pending_start_time),
                    "dataReceivedTime": _iso(data_received_time),
                    "timestamp": _iso(now),
                })

                # Non-blocking: hands the target to the dispatcher and moves
                # straight on to the next prediction. The dispatcher emits
                # servo_dispatched/servo_moved itself once it actually acts
                # on this (or a newer gesture that superseded it).
                self.servo_dispatcher.request(name, prediction_id)
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
            "revert_calibration": self.revert_calibration,
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
