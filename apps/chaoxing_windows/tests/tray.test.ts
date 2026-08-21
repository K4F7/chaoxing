import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  TrayController,
  buildTrayState,
  trayLabels,
  trayTooltip,
} from "../src/tray";

describe("Windows tray", () => {
  test("shows expiry in tooltip and login label", () => {
    const state = buildTrayState({
      refreshing: false,
      remindersEnabled: true,
      authenticationExpired: true,
      lastSyncedAt: null,
    });
    assert.match(trayTooltip(state), /⚠/);
    assert.match(trayTooltip(state), /登录已失效/);
    assert.deepEqual(trayLabels(state)[3], "重新登录");
  });

  test("close hides to tray; exit really ends", async () => {
    const calls: string[] = [];
    const tray = new TrayController({
      onOpenWindow: () => {
        calls.push("open");
      },
      onSyncNow: () => {
        calls.push("sync");
      },
      onToggleNotifications: () => {
        calls.push("pause");
      },
      onOpenLoginStatus: () => {
        calls.push("login");
      },
      onExit: () => {
        calls.push("exit");
      },
    });
    assert.equal(tray.shouldHideOnClose(), true);
    await tray.handleMenuAction("sync");
    await tray.handleMenuAction("exit");
    assert.deepEqual(calls, ["sync", "exit"]);
    assert.equal(tray.shouldHideOnClose(), false);
  });
});
