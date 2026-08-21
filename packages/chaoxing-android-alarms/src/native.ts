import { type AlarmBackend, type AndroidAlarmPlan } from "./types";

export type NativeAlarmModule = {
  schedule(plan: AndroidAlarmPlan): Promise<void>;
  cancel(key: string): Promise<void>;
  cancelAll(): Promise<void>;
  list(): Promise<AndroidAlarmPlan[]>;
  canScheduleExactAlarms(): boolean | Promise<boolean>;
};

export class NativeAlarmBackend implements AlarmBackend {
  private readonly native: NativeAlarmModule;

  constructor(native: NativeAlarmModule) {
    this.native = native;
  }

  schedule(plan: AndroidAlarmPlan): Promise<void> {
    return this.native.schedule(plan);
  }

  cancel(key: string): Promise<void> {
    return this.native.cancel(key);
  }

  cancelAll(): Promise<void> {
    return this.native.cancelAll();
  }

  list(): Promise<AndroidAlarmPlan[]> {
    return this.native.list();
  }

  async canScheduleExactAlarms(): Promise<boolean> {
    return this.native.canScheduleExactAlarms();
  }
}

export function nativeBackendFromModule(
  native: NativeAlarmModule | null | undefined,
): NativeAlarmBackend | null {
  return native ? new NativeAlarmBackend(native) : null;
}
