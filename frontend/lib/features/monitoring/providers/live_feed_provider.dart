import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/services/socket_stream_service.dart';
import '../models/log_entry.dart';

class _PendingPrediction {
  _PendingPrediction({
    required this.gesture,
    required this.confidence,
    required this.gestureStartTime,
    required this.dataReceivedTime,
    required this.predictionTime,
  });

  final String gesture;
  final double confidence;
  final DateTime gestureStartTime;
  final DateTime dataReceivedTime;
  final DateTime predictionTime;
}

class LiveFeedState {
  const LiveFeedState({
    this.currentGesture,
    this.currentConfidence,
    this.logs = const [],
    this.active = false,
  });

  final String? currentGesture;
  final double? currentConfidence;
  final List<LogEntry> logs; // newest first
  final bool active;

  LiveFeedState copyWith({
    String? currentGesture,
    double? currentConfidence,
    List<LogEntry>? logs,
    bool? active,
  }) {
    return LiveFeedState(
      currentGesture: currentGesture ?? this.currentGesture,
      currentConfidence: currentConfidence ?? this.currentConfidence,
      logs: logs ?? this.logs,
      active: active ?? this.active,
    );
  }
}

class LiveFeedController extends StateNotifier<LiveFeedState> {
  LiveFeedController(this._userId) : super(const LiveFeedState());

  final int _userId;
  SocketStreamService? _predictionSocket;
  SocketStreamService? _servoSocket;
  final Map<String, _PendingPrediction> _pending = {};

  Future<void> loadHistory() async {
    final res = await ApiClient.instance.dio.get('/logs/$_userId');
    final rows = (res.data['logs'] as List<dynamic>)
        .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
        .toList()
        .reversed
        .toList();
    state = state.copyWith(logs: rows);
  }

  void start() {
    if (_predictionSocket != null) return;
    state = state.copyWith(active: true);

    _predictionSocket = SocketStreamService('/prediction/stream');
    _predictionSocket!.messages.listen((msg) {
      if (msg['type'] != 'prediction') return;
      final p = msg['payload'] as Map<String, dynamic>;
      final id = p['predictionId'].toString();
      final gesture = p['gesture'] as String;
      final confidence = (p['confidence'] as num).toDouble();
      _pending[id] = _PendingPrediction(
        gesture: gesture,
        confidence: confidence,
        gestureStartTime: DateTime.parse(p['gestureStartTime'] as String),
        dataReceivedTime: DateTime.parse(p['dataReceivedTime'] as String),
        predictionTime: DateTime.parse(p['timestamp'] as String),
      );
      state = state.copyWith(currentGesture: gesture, currentConfidence: confidence);
    });

    _servoSocket = SocketStreamService('/servo/stream');
    _servoSocket!.messages.listen((msg) {
      if (msg['type'] != 'servo_event') return;
      final p = msg['payload'] as Map<String, dynamic>;
      final id = p['predictionId'].toString();
      final prediction = _pending.remove(id);
      if (prediction == null) return;

      final servoTime = DateTime.parse(p['timestamp'] as String);
      final entry = LogEntry(
        gestureStartTime: prediction.gestureStartTime,
        dataReceivedTime: prediction.dataReceivedTime,
        predictionTime: prediction.predictionTime,
        servoTime: servoTime,
        prediction: prediction.gesture,
        confidence: prediction.confidence,
        servoCommand: p['command'] as String,
        latencyMs: servoTime.difference(prediction.gestureStartTime).inMicroseconds / 1000,
      );
      state = state.copyWith(logs: [entry, ...state.logs]);
    });
  }

  void stop() {
    _predictionSocket?.dispose();
    _servoSocket?.dispose();
    _predictionSocket = null;
    _servoSocket = null;
    _pending.clear();
    state = state.copyWith(active: false, currentGesture: null, currentConfidence: null);
  }

  @override
  void dispose() {
    _predictionSocket?.dispose();
    _servoSocket?.dispose();
    super.dispose();
  }
}

final liveFeedControllerProvider =
    StateNotifierProvider.family<LiveFeedController, LiveFeedState, int>((ref, userId) {
  return LiveFeedController(userId);
});
