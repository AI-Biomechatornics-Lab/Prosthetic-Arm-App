class LogEntry {
  const LogEntry({
    required this.gestureStartTime,
    required this.dataReceivedTime,
    required this.predictionTime,
    required this.servoTime,
    required this.prediction,
    required this.confidence,
    required this.servoCommand,
    required this.latencyMs,
  });

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      gestureStartTime: DateTime.parse(json['gesture_start_time'] as String),
      dataReceivedTime: DateTime.parse(json['data_received_time'] as String),
      predictionTime: DateTime.parse(json['prediction_time'] as String),
      servoTime: DateTime.parse(json['servo_time'] as String),
      prediction: json['prediction'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      servoCommand: json['servo_command'] as String,
      latencyMs: (json['latency_ms'] as num).toDouble(),
    );
  }

  /// Oldest EMG sample used for this prediction - the closest available
  /// proxy for "when the user began the gesture".
  final DateTime gestureStartTime;

  /// Newest EMG sample used for this prediction - just before inference ran.
  final DateTime dataReceivedTime;

  /// When the model finished inference and produced this prediction.
  final DateTime predictionTime;

  /// When the servo command was issued (the finger started moving).
  final DateTime servoTime;

  final String prediction;
  final double confidence;
  final String servoCommand;

  /// Full pipeline: servoTime - gestureStartTime.
  final double latencyMs;
}
