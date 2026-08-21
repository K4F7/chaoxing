export type DeliveredReminder = {
  key: string;
  itemId: string;
  firedAtMs: number;
};

export type LaunchTarget = {
  itemId: string;
  reminderKey: string;
};

/**
 * Side effects that sit next to AlarmManager: permission, expiry notify,
 * delivered-reminder persistence, and notification-tap extras.
 */
export type AlarmRuntime = {
  requestPostNotifications(): Promise<boolean>;
  notifyAuthenticationExpired(): Promise<void>;
  listDelivered(): Promise<DeliveredReminder[]>;
  consumeDelivered(keys: readonly string[]): Promise<void>;
  getLaunchTarget(): Promise<LaunchTarget | null>;
};

export class MemoryAlarmRuntime implements AlarmRuntime {
  permissionGranted = true;
  permissionRequested = false;
  expiryNotifications = 0;
  launchTarget: LaunchTarget | null = null;
  readonly delivered: DeliveredReminder[] = [];

  async requestPostNotifications(): Promise<boolean> {
    this.permissionRequested = true;
    return this.permissionGranted;
  }

  async notifyAuthenticationExpired(): Promise<void> {
    this.expiryNotifications += 1;
  }

  async listDelivered(): Promise<DeliveredReminder[]> {
    return this.delivered.map((row) => ({ ...row }));
  }

  async consumeDelivered(keys: readonly string[]): Promise<void> {
    const drop = new Set(keys);
    for (let index = this.delivered.length - 1; index >= 0; index -= 1) {
      if (drop.has(this.delivered[index].key)) {
        this.delivered.splice(index, 1);
      }
    }
  }

  async getLaunchTarget(): Promise<LaunchTarget | null> {
    return this.launchTarget;
  }

  recordDelivered(row: DeliveredReminder): void {
    this.delivered.push({ ...row });
  }
}

export class UnsupportedAlarmRuntime implements AlarmRuntime {
  async requestPostNotifications(): Promise<boolean> {
    return false;
  }

  async notifyAuthenticationExpired(): Promise<void> {
    // Visible in-app banner still fires via SessionController.
  }

  async listDelivered(): Promise<DeliveredReminder[]> {
    return [];
  }

  async consumeDelivered(_keys: readonly string[]): Promise<void> {}

  async getLaunchTarget(): Promise<LaunchTarget | null> {
    return null;
  }
}
