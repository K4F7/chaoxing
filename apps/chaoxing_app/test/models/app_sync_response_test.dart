import 'package:chaoxing_app/models/app_sync_response.dart';
import 'package:chaoxing_app/models/sync_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects rate limiting from sanitized failure messages', () {
    final response = AppSyncResponse(
      lastSyncedAt: DateTime(2026, 7, 16),
      authStatus: 'ok',
      items: const [],
      failures: const [
        AppSyncFailure(
          entryUrl: '',
          sourceTitle: '',
          message: '任务列表抓取失败 (429)',
        ),
      ],
    );

    expect(response.rateLimited, isTrue);
    expect(
      AppSyncResponse(
        lastSyncedAt: DateTime(2026, 7, 16),
        authStatus: 'ok',
        items: const [],
        failures: const [],
      ).rateLimited,
      isFalse,
    );
  });

  test('sorts app items and derives display status with due hours', () {
    final response = AppSyncResponse.build(
      now: DateTime.parse('2026-06-05T09:00:00+08:00'),
      lastSyncedAt: DateTime.parse('2026-06-05T09:00:00+08:00'),
      failures: const [],
      items: [
        item(id: 'unscheduled', title: '无截止', dueAt: null),
        item(id: 'later', title: '明天考试', dueAt: '2026-06-06T10:00:00+08:00'),
        item(id: 'overdue', title: '已过期', dueAt: '2026-06-05T08:00:00+08:00'),
        item(id: 'today', title: '今天作业', dueAt: '2026-06-05T23:59:00+08:00'),
      ],
    );

    expect(response.items.map((item) => item.id), [
      'overdue',
      'today',
      'later',
      'unscheduled',
    ]);
    expect(response.items[0].displayStatus, SyncDisplayStatus.overdue);
    expect(response.items[0].dueInHours, -1);
    expect(response.items[1].displayStatus, SyncDisplayStatus.today);
    expect(response.items[1].dueInHours, 15);
    expect(response.items[2].displayStatus, SyncDisplayStatus.upcoming);
    expect(response.items[2].dueInHours, 25);
    expect(response.items[3].displayStatus, SyncDisplayStatus.unscheduled);
    expect(response.items[3].dueInHours, isNull);
  });

  test('redacts sensitive failure fields before cache serialization', () {
    const failure = AppSyncFailure(
      entryUrl:
          'https://mooc1.chaoxing.com/work?workId=1&token=url-secret&uid=42',
      sourceTitle: '作业 account=student-42',
      message: 'Authorization: Bearer bearer-secret',
    );

    final json = failure.toJson().toString();

    expect(json, contains('workId=1'));
    expect(json, isNot(contains('url-secret')));
    expect(json, isNot(contains('student-42')));
    expect(json, isNot(contains('bearer-secret')));
  });

  test('sorts concurrent failures deterministically', () {
    final now = DateTime(2026, 7, 16);
    const failures = [
      AppSyncFailure(
        entryUrl: 'https://mooc1.chaoxing.com/work?workId=2',
        sourceTitle: '课程二',
        message: '失败二',
      ),
      AppSyncFailure(
        entryUrl: 'https://mooc1.chaoxing.com/work?workId=1',
        sourceTitle: '课程一',
        message: '失败一',
      ),
    ];

    AppSyncResponse build(List<AppSyncFailure> values) => AppSyncResponse.build(
      now: now,
      lastSyncedAt: now,
      items: const [],
      failures: values,
    );

    expect(
      build(failures).toJson(),
      build(failures.reversed.toList()).toJson(),
    );
  });

  test('merges the same business item and unions its sources', () {
    final now = DateTime.parse('2026-06-05T09:00:00+08:00');
    final response = AppSyncResponse.build(
      now: now,
      lastSyncedAt: now,
      failures: const [],
      items: [
        SyncItem(
          id: 'assignment-42',
          kind: SyncItemKind.assignment,
          title: '作业通知',
          url: 'https://mooc1.chaoxing.com/work?workId=42',
          sourceTitle: '作业通知',
          status: 'unknown',
          displayStatus: SyncDisplayStatus.unscheduled,
          dueAt: DateTime.parse('2026-06-06T10:00:00+08:00'),
          workId: '42',
          sources: const ['inbox'],
        ),
        SyncItem(
          id: 'assignment-42',
          kind: SyncItemKind.assignment,
          title: '高等数学第一次作业',
          url: 'https://mooc1-api.chaoxing.com/work?workId=42',
          sourceTitle: '高等数学',
          status: 'answering',
          displayStatus: SyncDisplayStatus.unscheduled,
          dueAt: DateTime.parse('2026-06-06T10:00:00+08:00'),
          workId: '42',
          sources: const ['course_work'],
        ),
      ],
    );

    expect(response.items, hasLength(1));
    expect(response.items.single.title, '高等数学第一次作业');
    expect(response.items.single.sources, ['course_work', 'inbox']);
  });

  test('merging duplicate items is independent of completion order', () {
    final now = DateTime.parse('2026-06-05T09:00:00+08:00');
    final inbox = SyncItem(
      id: 'assignment-42',
      kind: SyncItemKind.assignment,
      title: '通知标题甲',
      url: 'https://mooc1.chaoxing.com/work?workId=42',
      sourceTitle: '课程甲',
      sourceSendTime: '2026-06-01 08:00:00',
      status: 'unknown',
      displayStatus: SyncDisplayStatus.unscheduled,
      dueAt: DateTime.parse('2026-06-07T10:00:00+08:00'),
      workId: '42',
      sources: const ['inbox'],
    );
    final course = SyncItem(
      id: 'assignment-42',
      kind: SyncItemKind.assignment,
      title: '课程标题乙',
      url: 'https://mooc1-api.chaoxing.com/work?workId=42',
      sourceTitle: '课程乙',
      status: 'answering',
      displayStatus: SyncDisplayStatus.unscheduled,
      dueAt: DateTime.parse('2026-06-06T10:00:00+08:00'),
      workId: '42',
      sources: const ['course_work'],
    );

    AppSyncResponse build(List<SyncItem> items) => AppSyncResponse.build(
      now: now,
      lastSyncedAt: now,
      failures: const [],
      items: items,
    );

    expect(build([inbox, course]).toJson(), build([course, inbox]).toJson());
    expect(build([inbox, course]).items.single.dueAt, course.dueAt);
  });

  test('round-trips sync stage statistics through cache JSON', () {
    final response = AppSyncResponse(
      lastSyncedAt: DateTime(2026, 7, 16, 12),
      authStatus: 'ok',
      items: const [],
      failures: const [],
      stats: const SyncStats(
        durationMs: 1234,
        authenticationMs: 100,
        inboxMs: 200,
        noticeDetailsMs: 300,
        assignmentDetailsMs: 400,
        coursesMs: 234,
        inboxMessages: 12,
        relevantNotices: 4,
        detailSummaries: 3,
        inboxTaskLinks: 5,
        inboxTaskDetails: 4,
        statusFilteredItems: 1,
        courses: 6,
        courseTaskLinksDiscovered: 10,
        courseTaskLinks: 7,
        courseTaskStatusFiltered: 3,
        itemCandidates: 8,
        courseSourcesEnabled: true,
      ),
    );

    final restored = AppSyncResponse.fromJson(response.toJson());

    expect(restored.stats.inboxMessages, 12);
    expect(restored.stats.durationMs, 1234);
    expect(restored.stats.authenticationMs, 100);
    expect(restored.stats.inboxMs, 200);
    expect(restored.stats.noticeDetailsMs, 300);
    expect(restored.stats.assignmentDetailsMs, 400);
    expect(restored.stats.coursesMs, 234);
    expect(restored.stats.detailSummaries, 3);
    expect(restored.stats.inboxTaskDetails, 4);
    expect(restored.stats.statusFilteredItems, 1);
    expect(restored.stats.courseTaskLinksDiscovered, 10);
    expect(restored.stats.courseTaskLinks, 7);
    expect(restored.stats.courseTaskStatusFiltered, 3);
    expect(restored.stats.courseSourcesEnabled, isTrue);
  });
}

SyncItem item({
  required String id,
  required String title,
  required String? dueAt,
}) {
  return SyncItem(
    id: id,
    kind: SyncItemKind.assignment,
    title: title,
    url: 'https://example.com/$id',
    sourceTitle: '通知',
    status: 'answering',
    displayStatus: SyncDisplayStatus.unscheduled,
    dueAt: dueAt == null ? null : DateTime.parse(dueAt),
  );
}
