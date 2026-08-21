import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  parseDisplayStatus,
  parseDueAt,
  parseSyncItemKind,
  SyncDisplayStatus,
  SyncItemKind,
  syncItemFromJson,
} from "../src/index";

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

  test("parses app sync item with missing optional fields", () => {
    const item = syncItemFromJson({
      id: "assignment-1",
      kind: "assignment",
      title: "线性代数作业",
      url: "https://example.com/work",
      sourceTitle: "作业通知",
      status: "answering",
      displayStatus: "today",
      dueAt: "2026-06-05T15:59:00.000Z",
      dueInHours: 3,
    });
    assert.equal(item.kind, SyncItemKind.assignment);
    assert.equal(item.displayStatus, SyncDisplayStatus.today);
    assert.ok(item.dueAt);
    assert.equal(item.courseId, null);
    assert.equal(item.examId, null);
    assert.deepEqual(item.sources, []);
    assert.equal(parseDisplayStatus("upcoming"), SyncDisplayStatus.upcoming);
    assert.equal(parseDisplayStatus("other"), SyncDisplayStatus.unscheduled);
  });
});
