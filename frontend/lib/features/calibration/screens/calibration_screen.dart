import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/calibration_provider.dart';
import '../providers/calibration_run_provider.dart';
import '../widgets/calibration_progress_bar.dart';
import '../widgets/gesture_instruction_card.dart';

class CalibrationScreen extends ConsumerWidget {
  const CalibrationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    if (user == null) return const SizedBox.shrink();

    final calibState = ref.watch(calibrationRunControllerProvider(user.id));
    final controller = ref.read(calibrationRunControllerProvider(user.id).notifier);

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Container(
            padding: const EdgeInsets.all(40),
            margin: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: AppColors.border),
            ),
            child: _buildContent(context, ref, calibState, controller, user.id),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    WidgetRef ref,
    CalibrationState state,
    CalibrationController controller,
    int userId,
  ) {
    switch (state.phase) {
      case CalibrationPhase.idle:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Guided calibration', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 10),
            const Text(
              '10 gestures, 3 repetitions of 5 seconds each. Follow the on-screen prompts and hold each pose steady.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, height: 1.5),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: controller.run,
              child: const Text('Begin calibration'),
            ),
          ],
        );

      case CalibrationPhase.countdown:
      case CalibrationPhase.recording:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CalibrationProgressBar(completed: state.completedSteps, total: state.totalSteps),
            const SizedBox(height: 32),
            GestureInstructionCard(gesture: state.currentGesture),
            const SizedBox(height: 32),
            Text(
              state.phase == CalibrationPhase.countdown ? 'Get ready…' : 'Hold!',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: state.phase == CalibrationPhase.recording ? AppColors.accent : AppColors.black,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${state.secondsRemaining}',
                style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () {
                controller.cancel();
                context.go('/dashboard');
              },
              child: const Text('Cancel'),
            ),
          ],
        );

      case CalibrationPhase.submitting:
        return const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accent),
            ),
            SizedBox(height: 20),
            Text('Fine-tuning your model…', style: TextStyle(color: AppColors.textSecondary)),
          ],
        );

      case CalibrationPhase.done:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle, color: AppColors.success, size: 48),
            const SizedBox(height: 16),
            Text('Calibration complete', style: Theme.of(context).textTheme.headlineMedium),
            if (state.resultAccuracy != null) ...[
              const SizedBox(height: 8),
              Text(
                '${(state.resultAccuracy! * 100).toStringAsFixed(1)}% model accuracy',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ],
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: () {
                ref.invalidate(calibrationStatusProvider(userId));
                context.go('/dashboard');
              },
              child: const Text('Go to dashboard'),
            ),
          ],
        );

      case CalibrationPhase.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            Text('Calibration failed', style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 8),
            Text(
              state.errorMessage ?? 'Please try again.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            const SizedBox(height: 28),
            ElevatedButton(onPressed: () => context.go('/dashboard'), child: const Text('Back to dashboard')),
          ],
        );
    }
  }
}
