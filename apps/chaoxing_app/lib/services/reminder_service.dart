import '../models/sync_item.dart';

class ReminderHistory {
  const ReminderHistory(this.sent);

  const ReminderHistory.empty() : sent = const {};

  final Map<String, DateTime> sent;

  bool contains(String key) => sent.containsKey(key);

  ReminderHistory markSent(String key, DateTime sentAt) {
    return ReminderHistory({...sent, key: sentAt});
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
  Future<bool> show(ReminderCandidate candidate) async {
    // TODO: Wire this to Windows toast notifications or tray integration.
    return false;
  }
}

class LocalReminderService {
  const LocalReminderService({this.notifier = const NoopReminderNotifier()});

  final ReminderNotifier notifier;

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
    var next = history;
    for (final candidate in collectPending(
      items: items,
      history: history,
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
