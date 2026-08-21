import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  CHAOXING_LOGIN_URL,
  classifyLoginNavigation,
  shouldAllowLoginNavigation,
} from "../src/auth/login-navigation";

describe("login navigation policy", () => {
  test("allows only trusted 学习通 https hosts", () => {
    assert.equal(classifyLoginNavigation(CHAOXING_LOGIN_URL), "allow");
    assert.equal(classifyLoginNavigation("https://i.chaoxing.com/"), "allow");
    assert.equal(classifyLoginNavigation("about:blank"), "ignore");
    assert.equal(shouldAllowLoginNavigation("about:srcdoc"), true);
  });

  test("blocks third-party, cleartext and malformed targets", () => {
    assert.equal(classifyLoginNavigation("https://evil.example/login"), "block");
    assert.equal(classifyLoginNavigation("http://i.chaoxing.com/"), "block");
    assert.equal(classifyLoginNavigation("https://notchaoxing.com/"), "block");
    assert.equal(
      classifyLoginNavigation("intent://passport2.chaoxing.com#Intent;end"),
      "block",
    );
    assert.equal(shouldAllowLoginNavigation("https://evil.example"), false);
  });
});
