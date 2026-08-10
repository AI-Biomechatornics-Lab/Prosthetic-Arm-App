import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/widgets/section_card.dart';
import '../../monitoring/providers/emg_provider.dart';
import '../../monitoring/widgets/emg_chart.dart';
import '../providers/myo_provider.dart';

class EmgGraphCard extends ConsumerWidget {
  const EmgGraphCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(myoControllerProvider.select((s) => s.status), (previous, next) {
      final emg = ref.read(emgControllerProvider.notifier);
      if (next == MyoStatus.connected) {
        emg.start();
      } else {
        emg.stop();
      }
    });

    final emgState = ref.watch(emgControllerProvider);

    return SectionCard(
      title: 'Live EMG Signal',
      child: SizedBox(
        height: 220,
        child: EmgChart(channels: emgState.channels),
      ),
    );
  }
}
