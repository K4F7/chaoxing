import { UnsupportedAlarmBackendError } from "./errors";
import { type AlarmBackend, type AndroidAlarmPlan } from "./types";

export class UnsupportedAlarmBackend implements AlarmBackend {
  constructor(private readonly detail?: string) {}

  async schedule(_plan: AndroidAlarmPlan): Promise<void> {
    throw new UnsupportedAlarmBackendError(this.detail);
  }

  async cancel(_key: string): Promise<void> {
    throw new UnsupportedAlarmBackendError(this.detail);
  }

  async cancelAll(): Promise<void> {
    throw new UnsupportedAlarmBackendError(this.detail);
  }

  async list(): Promise<AndroidAlarmPlan[]> {
    throw new UnsupportedAlarmBackendError(this.detail);
  }

  async canScheduleExactAlarms(): Promise<boolean> {
    return false;
  }
}
