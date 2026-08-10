import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../monitoring/widgets/hand_diagram.dart';

const Map<String, String> gestureInstructions = {
  'rest': 'Relax your hand completely',
  'fist': 'Make a tight fist',
  'grasp': 'Grasp as if holding a round object',
  'index': 'Bend only your index finger',
  'middle': 'Bend only your middle finger',
  'ring': 'Bend only your ring finger',
  'pinky': 'Bend only your pinky finger',
  'thumb': 'Bend only your thumb',
  'wrist_rotate_out': 'Rotate your wrist outward',
  'wrist_rotate_in': 'Rotate your wrist inward',
};

class GestureInstructionCard extends StatelessWidget {
  const GestureInstructionCard({super.key, required this.gesture});

  final String gesture;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          gesture.replaceAll('_', ' '),
          style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32),
        ),
        const SizedBox(height: 8),
        Text(
          gestureInstructions[gesture] ?? '',
          style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
        ),
        const SizedBox(height: 28),
        HandDiagram(gesture: gesture),
      ],
    );
  }
}
