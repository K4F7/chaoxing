import { describe, expect, test } from "bun:test";

import { buildAppSyncResponse } from "../src/app-sync";
import type { ProcessingResult } from "../src/processor";
import type { SyncItem } from "../src/sync";

describe("app sync response", () => {
  test("maps processing results to a compact app response", () => {
    const response = buildAppSyncResponse(
      processingResult({
        failedRequirements: [
          {
            entryUrl: "https://example.com/fail",
            sourceTitle: "失败通知",
            message: "assignment_fetch_failed_500",
          },
        ],
      }),
      [
        syncItem({
          id: "assignment-later",
          title: "后截止",
          dueAt: "2026-06-06T10:00:00.000Z",
        }),
        syncItem({
          id: "exam-soon",
          kind: "exam",
          title: "先截止",
          dueAt: "2026-06-05T10:00:00.000Z",
        }),
      ],
      { now: new Date("2026-06-05T09:00:00.000Z") },
    );

    expect(response).toEqual({
      lastSyncedAt: "2026-06-05T08:00:00.000Z",
      authStatus: "ok",
      items: [
        expect.objectContaining({
          id: "exam-soon",
          kind: "exam",
          displayStatus: "today",
          dueInHours: 1,
        }),
        expect.objectContaining({
          id: "assignment-later",
          displayStatus: "upcoming",
          dueInHours: 25,
        }),
      ],
      failures: [
        {
          entryUrl: "https://example.com/fail",
          sourceTitle: "失败通知",
          message: "assignment_fetch_failed_500",
        },
      ],
      meta: {
        inbox: {
          fetched: 3,
          relevant: 2,
          inspectedDetails: 2,
        },
        fetchedRequirements: 2,
        totalUniqueActivityLinks: 2,
        totalUniqueWorkLinks: 2,
      },
    });
  });

  test("marks overdue items for app grouping", () => {
    const response = buildAppSyncResponse(
      processingResult(),
      [
        syncItem({
          id: "assignment-overdue",
          dueAt: "2026-06-05T08:00:00.000Z",
        }),
      ],
      { now: new Date("2026-06-05T09:00:00.000Z") },
    );

    expect(response.items[0]).toEqual(
      expect.objectContaining({
        displayStatus: "overdue",
        dueInHours: -1,
      }),
    );
  });
});

function processingResult(
  overrides: Partial<ProcessingResult> = {},
): ProcessingResult {
  return {
    processedAt: "2026-06-05T08:00:00.000Z",
    inbox: {
      fetched: 3,
      relevant: 2,
      inspectedDetails: 2,
    },
    totalUniqueActivityLinks: 2,
    totalUniqueWorkLinks: 2,
    fetchedRequirements: 2,
    failedRequirements: [],
    requirements: [],
    ...overrides,
  };
}

function syncItem(overrides: Partial<SyncItem> = {}): SyncItem {
  return {
    id: "assignment-1",
    kind: "assignment",
    title: "作业",
    url: "https://mooc1.chaoxing.com/work?workId=1",
    sourceTitle: "作业通知",
    sourceSendTime: "2026-06-01 08:00:00",
    startAt: null,
    dueAt: "2026-06-05T10:00:00.000Z",
    status: "answering",
    courseId: null,
    classId: null,
    workId: "1",
    answerId: null,
    ...overrides,
  };
}
