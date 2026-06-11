import 'dart:async';

import 'package:chaoxing_app/models/app_config.dart';
import 'package:chaoxing_app/models/app_sync_response.dart';
import 'package:chaoxing_app/models/sync_item.dart';
import 'package:chaoxing_app/services/app_storage.dart';
import 'package:chaoxing_app/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads cached sync before refreshing configured accounts', () async {
    final cached = responseWithTitle('缓存作业');
    final fresh = responseWithTitle('最新作业');
    final storage = MemoryAppStorage(
      config: const AppConfig(
        cookie: 'UID=1',
        inboxPageLimit: 3,
        inboxItemLimit: 60,
        refreshMinutes: 60,
        remindersEnabled: true,
      ),
      cachedSync: cached,
    );
    final controller = AppController(storage, fetcher: (_) async => fresh);
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.items.single.title, '最新作业');
    expect(storage.cachedSync?.items.single.title, '最新作业');
  });

  test('keeps cached items when refresh fails', () async {
    final cached = responseWithTitle('缓存作业');
    final controller = AppController(
      MemoryAppStorage(
        config: const AppConfig(
          cookie: 'UID=1',
          inboxPageLimit: 3,
          inboxItemLimit: 60,
          refreshMinutes: 60,
          remindersEnabled: true,
        ),
        cachedSync: cached,
      ),
      fetcher: (_) async => throw Exception('network down'),
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.items.single.title, '缓存作业');
    expect(controller.error, contains('network down'));
  });

  test('coalesces overlapping refresh calls into one fetch', () async {
    final completer = Completer<AppSyncResponse>();
    var calls = 0;
    final controller = AppController(
      MemoryAppStorage(),
      fetcher: (_) {
        calls += 1;
        return completer.future;
      },
    );
    addTearDown(controller.dispose);

    final saveFuture = controller.saveConfig(
      const AppConfig(
        cookie: 'UID=1',
        inboxPageLimit: 3,
        inboxItemLimit: 60,
        refreshMinutes: 0,
        remindersEnabled: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final manualFuture = controller.refresh();
    final autoFuture = controller.refresh(silent: true);

    expect(calls, 1);
    completer.complete(responseWithTitle('最新作业'));
    await Future.wait([saveFuture, manualFuture, autoFuture]);

    expect(calls, 1);
    expect(controller.items.single.title, '最新作业');
  });

  test('redacts cookie from refresh errors', () async {
    final controller = AppController(
      MemoryAppStorage(),
      fetcher: (_) async =>
          throw Exception('network failed Cookie: UID=1; vc=secret'),
    );
    addTearDown(controller.dispose);

    await controller.saveConfig(
      const AppConfig(
        cookie: 'UID=1; vc=secret',
        inboxPageLimit: 3,
        inboxItemLimit: 60,
        refreshMinutes: 0,
        remindersEnabled: true,
      ),
    );

    expect(controller.error, isNot(contains('UID=1')));
    expect(controller.error, isNot(contains('vc=secret')));
  });
}

AppSyncResponse responseWithTitle(String title) {
  return AppSyncResponse(
    lastSyncedAt: DateTime(2026, 6, 5, 8),
    authStatus: 'ok',
    failures: const [],
    items: [
      SyncItem(
        id: 'assignment-1',
        kind: SyncItemKind.assignment,
        title: title,
        url: 'https://example.com/work',
        sourceTitle: '作业通知',
        status: 'answering',
        displayStatus: SyncDisplayStatus.upcoming,
        dueAt: DateTime(2026, 6, 6, 10),
      ),
    ],
  );
}
