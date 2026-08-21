import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  AuthenticationExpiredException,
  createLocalSyncRunner,
  defaultSyncConfig,
  emptyCourseCatalog,
  LocalSyncException,
  mergeDiscoveredCourses,
  setCourseMonitored,
  type ChaoxingHttpClient,
  type ChaoxingHttpRequest,
  type ChaoxingHttpResponse,
} from "../src/index";
import { htmlResponse, jsonResponse } from "./helpers";

function mockClient(
  handler: (
    request: ChaoxingHttpRequest,
    calls: string[],
  ) => ChaoxingHttpResponse | Promise<ChaoxingHttpResponse>,
): { http: ChaoxingHttpClient; calls: string[] } {
  const calls: string[] = [];
  return {
    calls,
    http: {
      async send(request) {
        calls.push(`${request.method} ${request.url}`);
        return handler(request, calls);
      },
    },
  };
}

const spaceHome = htmlResponse(
  '个人空间 https://notice.chaoxing.com/pc/notice/myNotice?s=sync',
  "https://i.chaoxing.com/base?ws=1&t=1780231212848",
);

describe("同步编排", () => {
  test("checkAuth marks a rendered login page as expired", async () => {
    const { http } = mockClient(() =>
      htmlResponse(
        '<title>用户登录</title><button id="loginBtn">登录</button>',
        "https://i.chaoxing.com/base",
      ),
    );
    const runner = createLocalSyncRunner({ http });
    const result = await runner.checkAuth("UID=1");
    assert.equal(result.authenticated, false);
    assert.equal(result.loginDetected, true);
    assert.equal(result.title, "用户登录");
  });

  test("run throws AuthenticationExpiredException on login page", async () => {
    const { http } = mockClient(() =>
      htmlResponse("<title>用户登录</title>", "https://passport2.chaoxing.com/login"),
    );
    const runner = createLocalSyncRunner({ http });
    await assert.rejects(
      () =>
        runner.run({
          config: { ...defaultSyncConfig, cookie: "UID=1" },
        }),
      (error: unknown) => error instanceof AuthenticationExpiredException,
    );
  });

  test("run refuses an empty cookie without sending HTTP", async () => {
    let requested = false;
    const runner = createLocalSyncRunner({
      http: {
        async send() {
          requested = true;
          throw new Error("network not allowed");
        },
      },
    });
    await assert.rejects(
      () => runner.run({ config: defaultSyncConfig }),
      (error: unknown) =>
        error instanceof LocalSyncException &&
        error.message === "请先在设置中填入学习通 Cookie",
    );
    assert.equal(requested, false);
  });

  test("accepts nested rows and string success in notice list responses", async () => {
    const { http } = mockClient((request) => {
      if (request.url.startsWith("https://i.chaoxing.com/base")) {
        return spaceHome;
      }
      if (request.url.startsWith("https://notice.chaoxing.com/pc/notice/myNotice")) {
        return htmlResponse("window.nowYear='2026';", request.url);
      }
      return jsonResponse({
        status: "true",
        data: {
          rows: [{ id: "nested-1", noticeTitle: "作业通知", content: "请完成作业" }],
          finished: 1,
        },
      });
    });
    const runner = createLocalSyncRunner({ http });
    const result = await runner.fetchInboxMessages({
      cookie: "UID=1",
      itemLimit: 20,
      pageLimit: 2,
    });
    assert.equal(result.pagesFetched, 1);
    assert.equal(result.messages[0].id, "nested-1");
    assert.equal(result.messages[0].title, "作业通知");
  });

  test("extracts work links from iframe-encoded notice details", async () => {
    const attachment = encodeURIComponent(
      Buffer.from(
        JSON.stringify({
          url: "https://mooc1.chaoxing.com/work?workOrExam=work&workId=1",
        }),
        "utf8",
      ).toString("base64"),
    );
    const { http } = mockClient((request) => {
      assert.equal(request.headers.Cookie, "UID=1");
      return jsonResponse({
        status: true,
        msg: {
          title: "作业通知",
          rtf_content: `<iframe name="${attachment}"></iframe>`,
        },
      });
    });
    const runner = createLocalSyncRunner({ http });
    const summary = await runner.fetchDetailSummary({
      cookie: "UID=1",
      message: {
        id: "notice-1",
        uuid: null,
        title: "作业通知",
        sender: null,
        sendTime: "2026-06-01 08:00:00",
        isRead: false,
        content: null,
        detailUrl: null,
        sendTag: 0,
      },
    });
    assert.deepEqual(summary.assignmentLinks, [
      "https://mooc1.chaoxing.com/work?workOrExam=work&workId=1",
    ]);
  });

  test("rejects an untrusted assignment entry without sending a cookie", async () => {
    let requested = false;
    const runner = createLocalSyncRunner({
      http: {
        async send() {
          requested = true;
          return htmlResponse("should not request", "https://evil.example/work");
        },
      },
    });
    await assert.rejects(
      () =>
        runner.fetchAssignmentRequirement({
          entryUrl: "https://evil.example/work?workId=1",
          cookie: "UID=secret; vc=token",
          summary: {
            title: "作业通知",
            sendTime: null,
            content: null,
            assignmentLinks: [],
          },
        }),
      (error: unknown) =>
        error instanceof LocalSyncException &&
        !error.message.includes("UID=secret"),
    );
    assert.equal(requested, false);
  });

  test("syncs inbox work details and records a seen notice", async () => {
    const { http } = mockClient((request) => {
      if (request.url.startsWith("https://i.chaoxing.com/base")) {
        return spaceHome;
      }
      if (request.url.startsWith("https://notice.chaoxing.com/pc/notice/myNotice")) {
        return htmlResponse("window.nowYear='2026';", request.url);
      }
      if (request.url.includes("/pc/notice/getNoticeList")) {
        return jsonResponse({
          status: true,
          notices: {
            list: [
              {
                id: "notice-1",
                title: "高等数学作业",
                content: "请完成作业",
                sendTime: "2026-06-01 08:00:00",
              },
            ],
            lastPage: true,
          },
        });
      }
      if (request.url.includes("getNoticeDetail")) {
        return jsonResponse({
          status: true,
          msg: {
            rtf_content:
              '<a href="https://mooc1.chaoxing.com/work?workId=9">作业</a>',
          },
        });
      }
      if (request.url.startsWith("https://mooc1.chaoxing.com/work")) {
        return htmlResponse(
          '<title>作业作答</title><input id="workId" value="9" /><p>截止时间：2026-07-20 23:59</p>',
          request.url,
        );
      }
      return { status: 404, url: request.url, headers: {}, body: "not found" };
    });
    const runner = createLocalSyncRunner({
      http,
      clock: () => new Date("2026-07-16T12:00:00+08:00"),
    });
    const response = await runner.run({
      config: {
        ...defaultSyncConfig,
        cookie: "UID=1",
        inboxPageLimit: 1,
        inboxItemLimit: 20,
        courseSourcesEnabled: false,
      },
    });
    assert.equal(response.items.length, 1);
    assert.equal(response.items[0].id, "assignment-9");
    assert.equal(response.items[0].dueAt?.toISOString(), "2026-07-20T15:59:00.000Z");
    assert.equal(response.seenNotices[0]?.id, "notice-1");
    assert.equal(response.seenNotices[0]?.detailParsed, true);
    assert.equal(response.failures.length, 0);
  });

  test("reuses a parsed 已见通知 and does not refetch its detail", async () => {
    const { http, calls } = mockClient((request) => {
      if (request.url.startsWith("https://i.chaoxing.com/base")) {
        return spaceHome;
      }
      if (request.url.startsWith("https://notice.chaoxing.com/pc/notice/myNotice")) {
        return htmlResponse("window.nowYear='2026';", request.url);
      }
      if (request.url.includes("/pc/notice/getNoticeList")) {
        return jsonResponse({
          status: true,
          notices: {
            list: [{ id: "notice-1", title: "高等数学作业", content: "请完成作业" }],
            lastPage: true,
          },
        });
      }
      if (request.url.startsWith("https://mooc1.chaoxing.com/work")) {
        return htmlResponse(
          '<title>作业作答</title><p>截止时间：2026-07-20 23:59</p>',
          request.url,
        );
      }
      return { status: 404, url: request.url, headers: {}, body: "not found" };
    });
    const runner = createLocalSyncRunner({
      http,
      clock: () => new Date("2026-07-16T12:00:00+08:00"),
    });
    const response = await runner.run({
      config: {
        ...defaultSyncConfig,
        cookie: "UID=1",
        courseSourcesEnabled: false,
      },
      previous: {
        lastSyncedAt: new Date("2026-07-15T12:00:00+08:00"),
        authStatus: "ok",
        items: [],
        failures: [],
        stats: {
          durationMs: 0,
          authenticationMs: 0,
          inboxMs: 0,
          noticeDetailsMs: 0,
          assignmentDetailsMs: 0,
          coursesMs: 0,
          inboxMessages: 0,
          relevantNotices: 0,
          detailSummaries: 0,
          inboxTaskLinks: 0,
          inboxTaskDetails: 0,
          statusFilteredItems: 0,
          courses: 0,
          courseTaskLinksDiscovered: 0,
          courseTaskLinks: 0,
          courseTaskStatusFiltered: 0,
          itemCandidates: 0,
          courseSourcesEnabled: false,
        },
        seenNotices: [
          {
            id: "notice-1",
            detailParsed: true,
            title: "高等数学作业",
            sendTime: "2026-06-01 08:00:00",
            content: "请完成作业",
            taskLinks: ["https://mooc1.chaoxing.com/work?workId=9"],
          },
        ],
      },
    });
    assert.equal(
      calls.some((call) => call.includes("getNoticeDetail")),
      false,
    );
    assert.equal(response.items[0]?.id, "assignment-9");
  });

  test("scans only 受监控课程 without rediscovery on the same local day", async () => {
    const { http, calls } = mockClient((request) => {
      if (request.url.startsWith("https://i.chaoxing.com/base")) {
        return spaceHome;
      }
      if (request.url.startsWith("https://notice.chaoxing.com/pc/notice/myNotice")) {
        return htmlResponse("window.nowYear='2026';", request.url);
      }
      if (request.url.includes("/pc/notice/getNoticeList")) {
        return jsonResponse({
          status: true,
          notices: { list: [], lastPage: true },
        });
      }
      if (request.url.includes("task-list")) {
        return htmlResponse("<ul></ul>", request.url);
      }
      return { status: 500, url: request.url, headers: {}, body: "unexpected" };
    });
    const catalog = setCourseMonitored(
      mergeDiscoveredCourses(
        emptyCourseCatalog,
        [
          {
            courseId: "monitored",
            classId: "1",
            cpi: "1",
            title: "受监控课程",
          },
          {
            courseId: "ignored",
            classId: "2",
            cpi: "2",
            title: "已取消课程",
          },
        ],
        new Date("2026-07-27T09:00:00+08:00"),
      ),
      "ignored:2",
      false,
    );
    const runner = createLocalSyncRunner({
      http,
      clock: () => new Date("2026-07-27T10:00:00+08:00"),
    });
    await runner.run({
      config: {
        ...defaultSyncConfig,
        cookie: "UID=1",
        inboxPageLimit: 1,
        inboxItemLimit: 20,
      },
      courseCatalog: catalog,
    });
    assert.equal(calls.some((call) => call.includes("/visit/interaction")), false);
    const taskCalls = calls.filter((call) => call.includes("task-list"));
    assert.equal(taskCalls.length, 2);
    assert.ok(taskCalls.every((call) => call.includes("courseId=monitored")));
    assert.equal(taskCalls.some((call) => call.includes("courseId=ignored")), false);
  });

  test("uses the current course endpoint before the legacy fallback", async () => {
    const { http, calls } = mockClient((request) => {
      if (request.url.startsWith("https://i.chaoxing.com/base")) {
        return htmlResponse(
          '<div dataurl="https://mooc1-1.chaoxing.com/visit/interaction?courseId=1&amp;clazzId=2"></div>',
          request.url,
          { "set-cookie": "route=home; Path=/; HttpOnly" },
        );
      }
      if (new URL(request.url).pathname === "/visit/interaction") {
        assert.doesNotMatch(request.headers.Cookie ?? "", /route=home/);
        assert.match(request.headers.Cookie ?? "", /UID=1/);
        return htmlResponse("course shell", request.url, {
          "set-cookie": "course_session=ready; Path=/",
        });
      }
      assert.equal(
        request.url,
        "https://mooc1-1.chaoxing.com/mooc-ans/visit/courselistdata",
      );
      assert.equal(request.method, "POST");
      assert.equal(request.form?.courseType, "1");
      assert.match(request.headers.Cookie ?? "", /course_session=ready/);
      return htmlResponse(
        '<ul id="courseList"><li class="course" courseid="1" clazzid="2" personid="3"><span class="course-name">测试课程</span></li></ul>',
        request.url,
      );
    });
    const runner = createLocalSyncRunner({ http });
    const courses = await runner.fetchCourseSpaces("UID=1");
    assert.equal(courses[0].title, "测试课程");
    assert.equal(calls.length, 3);
  });
});
