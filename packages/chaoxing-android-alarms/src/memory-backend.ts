import { type AlarmBackend, type AndroidAlarmPlan } from "./types";

/** In-memory AlarmManager stand-in for unit tests. Not a production fallback. */
export class MemoryAlarmBackend implements AlarmBackend {
  private readonly byKey = new Map<string, AndroidAlarmPlan>();
  exactAlarmsAllowed = true;

  async schedule(plan: AndroidAlarmPlan): Promise<void> {
    this.byKey.set(plan.key, { ...plan });
  }

  async cancel(key: string): Promise<void> {
    this.byKey.delete(key);
  }

  async cancelAll(): Promise<void> {
    this.byKey.clear();
  }

  async list(): Promise<AndroidAlarmPlan[]> {
    return [...this.byKey.values()].sort((left, right) => {
      const timeOrder = left.triggerAtMs - right.triggerAtMs;
      return timeOrder !== 0 ? timeOrder : left.key.localeCompare(right.key);
    });
  }

  async canScheduleExactAlarms(): Promise<boolean> {
    return this.exactAlarmsAllowed;
  }
}
