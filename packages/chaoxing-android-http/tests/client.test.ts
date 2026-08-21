import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  createCookieManagerJar,
  createFetchHttpClient,
  createNativeHttpClient,
  createProductionHttpClient,
  type FetchLike,
  type NativeHttpModule,
} from "../src/index";

describe("android cookie-aware HTTP", () => {
  test("native send exposes Set-Cookie that fetch would hide", async () => {
    const native: NativeHttpModule = {
      async send() {
        return {
          status: 200,
          url: "https://i.chaoxing.com/",
          headers: {
            "set-cookie": "vc3=from-okhttp; Domain=chaoxing.com; Path=/",
          },
          body: "ok",
        };
      },
    };
    const response = await createNativeHttpClient(native).send({
      method: "GET",
      url: "https://i.chaoxing.com/",
      headers: {},
    });
    assert.equal(
      response.headers["set-cookie"],
      "vc3=from-okhttp; Domain=chaoxing.com; Path=/",
    );
  });

  test("production client persists rotated cookies from the native jar", async () => {
    let source = "UID=1; vc3=old";
    const native: NativeHttpModule = {
      async send() {
        return {
          status: 200,
          url: "https://i.chaoxing.com/",
          headers: {},
          body: "ok",
        };
      },
      snapshotCookies() {
        return "UID=1; vc3=rotated";
      },
    };
    const client = createProductionHttpClient({
      session: {
        getSource: () => source,
        persist(next) {
          source = next;
        },
      },
      fetchImpl: async () => {
        throw new Error("fetch should not run when native is present");
      },
      userAgent: "test",
      native,
    });
    await client.send({
      method: "GET",
      url: "https://i.chaoxing.com/",
      headers: {},
    });
    assert.match(
      source.includes("rotated") ? "rotated" : source,
      /rotated/,
    );
  });

  test("fetch fallback records getSetCookie", async () => {
    const fetchImpl: FetchLike = async () => ({
      status: 200,
      url: "https://i.chaoxing.com/",
      headers: {
        get() {
          return null;
        },
        getSetCookie() {
          return ["a=1; Path=/"];
        },
      },
      async text() {
        return "ok";
      },
    });
    const response = await createFetchHttpClient(fetchImpl, "ua").send({
      method: "GET",
      url: "https://i.chaoxing.com/",
      headers: {},
    });
    assert.equal(response.headers["set-cookie"], "a=1; Path=/");
  });

  test("cookie manager snapshot formats a Cookie header as Set-Cookie lines", async () => {
    const jar = createCookieManagerJar({
      snapshotCookies: () => "UID=1; vc3=x",
    });
    assert.equal(await jar?.snapshot("https://i.chaoxing.com/"), "UID=1; Path=/, vc3=x; Path=/");
  });
});
