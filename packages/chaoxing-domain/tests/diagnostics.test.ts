import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { buildAppSyncResponse, emptySyncStats } from "../src/app-sync";
import { buildDiagnosticsReport } from "../src/diagnostics";
import { SyncItemKind } from "../src/sync-item";

describe("buildDiagnosticsReport", () => {
  test("redacts Cookie values and never echoes the raw source", () => {
    const cookie = "UID=super-secret-uid; vc3=token-value";
    const report = buildDiagnosticsReport({
      cookieSource: cookie,
      generatedAt: new Date("2026-08-21T04:00:00.000Z"),
      lastError: "probe failed Cookie: UID=super-secret-uid",
      sync: buildAppSyncResponse({
        now: new Date("2026-08-21T04:00:00.000Z"),
        lastSyncedAt: new Date("2026-08-21T04:00:00.000Z"),
        items: [
          {
            id: "work-1",
            kind: SyncItemKind.assignment,
            title: "作业",
            url: "https://mooc1.chaoxing.com/work?uid=1",
            sourceTitle: "收件箱",
            dueAt: new Date("2026-08-22T04:00:00.000Z"),
            displayStatus: "upcoming",
          },
        ],
        failures: [
          {
            entryUrl: "https://mooc1.chaoxing.com/work?uid=1&token=abc",
            sourceTitle: "Cookie: UID=super-secret-uid",
            message: "status 403 token=abc",
          },
        ],
        stats: { ...emptySyncStats, inboxMessages: 2 },
        seenNotices: [],
      }),
    });

    assert.match(report, /"hasCookie": true/);
    assert.match(report, /"failureCount": 1/);
    assert.doesNotMatch(report, /super-secret-uid/);
    assert.doesNotMatch(report, /token-value/);
    assert.doesNotMatch(report, /UID=super-secret-uid/);
    assert.match(report, /\[已隐藏\]/);
  });

  test("exports an empty report when nothing has synced yet", () => {
    const report = buildDiagnosticsReport({
      generatedAt: new Date("2026-08-21T04:00:00.000Z"),
    });
    assert.match(report, /"hasCookie": false/);
    assert.match(report, /"itemCount": 0/);
    assert.match(report, /"failureCount": 0/);
  });
});
