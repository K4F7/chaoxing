import { describe, expect, test } from "bun:test";

import { parseDevVars } from "../src/dev-vars";

describe("dev vars", () => {
  test("parses quoted and unquoted values", () => {
    expect(
      parseDevVars(`
# comment
CHAOXING_COOKIE="UID=1; route=abc"
RUN_TOKEN=plain-token
`),
    ).toEqual({
      CHAOXING_COOKIE: "UID=1; route=abc",
      RUN_TOKEN: "plain-token",
    });
  });
});
