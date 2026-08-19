import time

import board
import busio
from adafruit_pca9685 import PCA9685


# ============================================================
# PCA9685 SETUP
# ============================================================

I2C_ADDRESS = 0x40
FREQ = 50


class _PCA9685Servo:
    """
    Thin adapter so every existing call site can keep calling
    ChangeDutyCycle(percent) exactly like it did against RPi.GPIO.PWM -
    none of the gesture sequencing logic below needed to change, only how
    a duty cycle percentage actually reaches hardware.
    """

    def __init__(self, channel):
        self._channel = channel

    def ChangeDutyCycle(self, percent):
        self._channel.duty_cycle = int(percent / 100 * 65535)


# ============================================================
# SERVO CHANNELS (PCA9685, 0-15)
#
# Ring (channel 3) has a mechanical issue and is permanently disabled -
# it is deliberately NOT in this dict, so no gesture/movement code ever
# iterates over it or sends it a duty cycle. Its channel is force-silenced
# once at startup (see RING_CHANNEL / __init__) and never touched again.
# ============================================================

SERVO_CHANNELS = {
    'thumb':  0,
    'index':  1,
    'middle': 2,
    'pinky':  4,
}

RING_CHANNEL = 3


# ============================================================
# SERVO MOVEMENT SEQUENCES
#
# These are based directly on the tested PWM duty cycles.
#
# IMPORTANT:
# The order of values is intentional.
# Do NOT replace this with generic open/closed interpolation.
# ============================================================

FINGER_SEQUENCES = {

    # Thumb
    # Tested:
    # 2.5 -> 7.5 -> 10.0 -> 12.5
    'thumb': [2.5, 7.5, 10.0, 12.5],

    # Index
    # Tested:
    # 2.5 -> 10.0 -> 12.5
    'index': [2.5, 10.0, 12.5],

    # Middle
    # Tested:
    # 2.5 -> 7.5 -> 10.0 -> 12.5
    'middle': [2.5, 7.5, 10.0, 12.5],

    # Pinky
    # Tested:
    # 1.5 -> 2.5 -> 5.0 -> 7.5 -> 2.5 -> 1.5
    #
    # This servo behaves differently mechanically.
    'pinky': [1.5, 2.5, 5.0, 7.5, 2.5, 1.5],
}


# ============================================================
# OPEN / CLOSED POSITIONS
#
# Based on your tested values:
#
# Thumb  : closed = 2.5, open = 12.5
# Index  : closed = 2.5, open = 12.5
# Middle : closed = 2.5, open = 12.5
# Pinky  : closed = 7.5, open = 1.5
#
# Ring is permanently disabled (mechanical issue) - not tracked here.
# ============================================================

OPEN_POSITION = {
    'thumb':  12.5,
    'index':  12.5,
    'middle': 12.5,
    'pinky':  1.5,
}

CLOSED_POSITION = {
    'thumb':  2.5,
    'index':  2.5,
    'middle': 2.5,
    'pinky':  7.5,
}


# ============================================================
# GESTURES
# True  = finger closed
# False = finger open
# ============================================================

# The "ring" gesture (isolate ring finger) is removed entirely, not just
# disarmed - it's inherently about actuating ring, which can't happen
# anymore. If the AI still predicts it, set_gesture("ring") will hit the
# "Unknown gesture" branch and safely do nothing, rather than silently
# behaving like some other gesture.
GESTURES = {

    'rest': {
        'thumb':  False,
        'index':  False,
        'middle': False,
        'pinky':  False,
    },

    'fist': {
        'thumb':  True,
        'index':  True,
        'middle': True,
        'pinky':  True,
    },

    'open_hand': {
        'thumb':  False,
        'index':  False,
        'middle': False,
        'pinky':  False,
    },

    'grasp': {
        'thumb':  True,
        'index':  True,
        'middle': True,
        'pinky':  True,
    },

    'thumb': {
        'thumb':  False,
        'index':  True,
        'middle': True,
        'pinky':  True,
    },

    'index': {
        'thumb':  True,
        'index':  False,
        'middle': True,
        'pinky':  True,
    },

    'middle': {
        'thumb':  True,
        'index':  True,
        'middle': False,
        'pinky':  True,
    },

    'pinky': {
        'thumb':  True,
        'index':  True,
        'middle': True,
        'pinky':  False,
    },

    'wrist_rotate_out': {
        'thumb':  False,
        'index':  False,
        'middle': False,
        'pinky':  False,
    },

    'wrist_rotate_in': {
        'thumb':  False,
        'index':  False,
        'middle': False,
        'pinky':  False,
    },
}


