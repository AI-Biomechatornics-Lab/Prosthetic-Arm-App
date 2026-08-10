import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/widgets/section_card.dart';
import '../../calibration/models/calibration_status.dart';
import '../../monitoring/providers/live_feed_provider.dart';
import '../providers/myo_provider.dart';

class ControlCard extends ConsumerStatefulWidget {
  const ControlCard({super.key, required this.userId});

  final int userId;

  @override
  ConsumerState<ControlCard> createState() => _ControlCardState();
}

class _ControlCardState extends ConsumerState<ControlCard> {
  bool _checking = false;

  Future<void> _onStart() async {
    setState(() => _checking = true);
    try {
      final res = await ApiClient.instance.dio.get('/calibration/${widget.userId}');
      final status = CalibrationStatus.fromJson(res.data as Map<String, dynamic>);

      if (!status.calibrated) {
        if (mounted) context.go('/calibration');
        return;
      }
      final feed = ref.read(liveFeedControllerProvider(widget.userId).notifier);
      await feed.loadHistory();
      feed.start();
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  void _onStop() {
    ref.read(liveFeedControllerProvider(widget.userId).notifier).stop();
  }

  @override
  Widget build(BuildContext context) {
    final myoConnected = ref.watch(myoControllerProvider.select((s) => s.status == MyoStatus.connected));
    final active = ref.watch(liveFeedControllerProvider(widget.userId).select((s) => s.active));

    return SectionCard(
      title: 'Control',
      child: Row(
        children: [
          if (!active)
            ElevatedButton.icon(
              onPressed: (myoConnected && !_checking) ? _onStart : null,
              icon: _checking
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.play_arrow, size: 18),
              label: const Text('Start'),
            )
          else
            OutlinedButton.icon(
              onPressed: _onStop,
              icon: const Icon(Icons.stop, size: 18),
              label: const Text('Stop'),
            ),
          const SizedBox(width: 16),
          if (!myoConnected)
            const Text('Connect the Myo armband to begin', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}
