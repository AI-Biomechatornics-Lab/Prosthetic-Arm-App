import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/services/socket_stream_service.dart';

enum CalibrationPhase { idle, countdown, recording, submitting, done, error }

class CalibrationState {
  const CalibrationState({
    this.phase = CalibrationPhase.idle,
    this.gestureIndex = 0,
    this.rep = 0,
    this.secondsRemaining = 0,
    this.resultAccuracy,
    this.errorMessage,
  });

  final CalibrationPhase phase;
  final int gestureIndex;
  final int rep;
  final int secondsRemaining;
  final double? resultAccuracy;
  final String? errorMessage;

  int get totalSteps => AppConstants.gestures.length * AppConstants.repsPerGesture;
  int get completedSteps => gestureIndex * AppConstants.repsPerGesture + rep;
  String get currentGesture => AppConstants.gestures[gestureIndex.clamp(0, AppConstants.gestures.length - 1)];

  CalibrationState copyWith({
    CalibrationPhase? phase,
    int? gestureIndex,
    int? rep,
    int? secondsRemaining,
    double? resultAccuracy,
    String? errorMessage,
  }) {
    return CalibrationState(
      phase: phase ?? this.phase,
      gestureIndex: gestureIndex ?? this.gestureIndex,
      rep: rep ?? this.rep,
      secondsRemaining: secondsRemaining ?? this.secondsRemaining,
      resultAccuracy: resultAccuracy ?? this.resultAccuracy,
      errorMessage: errorMessage,
    );
  }
}

class CalibrationController extends StateNotifier<CalibrationState> {
  CalibrationController(this._userId) : super(const CalibrationState());

  final int _userId;
  SocketStreamService? _socket;
  final List<Map<String, dynamic>> _samples = [];
  bool _cancelled = false;

  Future<void> _countdown(int seconds) async {
    for (var s = seconds; s > 0; s--) {
      if (_cancelled) return;
      state = state.copyWith(secondsRemaining: s);
      await Future.delayed(const Duration(seconds: 1));
    }
  }

  Future<void> run() async {
    _cancelled = false;
    _samples.clear();
    _socket = SocketStreamService('/myo/stream');

    String? recordingGesture;
    _socket!.messages.listen((msg) {
      if (msg['type'] != 'emg_data' || recordingGesture == null) return;
      final payload = msg['payload'] as Map<String, dynamic>?;
      final channels = payload?['channels'];
      if (channels == null) return;
      _samples.add({
        'gesture': recordingGesture,
        'channels': channels,
        'timestamp': msg['ts'],
      });
    });

    for (var g = 0; g < AppConstants.gestures.length; g++) {
      for (var r = 0; r < AppConstants.repsPerGesture; r++) {
        if (_cancelled) return;
        state = state.copyWith(phase: CalibrationPhase.countdown, gestureIndex: g, rep: r);
        await _countdown(3);
        if (_cancelled) return;

        recordingGesture = AppConstants.gestures[g];
        state = state.copyWith(phase: CalibrationPhase.recording);
        await _countdown(AppConstants.secondsPerRep);
        recordingGesture = null;
      }
    }

    if (_cancelled) return;
    _socket?.dispose();
    _socket = null;

    state = state.copyWith(phase: CalibrationPhase.submitting);
    try {
      // Fine-tuning 30 epochs on the Pi's CPU is slow - the base Dio client's
      // 30s receiveTimeout is meant for ordinary API calls and was killing
      // this request client-side while the backend kept training and saved
      // the result anyway (visible only after a later refresh). Give this
      // specific call room to actually finish.
      final res = await ApiClient.instance.dio.post(
        '/calibration/$_userId',
        data: {'samples': _samples},
        options: Options(
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(minutes: 5),
        ),
      );
      final accuracy = (res.data['calibration']['accuracy'] as num?)?.toDouble();
      state = state.copyWith(phase: CalibrationPhase.done, resultAccuracy: accuracy);
    } catch (e) {
      state = state.copyWith(phase: CalibrationPhase.error, errorMessage: e.toString());
    }
  }

  void cancel() {
    _cancelled = true;
    _socket?.dispose();
    _socket = null;
  }

  @override
  void dispose() {
    _socket?.dispose();
    super.dispose();
  }
}

final calibrationRunControllerProvider =
    StateNotifierProvider.autoDispose.family<CalibrationController, CalibrationState, int>((ref, userId) {
  final controller = CalibrationController(userId);
  ref.onDispose(controller.cancel);
  return controller;
});
