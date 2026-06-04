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
        baseUrl: 'https://worker.example.com',
        token: 'secret',
        refreshMinutes: 60,
      ),
      cachedSync: cached,
    );
    final controller = AppController(storage, fetcher: (_) async => fresh);

    await controller.load();

    expect(controller.items.single.title, '最新作业');
    expect(storage.cachedSync?.items.single.title, '最新作业');
  });

  test('keeps cached items when refresh fails', () async {
    final cached = responseWithTitle('缓存作业');
    final controller = AppController(
      MemoryAppStorage(
        config: const AppConfig(
          baseUrl: 'https://worker.example.com',
          token: 'secret',
          refreshMinutes: 60,
        ),
        cachedSync: cached,
      ),
      fetcher: (_) async => throw Exception('network down'),
    );

    await controller.load();

    expect(controller.items.single.title, '缓存作业');
    expect(controller.error, contains('network down'));
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
