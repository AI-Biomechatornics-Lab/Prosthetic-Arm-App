import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/widgets/section_card.dart';
import '../../calibration/models/calibration_status.dart';
import '../../calibration/widgets/calibration_history_dialog.dart';
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

      // Tell the Python bridge to actually start the real-time
      // prediction/servo loop - opening the prediction/servo websockets
      // alone doesn't trigger anything, it only listens for events that
      // only exist once this has been called.
      await ApiClient.instance.dio.post('/control/start', data: {'userId': widget.userId});

      final feed = ref.read(liveFeedControllerProvider(widget.userId).notifier);
      await feed.loadHistory();
      feed.start();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not start control: $e')));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _onStop() async {
    ref.read(liveFeedControllerProvider(widget.userId).notifier).stop();
    try {
      await ApiClient.instance.dio.post('/control/stop');
    } catch (_) {
      // best-effort; the UI has already detached its listeners
    }
  }

  @override
  Widget build(BuildContext context) {
    final myoConnected = ref.watch(myoControllerProvider.select((s) => s.status == MyoStatus.connected));
    final active = ref.watch(liveFeedControllerProvider(widget.userId).select((s) => s.active));

    return SectionCard(
      title: 'Control',
      trailing: TextButton.icon(
        onPressed: () => showCalibrationHistoryDialog(context, widget.userId),
        icon: const Icon(Icons.history, size: 16),
        label: const Text('History'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: double.infinity,
            child: !active
                ? ElevatedButton.icon(
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
                : OutlinedButton.icon(
                    onPressed: _onStop,
                    icon: const Icon(Icons.stop, size: 18),
                    label: const Text('Stop'),
                  ),
          ),
          const SizedBox(height: 12),
          Text(
            active
                ? 'Real-time control running'
                : myoConnected
                    ? 'Ready to start'
                    : 'Connect the Myo armband to begin',
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
