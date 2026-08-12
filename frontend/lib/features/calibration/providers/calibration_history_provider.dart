import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/services/api_client.dart';
import '../models/calibration_history_entry.dart';

final calibrationHistoryProvider =
    FutureProvider.family.autoDispose<List<CalibrationHistoryEntry>, int>((ref, userId) async {
  final res = await ApiClient.instance.dio.get('/calibration/$userId/history');
  return (res.data['history'] as List<dynamic>)
      .map((e) => CalibrationHistoryEntry.fromJson(e as Map<String, dynamic>))
      .toList();
});

Future<void> deleteCalibrationEntry(int userId, int calibrationId) {
  return ApiClient.instance.dio.delete('/calibration/$userId/$calibrationId');
}
