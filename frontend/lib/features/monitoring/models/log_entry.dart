class LogEntry {
  const LogEntry({
    required this.gestureStartTime,
    required this.dataReceivedTime,
    required this.predictionTime,
    required this.servoTime,
    required this.servoMovedTime,
    required this.prediction,
    required this.confidence,
    required this.servoCommand,
    required this.latencyMs,
    required this.physicalLatencyMs,
  });

  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      gestureStartTime: DateTime.parse(json['gesture_start_time'] as String),
      dataReceivedTime: DateTime.parse(json['data_received_time'] as String),
      predictionTime: DateTime.parse(json['prediction_time'] as String),
      servoTime: DateTime.parse(json['servo_time'] as String),
      servoMovedTime: DateTime.parse(json['servo_moved_time'] as String),
      prediction: json['prediction'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      servoCommand: json['servo_command'] as String,
      latencyMs: (json['latency_ms'] as num).toDouble(),
      physicalLatencyMs: (json['physical_latency_ms'] as num).toDouble(),
    );
  }

  /// Oldest EMG sample used for this prediction - the closest available
  /// proxy for "when the user began the gesture".
  final DateTime gestureStartTime;

  /// Newest EMG sample used for this prediction - just before inference ran.
  final DateTime dataReceivedTime;

  /// When the model finished inference and produced this prediction.
  final DateTime predictionTime;

  /// When the servo command was dispatched (non-blocking - doesn't wait for
  /// the physical movement to finish).
  final DateTime servoTime;

  /// When the servo actually finished physically moving.
  final DateTime servoMovedTime;

  final String prediction;
  final double confidence;
  final String servoCommand;

  /// "Decision latency": servoTime - gestureStartTime. AI/pipeline
  /// responsiveness - target <300ms.
  final double latencyMs;

  /// "Physical latency": servoMovedTime - servoTime. Mechanical movement
  /// time - expected to be slow (800-1500ms), tracked separately so it
  /// doesn't get conflated with how responsive the AI pipeline is.
  final double physicalLatencyMs;
}
