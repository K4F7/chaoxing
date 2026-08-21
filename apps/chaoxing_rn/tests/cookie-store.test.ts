import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  androidCookiesToLegacyHeader,
  cookieHeaderForChaoxingUri,
  decodeChaoxingCookieStore,
  encodeAndroidCookieSource,
  encodeChaoxingCookieStore,
  hasChaoxingIdentityCookieSource,
  isSafeChaoxingCookieSource,
  parseManualCookieInput,
  UNSAFE_COOKIE_MESSAGE,
} from "../src/auth/cookie-store";

describe("cookie store", () => {
  test("rejects an entire cookie source containing newline injection", () => {
    const injected = "UID=1; route=ok\r\nX-Evil: injected";

    assert.equal(isSafeChaoxingCookieSource(injected), false);
    assert.equal(hasChaoxingIdentityCookieSource(injected), false);
    assert.equal(
      cookieHeaderForChaoxingUri(injected, "https://i.chaoxing.com/base"),
      "",
    );
    assert.throws(() => parseManualCookieInput(injected), {
      message: UNSAFE_COOKIE_MESSAGE,
    });
  });

  test("recognizes only supported 学习通 identity cookies", () => {
    assert.equal(hasChaoxingIdentityCookieSource("route=abc; vc3=secret"), true);
    assert.equal(hasChaoxingIdentityCookieSource("route=abc; theme=dark"), false);
  });

  test("keeps legacy headers compatible and ignores login-host cookies", () => {
    const legacy = "UID=1; vc3=secret";
    assert.match(
      cookieHeaderForChaoxingUri(
        legacy,
        "https://notice.chaoxing.com/pc/notice/myNotice",
      ),
      /UID=1/,
    );
    assert.equal(
      cookieHeaderForChaoxingUri(legacy, "https://PASSPORT2.CHAOXING.COM/login"),
      "",
    );
  });

  test("android cookies without secure or host-only still encode and scope", () => {
    const source = encodeAndroidCookieSource([
      { name: "UID", value: "42", domain: ".chaoxing.com", path: "/" },
      { name: "i_route", value: "i-only", domain: "i.chaoxing.com", path: "/" },
      {
        name: "notice_route",
        value: "notice-only",
        domain: "notice.chaoxing.com",
        path: "/",
      },
      { name: "foreign", value: "nope", domain: "example.com", path: "/" },
      { name: "bad", value: "line\nbreak", domain: ".chaoxing.com", path: "/" },
    ]);

    const records = decodeChaoxingCookieStore(source);
    assert.ok(records);
    assert.equal(
      records.some((cookie) => cookie.name === "foreign" || cookie.name === "bad"),
      false,
    );
    assert.equal(
      records.every((cookie) => cookie.secure === true && cookie.hostOnly === false),
      true,
    );
    assert.equal(hasChaoxingIdentityCookieSource(source), true);

    const home = cookieHeaderForChaoxingUri(source, "https://i.chaoxing.com/base");
    const notice = cookieHeaderForChaoxingUri(
      source,
      "https://notice.chaoxing.com/pc/notice/myNotice",
    );
    assert.match(home, /UID=42/);
    assert.match(home, /i_route=i-only/);
    assert.equal(home.includes("notice_route"), false);
    assert.match(notice, /UID=42/);
    assert.match(notice, /notice_route=notice-only/);
    assert.equal(notice.includes("i_route"), false);
  });

  test("android cookies also work on the flat header compatibility path", () => {
    const header = androidCookiesToLegacyHeader([
      { name: "UID", value: "42", domain: ".chaoxing.com" },
      { name: "UID", value: "host-specific", domain: "i.chaoxing.com", path: "/base" },
      { name: "vc3", value: "secret=value", domain: ".chaoxing.com" },
      { name: "foreign", value: "nope", domain: "example.com" },
    ]);

    assert.equal(header.includes("UID=42"), true);
    assert.equal(header.includes("UID=host-specific"), false);
    assert.equal(header.includes("vc3=secret=value"), true);
    assert.equal(header.includes("foreign"), false);
    assert.equal(hasChaoxingIdentityCookieSource(header), true);
    assert.match(
      cookieHeaderForChaoxingUri(header, "https://mooc1.chaoxing.com/work"),
      /UID=42/,
    );
  });

  test("decodes structured records that omit secure and hostOnly flags", () => {
    const source = JSON.stringify({
      format: "chaoxing-cookie-store-v1",
      cookies: [{ name: "UID", value: "1", domain: "chaoxing.com", path: "/" }],
    });
    const records = decodeChaoxingCookieStore(source);
    assert.deepEqual(records, [
      {
        name: "UID",
        value: "1",
        domain: "chaoxing.com",
        path: "/",
        secure: true,
        hostOnly: false,
      },
    ]);
    assert.equal(
      encodeChaoxingCookieStore(records ?? []).includes("chaoxing-cookie-store-v1"),
      true,
    );
  });
});
