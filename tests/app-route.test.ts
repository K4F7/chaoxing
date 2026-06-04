import { afterEach, describe, expect, test } from "bun:test";

import worker from "../src/index";

const originalFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = originalFetch;
});

describe("app sync route", () => {
  test("rejects requests without the run token", async () => {
    const response = await worker.fetch(
      new Request("https://worker.example.com/app/sync"),
      { RUN_TOKEN: "secret", CHAOXING_COOKIE: "UID=1" },
    );

    expect(response.status).toBe(401);
    const payload = (await response.json()) as unknown;
    expect(payload).toEqual({ error: "unauthorized" });
  });

  test("returns compact app sync payload for authenticated clients", async () => {
    globalThis.fetch = mockChaoxingFetch as typeof fetch;

    const response = await worker.fetch(
      new Request("https://worker.example.com/app/sync", {
        headers: { Authorization: "Bearer secret" },
      }),
      { RUN_TOKEN: "secret", CHAOXING_COOKIE: "UID=1" },
    );
    const payload = (await response.json()) as {
      authStatus?: string;
      items?: unknown[];
      lastSyncedAt?: string;
      failures?: unknown[];
    };

    expect(response.status).toBe(200);
    expect(payload.authStatus).toBe("ok");
    expect(payload.lastSyncedAt).toEqual(expect.any(String));
    expect(payload.failures).toEqual([]);
    expect(payload.items).toEqual([
      expect.objectContaining({
        id: "assignment-1",
        kind: "assignment",
        title: "作业通知",
        dueAt: "2026-06-05T15:59:00.000Z",
        displayStatus: expect.any(String),
        dueInHours: expect.any(Number),
      }),
    ]);
  });
});

async function mockChaoxingFetch(
  input: string | URL | Request,
  init?: RequestInit,
): Promise<Response> {
  const url = String(input);

  if (url.startsWith("https://i.chaoxing.com/base")) {
    return new Response("https://notice.chaoxing.com/pc/notice/myNotice?s=abc123", {
      headers: { "Content-Type": "text/html" },
    });
  }

  if (url.startsWith("https://notice.chaoxing.com/pc/notice/myNotice")) {
    return new Response("window.nowYear='2026';", {
      headers: { "Content-Type": "text/html" },
    });
  }

  if (url.endsWith("/pc/notice/getNoticeList")) {
    return Response.json({
      status: true,
      notices: {
        list: [
          {
            id: "notice-1",
            title: "作业通知",
            sendTime: "2026-06-01 08:00:00",
            isread: 0,
            content: "请完成作业",
            sendTag: 0,
          },
        ],
        lastPage: true,
      },
    });
  }

  if (url.includes("/getNoticeDetail")) {
    return Response.json({
      status: true,
      msg: {
        title: "作业通知",
        rtf_content: "https://mooc1.chaoxing.com/work?workOrExam=work&workId=1",
      },
    });
  }

  if (url.startsWith("https://mooc1.chaoxing.com/work")) {
    return new Response(
      `<title>作业作答</title>
      <input id="workId" value="1" />
      作答时间:<em>2026-06-01 08:00:00</em>至<em>2026-06-05 23:59:00</em>`,
      { status: init?.redirect === "follow" ? 200 : 302 },
    );
  }

  return new Response("not found", { status: 404 });
}
