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
            child: feed.isWarmingUp
                ? const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: AppColors.accent),
                      ),
                      SizedBox(height: 14),
                      Text('Warming up…', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                    ],
                  )
                : Column(
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
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 16,
                        child: feed.detectingGesture != null
                            ? Text(
                                'detecting ${feed.detectingGesture!.replaceAll('_', ' ')}…',
                                style: const TextStyle(
                                  color: AppColors.textMuted,
                                  fontSize: 11,
                                  fontStyle: FontStyle.italic,
                                ),
                              )
                            : null,
                      ),
                      const SizedBox(height: 14),
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

class _Col {
  const _Col(this.label, this.width);
  final String label;
  final double width;
}

const _columns = [
  _Col('Gesture Start', 95),
  _Col('Data Received', 95),
  _Col('Prediction', 95),
  _Col('Servo Dispatched', 105),
  _Col('Servo Moved', 95),
  _Col('Gesture', 100),
  _Col('Confidence', 80),
  _Col('Servo Command', 100),
  _Col('Decision Latency', 100),
  _Col('Physical Latency', 100),
];

class _LogTable extends StatelessWidget {
  const _LogTable({required this.logs});

  final List<LogEntry> logs;

  static final _timeFormat = DateFormat('HH:mm:ss.SSS');
  static double get _totalWidth => _columns.fold(0, (sum, c) => sum + c.width);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 280,
      decoration: BoxDecoration(border: Border.all(color: AppColors.border), borderRadius: BorderRadius.circular(12)),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: _totalWidth,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [for (final col in _columns) _HeaderCell(col.label, width: col.width)],
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
                                // Backend timestamps are UTC (correct for storage/transport) -
                                // toLocal() converts to whatever timezone this browser is in
                                // before display, otherwise the table shows UTC wall-clock time.
                                _Cell(_timeFormat.format(log.gestureStartTime.toLocal()), width: _columns[0].width),
                                _Cell(_timeFormat.format(log.dataReceivedTime.toLocal()), width: _columns[1].width),
                                _Cell(_timeFormat.format(log.predictionTime.toLocal()), width: _columns[2].width),
                                _Cell(_timeFormat.format(log.servoTime.toLocal()), width: _columns[3].width),
                                _Cell(_timeFormat.format(log.servoMovedTime.toLocal()), width: _columns[4].width),
                                _Cell(log.prediction, width: _columns[5].width, bold: true),
                                _Cell('${(log.confidence * 100).toStringAsFixed(1)}%', width: _columns[6].width),
                                _Cell(log.servoCommand, width: _columns[7].width),
                                _Cell('${log.latencyMs.toStringAsFixed(1)} ms', width: _columns[8].width),
                                _Cell('${log.physicalLatencyMs.toStringAsFixed(1)} ms', width: _columns[9].width),
                              ],
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell(this.text, {required this.width, this.bold = false});

  final String text;
  final double width;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Text(
        text,
        style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.w600 : FontWeight.w400),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
