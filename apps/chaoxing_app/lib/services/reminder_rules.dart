import '../models/sync_item.dart';

enum ReminderIntensity { low, high }

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
      raw.map(
        (key, value) => MapEntry(
          key.toString(),
          value is String
              ? DateTime.tryParse(value)?.toLocal() ?? DateTime(1970)
              : DateTime(1970),
        ),
      ),
    );
  }

  Map<String, dynamic> toJson() => {
    'sent': sent.map((key, value) => MapEntry(key, value.toIso8601String())),
  };
}

class PlannedReminder {
  const PlannedReminder({
    required this.key,
    required this.item,
    required this.ruleId,
    required this.triggerAt,
    required this.intensity,
  });

  final String key;
  final SyncItem item;
  final String ruleId;
  final DateTime triggerAt;
  final ReminderIntensity intensity;
}

const _rules = [
  (
    id: 'due-24h',
    beforeDue: Duration(hours: 24),
    intensity: ReminderIntensity.low,
  ),
  (
    id: 'due-2h',
    beforeDue: Duration(hours: 2),
    intensity: ReminderIntensity.high,
  ),
];

List<PlannedReminder> planReminders({
  required List<SyncItem> items,
  required ReminderHistory history,
  required DateTime now,
}) {
  final plans = <PlannedReminder>[];
  for (final item in items) {
    final dueAt = item.dueAt;
    if (dueAt == null || !dueAt.isAfter(now)) {
      continue;
    }
    for (final rule in _rules) {
      final key = [
        item.id,
        item.kind.name,
        rule.id,
        dueAt.toIso8601String(),
      ].join('|');
      if (!history.contains(key)) {
        plans.add(
          PlannedReminder(
            key: key,
            item: item,
            ruleId: rule.id,
            triggerAt: dueAt.subtract(rule.beforeDue),
            intensity: rule.intensity,
          ),
        );
      }
    }
  }
  plans.sort((left, right) {
    final timeOrder = left.triggerAt.compareTo(right.triggerAt);
    return timeOrder != 0 ? timeOrder : left.key.compareTo(right.key);
  });
  return plans;
}
