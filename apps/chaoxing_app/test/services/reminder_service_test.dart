import 'package:chaoxing_app/models/sync_item.dart';
import 'package:chaoxing_app/services/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('collects due-soon reminders once per item and due time', () {
    final now = DateTime.parse('2026-06-05T09:00:00+08:00');
    final item = syncItem(dueAt: now.add(const Duration(hours: 2)));
    final service = const LocalReminderService();

    final pending = service.collectPending(
      items: [item],
      history: const ReminderHistory.empty(),
      now: now,
    );
    final duplicate = service.collectPending(
      items: [item],
      history: ReminderHistory({pending.single.key: now}),
      now: now,
    );

    expect(pending.single.item.id, 'assignment-1');
    expect(duplicate, isEmpty);
  });
}

SyncItem syncItem({required DateTime dueAt}) {
  return SyncItem(
    id: 'assignment-1',
    kind: SyncItemKind.assignment,
    title: '作业',
    url: 'https://example.com/work',
    sourceTitle: '作业通知',
    status: 'answering',
    displayStatus: SyncDisplayStatus.upcoming,
    dueAt: dueAt,
  );
}
