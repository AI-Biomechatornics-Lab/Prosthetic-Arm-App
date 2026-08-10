import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/services/api_client.dart';
import '../models/calibration_status.dart';

final calibrationStatusProvider =
    FutureProvider.family.autoDispose<CalibrationStatus, int>((ref, userId) async {
  final res = await ApiClient.instance.dio.get('/calibration/$userId');
  return CalibrationStatus.fromJson(res.data as Map<String, dynamic>);
});
