import 'package:chaoxing_app/main.dart';
import 'package:chaoxing_app/models/app_config.dart';
import 'package:chaoxing_app/models/app_sync_response.dart';
import 'package:chaoxing_app/models/sync_item.dart';
import 'package:chaoxing_app/services/app_storage.dart';
import 'package:chaoxing_app/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows setup screen when no worker config exists', (
    tester,
  ) async {
    final controller = AppController(MemoryAppStorage());

    await tester.pumpWidget(ChaoxingApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('连接你的 Worker'), findsOneWidget);
    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();
    expect(find.text('Worker URL'), findsOneWidget);
  });

  testWidgets('shows synced assignments on the todo screen', (tester) async {
    final controller = AppController(
      MemoryAppStorage(
        config: const AppConfig(
          baseUrl: 'https://worker.example.com',
          token: 'secret',
          refreshMinutes: 60,
        ),
      ),
      fetcher: (_) async => AppSyncResponse(
        lastSyncedAt: DateTime(2026, 6, 5, 8),
        authStatus: 'ok',
        failures: const [],
        items: [
          SyncItem(
            id: 'exam-1',
            kind: SyncItemKind.exam,
            title: '期末测验',
            url: 'https://example.com/exam',
            sourceTitle: '考试通知',
            status: 'answering',
            displayStatus: SyncDisplayStatus.upcoming,
            dueAt: DateTime(2026, 6, 6, 10),
          ),
        ],
      ),
    );

    await tester.pumpWidget(ChaoxingApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('期末测验'), findsOneWidget);
    expect(find.text('未来待办'), findsOneWidget);
  });
}
