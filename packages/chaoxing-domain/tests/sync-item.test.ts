import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { parseDueAt, parseSyncItemKind, SyncItemKind } from "../src/index";

describe("sync item parsing", () => {
  test("defaults unknown kinds to assignment", () => {
    assert.equal(parseSyncItemKind("exam"), SyncItemKind.exam);
    assert.equal(parseSyncItemKind("assignment"), SyncItemKind.assignment);
    assert.equal(parseSyncItemKind("other"), SyncItemKind.assignment);
  });

  test("parses due times and rejects empty values", () => {
    const dueAt = parseDueAt("2026-07-28T10:00:00+08:00");
    assert.ok(dueAt);
    assert.equal(dueAt.getTime(), Date.parse("2026-07-28T10:00:00+08:00"));
    assert.equal(parseDueAt(""), null);
    assert.equal(parseDueAt(null), null);
  });
});
