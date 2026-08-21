import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { buildHomeViewModel } from "../src/auth/home-view-model";
import {
  AUTH_EXPIRED_BANNER_ACTION,
  AUTH_EXPIRED_BANNER_TITLE,
} from "../src/auth/session";

describe("认证失效 UI state", () => {
  test("expired session shows the 登录已失效 banner and stops auto sync", () => {
    const view = buildHomeViewModel({
      authenticationState: "expired",
      hasCookie: true,
      autoSyncStopped: true,
      error: "登录已失效，请重新登录后再刷新",
    });

    assert.deepEqual(view.expiryBanner, {
      visible: true,
      title: AUTH_EXPIRED_BANNER_TITLE,
      actionLabel: AUTH_EXPIRED_BANNER_ACTION,
    });
    assert.equal(view.expiryBanner?.title, "登录已失效");
    assert.equal(view.expiryBanner?.actionLabel, "重新登录");
    assert.equal(view.emptySetup, null);
    assert.equal(view.autoSyncStopped, true);
    assert.equal(view.statusLine, "登录已失效，自动同步已停止");
    assert.equal(view.configured, true);
  });

  test("valid session never shows a silent-looking empty expiry state", () => {
    const view = buildHomeViewModel({
      authenticationState: "valid",
      hasCookie: true,
      autoSyncStopped: false,
    });

    assert.equal(view.expiryBanner, null);
    assert.equal(view.autoSyncStopped, false);
    assert.equal(view.statusLine, "登录态有效");
  });

  test("unconfigured Android home offers in-app login and manual Cookie import", () => {
    const view = buildHomeViewModel({
      authenticationState: "unconfigured",
      hasCookie: false,
      autoSyncStopped: false,
    });

    assert.equal(view.expiryBanner, null);
    assert.deepEqual(view.emptySetup, {
      title: "配置学习通 Cookie",
      body: "在 App 内登录学习通后，将自动导入登录态并开始本地同步。",
      loginLabel: "登录学习通",
      manualLabel: "手动导入 Cookie",
    });
    assert.equal(view.statusLine, "尚未登录");
  });
});
