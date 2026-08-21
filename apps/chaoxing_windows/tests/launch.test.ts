import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { parseLaunchArguments, resolveLaunch } from "../src/launch";

describe("Windows launch", () => {
  test("second instance is rejected", () => {
    assert.equal(parseLaunchArguments(["--hidden"]).hidden, true);
    const first = resolveLaunch({ argv: ["--hidden"], tryAcquire: () => true });
    assert.equal(first.alreadyRunning, false);
    const second = resolveLaunch({ argv: [], tryAcquire: () => false });
    assert.equal(second.alreadyRunning, true);
  });
});
