export type TrayMenuState = {
  notificationsPaused: boolean;
  syncInProgress: boolean;
  authSummary: string;
  authenticationExpired: boolean;
};

export type TrayAction = "open" | "sync" | "pause" | "login" | "exit";

export function trayTooltip(state: TrayMenuState): string {
  return `${state.authenticationExpired ? "⚠ " : ""}学习通待办 - ${state.authSummary}`;
}

export function trayLabels(state: TrayMenuState): string[] {
  return [
    "打开窗口",
    state.syncInProgress ? "同步中" : "立即同步",
    state.notificationsPaused ? "恢复通知" : "暂停通知",
    state.authenticationExpired ? "重新登录" : "查看登录状态",
    "退出",
  ];
}

export function buildTrayState(input: {
  refreshing: boolean;
  remindersEnabled: boolean;
  authenticationExpired: boolean;
  lastSyncedAt: Date | null;
}): TrayMenuState {
  const authSummary = input.authenticationExpired
    ? "登录已失效"
    : input.lastSyncedAt
      ? `上次同步 ${input.lastSyncedAt.toISOString()}`
      : "尚未同步";
  return {
    notificationsPaused: !input.remindersEnabled,
    syncInProgress: input.refreshing,
    authSummary,
    authenticationExpired: input.authenticationExpired,
  };
}

export type TrayHostCallbacks = {
  onOpenWindow: () => Promise<void> | void;
  onSyncNow: () => Promise<void> | void;
  onToggleNotifications: () => Promise<void> | void;
  onOpenLoginStatus: () => Promise<void> | void;
  onExit: () => Promise<void> | void;
};

/**
 * Close-to-tray: hide unless the user chose 退出.
 * Explicit exit ends the process; a second instance is rejected by launch.ts.
 */
export class TrayController {
  private allowClose = false;
  private exitRequested = false;

  constructor(private readonly callbacks: TrayHostCallbacks) {}

  async handleMenuAction(action: TrayAction): Promise<void> {
    switch (action) {
      case "open":
        await this.callbacks.onOpenWindow();
        return;
      case "sync":
        await this.callbacks.onSyncNow();
        return;
      case "pause":
        await this.callbacks.onToggleNotifications();
        return;
      case "login":
        await this.callbacks.onOpenLoginStatus();
        return;
      case "exit":
        if (this.exitRequested) {
          return;
        }
        this.exitRequested = true;
        this.allowClose = true;
        try {
          await this.callbacks.onExit();
        } catch (error) {
          this.exitRequested = false;
          this.allowClose = false;
          throw error;
        }
        return;
    }
  }

  shouldHideOnClose(): boolean {
    return !this.allowClose;
  }
}
