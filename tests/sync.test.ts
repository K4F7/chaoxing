import { describe, expect, test } from "bun:test";

import { buildCalendarIcs, buildSyncItems, buildTodoIcs } from "../src/sync";
import type { AssignmentRequirement } from "../src/requirements";

describe("sync exports", () => {
  test("builds sync items from chaoxing assignment times", () => {
    const items = buildSyncItems(
      [
        requirement({
          sourceTitle: "作业通知",
          sourceSendTime: "2026-05-31 12:00:06",
          timeWindow: { start: "05-31 12:00", end: "06-05 23:59" },
          workId: "123",
        }),
      ],
      { generatedAt: new Date("2026-06-01T00:00:00Z") },
    );

    expect(items).toEqual([
      expect.objectContaining({
        id: "assignment-123",
        kind: "assignment",
        title: "作业通知",
        startAt: "2026-05-31T04:00:00.000Z",
        dueAt: "2026-06-05T15:59:00.000Z",
      }),
    ]);
  });

  test("builds calendar and todo ics output", () => {
    const items = buildSyncItems([
      requirement({
        sourceTitle: "考试通知",
        entryUrl: "https://mooc1.chaoxing.com/exam?workOrExam=exam&examId=9",
        finalUrl: "https://mooc1.chaoxing.com/exam?workOrExam=exam&examId=9",
        timeWindow: {
          start: "2026-06-01 09:00:00",
          end: "2026-06-01 10:00:00",
        },
      }),
    ]);

    const calendar = buildCalendarIcs(items, {
      generatedAt: new Date("2026-06-01T00:00:00Z"),
    });
    const todos = buildTodoIcs(items, {
      generatedAt: new Date("2026-06-01T00:00:00Z"),
    });

    expect(calendar).toContain("BEGIN:VEVENT");
    expect(calendar).toContain("SUMMARY:考试截止");
    expect(todos).toContain("BEGIN:VTODO");
    expect(todos).toContain("DUE:20260601T020000Z");
  });
});

function requirement(
  overrides: Partial<AssignmentRequirement> = {},
): AssignmentRequirement {
  return {
    sourceTitle: "作业",
    sourceSendTime: null,
    sourceContent: null,
    entryUrl: "https://mooc1.chaoxing.com/work?workOrExam=work&workId=1",
    finalUrl: "https://mooc1.chaoxing.com/work?workOrExam=work&workId=1",
    pageTitle: "作业作答",
    status: 200,
    courseId: null,
    classId: null,
    workId: "1",
    answerId: null,
    workStatus: "answering",
    timeWindow: { start: null, end: "2026-06-05 23:59:00" },
    prompt: null,
    questions: [],
    ...overrides,
  };
}
