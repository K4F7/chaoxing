import { type SyncItem } from "./sync-item";
import { addDays, addHours, toLocalIso8601 } from "./time";

export const ReminderIntensity = {
  low: "low",
  high: "high",
} as const;

export type ReminderIntensity =
  (typeof ReminderIntensity)[keyof typeof ReminderIntensity];

export type ReminderHistory = {
  sent: Readonly<Record<string, Date>>;
};

export type PlannedReminder = {
  key: string;
  item: SyncItem;
  ruleId: string;
  triggerAt: Date;
  intensity: ReminderIntensity;
};

const rules = [
  {
    id: "due-24h",
    beforeDueHours: 24,
    intensity: ReminderIntensity.low,
  },
  {
    id: "due-2h",
    beforeDueHours: 2,
    intensity: ReminderIntensity.high,
  },
] as const;

export function emptyReminderHistory(): ReminderHistory {
  return { sent: {} };
}

export function reminderHistoryContains(
  history: ReminderHistory,
  key: string,
): boolean {
  return Object.prototype.hasOwnProperty.call(history.sent, key);
}

export function markReminderSent(
  history: ReminderHistory,
  key: string,
  sentAt: Date,
): ReminderHistory {
  return { sent: { ...history.sent, [key]: sentAt } };
}

export function pruneReminderHistory(
  history: ReminderHistory,
  now: Date,
  options: { retentionDays?: number; maximumEntries?: number } = {},
): ReminderHistory {
  const retentionDays = options.retentionDays ?? 90;
  const maximumEntries = options.maximumEntries ?? 1000;
  const oldest = addDays(now, -retentionDays);
  const newest = addDays(now, 1);
  const entries = Object.entries(history.sent)
    .filter(([, sentAt]) => sentAt >= oldest && sentAt <= newest)
    .sort(([leftKey, leftAt], [rightKey, rightAt]) => {
      const timeOrder = rightAt.getTime() - leftAt.getTime();
      return timeOrder !== 0 ? timeOrder : leftKey.localeCompare(rightKey);
    });
  const limit = Math.min(Math.max(maximumEntries, 0), entries.length);
  return {
    sent: Object.fromEntries(entries.slice(0, limit)),
  };
}

export function reminderKey(item: SyncItem, ruleId: string, dueAt: Date): string {
  return [item.id, item.kind, ruleId, toLocalIso8601(dueAt)].join("|");
}

export function planReminders(input: {
  items: readonly SyncItem[];
  history: ReminderHistory;
  now: Date;
}): PlannedReminder[] {
  const plans: PlannedReminder[] = [];
  for (const item of input.items) {
    const dueAt = item.dueAt;
    if (dueAt === null || dueAt.getTime() <= input.now.getTime()) {
      continue;
    }
    for (const rule of rules) {
      const key = reminderKey(item, rule.id, dueAt);
      if (!reminderHistoryContains(input.history, key)) {
        plans.push({
          key,
          item,
          ruleId: rule.id,
          triggerAt: addHours(dueAt, -rule.beforeDueHours),
          intensity: rule.intensity,
        });
      }
    }
  }
  plans.sort((left, right) => {
    const timeOrder = left.triggerAt.getTime() - right.triggerAt.getTime();
    return timeOrder !== 0 ? timeOrder : left.key.localeCompare(right.key);
  });
  return plans;
}

export function collectDueReminders(input: {
  items: readonly SyncItem[];
  history: ReminderHistory;
  now: Date;
}): PlannedReminder[] {
  return planReminders(input).filter(
    (plan) => plan.triggerAt.getTime() <= input.now.getTime(),
  );
}
