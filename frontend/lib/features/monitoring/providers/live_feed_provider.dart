import 'dart:async';
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
  DateTime? servoTime; // set once servo_dispatched arrives
}

class LiveFeedState {
  const LiveFeedState({
    this.currentGesture,
    this.currentConfidence,
    this.detectingGesture,
    this.detectingConfidence,
    this.logs = const [],
    this.active = false,
    this.isWarmingUp = false,
  });

  final String? currentGesture;
  final double? currentConfidence;

  /// A candidate gesture still accumulating confident predictions, not yet
  /// confirmed/sent to the servo - purely a "detecting..." UI hint.
  final String? detectingGesture;
  final double? detectingConfidence;

  final List<LogEntry> logs; // newest first
  final bool active;

  /// True for a few seconds right after Start - predictions are ignored
  /// server-side during this window too (a false wrist_rotate_out otherwise
  /// tends to fire immediately, before the user's done anything).
  final bool isWarmingUp;

  LiveFeedState _copy({
    String? currentGesture,
    double? currentConfidence,
    String? detectingGesture,
    double? detectingConfidence,
    List<LogEntry>? logs,
    bool? active,
    bool? isWarmingUp,
    bool clearCurrent = false,
    bool clearDetecting = false,
  }) =>
      LiveFeedState(
        currentGesture: clearCurrent ? null : (currentGesture ?? this.currentGesture),
        currentConfidence: clearCurrent ? null : (currentConfidence ?? this.currentConfidence),
        detectingGesture: clearDetecting ? null : (detectingGesture ?? this.detectingGesture),
        detectingConfidence: clearDetecting ? null : (detectingConfidence ?? this.detectingConfidence),
        logs: logs ?? this.logs,
        active: active ?? this.active,
        isWarmingUp: isWarmingUp ?? this.isWarmingUp,
      );

  LiveFeedState withLogs(List<LogEntry> logs) => _copy(logs: logs);

  LiveFeedState withConfirmed(String gesture, double confidence) =>
      _copy(currentGesture: gesture, currentConfidence: confidence, clearDetecting: true);

  LiveFeedState withDetecting(String gesture, double confidence) =>
      _copy(detectingGesture: gesture, detectingConfidence: confidence);

  LiveFeedState withLogEntry(LogEntry entry) => _copy(logs: [entry, ...logs]);

  LiveFeedState withWarmup(bool warmingUp) => _copy(isWarmingUp: warmingUp);

  static LiveFeedState started(List<LogEntry> logs) => LiveFeedState(active: true, logs: logs);
}

class LiveFeedController extends StateNotifier<LiveFeedState> {
  LiveFeedController(this._userId) : super(const LiveFeedState());

  final int _userId;
  SocketStreamService? _predictionSocket;
  SocketStreamService? _detectingSocket;
  SocketStreamService? _servoSocket;
  final Map<String, _PendingPrediction> _pending = {};
  Timer? _warmupTimer;

  Future<void> loadHistory() async {
    // Latest session only: called right after /control/start, which has
    // already bumped the "current session" marker server-side - so this
    // naturally starts each session's table fresh instead of dragging in
    // everything ever recorded for this user.
    final res = await ApiClient.instance.dio.get('/logs/$_userId/latest-session');
    final rows = (res.data['logs'] as List<dynamic>)
        .map((e) => LogEntry.fromJson(e as Map<String, dynamic>))
        .toList()
        .reversed
        .toList();
    state = state.withLogs(rows);
  }

  void start() {
    if (_predictionSocket != null) return;
    state = LiveFeedState.started(state.logs);

    _predictionSocket = SocketStreamService('/prediction/stream');
    _predictionSocket!.messages.listen((msg) {
      if (msg['type'] == 'warmup') {
        final seconds = ((msg['payload'] as Map<String, dynamic>)['seconds'] as num).toInt();
        state = state.withWarmup(true);
        _warmupTimer?.cancel();
        _warmupTimer = Timer(Duration(seconds: seconds), () {
          state = state.withWarmup(false);
        });
        return;
      }
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
      state = state.withConfirmed(gesture, confidence);
    });

    _detectingSocket = SocketStreamService('/prediction/stream/detecting');
    _detectingSocket!.messages.listen((msg) {
      if (msg['type'] != 'detecting') return;
      final p = msg['payload'] as Map<String, dynamic>;
      state = state.withDetecting(p['gesture'] as String, (p['confidence'] as num).toDouble());
    });

    // Two events per gesture on this channel: servo_dispatched fires the
    // instant the command is handed off (non-blocking), servo_moved fires
    // once the physical movement actually finishes - together they split
    // "how fast did we decide" from "how long did the hand take to move".
    _servoSocket = SocketStreamService('/servo/stream');
    _servoSocket!.messages.listen((msg) {
      final p = msg['payload'] as Map<String, dynamic>;
      final id = p['predictionId'].toString();
      final prediction = _pending[id];
      if (prediction == null) return;

      if (msg['type'] == 'servo_dispatched') {
        prediction.servoTime = DateTime.parse(p['timestamp'] as String);
        return;
      }

      if (msg['type'] != 'servo_moved') return;
      final servoTime = prediction.servoTime;
      if (servoTime == null) return; // servo_moved arrived before servo_dispatched - shouldn't happen
      _pending.remove(id);

      final servoMovedTime = DateTime.parse(p['timestamp'] as String);
      final entry = LogEntry(
        gestureStartTime: prediction.gestureStartTime,
        dataReceivedTime: prediction.dataReceivedTime,
        predictionTime: prediction.predictionTime,
        servoTime: servoTime,
        servoMovedTime: servoMovedTime,
        prediction: prediction.gesture,
        confidence: prediction.confidence,
        servoCommand: p['command'] as String,
        latencyMs: servoTime.difference(prediction.gestureStartTime).inMicroseconds / 1000,
        physicalLatencyMs: servoMovedTime.difference(servoTime).inMicroseconds / 1000,
      );
      state = state.withLogEntry(entry);
    });
  }

  void stop() {
    _predictionSocket?.dispose();
    _detectingSocket?.dispose();
    _servoSocket?.dispose();
    _warmupTimer?.cancel();
    _predictionSocket = null;
    _detectingSocket = null;
    _servoSocket = null;
    _warmupTimer = null;
    _pending.clear();
    state = LiveFeedState(logs: state.logs);
  }

  @override
  void dispose() {
    _predictionSocket?.dispose();
    _detectingSocket?.dispose();
    _servoSocket?.dispose();
    _warmupTimer?.cancel();
    super.dispose();
  }
}

final liveFeedControllerProvider =
    StateNotifierProvider.family<LiveFeedController, LiveFeedState, int>((ref, userId) {
  return LiveFeedController(userId);
});
