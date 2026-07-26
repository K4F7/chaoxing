import 'dart:async';
import 'dart:io';

import 'package:local_notifier/local_notifier.dart';

import '../models/sync_item.dart';
import 'reminder_rules.dart';

export 'reminder_rules.dart';

class ReminderCandidate {
  const ReminderCandidate({
    required this.key,
    required this.item,
    this.showDetails = true,
    this.intensity = ReminderIntensity.high,
  });

  final String key;
  final SyncItem item;
  final bool showDetails;
  final ReminderIntensity intensity;
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
    final authenticationExpired = item.status == 'authentication_expired';
    await _backend.show(
      DesktopNotificationRequest(
        title: authenticationExpired
            ? '学习通登录已失效'
            : item.kind == SyncItemKind.exam
            ? '考试截止提醒'
            : '作业截止提醒',
        body: authenticationExpired
            ? '请打开应用重新登录，自动同步已停止。'
            : candidate.showDetails
            ? '${item.sourceTitle}\n${item.title}\n截止：${_formatDueAt(item.dueAt)}'
            : '有一项学习任务即将截止。点击通知可在 App 内查看详情。',
        onClick: () => onNotificationClick?.call(item.id),
      ),
    );
    return true;
  }
}

class LocalReminderService {
  const LocalReminderService({this.notifier = const NoopReminderNotifier()});

  final ReminderNotifier notifier;

  Future<bool> sendTestNotification({DateTime? now, bool showDetails = true}) {
    final sentAt = now ?? DateTime.now();
    return notifier.show(
      ReminderCandidate(
        key: 'notification-test',
        showDetails: showDetails,
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

  Future<bool> sendAuthenticationExpiredNotification() {
    return notifier.show(
      const ReminderCandidate(
        key: 'authentication-expired',
        showDetails: false,
        item: SyncItem(
          id: 'authentication-expired',
          kind: SyncItemKind.assignment,
          title: '登录已失效，请重新登录',
          url: '',
          sourceTitle: '',
          status: 'authentication_expired',
          displayStatus: SyncDisplayStatus.unscheduled,
        ),
      ),
    );
  }

  List<ReminderCandidate> collectPending({
    required List<SyncItem> items,
    required ReminderHistory history,
    required DateTime now,
  }) {
    return planReminders(items: items, history: history, now: now)
        .where((plan) {
          if (now.isBefore(plan.triggerAt)) {
            return false;
          }
          if (plan.ruleId == 'due-24h') {
            return now.isBefore(
              plan.item.dueAt!.subtract(const Duration(hours: 2)),
            );
          }
          return true;
        })
        .map(
          (plan) => ReminderCandidate(
            key: plan.key,
            item: plan.item,
            intensity: plan.intensity,
          ),
        )
        .toList();
  }

  Future<ReminderHistory> process({
    required List<SyncItem> items,
    required ReminderHistory history,
    required DateTime now,
    bool showDetails = true,
  }) async {
    var next = history.prune(now);
    for (final candidate in collectPending(
      items: items,
      history: next,
      now: now,
    )) {
      final delivered = await notifier.show(
        ReminderCandidate(
          key: candidate.key,
          item: candidate.item,
          showDetails: showDetails,
          intensity: candidate.intensity,
        ),
      );
      if (delivered) {
        next = next.markSent(candidate.key, now);
      }
    }
    return next;
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
