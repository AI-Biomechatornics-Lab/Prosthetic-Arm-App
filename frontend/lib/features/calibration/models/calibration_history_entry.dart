class CalibrationHistoryEntry {
  const CalibrationHistoryEntry({
    required this.id,
    required this.accuracy,
    required this.createdAt,
  });

  factory CalibrationHistoryEntry.fromJson(Map<String, dynamic> json) {
    return CalibrationHistoryEntry(
      id: json['id'] as int,
      accuracy: (json['accuracy'] as num?)?.toDouble(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  final int id;
  final double? accuracy;
  final DateTime createdAt;
}
