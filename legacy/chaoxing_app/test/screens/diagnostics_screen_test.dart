import 'package:chaoxing_app/models/app_sync_response.dart';
import 'package:chaoxing_app/screens/diagnostics_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows status, redacts failures, and copies diagnostics', (
    tester,
  ) async {
    var copies = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: DiagnosticsScreen(
          sync: AppSyncResponse(
            lastSyncedAt: DateTime(2026, 6, 8, 10),
            authStatus: 'ok',
            items: const [],
            failures: const [
              AppSyncFailure(
                entryUrl: 'https://example.com?token=url-secret',
                sourceTitle: '作业 uid=student-42',
                message: 'Authorization: Bearer bearer-secret',
              ),
            ],
            stats: const SyncStats(
              durationMs: 30700,
              authenticationMs: 1200,
              inboxMs: 900,
              noticeDetailsMs: 8400,
              assignmentDetailsMs: 7100,
              coursesMs: 13100,
              inboxMessages: 20,
              relevantNotices: 5,
              detailSummaries: 4,
              inboxTaskLinks: 6,
              inboxTaskDetails: 6,
              statusFilteredItems: 2,
              courses: 3,
              courseTaskLinksDiscovered: 10,
              courseTaskLinks: 8,
              courseTaskStatusFiltered: 2,
              itemCandidates: 9,
              courseSourcesEnabled: true,
            ),
          ),
          error: 'Cookie: UID=real-user; vc=cookie-secret',
          onCopyDiagnostics: () async => copies += 1,
        ),
      ),
    );

    expect(find.text('同步诊断'), findsOneWidget);
    expect(find.text('认证状态'), findsOneWidget);
    expect(find.text('同步耗时'), findsOneWidget);
    expect(find.text('30.7 秒'), findsOneWidget);
    expect(find.text('认证耗时'), findsOneWidget);
    expect(find.text('通知详情耗时'), findsOneWidget);
    expect(find.text('任务详情耗时'), findsOneWidget);
    expect(find.text('课程耗时'), findsOneWidget);
    expect(find.text('13.1 秒'), findsOneWidget);
    expect(find.text('失败数量'), findsOneWidget);
    expect(find.text('收件箱消息'), findsOneWidget);
    expect(find.text('课程详情请求'), findsOneWidget);
    expect(find.text('课程发现链接'), findsOneWidget);
    expect(find.text('课程状态过滤'), findsOneWidget);
    expect(find.text('可行动去重项'), findsOneWidget);
    expect(find.textContaining('student-42'), findsNothing);
    expect(find.textContaining('bearer-secret'), findsNothing);
    expect(find.textContaining('real-user'), findsNothing);

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('复制脱敏诊断'), findsOneWidget);

    await tester.tap(find.text('复制脱敏诊断'));
    await tester.pumpAndSettle();

    expect(copies, 1);
    expect(find.text('脱敏诊断信息已复制'), findsOneWidget);
  });

  testWidgets('explains an empty result when every task was filtered', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DiagnosticsScreen(
          sync: AppSyncResponse(
            lastSyncedAt: DateTime(2026, 7, 16, 10),
            authStatus: 'ok',
            items: const [],
            failures: const [],
            stats: const SyncStats(
              inboxMessages: 3,
              relevantNotices: 2,
              detailSummaries: 2,
              inboxTaskLinks: 2,
              inboxTaskDetails: 2,
              statusFilteredItems: 2,
              itemCandidates: 0,
            ),
          ),
          error: null,
          onCopyDiagnostics: () async {},
        ),
      ),
    );

    expect(find.text('空结果判断'), findsOneWidget);
    expect(find.text('发现的事项均已完成、已提交或已结束'), findsOneWidget);
  });
}
