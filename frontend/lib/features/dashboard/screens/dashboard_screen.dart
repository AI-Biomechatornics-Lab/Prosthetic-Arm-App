import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../auth/providers/auth_provider.dart';
import '../../calibration/providers/calibration_provider.dart';
import '../widgets/control_card.dart';
import '../widgets/emg_graph_card.dart';
import '../widgets/live_feed_card.dart';
import '../widgets/myo_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    if (user == null) return const SizedBox.shrink();

    final calibration = ref.watch(calibrationStatusProvider(user.id));

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text('Welcome, ${user.name}', style: Theme.of(context).textTheme.headlineMedium),
                      const SizedBox(width: 14),
                      calibration.when(
                        data: (status) => status.accuracy != null
                            ? _AccuracyBadge(accuracy: status.accuracy!)
                            : const SizedBox.shrink(),
                        loading: () => const SizedBox.shrink(),
                        error: (_, __) => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: () => ref.read(authControllerProvider.notifier).logout(),
                    icon: const Icon(Icons.logout, size: 16),
                    label: const Text('Log out'),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              Expanded(
                child: SingleChildScrollView(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const MyoCard(),
                            const SizedBox(height: 20),
                            ControlCard(userId: user.id),
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        flex: 7,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const EmgGraphCard(),
                            const SizedBox(height: 20),
                            LiveFeedCard(userId: user.id),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccuracyBadge extends StatelessWidget {
  const _AccuracyBadge({required this.accuracy});

  final double accuracy;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
      ),
      child: Text(
        '${(accuracy * 100).toStringAsFixed(1)}% accuracy',
        style: const TextStyle(color: AppColors.accentDark, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}
