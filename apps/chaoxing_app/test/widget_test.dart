import 'dart:async';

import 'package:chaoxing_app/main.dart';
import 'package:chaoxing_app/models/app_config.dart';
import 'package:chaoxing_app/models/app_sync_response.dart';
import 'package:chaoxing_app/models/course_catalog.dart';
import 'package:chaoxing_app/models/sync_item.dart';
import 'package:chaoxing_app/screens/settings_screen.dart';
import 'package:chaoxing_app/services/app_storage.dart';
import 'package:chaoxing_app/services/local_sync_runner.dart';
import 'package:chaoxing_app/services/update_service.dart';
import 'package:chaoxing_app/state/app_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings lists monitored courses and updates a selection', (
    tester,
  ) async {
    String? changedKey;
    bool? changedValue;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          initialConfig: AppConfig.empty,
          onSave: (_) async {},
          courseCatalog: const CourseCatalog(
            courses: [
              CoursePreference(
                course: CourseSpace(
                  courseId: '101',
                  classId: '201',
                  cpi: '1',
                  title: '线性代数',
                ),
              ),
              CoursePreference(
                course: CourseSpace(
                  courseId: '102',
                  classId: '202',
                  cpi: '2',
                  title: '大学物理',
                ),
                monitored: false,
              ),
            ],
          ),
          onCourseMonitoringChanged: (key, monitored) async {
            changedKey = key;
            changedValue = monitored;
          },
        ),
      ),
    );

    expect(find.text('已监控 1 / 2 门课程'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('线性代数'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.widgetWithText(SwitchListTile, '线性代数'));
    await tester.pump();

    expect(changedKey, '101:201');
    expect(changedValue, isFalse);
  });

  testWidgets('settings can refresh the course list on demand', (tester) async {
    var refreshes = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          initialConfig: AppConfig.empty,
          onSave: (_) async {},
          onRefreshCourses: () async => refreshes += 1,
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.text('刷新课程列表'),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('刷新课程列表'));
    await tester.pump();

    expect(refreshes, 1);
  });

  testWidgets('settings toggles Windows autostart from its actual state', (
    tester,
  ) async {
    bool? requested;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          initialConfig: AppConfig.empty,
          onSave: (_) async {},
          autostartEnabledLoader: () async => false,
          onAutostartChanged: (enabled) async => requested = enabled,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final toggle = find.widgetWithText(SwitchListTile, '开机自启');
    await tester.scrollUntilVisible(
      toggle,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(requested, isTrue);
    expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
  });

  testWidgets('settings only prompts when a newer build is available', (
    tester,
  ) async {
    Uri? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          initialConfig: AppConfig.empty,
          onSave: (_) async {},
          updateInfoLoader: () async =>
              UpdateInfo(buildNumber: 42, releasePage: trustedReleasesPage),
          onOpenReleasePage: (uri) async => opened = uri,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final prompt = find.text('发现新版本（构建 42）');
    await tester.scrollUntilVisible(
      prompt,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(prompt, findsOneWidget);
    await tester.tap(find.text('查看发布页'));
    await tester.pump();
    expect(opened, trustedReleasesPage);
  });

  testWidgets('shows setup screen when no cookie config exists', (
    tester,
  ) async {
    final controller = AppController(MemoryAppStorage());
    addTearDown(controller.dispose);

    await tester.pumpWidget(ChaoxingApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('配置学习通 Cookie'), findsOneWidget);
    await tester.tap(find.text('手动导入 Cookie'));
    await tester.pumpAndSettle();
    expect(find.text('学习通 Cookie'), findsOneWidget);
  });

  testWidgets(
    'opens diagnostics from the app bar without a configured cookie',
    (tester) async {
      final controller = AppController(MemoryAppStorage());
      addTearDown(controller.dispose);

      await tester.pumpWidget(ChaoxingApp(controller: controller));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('诊断'));
      await tester.pumpAndSettle();

      expect(find.text('同步诊断'), findsOneWidget);
      expect(find.text('尚未同步'), findsOneWidget);
      expect(find.text('复制脱敏诊断'), findsOneWidget);
    },
  );

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
      fetcher: (_, {previous}) async => AppSyncResponse(
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

  testWidgets('surfaces partial sync failures without exposing details', (
    tester,
  ) async {
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
      fetcher: (_, {previous}) async => AppSyncResponse(
        lastSyncedAt: DateTime(2026, 7, 16, 8),
        authStatus: 'ok',
        items: const [],
        failures: const [
          AppSyncFailure(
            entryUrl: 'https://example.com/private-task',
            sourceTitle: 'private-course-title',
            message: 'private-failure-detail',
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(ChaoxingApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('部分数据源同步失败（1）'), findsOneWidget);
    expect(find.text('查看诊断'), findsOneWidget);
    expect(find.textContaining('private-course-title'), findsNothing);
    expect(find.textContaining('private-failure-detail'), findsNothing);

    await tester.tap(find.text('查看诊断'));
    await tester.pumpAndSettle();
    expect(find.text('同步诊断'), findsOneWidget);
  });

  testWidgets('shows an authentication expiry banner with a login action', (
    tester,
  ) async {
    final controller = AppController(
      MemoryAppStorage(
        config: const AppConfig(
          cookie: 'UID=1',
          inboxPageLimit: 1,
          inboxItemLimit: 20,
          refreshMinutes: 60,
          remindersEnabled: true,
        ),
        cachedSync: AppSyncResponse(
          lastSyncedAt: DateTime(2026, 7, 27, 8),
          authStatus: 'ok',
          failures: const [],
          items: [
            SyncItem(
              id: 'assignment-cached',
              kind: SyncItemKind.assignment,
              title: '缓存作业',
              url: 'https://mooc1.chaoxing.com/work?workId=cached',
              sourceTitle: '通知',
              status: 'answering',
              displayStatus: SyncDisplayStatus.unscheduled,
            ),
          ],
        ),
      ),
      fetcher: (_, {previous}) async {
        throw const AuthenticationExpiredException();
      },
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(ChaoxingApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('登录已失效'), findsOneWidget);
    expect(find.text('重新登录'), findsOneWidget);
    expect(find.text('缓存作业'), findsOneWidget);
  });

  testWidgets('shows the current stage while a sync is running', (
    tester,
  ) async {
    final completer = Completer<AppSyncResponse>();
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
      fetcher: (_, {previous}) => completer.future,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(ChaoxingApp(controller: controller));
    await tester.pump();

    expect(find.text('验证登录态 0/1'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    completer.complete(
      AppSyncResponse(
        lastSyncedAt: DateTime(2026, 7, 16, 8),
        authStatus: 'ok',
        items: const [],
        failures: const [],
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('shows assignments without a parsed deadline', (tester) async {
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
      fetcher: (_, {previous}) async => AppSyncResponse(
        lastSyncedAt: DateTime(2026, 7, 16, 8),
        authStatus: 'ok',
        failures: const [],
        items: const [
          SyncItem(
            id: 'assignment-no-deadline',
            kind: SyncItemKind.assignment,
            title: '未标截止时间的作业',
            url: 'https://mooc1.chaoxing.com/work?workId=1',
            sourceTitle: '高等数学',
            status: 'answering',
            displayStatus: SyncDisplayStatus.unscheduled,
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(ChaoxingApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('未标截止时间的作业'), findsOneWidget);
    expect(find.text('未识别截止时间'), findsOneWidget);
  });

  testWidgets('shows a loading deadline without calling it unrecognized', (
    tester,
  ) async {
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
      fetcher: (_, {previous}) async => AppSyncResponse(
        lastSyncedAt: DateTime(2026, 7, 16, 8),
        authStatus: 'ok',
        failures: const [],
        items: const [
          SyncItem(
            id: 'assignment-loading',
            kind: SyncItemKind.assignment,
            title: '正在解析的作业',
            url: 'https://mooc1.chaoxing.com/work?workId=2',
            sourceTitle: '高等数学',
            status: 'details_loading',
            displayStatus: SyncDisplayStatus.unscheduled,
          ),
        ],
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(ChaoxingApp(controller: controller));
    await tester.pumpAndSettle();

    expect(find.text('截止时间加载中'), findsOneWidget);
    expect(find.text('未解析到截止时间'), findsNothing);
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

    final saveButton = find.widgetWithText(FilledButton, '保存并同步');
    await tester.scrollUntilVisible(
      saveButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(saved?.cookie, 'UID=real; vc=secret');
    expect(find.textContaining('UID=real'), findsNothing);

    final cookieField = find.byKey(const ValueKey('cookie-input'));
    await tester.scrollUntilVisible(
      cookieField,
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(cookieField, 'UID=new; vc=next');
    await tester.pump(const Duration(seconds: 5));
    await tester.scrollUntilVisible(
      saveButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(saved?.cookie, 'UID=new; vc=next');
    expect(find.textContaining('UID=new'), findsNothing);
    expect(find.textContaining('vc=next'), findsNothing);

    await tester.pump(const Duration(seconds: 5));
    final clearButton = find.widgetWithText(TextButton, '清除');
    await tester.scrollUntilVisible(
      clearButton,
      -200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(clearButton);
    await tester.pumpAndSettle();
    await tester.tap(clearButton);
    await tester.pumpAndSettle();
    expect(find.text('保存时将清除 Cookie'), findsOneWidget);

    await tester.scrollUntilVisible(
      saveButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.ensureVisible(saveButton);
    await tester.pumpAndSettle();
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(saved?.cookie, isEmpty);
  });

  testWidgets('settings can send a Windows notification test', (tester) async {
    var calls = 0;
    bool? requestedDetails;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          initialConfig: AppConfig.empty,
          onSave: (_) async {},
          onTestNotification: (showDetails) async {
            calls += 1;
            requestedDetails = showDetails;
            return true;
          },
        ),
      ),
    );

    final testButton = find.widgetWithText(OutlinedButton, '发送测试通知');
    await tester.scrollUntilVisible(
      testButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(testButton);
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(requestedDetails, isFalse);
    expect(find.text('测试通知已发送；点击通知应恢复主窗口'), findsOneWidget);
  });

  testWidgets('notification test previews the unsaved detail preference', (
    tester,
  ) async {
    bool? requestedDetails;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          initialConfig: AppConfig.empty,
          onSave: (_) async {},
          onTestNotification: (showDetails) async {
            requestedDetails = showDetails;
            return true;
          },
        ),
      ),
    );

    final detailsSwitch = find.widgetWithText(SwitchListTile, '在系统通知中显示任务详情');
    await tester.scrollUntilVisible(
      detailsSwitch,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(detailsSwitch);
    final testButton = find.widgetWithText(OutlinedButton, '发送测试通知');
    await tester.scrollUntilVisible(
      testButton,
      100,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(testButton);
    await tester.pumpAndSettle();

    expect(requestedDetails, isTrue);
  });

  testWidgets('settings saves notification detail privacy preference', (
    tester,
  ) async {
    AppConfig? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          initialConfig: AppConfig.empty,
          onSave: (config) async => saved = config,
        ),
      ),
    );

    final detailsSwitch = find.widgetWithText(SwitchListTile, '在系统通知中显示任务详情');
    await tester.scrollUntilVisible(
      detailsSwitch,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(detailsSwitch);
    final saveButton = find.widgetWithText(FilledButton, '保存并同步');
    await tester.scrollUntilVisible(
      saveButton,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(saved?.showNotificationDetails, isTrue);
  });

  testWidgets('settings shows a safe cookie validation error', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          initialConfig: AppConfig.empty,
          onSave: (_) async =>
              throw const LocalSyncException('Cookie 格式不安全或无有效字段，请重新登录或检查手动输入'),
        ),
      ),
    );

    final saveButton = find.widgetWithText(FilledButton, '保存并同步');
    await tester.drag(find.byType(ListView), const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(saveButton, findsOneWidget);
    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('Cookie 格式不安全或无有效字段，请重新登录或检查手动输入'), findsOneWidget);
    expect(find.textContaining('LocalSyncException'), findsNothing);
  });

  testWidgets('settings shows the installed version and build number', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          initialConfig: AppConfig.empty,
          onSave: (_) async {},
          versionLabelLoader: () async => '版本 1.2.3（构建 456）',
        ),
      ),
    );
    await tester.pumpAndSettle();

    final version = find.text('版本 1.2.3（构建 456）');
    await tester.scrollUntilVisible(
      version,
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(version, findsOneWidget);
  });

  testWidgets('settings degrades safely when version lookup fails', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          initialConfig: AppConfig.empty,
          onSave: (_) async {},
          versionLabelLoader: () async => throw StateError('unavailable'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final unavailable = find.text('版本信息不可用');
    await tester.scrollUntilVisible(
      unavailable,
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(unavailable, findsOneWidget);
    expect(find.textContaining('StateError'), findsNothing);
  });
}
