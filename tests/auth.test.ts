import { describe, expect, test } from "bun:test";

import {
  checkChaoxingAuth,
  detectLoginSignals,
  extractPageTitle,
} from "../src/auth";

describe("chaoxing auth detection", () => {
  test("reports missing cookie without calling fetch", async () => {
    let called = false;
    const result = await checkChaoxingAuth({
      fetcher: async () => {
        called = true;
        return new Response("unexpected");
      },
    });

    expect(called).toBe(false);
    expect(result.authenticated).toBe(false);
    expect(result.failureReason).toBe("missing CHAOXING_COOKIE");
  });

  test("detects chaoxing login page signals", () => {
    const html = '<title>用户登录</title><button id="loginBtn">登录</button>';
    const signals = detectLoginSignals(
      "https://passport2.chaoxing.com/login?fid=12",
      html,
    );

    expect(signals.hasPassportLoginUrl).toBe(true);
    expect(signals.hasLoginTitle).toBe(true);
    expect(signals.hasLoginButton).toBe(true);
  });

  test("treats rendered login page as unauthenticated", async () => {
    const result = await checkChaoxingAuth({
      cookie: "UID=expired",
      fetcher: async () =>
        new Response('<html><title>用户登录</title><button id="loginBtn">登录</button></html>', {
          status: 200,
        }),
    });

    expect(result.authenticated).toBe(false);
    expect(result.failureReason).toBe("redirected_or_rendered_login_page");
    expect(JSON.stringify(result)).not.toContain("UID=expired");
  });

  test("accepts a likely logged-in personal space page", async () => {
    const result = await checkChaoxingAuth({
      cookie: "UID=valid",
      fetcher: async () =>
        new Response("<html><title>学习通</title><body>个人空间 我的课程 收件箱</body></html>", {
          status: 200,
        }),
    });

    expect(result.authenticated).toBe(true);
    expect(result.title).toBe("学习通");
    expect(result.features.hasLikelySpaceText).toBe(true);
    expect(result.features.hasCourseText).toBe(true);
    expect(result.features.hasInboxText).toBe(true);
    expect(JSON.stringify(result)).not.toContain("UID=valid");
  });

  test("extracts and normalizes page title", () => {
    expect(extractPageTitle("<title> 学习通 &amp; 个人空间 </title>")).toBe(
      "学习通 & 个人空间",
    );
  });
});
