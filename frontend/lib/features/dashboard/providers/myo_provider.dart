import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/services/api_client.dart';

enum MyoStatus { disconnected, connecting, connected, lost }

class MyoState {
  const MyoState({this.status = MyoStatus.disconnected, this.battery, this.error});

  final MyoStatus status;
  final int? battery;
  final String? error;

  MyoState copyWith({MyoStatus? status, int? battery, String? error}) {
    return MyoState(
      status: status ?? this.status,
      battery: battery ?? this.battery,
      error: error,
    );
  }
}

class MyoController extends StateNotifier<MyoState> {
  MyoController() : super(const MyoState());

  final _dio = ApiClient.instance.dio;

  Future<void> connect() async {
    state = state.copyWith(status: MyoStatus.connecting, error: null);
    try {
      await _dio.get('/myo/connect');
      state = state.copyWith(status: MyoStatus.connected);
      await refreshBattery();
    } catch (e) {
      state = state.copyWith(status: MyoStatus.lost, error: e.toString());
    }
  }

  Future<void> disconnect() async {
    try {
      await _dio.get('/myo/disconnect');
    } finally {
      state = const MyoState();
    }
  }

  Future<void> refreshBattery() async {
    try {
      final res = await _dio.get('/myo/battery');
      state = state.copyWith(battery: res.data['battery'] as int?);
    } catch (_) {
      // non-fatal; keep last known battery reading
    }
  }

  Future<void> powerOff() async {
    await _dio.post('/myo/poweroff');
    state = const MyoState();
  }
}

final myoControllerProvider = StateNotifierProvider<MyoController, MyoState>((ref) {
  return MyoController();
});
