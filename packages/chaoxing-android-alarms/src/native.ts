import {
  type AlarmRuntime,
  type DeliveredReminder,
  type LaunchTarget,
} from "./runtime";
import { type AlarmBackend, type AndroidAlarmPlan } from "./types";

export type NativeAlarmModule = {
  schedule(plan: AndroidAlarmPlan): Promise<void>;
  cancel(key: string): Promise<void>;
  cancelAll(): Promise<void>;
  list(): Promise<AndroidAlarmPlan[]>;
  canScheduleExactAlarms(): boolean | Promise<boolean>;
  requestPostNotifications?(): boolean | Promise<boolean>;
  notifyAuthenticationExpired?(): Promise<void> | void;
  listDelivered?(): Promise<DeliveredReminder[]>;
  consumeDelivered?(keys: readonly string[]): Promise<void>;
  getLaunchTarget?(): Promise<LaunchTarget | null> | LaunchTarget | null;
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

export class NativeAlarmRuntime implements AlarmRuntime {
  private readonly native: NativeAlarmModule;

  constructor(native: NativeAlarmModule) {
    this.native = native;
  }

  async requestPostNotifications(): Promise<boolean> {
    return this.native.requestPostNotifications?.() ?? false;
  }

  async notifyAuthenticationExpired(): Promise<void> {
    await this.native.notifyAuthenticationExpired?.();
  }

  async listDelivered(): Promise<DeliveredReminder[]> {
    return (await this.native.listDelivered?.()) ?? [];
  }

  async consumeDelivered(keys: readonly string[]): Promise<void> {
    await this.native.consumeDelivered?.(keys);
  }

  async getLaunchTarget(): Promise<LaunchTarget | null> {
    return (await this.native.getLaunchTarget?.()) ?? null;
  }
}

export function nativeRuntimeFromModule(
  native: NativeAlarmModule | null | undefined,
): NativeAlarmRuntime | null {
  return native ? new NativeAlarmRuntime(native) : null;
}
