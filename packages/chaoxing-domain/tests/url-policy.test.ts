import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  isTrustedChaoxingCookieDomain,
  isTrustedChaoxingUrl,
} from "../src/index";

describe("URL 信任分级", () => {
  test("allows explicit https chaoxing request hosts", () => {
    assert.equal(isTrustedChaoxingUrl("https://mooc1.chaoxing.com/work"), true);
    assert.equal(
      isTrustedChaoxingUrl("https://mooc1-12.chaoxing.com/work"),
      true,
    );
    assert.equal(
      isTrustedChaoxingUrl("https://passport2.chaoxing.com/login"),
      true,
    );
  });

  test("rejects arbitrary chaoxing subdomains and cleartext", () => {
    assert.equal(isTrustedChaoxingUrl("https://evil.chaoxing.com/work"), false);
    assert.equal(isTrustedChaoxingUrl("http://mooc1.chaoxing.com/work"), false);
    assert.equal(isTrustedChaoxingUrl("https://example.com/work"), false);
    assert.equal(isTrustedChaoxingUrl("not a url"), false);
  });

  test("allows the root cookie domain without trusting it as a request host", () => {
    assert.equal(isTrustedChaoxingCookieDomain("chaoxing.com"), true);
    assert.equal(isTrustedChaoxingCookieDomain(".Chaoxing.com"), true);
    assert.equal(isTrustedChaoxingUrl("https://chaoxing.com/"), false);
  });
});
