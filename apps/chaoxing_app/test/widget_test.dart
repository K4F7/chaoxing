import 'package:chaoxing_app/main.dart';
import 'package:chaoxing_app/models/app_config.dart';
import 'package:chaoxing_app/models/app_sync_response.dart';
import 'package:chaoxing_app/models/sync_item.dart';
import 'package:chaoxing_app/screens/settings_screen.dart';
import 'package:chaoxing_app/services/app_storage.dart';
import 'package:chaoxing_app/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows setup screen when no cookie config exists', (
    tester,
  ) async {
    final controller = AppController(MemoryAppStorage());
    addTearDown(controller.dispose);

    await tester.pumpWidget(ChaoxingApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('配置学习通 Cookie'), findsOneWidget);
    await tester.tap(find.text('打开设置'));
    await tester.pumpAndSettle();
    expect(find.text('学习通 Cookie'), findsOneWidget);
  });

  testWidgets('shows synced assignments on the todo screen', (tester) async {
    final controller = AppController(
      MemoryAppStorage(
        config: const AppConfig(
          cookie: 'UID=1',
          inboxPageLimit: 3,
          inboxItemLimit: 60,
          refreshMinutes: 0,
          remindersEnabled: true,
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
    addTearDown(controller.dispose);

    await tester.pumpWidget(ChaoxingApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('期末测验'), findsOneWidget);
    expect(find.text('未来待办'), findsOneWidget);
  });

  testWidgets('settings screen never renders saved cookie and preserves it', (
    tester,
  ) async {
    AppConfig? saved;

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          initialConfig: const AppConfig(
            cookie: 'UID=real; vc=secret',
            inboxPageLimit: 3,
            inboxItemLimit: 60,
            refreshMinutes: 60,
            remindersEnabled: true,
          ),
          onSave: (config) async => saved = config,
        ),
      ),
    );

    expect(find.text('已保存 Cookie'), findsOneWidget);
    expect(find.textContaining('UID=real'), findsNothing);
    expect(find.textContaining('vc=secret'), findsNothing);

    await tester.tap(find.text('保存并同步'));
    await tester.pumpAndSettle();

    expect(saved?.cookie, 'UID=real; vc=secret');
    expect(find.textContaining('UID=real'), findsNothing);

    await tester.enterText(find.byType(TextField).first, 'UID=new; vc=next');
    await tester.tap(find.text('保存并同步'));
    await tester.pumpAndSettle();

    expect(saved?.cookie, 'UID=new; vc=next');
    expect(find.textContaining('UID=new'), findsNothing);
    expect(find.textContaining('vc=next'), findsNothing);
  });
}
