import { describe, expect, test } from "bun:test";

import {
  buildGoogleCalendarEvent,
  refreshGoogleOAuthAccessToken,
  syncGoogleCalendar,
} from "../src/google-calendar";
import type { SyncItem } from "../src/sync";

describe("google calendar sync", () => {
  test("builds google calendar event payloads with deterministic ids", async () => {
    const event = await buildGoogleCalendarEvent(syncItem());

    expect(event.id).toMatch(/^cx[0-9a-f]{64}$/);
    expect(event.summary).toBe("作业截止：作业通知");
    expect(event.start).toEqual({
      dateTime: "2026-06-05T15:59:00.000Z",
      timeZone: "Asia/Shanghai",
    });
    expect(event.extendedProperties.private.chaoxingItemId).toBe("assignment-123");
  });

  test("updates existing events and inserts missing events", async () => {
    const calls: { url: string; method: string }[] = [];
    const fetcher = async (input: string | URL | Request, init?: RequestInit) => {
      const url = String(input);
      const method = init?.method || "GET";
      calls.push({ url, method });

      if (method === "PUT") {
        return new Response("not found", { status: 404 });
      }

      return Response.json({ id: "created" });
    };

    const result = await syncGoogleCalendar(
      [syncItem()],
      {
        calendarId: "calendar@example.com",
        serviceAccountEmail: "service@example.iam.gserviceaccount.com",
        privateKey: "unused in test",
      },
      {
        fetcher: fetcher as unknown as typeof fetch,
        accessToken: "token",
      },
    );

    expect(result).toEqual({
      calendarId: "calendar@example.com",
      attempted: 1,
      created: 1,
      updated: 0,
      skipped: 0,
      failed: [],
    });
    expect(calls.map((call) => call.method)).toEqual(["PUT", "POST"]);
    expect(calls[0].url).toContain("/calendars/calendar%40example.com/events/");
  });

  test("refreshes oauth access tokens", async () => {
    const fetcher = async (_input: string | URL | Request, init?: RequestInit) => {
      expect(String(init?.body)).toContain("grant_type=refresh_token");
      return Response.json({ access_token: "access-token" });
    };

    await expect(
      refreshGoogleOAuthAccessToken(
        {
          calendarId: "primary",
          oauthClientId: "client",
          oauthClientSecret: "secret",
          oauthRefreshToken: "refresh",
        },
        { fetcher: fetcher as unknown as typeof fetch },
      ),
    ).resolves.toBe("access-token");
  });
});

function syncItem(overrides: Partial<SyncItem> = {}): SyncItem {
  return {
    id: "assignment-123",
    kind: "assignment",
    title: "作业通知",
    url: "https://mooc1.chaoxing.com/work?workId=123",
    sourceTitle: "作业通知",
    sourceSendTime: "2026-06-01 08:00:00",
    startAt: "2026-06-01T00:00:00.000Z",
    dueAt: "2026-06-05T15:59:00.000Z",
    status: "answering",
    courseId: "1",
    classId: "2",
    workId: "123",
    answerId: null,
    ...overrides,
  };
}
