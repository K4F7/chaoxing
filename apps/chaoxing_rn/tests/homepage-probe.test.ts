import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  createHomepageAuthProbe,
  type FetchLike,
} from "../src/auth/homepage-probe";
import { detectLoginSignals, evaluateAuth } from "../src/auth/login-signals";

function fetchSequence(
  responses: Array<{
    url?: string;
    status: number;
    location?: string;
    body?: string;
    seenHeaders?: Array<Record<string, string>>;
  }>,
): FetchLike {
  let index = 0;
  return async (_input, init) => {
    const current = responses[index] ?? responses[responses.length - 1];
    index += 1;
    current?.seenHeaders?.push(init.headers);
    return {
      status: current.status,
      url: current.url,
      headers: {
        get(name: string) {
          return name.toLowerCase() === "location" ? current.location ?? null : null;
        },
      },
      async text() {
        return current.body ?? "";
      },
    };
  };
}

describe("homepage auth probe", () => {
  test("detects 用户登录 the same way Flutter does", () => {
    assert.equal(
      detectLoginSignals("https://i.chaoxing.com/", "<title>用户登录</title>"),
      true,
    );
    assert.equal(
      detectLoginSignals("https://passport2.chaoxing.com/login", "<html></html>"),
      true,
    );
    assert.equal(
      evaluateAuth({
        statusCode: 200,
        finalUrl: "https://i.chaoxing.com/",
        html: "<title>个人空间</title>",
      }).authenticated,
      true,
    );
  });

  test("treats a login-page homepage as 认证失效", async () => {
    const probe = createHomepageAuthProbe(
      fetchSequence([
        {
          status: 200,
          url: "https://i.chaoxing.com/",
          body: "<title>用户登录</title><button id=\"loginBtn\">登录</button>",
        },
      ]),
    );
    const result = await probe("UID=1; vc3=secret");
    assert.equal(result.authenticated, false);
    assert.equal(result.loginDetected, true);
  });

  test("does not follow a redirect off the 学习通 allowlist with Cookie", async () => {
    const seenHeaders: Array<Record<string, string>> = [];
    const probe = createHomepageAuthProbe(
      fetchSequence([
        {
          status: 302,
          location: "https://evil.example/phish",
          seenHeaders,
        },
        {
          status: 200,
          body: "should-not-run",
          seenHeaders,
        },
      ]),
    );
    const result = await probe("UID=1; vc3=secret");
    assert.equal(result.authenticated, false);
    assert.equal(result.finalUrl, "https://evil.example/phish");
    assert.equal(seenHeaders.length, 1);
  });
});
