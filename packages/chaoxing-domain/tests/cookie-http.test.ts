import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  collectSetCookieHeader,
  createCookieAwareHttpClient,
} from "../src/cookie-http";
import { cookieHeaderForChaoxingUri } from "../src/cookie";
import type { ChaoxingHttpClient } from "../src/http";

describe("cookie-aware Chaoxing HTTP client", () => {
  test("attaches vault cookies and persists Set-Cookie into the session", async () => {
    let source = "UID=1; vc3=old";
    const seen: string[] = [];
    const inner: ChaoxingHttpClient = {
      async send(request) {
        seen.push(request.headers.Cookie ?? "");
        return {
          status: 200,
          url: request.url,
          headers: {
            "set-cookie": "vc3=rotated; Domain=chaoxing.com; Path=/; Secure",
          },
          body: "<html>ok</html>",
        };
      },
    };

    const client = createCookieAwareHttpClient({
      inner,
      session: {
        getSource: () => source,
        persist(next) {
          source = next;
        },
      },
    });

    await client.send({
      method: "GET",
      url: "https://i.chaoxing.com/",
      headers: {},
    });

    assert.match(seen[0] ?? "", /UID=1/);
    assert.match(source, /vc3=rotated/);
    const header = cookieHeaderForChaoxingUri(
      source,
      new URL("https://i.chaoxing.com/"),
    );
    assert.match(header, /vc3=rotated/);
  });

  test("uses the native cookie jar when fetch hides Set-Cookie", async () => {
    let source = "UID=1; vc3=old";
    const inner: ChaoxingHttpClient = {
      async send(request) {
        return {
          status: 200,
          url: request.url,
          headers: {},
          body: "ok",
        };
      },
    };

    const client = createCookieAwareHttpClient({
      inner,
      session: {
        getSource: () => source,
        persist(next) {
          source = next;
        },
      },
      nativeJar: {
        snapshot() {
          return "session=native-jar; Domain=chaoxing.com; Path=/";
        },
      },
    });

    await client.send({
      method: "GET",
      url: "https://mooc1.chaoxing.com/work",
      headers: {},
    });

    assert.match(source, /session=native-jar/);
  });

  test("does not attach Cookie to untrusted hosts", async () => {
    const headers: Record<string, string>[] = [];
    const inner: ChaoxingHttpClient = {
      async send(request) {
        headers.push(request.headers);
        return {
          status: 200,
          url: request.url,
          headers: {},
          body: "",
        };
      },
    };
    await createCookieAwareHttpClient({
      inner,
      session: {
        getSource: () => "UID=1; vc3=secret",
        persist() {},
      },
    }).send({
      method: "GET",
      url: "https://evil.example/",
      headers: {},
    });
    assert.equal(headers[0]?.Cookie, undefined);
  });

  test("collectSetCookieHeader prefers getSetCookie()", () => {
    const header = collectSetCookieHeader({
      get() {
        return "ignored=1";
      },
      getSetCookie() {
        return ["a=1; Path=/", "b=2; Path=/"];
      },
    });
    assert.equal(header, "a=1; Path=/, b=2; Path=/");
  });
});
