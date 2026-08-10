class CalibrationStatus {
  const CalibrationStatus({
    required this.calibrated,
    required this.accuracy,
    required this.gestures,
  });

  factory CalibrationStatus.fromJson(Map<String, dynamic> json) {
    return CalibrationStatus(
      calibrated: json['calibrated'] as bool,
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      gestures: (json['gestures'] as List<dynamic>).cast<String>(),
    );
  }

  final bool calibrated;
  final double? accuracy;
  final List<String> gestures;
}
