import 'package:chaoxing_app/models/sync_item.dart';
import 'package:chaoxing_app/services/reminder_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plans 24 hour low and 2 hour high reminder rules', () {
    final now = DateTime(2026, 7, 27, 9);

    final plans = planReminders(
      items: [syncItem(dueAt: now.add(const Duration(hours: 25)), id: 'day')],
      history: const ReminderHistory.empty(),
      now: now,
    );

    expect(plans.map((plan) => plan.ruleId), ['due-24h', 'due-2h']);
    expect(plans.map((plan) => plan.intensity), [
      ReminderIntensity.low,
      ReminderIntensity.high,
    ]);
    expect(plans.map((plan) => plan.triggerAt), [
      now.add(const Duration(hours: 1)),
      now.add(const Duration(hours: 23)),
    ]);
    expect(plans[0].key, contains('|due-24h|'));
    expect(plans[1].key, contains('|due-2h|'));
  });

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

  test(
    'windows notifier initializes and records a delivered reminder',
    () async {
      final backend = FakeNotificationBackend();
      String? clickedItemId;
      final notifier = WindowsReminderNotifier(
        backend: backend,
        enabled: true,
        onNotificationClick: (itemId) => clickedItemId = itemId,
      );
      final candidate = ReminderCandidate(
        key: 'assignment-1|assignment|due',
        item: syncItem(dueAt: DateTime(2026, 6, 5, 11)),
      );

      await notifier.initialize();
      final delivered = await notifier.show(candidate);
      backend.lastRequest?.onClick();

      expect(backend.initialized, true);
      expect(delivered, true);
      expect(backend.lastRequest?.title, '作业截止提醒');
      expect(backend.lastRequest?.body, contains('2026-06-05 11:00'));
      expect(clickedItemId, 'assignment-1');
    },
  );

  test('windows notifier remains inactive on unsupported platforms', () async {
    final backend = FakeNotificationBackend();
    final notifier = WindowsReminderNotifier(backend: backend, enabled: false);

    await notifier.initialize();
    final delivered = await notifier.show(
      ReminderCandidate(
        key: 'assignment-1|assignment|due',
        item: syncItem(dueAt: DateTime(2026, 6, 5, 11)),
      ),
    );

    expect(backend.initialized, false);
    expect(backend.lastRequest, isNull);
    expect(delivered, false);
  });

  test(
    'windows notifier hides task details when privacy mode is enabled',
    () async {
      final backend = FakeNotificationBackend();
      final notifier = WindowsReminderNotifier(backend: backend, enabled: true);

      await notifier.show(
        ReminderCandidate(
          key: 'assignment-1|assignment|due',
          item: syncItem(dueAt: DateTime(2026, 6, 5, 11)),
          showDetails: false,
        ),
      );

      expect(backend.lastRequest?.body, contains('学习任务即将截止'));
      expect(backend.lastRequest?.body, isNot(contains('作业通知')));
      expect(backend.lastRequest?.body, isNot(contains('2026-06-05')));
    },
  );

  test('marks reminder history only after successful delivery', () async {
    final notifier = RecordingReminderNotifier(delivered: true);
    final service = LocalReminderService(notifier: notifier);
    final now = DateTime(2026, 6, 5, 9);

    final history = await service.process(
      items: [syncItem(dueAt: now.add(const Duration(hours: 1)))],
      history: const ReminderHistory.empty(),
      now: now,
    );

    expect(notifier.candidates, hasLength(1));
    expect(notifier.candidates.single.showDetails, isTrue);
    expect(history.contains(notifier.candidates.single.key), true);
  });

  test(
    'delivers both reminder rules without one suppressing the other',
    () async {
      final notifier = RecordingReminderNotifier(delivered: true);
      final service = LocalReminderService(notifier: notifier);
      final dueAt = DateTime(2026, 7, 28, 10);
      final item = syncItem(dueAt: dueAt);

      final afterLow = await service.process(
        items: [item],
        history: const ReminderHistory.empty(),
        now: dueAt.subtract(const Duration(hours: 24)),
      );
      final afterHigh = await service.process(
        items: [item],
        history: afterLow,
        now: dueAt.subtract(const Duration(hours: 2)),
      );

      expect(notifier.candidates.map((candidate) => candidate.intensity), [
        ReminderIntensity.low,
        ReminderIntensity.high,
      ]);
      expect(
        afterHigh.sent.keys,
        containsAll([contains('|due-24h|'), contains('|due-2h|')]),
      );
    },
  );

  test('prunes stale, future, and excess reminder history entries', () {
    final now = DateTime(2026, 7, 16, 12);
    final history = ReminderHistory({
      'stale': now.subtract(const Duration(days: 91)),
      'future': now.add(const Duration(days: 2)),
      'recent-a': now.subtract(const Duration(hours: 1)),
      'recent-b': now.subtract(const Duration(hours: 2)),
      'recent-c': now.subtract(const Duration(hours: 3)),
    });

    final pruned = history.prune(now, maximumEntries: 2);

    expect(pruned.sent.keys, ['recent-a', 'recent-b']);
    expect(pruned.sent, isNot(contains('stale')));
    expect(pruned.sent, isNot(contains('future')));
  });

  test(
    'sends a repeatable notification test without reminder history',
    () async {
      final notifier = RecordingReminderNotifier(delivered: true);
      final service = LocalReminderService(notifier: notifier);

      final delivered = await service.sendTestNotification(
        now: DateTime(2026, 7, 16, 17, 30),
      );

      expect(delivered, isTrue);
      expect(notifier.candidates, hasLength(1));
      expect(notifier.candidates.single.key, 'notification-test');
      expect(notifier.candidates.single.item.id, 'notification-test');
      expect(notifier.candidates.single.item.title, contains('恢复主窗口'));
    },
  );

  test('passes privacy mode through reminder processing', () async {
    final notifier = RecordingReminderNotifier(delivered: true);
    final service = LocalReminderService(notifier: notifier);
    final now = DateTime(2026, 6, 5, 9);

    await service.process(
      items: [syncItem(dueAt: now.add(const Duration(hours: 1)))],
      history: const ReminderHistory.empty(),
      now: now,
      showDetails: false,
    );

    expect(notifier.candidates.single.showDetails, isFalse);
  });
}

class FakeNotificationBackend implements DesktopNotificationBackend {
  bool initialized = false;
  DesktopNotificationRequest? lastRequest;

  @override
  Future<void> initialize() async {
    initialized = true;
  }

  @override
  Future<void> show(DesktopNotificationRequest request) async {
    lastRequest = request;
  }
}

class RecordingReminderNotifier implements ReminderNotifier {
  RecordingReminderNotifier({required this.delivered});

  final bool delivered;
  final List<ReminderCandidate> candidates = [];

  @override
  Future<bool> show(ReminderCandidate candidate) async {
    candidates.add(candidate);
    return delivered;
  }
}

SyncItem syncItem({required DateTime dueAt, String id = 'assignment-1'}) {
  return SyncItem(
    id: id,
    kind: SyncItemKind.assignment,
    title: '作业',
    url: 'https://example.com/work',
    sourceTitle: '作业通知',
    status: 'answering',
    displayStatus: SyncDisplayStatus.upcoming,
    dueAt: dueAt,
  );
}
