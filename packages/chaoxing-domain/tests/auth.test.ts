import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  AuthenticationState,
  AuthStatus,
  authStatusFromCheck,
  detectLoginSignals,
  enterAuthenticationExpired,
  evaluateHomeAuth,
  extractPageTitle,
  restoreAuthentication,
  shouldAutoSync,
} from "../src/index";

describe("认证失效检测", () => {
  test("detects rendered chaoxing login pages", () => {
    const html = '<title>用户登录</title><button id="loginBtn">登录</button>';
    const result = evaluateHomeAuth({
      statusCode: 200,
      finalUrl: "https://i.chaoxing.com/base",
      html,
    });

    assert.equal(result.authenticated, false);
    assert.equal(result.loginDetected, true);
    assert.equal(result.title, "用户登录");
    assert.equal(authStatusFromCheck("UID=1", result), AuthStatus.expired);
  });

  test("treats a personal space page as authenticated", () => {
    const html = "<title>个人空间</title><div>收件箱</div>";
    const result = evaluateHomeAuth({
      statusCode: 200,
      finalUrl: "https://i.chaoxing.com/base",
      html,
    });

    assert.equal(result.authenticated, true);
    assert.equal(result.loginDetected, false);
    assert.equal(result.title, "个人空间");
    assert.equal(authStatusFromCheck("UID=1", result), AuthStatus.authenticated);
  });

  test("detects passport login redirects from the final URL", () => {
    const signals = detectLoginSignals(
      "https://passport2.chaoxing.com/login?fid=1",
      "<html></html>",
    );
    assert.equal(signals.hasPassportLoginUrl, true);
    assert.equal(extractPageTitle("<title>  学习通  </title>"), "学习通");
  });

  test("empty cookie is missingCookie without treating a page as authenticated", () => {
    assert.equal(authStatusFromCheck("", null), AuthStatus.missingCookie);
    assert.equal(authStatusFromCheck("UID=1", null), AuthStatus.unknown);
  });

  test("notifies once on 认证失效 and stops auto sync until login is restored", () => {
    const first = enterAuthenticationExpired(AuthenticationState.valid);
    const second = enterAuthenticationExpired(first.state);
    const restored = restoreAuthentication();

    assert.equal(first.notify, true);
    assert.equal(first.stopAutoSync, true);
    assert.equal(shouldAutoSync(first.state), false);
    assert.equal(second.notify, false);
    assert.equal(second.stopAutoSync, true);
    assert.equal(restored.state, AuthenticationState.valid);
    assert.equal(shouldAutoSync(restored.state), true);
  });
});
