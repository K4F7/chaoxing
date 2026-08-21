import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  captureLoginCookieSource,
  collectAndroidLoginCookies,
  flattenNativeCookieBag,
  type NativeCookieBag,
  type NativeCookieCollector,
} from "../src/auth/android-cookies";
import { hasChaoxingIdentityCookieSource } from "../src/auth/cookie-store";

describe("android cookie collector", () => {
  test("drops secure and host-only fields from the native jar", () => {
    const cookies = flattenNativeCookieBag({
      UID: {
        name: "UID",
        value: "42",
        domain: ".chaoxing.com",
        path: "/",
      },
      vc3: {
        name: "vc3",
        value: "token",
        domain: "chaoxing.com",
        path: "/",
      },
    });

    assert.deepEqual(cookies, [
      { name: "UID", value: "42", domain: ".chaoxing.com", path: "/" },
      { name: "vc3", value: "token", domain: "chaoxing.com", path: "/" },
    ]);
    assert.equal(
      cookies.every((cookie) => !("secure" in cookie) && !("hostOnly" in cookie)),
      true,
    );
  });

  test("captures identity cookies from a mocked CookieManager", async () => {
    const jar: NativeCookieBag = {
      UID: { name: "UID", value: "42", domain: ".chaoxing.com", path: "/" },
      theme: { name: "theme", value: "dark", domain: ".chaoxing.com", path: "/" },
    };
    const collector: NativeCookieCollector = {
      async get() {
        return jar;
      },
      async getAll() {
        return jar;
      },
    };

    const source = await captureLoginCookieSource(collector);
    assert.equal(hasChaoxingIdentityCookieSource(source), true);
    assert.equal(source.includes("42"), true);
    assert.equal(source.includes("theme"), true);
  });

  test("returns empty when the jar has no identity cookie", async () => {
    const collector: NativeCookieCollector = {
      async get() {
        return {
          theme: { name: "theme", value: "dark", domain: ".chaoxing.com", path: "/" },
        };
      },
    };

    assert.equal(await captureLoginCookieSource(collector), "");
    assert.equal((await collectAndroidLoginCookies(collector)).length, 1);
  });
});
