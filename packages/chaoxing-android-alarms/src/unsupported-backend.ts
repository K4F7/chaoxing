import { UnsupportedAlarmBackendError } from "./errors";
import { type AlarmBackend, type AndroidAlarmPlan } from "./types";

export class UnsupportedAlarmBackend implements AlarmBackend {
  private readonly detail?: string;

  constructor(detail?: string) {
    this.detail = detail;
  }

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
    throw new UnsupportedAlarmBackendError(this.detail);
  }
}
