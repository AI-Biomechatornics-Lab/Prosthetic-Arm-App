import 'dart:async';
import 'dart:convert';
import 'package:web_socket_channel/web_socket_channel.dart';
import '../../core/constants/app_constants.dart';

/// Opens a WebSocket at [path] (e.g. "/myo/stream") and exposes decoded
/// JSON messages as a broadcast stream. Callers should [dispose] when done.
class SocketStreamService {
  SocketStreamService(String path)
      : _channel = WebSocketChannel.connect(Uri.parse('${AppConstants.wsBaseUrl}$path'));

  final WebSocketChannel _channel;
  final _controller = StreamController<Map<String, dynamic>>.broadcast();
  StreamSubscription? _sub;

  Stream<Map<String, dynamic>> get messages {
    _sub ??= _channel.stream.listen(
      (raw) {
        try {
          final decoded = jsonDecode(raw as String) as Map<String, dynamic>;
          _controller.add(decoded);
        } catch (_) {
          // ignore malformed frames
        }
      },
      onError: (_) => _controller.close(),
      onDone: () => _controller.close(),
    );
    return _controller.stream;
  }

  void dispose() {
    _sub?.cancel();
    _channel.sink.close();
    _controller.close();
  }
}
