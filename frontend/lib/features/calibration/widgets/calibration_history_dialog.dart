import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../models/calibration_history_entry.dart';
import '../providers/calibration_history_provider.dart';
import '../providers/calibration_provider.dart';

void showCalibrationHistoryDialog(BuildContext context, int userId) {
  showDialog<void>(
    context: context,
    builder: (_) => CalibrationHistoryDialog(userId: userId),
  );
}

class CalibrationHistoryDialog extends ConsumerWidget {
  const CalibrationHistoryDialog({super.key, required this.userId});

  final int userId;

  static final _dateFormat = DateFormat('MMM d, y - HH:mm');

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, CalibrationHistoryEntry entry, bool isLatest) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete this calibration?'),
        content: Text(
          isLatest
              ? 'This is your most recent session - deleting it rolls the live model back to the previous one.'
              : "Older sessions were already trained on top of this one, so deleting it only removes it from "
                  'this list; it won\'t change the current model.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;

    await deleteCalibrationEntry(userId, entry.id);
    ref.invalidate(calibrationHistoryProvider(userId));
    ref.invalidate(calibrationStatusProvider(userId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final history = ref.watch(calibrationHistoryProvider(userId));

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, maxHeight: 520),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Calibration history', style: Theme.of(context).textTheme.titleLarge),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Deleting your most recent session rolls the model back to the one before it.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              Flexible(
                child: history.when(
                  data: (entries) {
                    if (entries.isEmpty) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text('No calibration sessions yet', style: TextStyle(color: AppColors.textMuted)),
                        ),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        final isLatest = index == 0;
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          _dateFormat.format(entry.createdAt.toLocal()),
                                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                        ),
                                        if (isLatest) ...[
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: AppColors.accentSoft,
                                              borderRadius: BorderRadius.circular(20),
                                            ),
                                            child: const Text(
                                              'Active',
                                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.accentDark),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      entry.accuracy != null
                                          ? '${(entry.accuracy! * 100).toStringAsFixed(1)}% accuracy'
                                          : 'accuracy unknown',
                                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () => _confirmDelete(context, ref, entry, isLatest),
                                icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.error),
                                tooltip: 'Delete',
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 32),
                    child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  error: (e, __) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text('Failed to load: $e', style: const TextStyle(color: AppColors.error, fontSize: 12)),
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
