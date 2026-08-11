import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/app_constants.dart';
import '../../../shared/services/socket_stream_service.dart';
import '../models/ring_buffer.dart';

const int emgWindowSize = 200;

/// Drives the live EMG waveform outside of Riverpod's state/rebuild cycle:
/// samples land in fixed-capacity ring buffers (no allocation, no list
/// shifting) and [hasData]/notifyListeners are the only signals sent to the
/// UI. The chart listens to this directly via CustomPainter's `repaint`
/// hook, so a new sample repaints the canvas only - it never rebuilds the
/// widget tree.
///
/// Connects to /myo/stream/preview, not /myo/stream: the raw feed pushes
/// ~200 messages/sec (2 samples per Myo BLE packet), and JSON-parsing that
/// firehose just to average it back down client-side was itself enough
/// allocation/GC churn to cause periodic stutter. The bridge already
/// averages down to ~20Hz on that channel, so this only has to smooth it a
/// touch further, not aggregate it.
class EmgSignalController extends ChangeNotifier {
  final List<RingBuffer> buffers =
      List.generate(AppConstants.emgChannelCount, (_) => RingBuffer(emgWindowSize));
  final ValueNotifier<bool> hasData = ValueNotifier(false);

  final List<double> _smoothed = List.filled(AppConstants.emgChannelCount, 0);
  bool _hasSmoothed = false;
  static const double _emaAlpha = 0.45;

  SocketStreamService? _socket;

  void start() {
    if (_socket != null) return;
    _socket = SocketStreamService('/myo/stream/preview');

    _socket!.messages.listen((msg) {
      if (msg['type'] != 'emg_data_preview') return;
      final payload = msg['payload'] as Map<String, dynamic>?;
      final raw = payload?['channels'] as List<dynamic>?;
      if (raw == null || raw.length != AppConstants.emgChannelCount) return;

      for (var i = 0; i < buffers.length; i++) {
        final value = (raw[i] as num).toDouble();
        final smoothed =
            _hasSmoothed ? _emaAlpha * value + (1 - _emaAlpha) * _smoothed[i] : value;
        _smoothed[i] = smoothed;
        buffers[i].add(smoothed);
      }
      _hasSmoothed = true;

      if (!hasData.value) hasData.value = true;
      notifyListeners();
    });
  }

  void stop() {
    _hasSmoothed = false;
    for (var i = 0; i < _smoothed.length; i++) {
      _smoothed[i] = 0;
    }
    _socket?.dispose();
    _socket = null;
    hasData.value = false;
    for (var i = 0; i < buffers.length; i++) {
      buffers[i] = RingBuffer(emgWindowSize);
    }
  }

  @override
  void dispose() {
    _socket?.dispose();
    hasData.dispose();
    super.dispose();
  }
}

final emgSignalControllerProvider = Provider<EmgSignalController>((ref) {
  final controller = EmgSignalController();
  ref.onDispose(controller.dispose);
  return controller;
});
