export type SyncConfig = {
  cookie: string;
  inboxPageLimit: number;
  inboxItemLimit: number;
  refreshMinutes: number;
  remindersEnabled: boolean;
  showNotificationDetails: boolean;
  courseSourcesEnabled: boolean;
  courseLimit: number;
};

export const defaultSyncConfig: SyncConfig = {
  cookie: "",
  inboxPageLimit: 3,
  inboxItemLimit: 60,
  refreshMinutes: 60,
  remindersEnabled: true,
  showNotificationDetails: false,
  courseSourcesEnabled: true,
  courseLimit: 20,
};

export function isSyncConfigured(config: SyncConfig): boolean {
  return config.cookie.trim().length > 0;
}

export function normalizeSyncConfig(config: SyncConfig): SyncConfig {
  return {
    cookie: config.cookie.trim(),
    inboxPageLimit: boundedOrDefault(config.inboxPageLimit, 1, 20, 3),
    inboxItemLimit: boundedOrDefault(config.inboxItemLimit, 1, 500, 60),
    refreshMinutes: normalizedRefreshMinutes(config.refreshMinutes),
    remindersEnabled: config.remindersEnabled,
    showNotificationDetails: config.showNotificationDetails,
    courseSourcesEnabled: config.courseSourcesEnabled,
    courseLimit: boundedOrDefault(config.courseLimit, 1, 100, 20),
  };
}

function boundedOrDefault(
  value: number,
  minimum: number,
  maximum: number,
  fallback: number,
): number {
  if (value < minimum) {
    return fallback;
  }
  return value > maximum ? maximum : value;
}

function normalizedRefreshMinutes(value: number): number {
  if (value === 0) {
    return 0;
  }
  if (value < 0) {
    return 60;
  }
  if (value < 15) {
    return 15;
  }
  return value > 180 ? 180 : value;
}
