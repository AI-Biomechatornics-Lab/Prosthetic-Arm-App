import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/constants/app_constants.dart';

final storageServiceProvider = Provider<StorageService>((ref) {
  throw UnimplementedError('storageServiceProvider must be overridden in main()');
});

class StorageService {
  StorageService(this._prefs);

  final SharedPreferences _prefs;

  static Future<StorageService> create() async {
    final prefs = await SharedPreferences.getInstance();
    return StorageService(prefs);
  }

  int? get lastUserId => _prefs.getInt(AppConstants.lastUserIdKey);

  Future<void> setLastUserId(int userId) => _prefs.setInt(AppConstants.lastUserIdKey, userId);

  Future<void> clearLastUserId() => _prefs.remove(AppConstants.lastUserIdKey);
}
