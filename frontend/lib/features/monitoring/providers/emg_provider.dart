import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/services/socket_stream_service.dart';

/// Rolling buffer of the 8 EMG channels for the live scrolling waveform.
class EmgState {
  const EmgState({required this.channels, this.connected = false});

  final List<List<double>> channels; // one list of recent samples per channel
  final bool connected;

  static EmgState empty() => EmgState(
        channels: List.generate(AppConstants.emgChannelCount, (_) => <double>[]),
      );

  EmgState copyWith({List<List<double>>? channels, bool? connected}) {
    return EmgState(channels: channels ?? this.channels, connected: connected ?? this.connected);
  }
}

class EmgController extends StateNotifier<EmgState> {
  EmgController() : super(EmgState.empty());

  static const int _maxPoints = 250;

  SocketStreamService? _socket;

  void start() {
    if (_socket != null) return;
    _socket = SocketStreamService('/myo/stream');
    state = state.copyWith(connected: true);
    _socket!.messages.listen(
      (msg) {
        if (msg['type'] != 'emg_data') return;
        final payload = msg['payload'] as Map<String, dynamic>?;
        final raw = payload?['channels'] as List<dynamic>?;
        if (raw == null || raw.length != AppConstants.emgChannelCount) return;

        final updated = List<List<double>>.generate(AppConstants.emgChannelCount, (i) {
          final series = List<double>.from(state.channels[i]);
          series.add((raw[i] as num).toDouble());
          if (series.length > _maxPoints) series.removeAt(0);
          return series;
        });
        state = state.copyWith(channels: updated);
      },
      onError: (_) => state = state.copyWith(connected: false),
      onDone: () => state = state.copyWith(connected: false),
    );
  }

  void stop() {
    _socket?.dispose();
    _socket = null;
    state = EmgState.empty();
  }

  @override
  void dispose() {
    _socket?.dispose();
    super.dispose();
  }
}

final emgControllerProvider = StateNotifierProvider<EmgController, EmgState>((ref) {
  return EmgController();
});
