import { ANDROID_CONCURRENT_ALARM_LIMIT } from "./types";

export class AlarmLimitExceededError extends Error {
  readonly plannedCount: number;
  readonly limit: number;

  constructor(
    plannedCount: number,
    limit: number = ANDROID_CONCURRENT_ALARM_LIMIT,
  ) {
    super(
      `预排闹钟 ${plannedCount} 条，超过 Android 并发上限 ${limit}。不会悄悄丢掉末尾的提醒；请减少待办事项或规则后再重排。`,
    );
    this.name = "AlarmLimitExceededError";
    this.plannedCount = plannedCount;
    this.limit = limit;
  }
}

export class ExactAlarmPermissionError extends Error {
  constructor() {
    super(
      "无法安排精确闹钟：系统未授予 USE_EXACT_ALARM。提醒会失准，因此拒绝静默降级为非精确闹钟或后台抓取。",
    );
    this.name = "ExactAlarmPermissionError";
  }
}

export class UnsupportedAlarmBackendError extends Error {
  constructor(detail?: string) {
    super(
      detail ??
        "当前运行时没有 Android AlarmManager。预排提醒必须调用 setExactAndAllowWhileIdle，不能用 setTimeout、后台抓取或内存计时器代替。",
    );
    this.name = "UnsupportedAlarmBackendError";
  }
}
