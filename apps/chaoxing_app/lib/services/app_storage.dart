import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_config.dart';
import '../models/app_sync_response.dart';

abstract class AppStorage {
  Future<AppConfig> loadConfig();

  Future<void> saveConfig(AppConfig config);

  Future<AppSyncResponse?> loadCachedSync();

  Future<void> saveCachedSync(AppSyncResponse response);
}

class DeviceAppStorage implements AppStorage {
  DeviceAppStorage({FlutterSecureStorage? secureStorage})
    : _secureStorage = secureStorage ?? const FlutterSecureStorage();

  static const _baseUrlKey = 'worker_base_url';
  static const _tokenKey = 'run_token';
  static const _refreshMinutesKey = 'refresh_minutes';
  static const _cachedSyncKey = 'cached_app_sync';

  final FlutterSecureStorage _secureStorage;
  SharedPreferencesWithCache? _preferences;

  @override
  Future<AppConfig> loadConfig() async {
    final prefs = await _prefs();
    final baseUrl = await _secureStorage.read(key: _baseUrlKey) ?? '';
    final token = await _secureStorage.read(key: _tokenKey) ?? '';
    return AppConfig(
      baseUrl: baseUrl,
      token: token,
      refreshMinutes: prefs.getInt(_refreshMinutesKey) ?? 60,
    );
  }

  @override
  Future<void> saveConfig(AppConfig config) async {
    final prefs = await _prefs();
    await _secureStorage.write(key: _baseUrlKey, value: config.baseUrl.trim());
    await _secureStorage.write(key: _tokenKey, value: config.token.trim());
    await prefs.setInt(_refreshMinutesKey, config.refreshMinutes);
  }

  @override
  Future<AppSyncResponse?> loadCachedSync() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_cachedSyncKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      return null;
    }
    return AppSyncResponse.fromJson(decoded);
  }

  @override
  Future<void> saveCachedSync(AppSyncResponse response) async {
    final prefs = await _prefs();
    await prefs.setString(_cachedSyncKey, jsonEncode(response.toJson()));
  }

  Future<SharedPreferencesWithCache> _prefs() async {
    return _preferences ??= await SharedPreferencesWithCache.create(
      cacheOptions: const SharedPreferencesWithCacheOptions(),
    );
  }
}

class MemoryAppStorage implements AppStorage {
  AppConfig config;
  AppSyncResponse? cachedSync;

  MemoryAppStorage({this.config = AppConfig.empty, this.cachedSync});

  @override
  Future<AppConfig> loadConfig() async => config;

  @override
  Future<void> saveConfig(AppConfig config) async {
    this.config = config;
  }

  @override
  Future<AppSyncResponse?> loadCachedSync() async => cachedSync;

  @override
  Future<void> saveCachedSync(AppSyncResponse response) async {
    cachedSync = response;
  }
}
