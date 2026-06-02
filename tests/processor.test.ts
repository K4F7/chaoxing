import { describe, expect, test } from "bun:test";

import {
  collectUniqueWorkLinks,
  fetchDetailSummary,
  isAssignmentOrExamRelated,
  processAssignments,
  type DetailSummary,
} from "../src/processor";

describe("assignment processor", () => {
  test("detects assignment related inbox messages", () => {
    expect(
      isAssignmentOrExamRelated({
        id: "1",
        uuid: null,
        title: "作业截止提醒",
        sender: null,
        sendTime: null,
        isRead: false,
        content: null,
        detailUrl: null,
        sendTag: 0,
      }),
    ).toBe(true);
  });

  test("extracts unique work links from detail summaries", () => {
    const summary = {
      title: "作业",
      sendTime: null,
      detailStatus: 200,
      apiStatus: true,
      detailTitle: "作业",
      sourceType: null,
      content: null,
      assignmentLinks: [
        "https://mooc1.chaoxing.com/work?workOrExam=work&workId=1",
        "https://mooc1.chaoxing.com/work?workOrExam=work&workId=1",
        "https://mooc1.chaoxing.com/exam?workOrExam=exam&examId=2",
      ],
      decodedAttachments: [],
    } satisfies DetailSummary;

    expect([...collectUniqueWorkLinks([summary]).keys()]).toEqual([
      "https://mooc1.chaoxing.com/work?workOrExam=work&workId=1",
      "https://mooc1.chaoxing.com/exam?workOrExam=exam&examId=2",
    ]);
  });

  test("fetches detail summary with decoded attachment links", async () => {
    const attachment = encodeURIComponent(
      btoa(
        JSON.stringify({
          url: "https://mooc1.chaoxing.com/work?workOrExam=work&workId=1",
        }),
      ),
    );
    const fetcher = async () =>
      Response.json({
        status: true,
        msg: {
          title: "作业",
          rtf_content: `<iframe name="${attachment}"></iframe>`,
        },
      });

    const summary = await fetchDetailSummary({
      cookie: "UID=1",
      fetcher: fetcher as unknown as typeof fetch,
      message: {
        id: "notice-1",
        uuid: null,
        title: "作业",
        sender: null,
        sendTime: "2026-06-01 08:00:00",
        isRead: false,
        content: null,
        detailUrl: null,
        sendTag: 0,
      },
    });

    expect(summary.assignmentLinks).toEqual([
      "https://mooc1.chaoxing.com/work?workOrExam=work&workId=1",
    ]);
  });

  test("processes inbox details and assignment requirements", async () => {
    const calls: string[] = [];
    const fetcher = async (input: string | URL | Request, init?: RequestInit) => {
      const url = String(input);
      calls.push(url);

      if (url.startsWith("https://i.chaoxing.com/base")) {
        return new Response(
          `https://notice.chaoxing.com/pc/notice/myNotice?s=abc123`,
          { headers: { "Content-Type": "text/html" } },
        );
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
            rtf_content:
              "https://mooc1.chaoxing.com/work?workOrExam=work&workId=1",
          },
        });
      }

      if (url.startsWith("https://mooc1.chaoxing.com/work")) {
        return new Response(
          `<title>作业作答</title><input id="workId" value="1" />`,
          { status: init?.redirect === "follow" ? 200 : 302 },
        );
      }

      return new Response("not found", { status: 404 });
    };

    const result = await processAssignments({
      cookie: "UID=1",
      fetcher: fetcher as unknown as typeof fetch,
      inboxLimit: 5,
      detailsLimit: 5,
      requirementsLimit: 5,
    });

    expect(result.inbox).toEqual({
      fetched: 1,
      relevant: 1,
      inspectedDetails: 1,
    });
    expect(result.totalUniqueActivityLinks).toBe(1);
    expect(result.totalUniqueWorkLinks).toBe(1);
    expect(result.fetchedRequirements).toBe(1);
    expect(result.failedRequirements).toEqual([]);
    expect(result.requirements[0].workId).toBe("1");
    expect(calls).toContain("https://notice.chaoxing.com/pc/notice/getNoticeList");
  });
});
