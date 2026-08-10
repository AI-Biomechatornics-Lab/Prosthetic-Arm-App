# emg_bridge_server.py

Deployed copy lives on the Pi at `~/Desktop/EMG_Hand_Control/emg_bridge_server.py`,
alongside (not modifying) `quick_calibration.py` and `hand_controller.py`, which it
imports. The Node backend spawns it via `myo_env/bin/python emg_bridge_server.py`
(see `EMG_PROJECT_DIR` / `EMG_PYTHON_BIN` in `.env`).

To redeploy after edits:

```
scp python-bridge/emg_bridge_server.py biomekatronik@172.29.68.89:~/Desktop/EMG_Hand_Control/emg_bridge_server.py
```

Requires the Pi user to be in the `gpio` group (see udev rule
`/etc/udev/rules.d/99-gpiomem.rules` on the Pi) so `RPi.GPIO` can access
`/dev/gpiomem` without root.
