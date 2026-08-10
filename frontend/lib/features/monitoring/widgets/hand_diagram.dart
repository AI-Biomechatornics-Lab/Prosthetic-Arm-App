import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Finger open/closed state derived from the recognized gesture name.
/// Individual-finger gestures (index/middle/ring/pinky/thumb) close only that
/// finger; fist/grasp close the whole hand; rest and wrist rotations keep the
/// hand open.
Map<String, bool> fingerStateForGesture(String? gesture) {
  const fingers = ['thumb', 'index', 'middle', 'ring', 'pinky'];
  if (gesture == null) return {for (final f in fingers) f: true};

  if (gesture == 'fist' || gesture == 'grasp') {
    return {for (final f in fingers) f: false};
  }
  if (fingers.contains(gesture)) {
    return {for (final f in fingers) f: f != gesture};
  }
  return {for (final f in fingers) f: true}; // rest, wrist_rotate_*
}

class HandDiagram extends StatelessWidget {
  const HandDiagram({super.key, required this.gesture});

  final String? gesture;

  static const _labels = {
    'thumb': 'Thumb',
    'index': 'Index',
    'middle': 'Middle',
    'ring': 'Ring',
    'pinky': 'Pinky',
  };

  @override
  Widget build(BuildContext context) {
    final states = fingerStateForGesture(gesture);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: _labels.entries.map((entry) {
        final open = states[entry.key] ?? true;
        return _FingerIndicator(label: entry.value, open: open);
      }).toList(),
    );
  }
}

class _FingerIndicator extends StatelessWidget {
  const _FingerIndicator({required this.label, required this.open});

  final String label;
  final bool open;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: 14,
          height: open ? 56 : 26,
          decoration: BoxDecoration(
            color: open ? AppColors.accent : AppColors.borderStrong,
            borderRadius: BorderRadius.circular(7),
          ),
          alignment: Alignment.topCenter,
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
