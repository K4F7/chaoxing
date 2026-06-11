import 'package:chaoxing_app/models/app_sync_response.dart';
import 'package:chaoxing_app/models/sync_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
