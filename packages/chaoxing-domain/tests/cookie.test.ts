import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  chaoxingCookieSecrets,
  cookieHeaderForChaoxingUri,
  encodeChaoxingCookieStore,
  hasChaoxingIdentityCookieSource,
  isSafeChaoxingCookieSource,
  mergeChaoxingResponseCookies,
  redactSensitiveText,
} from "../src/index";

describe("认证 Cookie 会话", () => {
  test("rejects an entire cookie source containing newline injection", () => {
    const injected = "UID=1; route=ok\r\nX-Evil: injected";
    assert.equal(isSafeChaoxingCookieSource(injected), false);
    assert.equal(hasChaoxingIdentityCookieSource(injected), false);
    assert.equal(
      cookieHeaderForChaoxingUri(injected, new URL("https://i.chaoxing.com/base")),
      "",
    );
  });

  test("keeps host-only cookies on their exact response host", () => {
    const store = mergeChaoxingResponseCookies(
      "",
      new URL("https://i.chaoxing.com/base"),
      "host_route=i-only; Path=/,global_route=global; Domain=.chaoxing.com; Path=/",
    );
    const home = cookieHeaderForChaoxingUri(
      store,
      new URL("https://i.chaoxing.com/base"),
    );
    const notice = cookieHeaderForChaoxingUri(
      store,
      new URL("https://notice.chaoxing.com/pc/notice/myNotice"),
    );
    assert.match(home, /host_route=i-only/);
    assert.match(home, /global_route=global/);
    assert.doesNotMatch(notice, /host_route/);
    assert.match(notice, /global_route=global/);
  });

  test("uses the response request directory as the default cookie path", () => {
    const store = mergeChaoxingResponseCookies(
      "",
      new URL("https://mooc1.chaoxing.com/account/login"),
      "scoped=ready; HttpOnly",
    );
    assert.match(
      cookieHeaderForChaoxingUri(
        store,
        new URL("https://mooc1.chaoxing.com/account/home"),
      ),
      /scoped=ready/,
    );
    assert.doesNotMatch(
      cookieHeaderForChaoxingUri(store, new URL("https://mooc1.chaoxing.com/work")),
      /scoped/,
    );
    assert.doesNotMatch(
      cookieHeaderForChaoxingUri(
        store,
        new URL("https://mooc1.chaoxing.com/accounting"),
      ),
      /scoped/,
    );
  });

  test("deletes expired response cookies and exposes values for redaction", () => {
    const initial = encodeChaoxingCookieStore([
      {
        name: "route",
        value: "old-secret",
        domain: "i.chaoxing.com",
        path: "/",
        secure: true,
        hostOnly: true,
      },
    ]);
    const updated = mergeChaoxingResponseCookies(
      initial,
      new URL("https://i.chaoxing.com/base"),
      "route=expired-secret; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/",
    );
    assert.doesNotMatch(
      cookieHeaderForChaoxingUri(updated, new URL("https://i.chaoxing.com/base")),
      /route=/,
    );
    assert.ok(chaoxingCookieSecrets(initial).includes("old-secret"));
    assert.doesNotMatch(
      redactSensitiveText("request failed for old-secret", chaoxingCookieSecrets(initial)),
      /old-secret/,
    );
    const maxAgeDeleted = mergeChaoxingResponseCookies(
      initial,
      new URL("https://i.chaoxing.com/base"),
      "route=next-secret; Max-Age=-1; Path=/",
    );
    assert.doesNotMatch(
      cookieHeaderForChaoxingUri(
        maxAgeDeleted,
        new URL("https://i.chaoxing.com/base"),
      ),
      /route=/,
    );
  });

  test("keeps legacy headers compatible and ignores login-host cookies", () => {
    const legacy = "UID=1; vc3=secret";
    assert.match(
      cookieHeaderForChaoxingUri(
        legacy,
        new URL("https://notice.chaoxing.com/pc/notice/myNotice"),
      ),
      /UID=1/,
    );
    assert.equal(
      cookieHeaderForChaoxingUri(
        legacy,
        new URL("https://PASSPORT2.CHAOXING.COM/login"),
      ),
      "",
    );
    assert.equal(
      mergeChaoxingResponseCookies(
        legacy,
        new URL("https://passport2.chaoxing.com/login"),
        "login_route=should-not-store; Path=/",
      ),
      legacy,
    );
    assert.equal(hasChaoxingIdentityCookieSource(legacy), true);
  });
});
