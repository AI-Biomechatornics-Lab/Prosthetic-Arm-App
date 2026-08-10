class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.prediction,
    required this.confidence,
    required this.servoCommand,
    required this.latencyMs,
  });

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp: DateTime.parse(json['servo_time'] as String? ?? json['prediction_time'] as String),
      prediction: json['prediction'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      servoCommand: json['servo_command'] as String,
      latencyMs: (json['latency_ms'] as num).toDouble(),
    );
  }

  final DateTime timestamp;
  final String prediction;
  final double confidence;
  final String servoCommand;
  final double latencyMs;
}
