import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  appSyncResponseFromJson,
  appSyncResponseToJson,
  buildAppSyncResponse,
  emptySyncStats,
  isRateLimited,
  maxSeenNotices,
  SyncDisplayStatus,
  SyncItemKind,
  type AppSyncFailure,
  type SeenNotice,
  type SyncItem,
} from "../src/index";

function item(input: {
  id: string;
  title: string;
  dueAt: string | null;
  sources?: readonly string[];
  status?: string;
  url?: string;
  sourceTitle?: string;
  sourceSendTime?: string;
  workId?: string;
}): SyncItem {
  return {
    id: input.id,
    kind: SyncItemKind.assignment,
    title: input.title,
    url: input.url ?? `https://mooc1.chaoxing.com/work?workId=${input.id}`,
    sourceTitle: input.sourceTitle ?? "通知",
    sourceSendTime: input.sourceSendTime,
    status: input.status ?? "answering",
    displayStatus: SyncDisplayStatus.unscheduled,
    dueAt: input.dueAt === null ? null : new Date(input.dueAt),
    workId: input.workId,
    sources: input.sources ?? [],
  };
}

describe("同步结果模型", () => {
  test("detects rate limiting from sanitized failure messages", () => {
    const limited = buildAppSyncResponse({
      now: new Date("2026-07-16T00:00:00+08:00"),
      lastSyncedAt: new Date("2026-07-16T00:00:00+08:00"),
      items: [],
      failures: [
        {
          entryUrl: "",
          sourceTitle: "",
          message: "任务列表抓取失败 (429)",
        },
      ],
    });
    assert.equal(isRateLimited(limited), true);
    assert.equal(
      isRateLimited(
        buildAppSyncResponse({
          now: new Date("2026-07-16T00:00:00+08:00"),
          lastSyncedAt: new Date("2026-07-16T00:00:00+08:00"),
          items: [],
          failures: [],
        }),
      ),
      false,
    );
  });

  test("sorts items and derives display status with due hours", () => {
    const response = buildAppSyncResponse({
      now: new Date("2026-06-05T09:00:00+08:00"),
      lastSyncedAt: new Date("2026-06-05T09:00:00+08:00"),
      failures: [],
      items: [
        item({ id: "unscheduled", title: "无截止", dueAt: null }),
        item({ id: "later", title: "明天考试", dueAt: "2026-06-06T10:00:00+08:00" }),
        item({ id: "overdue", title: "已过期", dueAt: "2026-06-05T08:00:00+08:00" }),
        item({ id: "today", title: "今天作业", dueAt: "2026-06-05T23:59:00+08:00" }),
      ],
    });

    assert.deepEqual(
      response.items.map((value) => value.id),
      ["overdue", "today", "later", "unscheduled"],
    );
    assert.equal(response.items[0].displayStatus, SyncDisplayStatus.overdue);
    assert.equal(response.items[0].dueInHours, -1);
    assert.equal(response.items[1].displayStatus, SyncDisplayStatus.today);
    assert.equal(response.items[1].dueInHours, 15);
    assert.equal(response.items[2].displayStatus, SyncDisplayStatus.upcoming);
    assert.equal(response.items[2].dueInHours, 25);
    assert.equal(response.items[3].displayStatus, SyncDisplayStatus.unscheduled);
    assert.equal(response.items[3].dueInHours, null);
  });

  test("redacts sensitive failure fields before cache serialization", () => {
    const failure: AppSyncFailure = {
      entryUrl:
        "https://mooc1.chaoxing.com/work?workId=1&token=url-secret&uid=42",
      sourceTitle: "作业 account=student-42",
      message: "Authorization: Bearer bearer-secret",
    };
    const json = JSON.stringify(
      buildAppSyncResponse({
        now: new Date("2026-07-16T00:00:00+08:00"),
        lastSyncedAt: new Date("2026-07-16T00:00:00+08:00"),
        items: [],
        failures: [failure],
      }).failures[0],
    );

    assert.match(json, /workId=1/);
    assert.doesNotMatch(json, /url-secret/);
    assert.doesNotMatch(json, /student-42/);
    assert.doesNotMatch(json, /bearer-secret/);
  });

  test("sorts concurrent failures deterministically", () => {
    const now = new Date("2026-07-16T00:00:00+08:00");
    const failures: AppSyncFailure[] = [
      {
        entryUrl: "https://mooc1.chaoxing.com/work?workId=2",
        sourceTitle: "课程二",
        message: "失败二",
      },
      {
        entryUrl: "https://mooc1.chaoxing.com/work?workId=1",
        sourceTitle: "课程一",
        message: "失败一",
      },
    ];
    const left = appSyncResponseToJson(
      buildAppSyncResponse({ now, lastSyncedAt: now, items: [], failures }),
    );
    const right = appSyncResponseToJson(
      buildAppSyncResponse({
        now,
        lastSyncedAt: now,
        items: [],
        failures: [...failures].reverse(),
      }),
    );
    assert.deepEqual(left, right);
  });

  test("merges the same business item and unions its sources", () => {
    const now = new Date("2026-06-05T09:00:00+08:00");
    const response = buildAppSyncResponse({
      now,
      lastSyncedAt: now,
      failures: [],
      items: [
        item({
          id: "assignment-42",
          title: "作业通知",
          dueAt: "2026-06-06T10:00:00+08:00",
          url: "https://mooc1.chaoxing.com/work?workId=42",
          sourceTitle: "作业通知",
          status: "unknown",
          workId: "42",
          sources: ["inbox"],
        }),
        item({
          id: "assignment-42",
          title: "高等数学第一次作业",
          dueAt: "2026-06-06T10:00:00+08:00",
          url: "https://mooc1-api.chaoxing.com/work?workId=42",
          sourceTitle: "高等数学",
          status: "answering",
          workId: "42",
          sources: ["course_work"],
        }),
      ],
    });

    assert.equal(response.items.length, 1);
    assert.equal(response.items[0].title, "高等数学第一次作业");
    assert.deepEqual(response.items[0].sources, ["course_work", "inbox"]);
  });

  test("merging duplicate items is independent of completion order", () => {
    const now = new Date("2026-06-05T09:00:00+08:00");
    const inbox = item({
      id: "assignment-42",
      title: "通知标题甲",
      dueAt: "2026-06-07T10:00:00+08:00",
      url: "https://mooc1.chaoxing.com/work?workId=42",
      sourceTitle: "课程甲",
      sourceSendTime: "2026-06-01 08:00:00",
      status: "unknown",
      workId: "42",
      sources: ["inbox"],
    });
    const course = item({
      id: "assignment-42",
      title: "课程标题乙",
      dueAt: "2026-06-06T10:00:00+08:00",
      url: "https://mooc1-api.chaoxing.com/work?workId=42",
      sourceTitle: "课程乙",
      status: "answering",
      workId: "42",
      sources: ["course_work"],
    });
    const left = appSyncResponseToJson(
      buildAppSyncResponse({ now, lastSyncedAt: now, failures: [], items: [inbox, course] }),
    );
    const right = appSyncResponseToJson(
      buildAppSyncResponse({ now, lastSyncedAt: now, failures: [], items: [course, inbox] }),
    );
    assert.deepEqual(left, right);
    assert.equal(
      buildAppSyncResponse({ now, lastSyncedAt: now, failures: [], items: [inbox, course] })
        .items[0].dueAt?.getTime(),
      course.dueAt?.getTime(),
    );
  });

  test("round-trips sync stage statistics and seen notices", () => {
    const seen: SeenNotice[] = [
      {
        id: "notice-1",
        detailParsed: true,
        sendTag: 7,
        title: "高等数学作业通知",
        sendTime: "2025-12-01 00:30:00",
        content: "结束时间：06-20 23:59",
        taskLinks: ["https://mooc1.chaoxing.com/work?workId=1"],
      },
      {
        id: "notice-2",
        detailParsed: false,
        title: "",
        sendTime: null,
        content: null,
        taskLinks: [],
      },
    ];
    const response = {
      lastSyncedAt: new Date("2026-07-16T12:00:00+08:00"),
      authStatus: "ok",
      items: [],
      failures: [],
      stats: {
        ...emptySyncStats,
        durationMs: 1234,
        authenticationMs: 100,
        inboxMs: 200,
        noticeDetailsMs: 300,
        assignmentDetailsMs: 400,
        coursesMs: 234,
        inboxMessages: 12,
        relevantNotices: 4,
        detailSummaries: 3,
        inboxTaskLinks: 5,
        inboxTaskDetails: 4,
        statusFilteredItems: 1,
        courses: 6,
        courseTaskLinksDiscovered: 10,
        courseTaskLinks: 7,
        courseTaskStatusFiltered: 3,
        itemCandidates: 8,
        courseSourcesEnabled: true,
      },
      seenNotices: seen,
    };
    const restored = appSyncResponseFromJson(appSyncResponseToJson(response));
    assert.equal(restored.stats.inboxMessages, 12);
    assert.equal(restored.stats.courseSourcesEnabled, true);
    assert.deepEqual(
      restored.seenNotices.map((notice) => notice.id),
      ["notice-1", "notice-2"],
    );
    assert.equal(restored.seenNotices[0].detailParsed, true);
    assert.equal(restored.seenNotices[0].sendTag, 7);
    assert.deepEqual(restored.seenNotices[0].taskLinks, [
      "https://mooc1.chaoxing.com/work?workId=1",
    ]);
  });

  test("an older cache without seen notices restores with none seen", () => {
    const restored = appSyncResponseFromJson({
      lastSyncedAt: "2026-07-16T12:00:00.000",
      authStatus: "ok",
      items: [],
      failures: [],
    });
    assert.deepEqual(restored.seenNotices, []);
  });

  test("bounds seen notices and keeps the most recent ones", () => {
    const response = buildAppSyncResponse({
      now: new Date("2026-07-16T00:00:00+08:00"),
      lastSyncedAt: new Date("2026-07-16T00:00:00+08:00"),
      items: [],
      failures: [],
      seenNotices: [
        ...Array.from({ length: maxSeenNotices + 20 }, (_, index) => ({
          id: `notice-${index}`,
          detailParsed: false,
          title: "",
          sendTime: null,
          content: null,
          taskLinks: [],
        })),
        {
          id: "notice-0",
          detailParsed: true,
          title: "",
          sendTime: null,
          content: null,
          taskLinks: [],
        },
        {
          id: "",
          detailParsed: false,
          title: "",
          sendTime: null,
          content: null,
          taskLinks: [],
        },
      ],
    });
    assert.equal(response.seenNotices.length, maxSeenNotices);
    assert.equal(response.seenNotices[0].id, "notice-0");
    assert.equal(response.seenNotices.at(-1)?.id, `notice-${maxSeenNotices - 1}`);
    assert.equal(
      response.seenNotices.some((notice) => notice.id.length === 0),
      false,
    );
  });
});
