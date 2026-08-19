# emg_bridge_server.py

Deployed copy lives on the Pi at `~/Desktop/EMG_Hand_Control/emg_bridge_server.py`,
alongside `quick_calibration.py` (untouched) and `hand_controller.py` (now
ours, see below), which it imports. The Node backend spawns it via
`myo_env/bin/python emg_bridge_server.py` (see `EMG_PROJECT_DIR` /
`EMG_PYTHON_BIN` in `.env`).

To redeploy after edits:

```
scp python-bridge/emg_bridge_server.py biomekatronik@172.29.68.89:~/Desktop/EMG_Hand_Control/emg_bridge_server.py
```

Requires the Pi user to be in the `gpio` group (see udev rule
`/etc/udev/rules.d/99-gpiomem.rules` on the Pi) so `RPi.GPIO` can access
`/dev/gpiomem` without root.

# hand_controller.py

Originally a hands-off/do-not-modify file driving the 5 finger servos
directly via `RPi.GPIO` PWM. As of 2026-08-19 it was rewritten to drive them
through a PCA9685 I2C PWM board instead (`adafruit-circuitpython-pca9685`,
address `0x40`, 50Hz) - all gesture sequencing logic (thumb clearance,
progressive recovery, fist/rest ordering, double-pulse verification) is
unchanged, only the hardware I/O layer changed. A `_PCA9685Servo` adapter
exposes the same `ChangeDutyCycle(percent)` call every gesture branch already
used, so the rewrite touched only `__init__`/`cleanup` and left the rest
byte-for-byte identical.

The pre-rewrite GPIO version is backed up on the Pi at
`~/Desktop/EMG_Hand_Control/hand_controller_gpio_backup_20260819_145626.py`
in case of a revert. A second backup, from just before the pinky release fix
below, is at
`~/Desktop/EMG_Hand_Control/hand_controller_pca9685_no_pinky_fix_20260819_154055.py`.

Pinky gets mechanically stuck partway when opening (tendon friction), so
every place that opens it (`fast_open`, `recover_open`, `open_all`,
`open_finger`, and the simultaneous-movement branch in `set_gesture`) routes
through a dedicated `open_pinky()` instead: 8 rapid on/off pulses at 2.5%
duty to break static friction, then a 2s hold at 0 (signal off) to settle.
Closing pinky is unaffected - the friction only shows up on release.

Requires the Pi user to be in the `i2c` group (already existed on this
system; just needed `usermod -aG i2c biomekatronik`) so `/dev/i2c-1` is
accessible without root.

To redeploy after edits:

```
scp python-bridge/hand_controller.py biomekatronik@172.29.68.89:~/Desktop/EMG_Hand_Control/hand_controller.py
```
