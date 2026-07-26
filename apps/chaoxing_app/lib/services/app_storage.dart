import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_config.dart';
import '../models/app_sync_response.dart';
import 'reminder_service.dart';

abstract class AppStorage {
  Future<AppConfig> loadConfig();

  Future<void> saveConfig(AppConfig config);

  Future<void> clearCookie();

  Future<AppSyncResponse?> loadCachedSync();

  Future<void> saveCachedSync(AppSyncResponse response);

  Future<void> clearCachedSync();

  Future<ReminderHistory> loadReminderHistory();

  Future<void> saveReminderHistory(ReminderHistory history);
}

class DeviceAppStorage implements AppStorage {
  DeviceAppStorage({
    FlutterSecureStorage? secureStorage,
    DateTime Function()? clock,
  }) : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
       _clock = clock ?? DateTime.now;

  static const _cookieKey = 'chaoxing_cookie';
  static const _legacyBaseUrlKey = 'worker_base_url';
  static const _legacyTokenKey = 'run_token';
  static const _inboxPageLimitKey = 'inbox_page_limit';
  static const _inboxItemLimitKey = 'inbox_item_limit';
  static const _refreshMinutesKey = 'refresh_minutes';
  static const _remindersEnabledKey = 'reminders_enabled';
  static const _showNotificationDetailsKey = 'show_notification_details';
  static const _courseSourcesEnabledKey = 'course_sources_enabled';
  static const _courseSourcesDefaultMigrationKey =
      'course_sources_default_enabled_v2';
  static const _courseLimitKey = 'course_limit';
  static const _cachedSyncKey = 'cached_app_sync';
  static const _reminderHistoryKey = 'reminder_history';

  final FlutterSecureStorage _secureStorage;
  final DateTime Function() _clock;
  SharedPreferencesWithCache? _preferences;

  @override
  Future<AppConfig> loadConfig() async {
    final prefs = await _prefs();
    final cookie = await _secureStorage.read(key: _cookieKey) ?? '';
    final legacyBaseUrl =
        await _secureStorage.read(key: _legacyBaseUrlKey) ?? '';
    final legacyToken = await _secureStorage.read(key: _legacyTokenKey) ?? '';
    var courseSourcesEnabled = prefs.getBool(_courseSourcesEnabledKey) ?? true;
    final courseDefaultMigrated =
        prefs.getBool(_courseSourcesDefaultMigrationKey) ?? false;
    if (cookie.trim().isNotEmpty && !courseDefaultMigrated) {
      courseSourcesEnabled = true;
      await prefs.setBool(_courseSourcesEnabledKey, true);
      await prefs.setBool(_courseSourcesDefaultMigrationKey, true);
    }
    return AppConfig(
      cookie: cookie,
      inboxPageLimit: prefs.getInt(_inboxPageLimitKey) ?? 3,
      inboxItemLimit: prefs.getInt(_inboxItemLimitKey) ?? 60,
      refreshMinutes: prefs.getInt(_refreshMinutesKey) ?? 60,
      remindersEnabled: prefs.getBool(_remindersEnabledKey) ?? true,
      showNotificationDetails:
          prefs.getBool(_showNotificationDetailsKey) ?? false,
      courseSourcesEnabled: courseSourcesEnabled,
      courseLimit: prefs.getInt(_courseLimitKey) ?? 20,
      legacyWorkerConfigDetected:
          legacyBaseUrl.trim().isNotEmpty || legacyToken.trim().isNotEmpty,
    ).normalized();
  }

  @override
  Future<void> saveConfig(AppConfig config) async {
    config = config.normalized();
    final prefs = await _prefs();
    final cookie = config.cookie.trim();
    if (cookie.isEmpty) {
      await _secureStorage.delete(key: _cookieKey);
    } else {
      await _secureStorage.write(key: _cookieKey, value: cookie);
    }
    await _secureStorage.delete(key: _legacyBaseUrlKey);
    await _secureStorage.delete(key: _legacyTokenKey);
    await prefs.setInt(_inboxPageLimitKey, config.inboxPageLimit);
    await prefs.setInt(_inboxItemLimitKey, config.inboxItemLimit);
    await prefs.setInt(_refreshMinutesKey, config.refreshMinutes);
    await prefs.setBool(_remindersEnabledKey, config.remindersEnabled);
    await prefs.setBool(
      _showNotificationDetailsKey,
      config.showNotificationDetails,
    );
    await prefs.setBool(_courseSourcesEnabledKey, config.courseSourcesEnabled);
    await prefs.setBool(_courseSourcesDefaultMigrationKey, true);
    await prefs.setInt(_courseLimitKey, config.courseLimit);
  }

  @override
  Future<void> clearCookie() => _secureStorage.delete(key: _cookieKey);

  @override
  Future<AppSyncResponse?> loadCachedSync() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_cachedSyncKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(_cachedSyncKey);
        return null;
      }
      final cached = AppSyncResponse.fromJson(decoded);
      final now = _clock();
      return AppSyncResponse.build(
        now: now,
        lastSyncedAt: cached.lastSyncedAt ?? now,
        authStatus: cached.authStatus,
        items: cached.items,
        failures: cached.failures,
        stats: cached.stats,
        seenNotices: cached.seenNotices,
      );
    } catch (_) {
      await prefs.remove(_cachedSyncKey);
      return null;
    }
  }

  @override
  Future<void> saveCachedSync(AppSyncResponse response) async {
    final prefs = await _prefs();
    await prefs.setString(_cachedSyncKey, jsonEncode(response.toJson()));
  }

  @override
  Future<void> clearCachedSync() async {
    final prefs = await _prefs();
    await prefs.remove(_cachedSyncKey);
  }

  @override
  Future<ReminderHistory> loadReminderHistory() async {
    final prefs = await _prefs();
    final raw = prefs.getString(_reminderHistoryKey);
    if (raw == null || raw.isEmpty) {
      return const ReminderHistory.empty();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        await prefs.remove(_reminderHistoryKey);
        return const ReminderHistory.empty();
      }
      return ReminderHistory.fromJson(decoded);
    } catch (_) {
      await prefs.remove(_reminderHistoryKey);
      return const ReminderHistory.empty();
    }
  }

  @override
  Future<void> saveReminderHistory(ReminderHistory history) async {
    final prefs = await _prefs();
    await prefs.setString(_reminderHistoryKey, jsonEncode(history.toJson()));
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
  ReminderHistory reminderHistory;

  MemoryAppStorage({
    this.config = AppConfig.empty,
    this.cachedSync,
    this.reminderHistory = const ReminderHistory.empty(),
  });

  @override
  Future<AppConfig> loadConfig() async => config;

  @override
  Future<void> saveConfig(AppConfig config) async {
    this.config = config;
  }

  @override
  Future<void> clearCookie() async {
    config = config.copyWith(cookie: '');
  }

  @override
  Future<AppSyncResponse?> loadCachedSync() async => cachedSync;

  @override
  Future<void> saveCachedSync(AppSyncResponse response) async {
    cachedSync = response;
  }

  @override
  Future<void> clearCachedSync() async {
    cachedSync = null;
  }

  @override
  Future<ReminderHistory> loadReminderHistory() async => reminderHistory;

  @override
  Future<void> saveReminderHistory(ReminderHistory history) async {
    reminderHistory = history;
  }
}
