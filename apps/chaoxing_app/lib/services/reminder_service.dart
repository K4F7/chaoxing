import 'dart:async';
import 'dart:io';

import 'package:local_notifier/local_notifier.dart';

import '../models/sync_item.dart';

class ReminderHistory {
  const ReminderHistory(this.sent);

  const ReminderHistory.empty() : sent = const {};

  final Map<String, DateTime> sent;

  bool contains(String key) => sent.containsKey(key);

  ReminderHistory markSent(String key, DateTime sentAt) {
    return ReminderHistory({...sent, key: sentAt});
  }

  ReminderHistory prune(
    DateTime now, {
    Duration retention = const Duration(days: 90),
    int maximumEntries = 1000,
  }) {
    final oldest = now.subtract(retention);
    final newest = now.add(const Duration(days: 1));
    final entries =
        sent.entries
            .where(
              (entry) =>
                  !entry.value.isBefore(oldest) && !entry.value.isAfter(newest),
            )
            .toList()
          ..sort((left, right) {
            final timeOrder = right.value.compareTo(left.value);
            return timeOrder != 0 ? timeOrder : left.key.compareTo(right.key);
          });
    return ReminderHistory(
      Map.fromEntries(
        entries.take(maximumEntries.clamp(0, entries.length).toInt()),
      ),
    );
  }

  factory ReminderHistory.fromJson(Map<String, dynamic> json) {
    final raw = json['sent'];
    if (raw is! Map) {
      return const ReminderHistory.empty();
    }

    return ReminderHistory(
      raw.map((key, value) {
        return MapEntry(
          key.toString(),
          value is String
              ? DateTime.tryParse(value)?.toLocal() ?? DateTime(1970)
              : DateTime(1970),
        );
      }),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'sent': sent.map((key, value) => MapEntry(key, value.toIso8601String())),
    };
  }
}

class ReminderCandidate {
  const ReminderCandidate({required this.key, required this.item});

  final String key;
  final SyncItem item;
}

abstract class ReminderNotifier {
  Future<bool> show(ReminderCandidate candidate);
}

class NoopReminderNotifier implements ReminderNotifier {
  const NoopReminderNotifier();

  @override
  Future<bool> show(ReminderCandidate candidate) async => false;
}

class DesktopNotificationRequest {
  const DesktopNotificationRequest({
    required this.title,
    required this.body,
    required this.onClick,
  });

  final String title;
  final String body;
  final void Function() onClick;
}

abstract class DesktopNotificationBackend {
  Future<void> initialize();

  Future<void> show(DesktopNotificationRequest request);
}

class LocalNotifierBackend implements DesktopNotificationBackend {
  const LocalNotifierBackend();

  @override
  Future<void> initialize() {
    return localNotifier.setup(
      appName: '学习通待办',
      shortcutPolicy: ShortcutPolicy.requireCreate,
    );
  }

  @override
  Future<void> show(DesktopNotificationRequest request) async {
    final notification = LocalNotification(
      title: request.title,
      body: request.body,
    );
    notification.onClick = () {
      try {
        request.onClick();
      } finally {
        unawaited(notification.destroy());
      }
    };
    notification.onClose = (_) {
      unawaited(notification.destroy());
    };
    await notification.show();
  }
}

class WindowsReminderNotifier implements ReminderNotifier {
  WindowsReminderNotifier({
    DesktopNotificationBackend? backend,
    this.onNotificationClick,
    bool? enabled,
  }) : _backend = backend ?? const LocalNotifierBackend(),
       _enabled = enabled ?? Platform.isWindows;

  final DesktopNotificationBackend _backend;
  final void Function(String itemId)? onNotificationClick;
  final bool _enabled;

  Future<void> initialize() async {
    if (_enabled) {
      await _backend.initialize();
    }
  }

  @override
  Future<bool> show(ReminderCandidate candidate) async {
    if (!_enabled) {
      return false;
    }

    final item = candidate.item;
    await _backend.show(
      DesktopNotificationRequest(
        title: item.kind == SyncItemKind.exam ? '考试截止提醒' : '作业截止提醒',
        body:
            '${item.sourceTitle}\n${item.title}\n截止：${_formatDueAt(item.dueAt)}',
        onClick: () => onNotificationClick?.call(item.id),
      ),
    );
    return true;
  }
}

class LocalReminderService {
  const LocalReminderService({this.notifier = const NoopReminderNotifier()});

  final ReminderNotifier notifier;

  Future<bool> sendTestNotification({DateTime? now}) {
    final sentAt = now ?? DateTime.now();
    return notifier.show(
      ReminderCandidate(
        key: 'notification-test',
        item: SyncItem(
          id: 'notification-test',
          kind: SyncItemKind.assignment,
          title: '点击此通知应恢复主窗口',
          url: '',
          sourceTitle: '系统通知测试',
          status: 'test',
          displayStatus: SyncDisplayStatus.today,
          dueAt: sentAt,
        ),
      ),
    );
  }

  List<ReminderCandidate> collectPending({
    required List<SyncItem> items,
    required ReminderHistory history,
    required DateTime now,
  }) {
    return items
        .where((item) => _shouldRemind(item, now))
        .map((item) => ReminderCandidate(key: _reminderKey(item), item: item))
        .where((candidate) => !history.contains(candidate.key))
        .toList();
  }

  Future<ReminderHistory> process({
    required List<SyncItem> items,
    required ReminderHistory history,
    required DateTime now,
  }) async {
    var next = history.prune(now);
    for (final candidate in collectPending(
      items: items,
      history: next,
      now: now,
    )) {
      final delivered = await notifier.show(candidate);
      if (delivered) {
        next = next.markSent(candidate.key, now);
      }
    }
    return next;
  }

  bool _shouldRemind(SyncItem item, DateTime now) {
    final dueAt = item.dueAt;
    if (dueAt == null || dueAt.isBefore(now)) {
      return false;
    }
    return dueAt.difference(now).inHours <= 72;
  }

  String _reminderKey(SyncItem item) {
    return [
      item.id,
      item.kind.name,
      item.dueAt?.toIso8601String() ?? 'unscheduled',
    ].join('|');
  }
}

String _formatDueAt(DateTime? value) {
  if (value == null) {
    return '时间未知';
  }
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${twoDigits(value.month)}-${twoDigits(value.day)} '
      '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}
