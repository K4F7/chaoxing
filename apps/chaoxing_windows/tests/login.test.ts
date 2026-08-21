import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  classifyLoginNavigation,
  runWebView2Login,
} from "../src/login";

describe("Windows WebView2 login", () => {
  test("blocks third-party navigation", async () => {
    assert.equal(classifyLoginNavigation("https://evil.example/login"), "block");
    const capture = await runWebView2Login(
      {
        navigate() {},
        async collectCookies() {
          return "UID=1; vc3=x";
        },
      },
      { navigations: ["https://phishing.test/"] },
    );
    assert.equal(capture.blocked, true);
    assert.equal(capture.cookieSource, null);
  });

  test("collects cookies after trusted navigation", async () => {
    const capture = await runWebView2Login({
      navigate() {},
      async collectCookies() {
        return "UID=1; vc3=x";
      },
    });
    assert.equal(capture.blocked, false);
    assert.equal(capture.cookieSource, "UID=1; vc3=x");
  });
});
