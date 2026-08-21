import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { createFetchChaoxingClient, type FetchLike } from "../src/http/fetch-client";

describe("fetch Chaoxing HTTP client", () => {
  test("sends GET with manual redirects and records headers", async () => {
    const seen: Array<{ url: string; init: Parameters<FetchLike>[1] }> = [];
    const fetchImpl: FetchLike = async (url, init) => {
      seen.push({ url, init });
      return {
        status: 302,
        url,
        headers: {
          get(name) {
            return name.toLowerCase() === "location"
              ? "https://i.chaoxing.com/base"
              : null;
          },
        },
        async text() {
          return "";
        },
      };
    };

    const response = await createFetchChaoxingClient(fetchImpl).send({
      method: "GET",
      url: "https://i.chaoxing.com/",
      headers: { Cookie: "UID=1" },
    });

    assert.equal(seen[0]?.init.redirect, "manual");
    assert.equal(seen[0]?.init.headers.Cookie, "UID=1");
    assert.equal(response.status, 302);
    assert.equal(response.headers.location, "https://i.chaoxing.com/base");
  });

  test("posts form bodies as urlencoded", async () => {
    let body: string | undefined;
    const fetchImpl: FetchLike = async (_url, init) => {
      body = init.body;
      return {
        status: 200,
        headers: {
          get() {
            return null;
          },
        },
        async text() {
          return "<html></html>";
        },
      };
    };

    const response = await createFetchChaoxingClient(fetchImpl).send({
      method: "POST",
      url: "https://mooc1-1.chaoxing.com/mooc-ans/visit/courselistdata",
      headers: {},
      form: { courseType: "1", view: "json" },
    });

    assert.equal(body, "courseType=1&view=json");
    assert.equal(response.body, "<html></html>");
  });
});
