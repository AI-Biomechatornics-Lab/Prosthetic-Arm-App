import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/section_card.dart';
import '../../monitoring/providers/emg_provider.dart';
import '../../monitoring/widgets/emg_chart.dart';
import '../providers/myo_provider.dart';

class EmgGraphCard extends ConsumerWidget {
  const EmgGraphCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A plain Provider, not a ChangeNotifierProvider: watching it just hands
    // back the singleton controller and does NOT rebuild this widget every
    // time it calls notifyListeners() for a new sample. Only the CustomPaint
    // inside EmgChart listens to that (via CustomPainter's `repaint` hook).
    final controller = ref.watch(emgSignalControllerProvider);

    ref.listen(myoControllerProvider.select((s) => s.status), (previous, next) {
      if (next == MyoStatus.connected) {
        controller.start();
      } else {
        controller.stop();
      }
    });


    return SectionCard(
      title: 'Live EMG Signal',
      child: Column(
        children: [
          Container(
            height: 220,
            decoration: BoxDecoration(
              color: AppColors.white,
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.all(8),
            child: EmgChart(controller: controller),
          ),
          const SizedBox(height: 8),
          // Legend
          Wrap(
            spacing: 12,
            runSpacing: 6,
            children: List.generate(8, (i) {
              final color = AppColors.emgChannels[i % AppColors.emgChannels.length];
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(width: 12, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 6),
                  Text('CH${i + 1}', style: const TextStyle(color: AppColors.textPrimary, fontSize: 12)),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}