# ============================================================
# HAND CONTROLLER
# ============================================================

class HandController:

    def __init__(self):

        i2c = busio.I2C(board.SCL, board.SDA)
        self.pca = PCA9685(i2c, address=I2C_ADDRESS)
        self.pca.frequency = FREQ

        self.servos = {}

        # Current PWM position of every finger
        self.current_position = {
            finger: OPEN_POSITION[finger]
            for finger in SERVO_CHANNELS
        }

        # Set up all servos
        for finger, channel in SERVO_CHANNELS.items():

            self.servos[finger] = _PCA9685Servo(self.pca.channels[channel])

        # Ring (channel 3) is permanently disabled - force it to 0 duty
        # cycle once, here, and never send it a signal again. Accessed
        # directly (not through self.servos, which deliberately has no
        # entry for it) so no other code path can accidentally reach it.
        self.pca.channels[RING_CHANNEL].duty_cycle = 0

        self.current_gesture = None
        self.busy = False

        print("Hand controller initialized (PCA9685)")
        print(f"  Ring (channel {RING_CHANNEL}) disabled - duty cycle forced to 0")

        # Start with fully open hand. force=True: current_position above is
        # just an assumed default, not a verified hardware state, so this
        # first call must actually move everything rather than trusting
        # (and skipping based on) that assumption.
        self.open_all(force=True)
        self.current_gesture = "rest"


    # ========================================================
    # MOVE ONE SERVO
    # ========================================================

    def move_servo(self, finger, duty, hold_time=0.5):

        print(
            f"  {finger.upper()} "
            f"-> Duty cycle: {duty}%"
        )

        self.servos[finger].ChangeDutyCycle(duty)

        time.sleep(hold_time)

        # Stop PWM after reaching position
        self.servos[finger].ChangeDutyCycle(0)

        self.current_position[finger] = duty


    # ========================================================
    # CLOSE ONE FINGER
    #
    # Goes directly to the fully closed position.
    # ========================================================

    def close_finger(self, finger):

        duty = CLOSED_POSITION[finger]

        print(
            f"  Closing {finger}: "
            f"{duty}%"
        )

        self.servos[finger].ChangeDutyCycle(duty)

        time.sleep(0.5)

        self.servos[finger].ChangeDutyCycle(0)

        self.current_position[finger] = duty


    # ========================================================
    # OPEN ONE FINGER
    #
    # Goes directly to fully open position.
    # ========================================================

    # ========================================================
    # PINKY RELEASE
    #
    # Pinky gets mechanically stuck after closing - tendon friction
    # holds it partway instead of letting it reach the open position.
    # A single fast_open() pulse isn't enough to break that friction,
    # so pinky gets its own vibration-then-settle sequence instead of
    # the normal fast-open path every other finger uses. Every place
    # that opens pinky routes through this method.
    # ========================================================

    def open_pinky(self):

        print("  PINKY: vibration release sequence")

        # Vibration to break friction
        for _ in range(2):
            self.servos['pinky'].ChangeDutyCycle(0.0)
            time.sleep(0.08)
            self.servos['pinky'].ChangeDutyCycle(2.5)
            time.sleep(0.08)

        # Final hold at open position
        self.servos['pinky'].ChangeDutyCycle(0.0)
        time.sleep(1.2)

        self.current_position['pinky'] = OPEN_POSITION['pinky']


    def open_finger(self, finger):

        if finger == 'pinky':
            self.open_pinky()
            return

        duty = OPEN_POSITION[finger]

        print(
            f"  Opening {finger}: "
            f"{duty}%"
        )

        self.servos[finger].ChangeDutyCycle(duty)

        time.sleep(0.5)

        self.servos[finger].ChangeDutyCycle(0)

        self.current_position[finger] = duty


    # ========================================================
    # CLOSE ALL FINGERS
    #
    # IMPORTANT:
    # All fingers start opening/closing independently
    # using their own tested PWM values.
    # ========================================================

    def close_all(self):

        print("\n==============================")
        print("  CLOSING ALL FINGERS")
        print("==============================")

        # All fingers simultaneously
        for finger in SERVO_CHANNELS:
            self.servos[finger].ChangeDutyCycle(CLOSED_POSITION[finger])

        time.sleep(1.0)

        for finger in SERVO_CHANNELS:
            self.servos[finger].ChangeDutyCycle(0)
            self.current_position[finger] = CLOSED_POSITION[finger]


    def open_all(self, force=False):

        print("\n==============================")
        print("  OPENING ALL FINGERS")
        print("==============================")

        # All fingers except pinky move simultaneously as before; pinky
        # needs its own vibration release sequence (see open_pinky()) so
        # it's handled separately, after the others.
        #
        # force=False (the default) skips any finger already at
        # OPEN_POSITION, same optimization as set_gesture("rest"). This is
        # what the live "rest" AI command actually calls (via
        # _rest_hand_fast() in emg_bridge_server.py), so it's the number
        # that matters for real responsiveness. force=True (only used at
        # __init__) ignores current_position and moves everything
        # unconditionally, since that tracked state is just an assumed
        # default there, not a verified hardware position.
        others = [
            finger for finger in SERVO_CHANNELS
            if finger != 'pinky' and (force or self.current_position[finger] != OPEN_POSITION[finger])
        ]

        if others:
            for finger in others:
                self.servos[finger].ChangeDutyCycle(OPEN_POSITION[finger])

            time.sleep(1.0)

            for finger in others:
                self.servos[finger].ChangeDutyCycle(0)
                self.current_position[finger] = OPEN_POSITION[finger]

        if force or self.current_position['pinky'] != OPEN_POSITION['pinky']:
            self.open_pinky()


    # ========================================================
    # FIST
    #
    # First:
    #   Fully close all fingers.
    #
    # Then:
    #   Fully open them one by one.
    #
    # This follows the movement logic you described.
    # ========================================================

    def test_fist_sequence(self):

        print("\n")
        print("=" * 50)
        print("  FIST SEQUENCE")
        print("=" * 50)

        # Step 1:
        # Close all fingers completely
        self.close_all()

        time.sleep(1)

        # Step 2:
        # Open each finger one by one
        for finger in [
            'thumb',
            'index',
            'middle',
            'pinky'
        ]:

            print(
                f"\nOpening {finger.upper()}..."
            )

            self.open_finger(finger)

            time.sleep(0.5)


    # ========================================================
    # SET GESTURE
    # ========================================================

    # ========================================================
    # FAST RECOVERY / RE-HOME
    #
    # Used when a servo may be mechanically stuck.
    # Moves progressively instead of forcing one large jump.
    # ========================================================

    def recover_open(self, finger):

        print(f"  Recovery opening: {finger}")

        sequence = FINGER_SEQUENCES.get(finger, [])

        # Only use intermediate positions between current
        # and fully open. This avoids unnecessary movement.
        open_duty = OPEN_POSITION[finger]
        current = self.current_position[finger]

        if current == open_duty:
            return

        # Pinky doesn't use the generic progressive recovery below - it
        # needs the vibration release sequence instead (see open_pinky()).
        if finger == "pinky":
            self.open_pinky()
            return

        # Generic progressive recovery.
        # For standard fingers this becomes:
        # 7.5 -> 10.0 -> 12.5
        recovery_steps = [7.5, 10.0, 12.5]

        for duty in recovery_steps:

            # Skip values that are not moving toward open.
            if duty <= current:
                continue

            print(
                f"    {finger.upper()} recovery -> "
                f"{duty}%"
            )

            self.servos[finger].ChangeDutyCycle(duty)

            # Short pulse: fast but enough to overcome friction.
            time.sleep(0.15)

            self.servos[finger].ChangeDutyCycle(0)

            # Small pause between recovery steps.
            time.sleep(0.03)

        self.current_position[finger] = open_duty


    # ========================================================
    # FAST OPEN
    #
    # Normal direct movement.
    # If the servo was already commanded open, do nothing.
    #
    # Double-pulse verification: the target duty is sent twice
    # (attempt 1, then attempt 2 after a short gap) to guarantee
    # the servo actually reaches position even if the first pulse
    # was absorbed by mechanical resistance/friction.
    # ========================================================

    def fast_open(self, finger):

        if finger == 'pinky':
            self.open_pinky()
            return

        target = OPEN_POSITION[finger]

        print(f"  Opening {finger}: {target}%")

        # Longer hold for index and middle (more resistance)
        hold = 0.7 if finger in ['index', 'middle'] else 0.6

        # Attempt 1
        self.servos[finger].ChangeDutyCycle(target)
        time.sleep(hold)
        self.servos[finger].ChangeDutyCycle(0)
        time.sleep(0.1)

        # Attempt 2 — always re-send to guarantee physical position
        self.servos[finger].ChangeDutyCycle(target)
        time.sleep(0.2)
        self.servos[finger].ChangeDutyCycle(0)

        self.current_position[finger] = target


    # ========================================================
    # FAST CLOSE
    #
    # Double-pulse verification, same idea as fast_open() above.
    # ========================================================

    def fast_close(self, finger):

        target = CLOSED_POSITION[finger]

        print(f"  Closing {finger}: {target}%")

        # Attempt 1
        self.servos[finger].ChangeDutyCycle(target)
        time.sleep(0.6)
        self.servos[finger].ChangeDutyCycle(0)
        time.sleep(0.1)

        # Attempt 2 — guarantee physical position
        self.servos[finger].ChangeDutyCycle(target)
        time.sleep(0.2)
        self.servos[finger].ChangeDutyCycle(0)

        self.current_position[finger] = target


    # ========================================================
    # SET GESTURE
    #
    # Stateful controller:
    #
    # - Never re-closes an already closed finger.
    # - Never re-opens an already open finger.
    # - Uses thumb clearance when required.
    # - Uses recovery when opening a finger.
    # - Keeps movements fast.
    # ========================================================

    def set_gesture(self, gesture_name):

        if gesture_name not in GESTURES:
            print(f"Unknown gesture: {gesture_name}")
            return

        # Ignore duplicate AI commands.
        if getattr(self, "current_gesture", None) == gesture_name:
            return

        # Ignore if hand is busy executing previous command
        if self.busy:
            print(f"  Hand busy — ignoring: {gesture_name}")
            return

        self.busy = True

        print("\n" + "=" * 50)
        print(f"  GESTURE: {gesture_name.upper()}")
        print("=" * 50)

        targets = GESTURES[gesture_name]

        # ====================================================
        # SIMULTANEOUS MOVEMENT
        # Send all PWM signals at once, then wait, then stop
        # ====================================================

        if gesture_name not in ["fist", "rest", "thumb",
                                  "wrist_rotate_out", "wrist_rotate_in"]:

            # Determine target duty for each finger. Pinky is pulled out
            # of the simultaneous batch specifically when it needs to
            # OPEN (closing it simultaneously with the others is fine -
            # the friction problem only shows up on release), and handled
            # separately via open_pinky() instead.
            duties = {}
            pinky_opening = False
            for finger in SERVO_CHANNELS:
                target_closed = targets.get(finger, False)
                target_duty = (CLOSED_POSITION[finger]
                               if target_closed
                               else OPEN_POSITION[finger])
                # Only move if needed
                if self.current_position[finger] != target_duty:
                    if finger == "pinky" and not target_closed:
                        pinky_opening = True
                    else:
                        duties[finger] = target_duty

            if duties:
                # Send all at once
                for finger, duty in duties.items():
                    self.servos[finger].ChangeDutyCycle(duty)

                time.sleep(1.0)

                for finger, duty in duties.items():
                    self.servos[finger].ChangeDutyCycle(0)
                    self.current_position[finger] = duty

                # recover_open() removed here: pinky is never in `duties`
                # when opening (handled separately below), and the PCA9685's
                # hardware PWM is accurate enough that the other fingers
                # don't need the progressive recovery pass.

            if pinky_opening:
                self.open_pinky()

            self.current_gesture = gesture_name
            self.busy = False
            return

        # ====================================================
        # WRIST COMMANDS
        #
        # No wrist servo is currently connected.
        # Never move the fingers for a wrist command.
        # ====================================================

        if gesture_name in [
            "wrist_rotate_out",
            "wrist_rotate_in"
        ]:

            print(
                f"  Wrist command ignored "
                f"(no wrist actuator)"
            )

            self.current_gesture = gesture_name
            self.busy = False
            return

        # ====================================================
        # FIST
        #
        # Mechanical order:
        #
        # 1. Index
        # 2. Middle
        # 3. Ring
        # 4. Pinky
        # 5. Thumb LAST
        #
        # Already closed fingers are NOT touched.
        # ====================================================

        if gesture_name == "fist":

            for finger in [
                "index",
                "middle",
                "pinky"
            ]:

                if (
                    self.current_position[finger]
                    != CLOSED_POSITION[finger]
                ):
                    self.fast_close(finger)

            # Thumb closes LAST.
            if (
                self.current_position["thumb"]
                != CLOSED_POSITION["thumb"]
            ):
                self.fast_close("thumb")

            self.current_gesture = gesture_name
            self.busy = False
            return

        # ====================================================
        # REST
        #
        # Open only fingers that are currently closed - same simultaneous
        # approach as open_all() (thumb included in the simultaneous
        # batch, not last) instead of opening each finger one at a time.
        # Pinky still gets its own vibration release regardless, since its
        # friction problem is independent of this.
        # ====================================================

        if gesture_name == "rest":

            simul_fingers = [
                finger for finger in ["thumb", "index", "middle"]
                if self.current_position[finger] == CLOSED_POSITION[finger]
            ]

            if simul_fingers:

                for finger in simul_fingers:
                    self.servos[finger].ChangeDutyCycle(OPEN_POSITION[finger])

                time.sleep(1.0)

                for finger in simul_fingers:
                    self.servos[finger].ChangeDutyCycle(0)
                    self.current_position[finger] = OPEN_POSITION[finger]

            if self.current_position["pinky"] == CLOSED_POSITION["pinky"]:
                self.open_pinky()

            self.current_gesture = gesture_name
            self.busy = False
            return

        # ====================================================
        # THUMB
        #
        # Target:
        # thumb OPEN
        # all other fingers CLOSED
        #
        # Latency optimization: no clearance pulse, no fast_open double
        # pulse, no recovery - thumb just gets a single direct 1.0s pulse.
        # This trades away the mechanical clearance that protected thumb
        # from bumping already-closed fingers on its way out; watch the
        # first real "thumb" gestures for catching/binding.
        # ====================================================

        if gesture_name == "thumb":

            if self.current_position["thumb"] != OPEN_POSITION["thumb"]:

                print(f"  Opening thumb: {OPEN_POSITION['thumb']}%")

                self.servos["thumb"].ChangeDutyCycle(OPEN_POSITION["thumb"])
                time.sleep(1.0)
                self.servos["thumb"].ChangeDutyCycle(0)

                self.current_position["thumb"] = OPEN_POSITION["thumb"]

            for finger in [
                "index",
                "middle",
                "pinky"
            ]:

                if (
                    self.current_position[finger]
                    != CLOSED_POSITION[finger]
                ):
                    self.fast_close(finger)

            self.current_gesture = gesture_name
            self.busy = False
            return

        # ====================================================
        # SINGLE FINGER GESTURES
        #
        # Example:
        #
        # FIST -> INDEX
        #
        # index:  CLOSED -> OPEN
        # middle: CLOSED -> CLOSED  NO ACTION
        # pinky:  CLOSED -> CLOSED  NO ACTION
        # thumb:  CLOSED -> CLOSED  NO ACTION
        #
        # Only the required state changes happen.
        # ====================================================

        # Detect which finger must open.
        opening_fingers = []

        for finger in [
            "index",
            "middle",
            "pinky",
            "thumb"
        ]:

            target_closed = targets[finger]

            if not target_closed:

                if (
                    self.current_position[finger]
                    == CLOSED_POSITION[finger]
                ):
                    opening_fingers.append(finger)

        # ====================================================
        # THUMB CLEARANCE
        #
        # If thumb is closed and another finger must open,
        # create temporary space before opening that finger.
        #
        # We DO NOT change the logical state of the other
        # fingers because the clearance is temporary.
        # ====================================================

        non_thumb_opening = [
            finger
            for finger in opening_fingers
            if finger != "thumb"
        ]

        if (
            non_thumb_opening
            and self.current_position["thumb"]
            == CLOSED_POSITION["thumb"]
        ):

            print("  Thumb clearance")

            clearance_fingers = []

            for finger in [
                "index",
                "middle",
                "pinky"
            ]:

                if finger in non_thumb_opening:
                    continue

                if (
                    self.current_position[finger]
                    == CLOSED_POSITION[finger]
                ):

                    clearance_fingers.append(finger)

                    self.servos[finger].ChangeDutyCycle(5.0)

            if clearance_fingers:
                time.sleep(0.15)

                for finger in clearance_fingers:
                    self.servos[finger].ChangeDutyCycle(0)

        # ====================================================
        # APPLY TARGET STATE
        #
        # Only actual state transitions.
        # ====================================================

        for finger in [
            "index",
            "middle",
            "pinky",
            "thumb"
        ]:

            target_closed = targets[finger]

            target = (
                CLOSED_POSITION[finger]
                if target_closed
                else OPEN_POSITION[finger]
            )

            # Already logically at target.
            if self.current_position[finger] == target:
                continue

            if target_closed:

                self.fast_close(finger)

            else:

                self.fast_open(finger)

                # Progressive recovery for opening.
                self.recover_open(finger)

        self.current_gesture = gesture_name
        self.busy = False


    # ========================================================
    # CLEANUP
    # ========================================================

    def cleanup(self):

        print("\nCleaning up...")

        # Open hand before exit. force=True to guarantee it actually moves
        # regardless of what current_position claims - this is a shutdown
        # safety step, not a hot-path optimization.
        self.open_all(force=True)

        time.sleep(1)

        for finger in self.servos:
            self.servos[finger].ChangeDutyCycle(0)

        self.pca.deinit()

        print("Cleaned up")


# ============================================================
# TEST
# ============================================================

def test_all_gestures():

    hand = HandController()

    gestures = [

        'rest',

        'fist',

        'open_hand',

        'grasp',

        'thumb',

        'index',

        'middle',

        'pinky',

        'rest',

    ]

    try:

        print("\n")
        print("=" * 50)
        print("  GESTURE TEST SEQUENCE")
        print("=" * 50)

        for gesture in gestures:

            hand.set_gesture(gesture)

            time.sleep(2)

        print("\nDone!")

    except KeyboardInterrupt:

        print("\nStopped by user")

    finally:

        hand.cleanup()


# ============================================================
# MAIN
# ============================================================

if __name__ == "__main__":

    test_all_gestures()
