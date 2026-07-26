import 'dart:convert';

import 'package:chaoxing_app/models/app_config.dart';
import 'package:chaoxing_app/models/app_sync_response.dart';
import 'package:chaoxing_app/models/sync_item.dart';
import 'package:chaoxing_app/services/app_storage.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
    FlutterSecureStorage.setMockInitialValues({});
  });

  test(
    'stores cookie only in secure storage, not shared preferences',
    () async {
      final storage = DeviceAppStorage();

      await storage.saveConfig(
        const AppConfig(
          cookie: 'UID=real; vc=secret',
          inboxPageLimit: 3,
          inboxItemLimit: 60,
          refreshMinutes: 60,
          remindersEnabled: true,
          showNotificationDetails: true,
          courseSourcesEnabled: true,
          courseLimit: 12,
        ),
      );

      final loaded = await storage.loadConfig();
      expect(loaded.cookie, 'UID=real; vc=secret');
      expect(loaded.courseSourcesEnabled, isTrue);
      expect(loaded.showNotificationDetails, isTrue);
      expect(loaded.courseLimit, 12);
      final prefs = SharedPreferencesAsync();
      final preferenceDump = (await prefs.getAll()).entries
          .map((entry) => '${entry.key}=${entry.value}')
          .join('\n');
      expect(preferenceDump, isNot(contains('UID=real')));
      expect(preferenceDump, isNot(contains('vc=secret')));
    },
  );

  test('cleans invalid cached sync JSON and returns null', () async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          'cached_app_sync': '{bad json',
        });
    final storage = DeviceAppStorage();

    expect(await storage.loadCachedSync(), isNull);

    final prefs = SharedPreferencesAsync();
    expect(await prefs.getString('cached_app_sync'), isNull);
  });

  test('enables course sources when no preference was stored yet', () async {
    final storage = DeviceAppStorage();

    final loaded = await storage.loadConfig();

    expect(loaded.courseSourcesEnabled, isTrue);
    expect(loaded.showNotificationDetails, isFalse);
  });

  test(
    'normalizes unsafe persisted request limits and refresh intervals',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            'inbox_page_limit': -10,
            'inbox_item_limit': 999999,
            'refresh_minutes': 1,
            'course_limit': 0,
          });
      final storage = DeviceAppStorage();

      final loaded = await storage.loadConfig();

      expect(loaded.inboxPageLimit, 3);
      expect(loaded.inboxItemLimit, 500);
      expect(loaded.refreshMinutes, 15);
      expect(loaded.courseLimit, 20);
    },
  );

  test('normalizes config before persisting it', () async {
    final storage = DeviceAppStorage();

    await storage.saveConfig(
      const AppConfig(
        cookie: '  UID=1  ',
        inboxPageLimit: 100,
        inboxItemLimit: -1,
        refreshMinutes: 999,
        remindersEnabled: true,
        courseLimit: 1000,
      ),
    );
    final loaded = await storage.loadConfig();

    expect(loaded.cookie, 'UID=1');
    expect(loaded.inboxPageLimit, 20);
    expect(loaded.inboxItemLimit, 60);
    expect(loaded.refreshMinutes, 180);
    expect(loaded.courseLimit, 100);
  });

  test(
    'migrates an existing configured account to the new course default',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            'course_sources_enabled': false,
          });
      FlutterSecureStorage.setMockInitialValues({'chaoxing_cookie': 'UID=old'});
      final storage = DeviceAppStorage();

      final migrated = await storage.loadConfig();
      expect(migrated.courseSourcesEnabled, isTrue);

      await storage.saveConfig(migrated.copyWith(courseSourcesEnabled: false));
      expect((await storage.loadConfig()).courseSourcesEnabled, isFalse);
    },
  );

  test('deletes the secure cookie when an empty config is saved', () async {
    FlutterSecureStorage.setMockInitialValues({'chaoxing_cookie': 'UID=old'});
    final storage = DeviceAppStorage();

    await storage.saveConfig(AppConfig.empty);

    expect((await storage.loadConfig()).cookie, isEmpty);
  });

  test('clears only the secure cookie without changing preferences', () async {
    final storage = DeviceAppStorage();
    await storage.saveConfig(
      const AppConfig(
        cookie: 'UID=old',
        inboxPageLimit: 7,
        inboxItemLimit: 80,
        refreshMinutes: 90,
        remindersEnabled: false,
        courseSourcesEnabled: false,
        courseLimit: 30,
      ),
    );

    await storage.clearCookie();
    final loaded = await storage.loadConfig();

    expect(loaded.cookie, isEmpty);
    expect(loaded.inboxPageLimit, 7);
    expect(loaded.inboxItemLimit, 80);
    expect(loaded.refreshMinutes, 90);
    expect(loaded.remindersEnabled, isFalse);
    expect(loaded.courseSourcesEnabled, isFalse);
    expect(loaded.courseLimit, 30);
  });

  test(
    'cleans invalid reminder history JSON and returns empty history',
    () async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData({
            'reminder_history': '[bad]',
          });
      final storage = DeviceAppStorage();

      final history = await storage.loadReminderHistory();

      expect(history.sent, isEmpty);
      final prefs = SharedPreferencesAsync();
      expect(await prefs.getString('reminder_history'), isNull);
    },
  );

  test('rebuilds cached sync display status, due hours, and sorting', () async {
    final cached = AppSyncResponse(
      lastSyncedAt: DateTime.parse('2026-06-08T23:30:00+08:00'),
      authStatus: 'ok',
      failures: const [],
      seenNotices: const [
        SeenNotice(
          id: 'notice-1',
          detailParsed: true,
          sendTag: 7,
          title: '作业通知',
          taskLinks: ['https://mooc1.chaoxing.com/work?workId=1'],
        ),
      ],
      items: [
        cachedItem(
          id: 'tomorrow',
          title: '明天作业',
          dueAt: '2026-06-09T08:30:00+08:00',
          displayStatus: SyncDisplayStatus.today,
          dueInHours: 1,
        ),
        cachedItem(
          id: 'today',
          title: '今天作业',
          dueAt: '2026-06-08T23:00:00+08:00',
          displayStatus: SyncDisplayStatus.upcoming,
          dueInHours: 99,
        ),
      ],
    );
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData({
          'cached_app_sync': jsonEncode(cached.toJson()),
        });
    final storage = DeviceAppStorage(
      clock: () => DateTime.parse('2026-06-08T22:00:00+08:00'),
    );

    final restored = await storage.loadCachedSync();

    expect(restored?.items.map((item) => item.id), ['today', 'tomorrow']);
    expect(restored?.items[0].displayStatus, SyncDisplayStatus.today);
    expect(restored?.items[0].dueInHours, 1);
    expect(restored?.items[1].displayStatus, SyncDisplayStatus.upcoming);
    expect(restored?.items[1].dueInHours, 11);
    expect(restored?.seenNotices.single.id, 'notice-1');
    expect(restored?.seenNotices.single.detailParsed, isTrue);
    expect(restored?.seenNotices.single.sendTag, 7);
  });
}

SyncItem cachedItem({
  required String id,
  required String title,
  required String dueAt,
  required SyncDisplayStatus displayStatus,
  required int dueInHours,
}) {
  return SyncItem(
    id: id,
    kind: SyncItemKind.assignment,
    title: title,
    url: 'https://mooc1.chaoxing.com/work?workId=$id',
    sourceTitle: '作业通知',
    status: 'answering',
    displayStatus: displayStatus,
    dueAt: DateTime.parse(dueAt),
    dueInHours: dueInHours,
  );
}
