import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../shared/services/api_client.dart';
import '../../../shared/services/storage_service.dart';
import '../models/user.dart';

class AuthController extends AsyncNotifier<AppUser?> {
  @override
  FutureOr<AppUser?> build() async {
    final storage = ref.read(storageServiceProvider);
    final lastId = storage.lastUserId;
    if (lastId == null) return null;

    try {
      return await _fetchUser(lastId);
    } catch (_) {
      await storage.clearLastUserId();
      return null;
    }
  }

  Future<AppUser> _fetchUser(int id) async {
    final res = await ApiClient.instance.dio.post('/auth/login', data: {'id': id});
    return AppUser.fromJson(res.data['user'] as Map<String, dynamic>);
  }

  Future<void> login(int id) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final user = await _fetchUser(id);
      await ref.read(storageServiceProvider).setLastUserId(user.id);
      return user;
    });
  }

  /// Creates the account without logging in yet, so the caller can show the
  /// new user their ID (the only thing they can log back in with) before
  /// [completeLogin] triggers the router redirect to the dashboard.
  Future<AppUser> registerOnly({
    required String name,
    required String surname,
    required String gender,
    required DateTime birthdate,
  }) async {
    final res = await ApiClient.instance.dio.post('/auth/register', data: {
      'name': name,
      'surname': surname,
      'gender': gender,
      'birthdate': birthdate.toIso8601String().split('T').first,
    });
    return AppUser.fromJson(res.data['user'] as Map<String, dynamic>);
  }

  Future<void> completeLogin(AppUser user) async {
    await ref.read(storageServiceProvider).setLastUserId(user.id);
    state = AsyncValue.data(user);
  }

  Future<void> logout() async {
    await ref.read(storageServiceProvider).clearLastUserId();
    state = const AsyncValue.data(null);
  }
}

final authControllerProvider = AsyncNotifierProvider<AuthController, AppUser?>(AuthController.new);
