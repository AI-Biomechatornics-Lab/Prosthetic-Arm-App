import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/widgets/section_card.dart';
import '../providers/myo_provider.dart';

class MyoCard extends ConsumerWidget {
  const MyoCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myo = ref.watch(myoControllerProvider);
    final controller = ref.read(myoControllerProvider.notifier);

    return SectionCard(
      title: 'Myo Armband',
      trailing: _StatusPill(status: myo.status),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.battery_std, size: 18, color: AppColors.textSecondary),
              const SizedBox(width: 8),
              Text(
                myo.battery != null ? '${myo.battery}%' : '—',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              if (myo.status == MyoStatus.disconnected || myo.status == MyoStatus.lost)
                ElevatedButton(
                  onPressed: myo.status == MyoStatus.connecting ? null : controller.connect,
                  child: const Text('Connect'),
                )
              else
                OutlinedButton(
                  onPressed: controller.disconnect,
                  child: const Text('Disconnect'),
                ),
              const SizedBox(width: 12),
              if (myo.status == MyoStatus.connected)
                TextButton(
                  onPressed: controller.powerOff,
                  child: const Text('Power off'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status});

  final MyoStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      MyoStatus.connected => ('Connected', AppColors.success),
      MyoStatus.connecting => ('Connecting…', AppColors.warning),
      MyoStatus.lost => ('Connection lost', AppColors.error),
      MyoStatus.disconnected => ('Disconnected', AppColors.textMuted),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
