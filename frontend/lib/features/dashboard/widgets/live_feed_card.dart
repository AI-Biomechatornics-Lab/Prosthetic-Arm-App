import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../shared/services/pdf_download_service.dart';
import '../../../shared/widgets/section_card.dart';
import '../../monitoring/models/log_entry.dart';
import '../../monitoring/providers/live_feed_provider.dart';
import '../../monitoring/widgets/hand_diagram.dart';

class LiveFeedCard extends ConsumerWidget {
  const LiveFeedCard({super.key, required this.userId});

  final int userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feed = ref.watch(liveFeedControllerProvider(userId));

    return SectionCard(
      title: 'Live Control Feed',
      trailing: OutlinedButton.icon(
        onPressed: feed.logs.isEmpty ? null : () => downloadLogsPdf(userId),
        icon: const Icon(Icons.download, size: 16),
        label: const Text('Export PDF'),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14)),
            child: Column(
              children: [
                Text(
                  feed.currentGesture?.replaceAll('_', ' ') ?? '—',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 34),
                ),
                if (feed.currentConfidence != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    '${(feed.currentConfidence! * 100).toStringAsFixed(1)}% confidence',
                    style: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
                  ),
                ],
                const SizedBox(height: 24),
                HandDiagram(gesture: feed.currentGesture),
              ],
            ),
          ),
          const SizedBox(height: 20),
          _LogTable(logs: feed.logs),
        ],
      ),
    );
  }
}

class _LogTable extends StatelessWidget {
  const _LogTable({required this.logs});

  final List<LogEntry> logs;

  static final _timeFormat = DateFormat('HH:mm:ss.SSS');

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 260,
      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                _HeaderCell('Timestamp', flex: 2),
                _HeaderCell('Prediction', flex: 2),
                _HeaderCell('Confidence', flex: 2),
                _HeaderCell('Servo Command', flex: 2),
                _HeaderCell('Latency', flex: 2),
              ],
            ),
          ),
          Expanded(
            child: logs.isEmpty
                ? const Center(
                    child: Text('No activity yet', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                  )
                : ListView.separated(
                    itemCount: logs.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final log = logs[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                        child: Row(
                          children: [
                            Expanded(flex: 2, child: Text(_timeFormat.format(log.timestamp), style: const TextStyle(fontSize: 12))),
                            Expanded(flex: 2, child: Text(log.prediction, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                            Expanded(flex: 2, child: Text('${(log.confidence * 100).toStringAsFixed(1)}%', style: const TextStyle(fontSize: 12))),
                            Expanded(flex: 2, child: Text(log.servoCommand, style: const TextStyle(fontSize: 12))),
                            Expanded(flex: 2, child: Text('${log.latencyMs.toStringAsFixed(1)} ms', style: const TextStyle(fontSize: 12))),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {required this.flex});

  final String label;
  final int flex;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
    );
  }
}
