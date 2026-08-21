import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  buildSyncItem,
  extractNoticeLinks,
  extractTimeWindow,
  findCourseInteractionUrl,
  findInboxUrl,
  isActionableWorkStatus,
  isAssignmentOrExamRelated,
  parseAssignmentRequirement,
  parseChaoxingDateTime,
  parseCourseSpaces,
  parseCourseTaskLinks,
  parseNoticeDetailSummary,
  SyncItemKind,
} from "../src/index";

describe("学习通解析", () => {
  test("parses course spaces from backclazzdata JSON", () => {
    const courses = parseCourseSpaces(
      JSON.stringify({
        channelList: [
          {
            cpi: 9001,
            content: {
              course: {
                data: [
                  {
                    name: "线性代数",
                    courseSquareUrl:
                      "https://mooc1.chaoxing.com/course?courseId=101&classId=202&userId=303",
                  },
                ],
              },
            },
          },
        ],
      }),
    );
    assert.equal(courses.length, 1);
    assert.equal(courses[0].courseId, "101");
    assert.equal(courses[0].classId, "202");
    assert.equal(courses[0].cpi, "9001");
    assert.equal(courses[0].title, "线性代数");
  });

  test("keeps inherited cpi scoped to each course channel", () => {
    const courses = parseCourseSpaces(
      JSON.stringify({
        channelList: [
          {
            cpi: 9001,
            content: {
              course: {
                data: [{ name: "课程一", courseId: "101", classId: "201" }],
              },
            },
          },
          {
            cpi: 9002,
            content: {
              course: {
                data: [{ name: "课程二", courseId: "102", classId: "202" }],
              },
            },
          },
        ],
      }),
    );
    assert.deepEqual(Object.fromEntries(courses.map((course) => [course.courseId, course.cpi])), {
      "101": "9001",
      "102": "9002",
    });
  });

  test("parses course spaces from courselistdata HTML", () => {
    const courses = parseCourseSpaces(`
      <ul id="courseList">
        <li class="course" courseid="301" clazzid="401" personid="501">
          <div class="course-info">
            <a href="https://mooc2-ans.chaoxing.com/mooc2-ans/mycourse/stu?courseid=301&amp;clazzid=401&amp;cpi=501"></a>
            <h3 class="course-name">大学物理</h3>
          </div>
        </li>
      </ul>
    `);
    assert.equal(courses.length, 1);
    assert.equal(courses[0].courseId, "301");
    assert.equal(courses[0].classId, "401");
    assert.equal(courses[0].cpi, "501");
    assert.equal(courses[0].title, "大学物理");
  });

  test("extracts trusted work and exam task links", () => {
    const links = parseCourseTaskLinks(
      `
      <a data="/mooc-ans/work/phone/task-work?taskrefId=11&amp;courseId=101&amp;classId=202">第一次作业</a>
      <li data="https://mooc1-api.chaoxing.com/exam-ans/exam/phone/task-exam?taskrefId=22&amp;courseId=101&amp;classId=202">期中考试</li>
      <a href="https://evil.example/work?workId=33">不可信链接</a>
      <a href="/work/task-list?courseId=101">列表自身</a>
      `,
      "https://mooc1-api.chaoxing.com/work/task-list?courseId=101",
      "线性代数",
    );
    assert.deepEqual(
      links.map((link) => link.title),
      ["第一次作业", "期中考试"],
    );
    assert.match(links[0].url, /taskrefId=11/);
    assert.match(links[1].url, /taskrefId=22/);
  });

  test("recognizes completed, submitted, and expired course tasks", () => {
    const links = parseCourseTaskLinks(
      `
      <ul id="chaoxing-assignment-wrapper">
        <li data="/mooc-ans/work/phone/task-work?taskrefId=11&amp;courseId=101">
          <p>待做作业</p><span class="status">未提交</span>
        </li>
        <li data="/mooc-ans/work/phone/task-work?taskrefId=12&amp;courseId=101">
          <p>作业二</p><span class="status">已完成</span>
        </li>
        <li data="/mooc-ans/work/phone/task-work?taskrefId=13&amp;courseId=101">
          <p>作业三</p><span class="status">待批阅</span>
        </li>
        <li data="/exam-ans/exam/phone/task-exam?taskrefId=14&amp;courseId=101">
          <div class="ks_pic"><img src="/images/ks_02.png"></div>
          <dl><dt>旧考试</dt></dl><span class="ks_state">已结束</span>
        </li>
      </ul>
      `,
      "https://mooc1-api.chaoxing.com/work/task-list?courseId=101",
      "线性代数",
    );
    assert.deepEqual(
      links.map((link) => link.title),
      ["待做作业", "作业二", "作业三", "旧考试"],
    );
    assert.deepEqual(
      links.map((link) => link.status),
      ["unknown", "completed", "submitted", "expired"],
    );
    assert.deepEqual(
      links.map((link) => isActionableWorkStatus(link.status)),
      [true, false, false, false],
    );
  });

  test("uses taskrefId as the stable work id for course work", () => {
    const requirement = parseAssignmentRequirement({
      html: "<title>作业作答</title><p>截止时间：2026-07-20 23:59</p>",
      entryUrl:
        "https://mooc1-api.chaoxing.com/mooc-ans/work/phone/task-work?taskrefId=11&courseId=101&classId=202",
      finalUrl:
        "https://mooc1-api.chaoxing.com/mooc-ans/work/phone/task-work?taskrefId=11&courseId=101&classId=202",
      status: 200,
      sourceTitle: "第一次作业",
      sourceSendTime: null,
      sourceContent: null,
      source: "course_work",
    });
    const item = buildSyncItem(requirement, new Date(2026, 6, 16));
    assert.equal(item.id, "assignment-11");
    assert.equal(item.workId, "11");
    assert.deepEqual(item.sources, ["course_work"]);
  });

  test("marks explicitly completed detail pages as non-actionable", () => {
    const requirement = parseAssignmentRequirement({
      html: '<title>作业详情</title><div class="status">已完成</div>',
      entryUrl: "https://mooc1.chaoxing.com/work?workId=99",
      finalUrl: "https://mooc1.chaoxing.com/work/view?workId=99",
      status: 200,
      sourceTitle: "已完成作业",
      sourceSendTime: null,
      sourceContent: null,
    });
    assert.equal(requirement.workStatus, "completed");
    assert.equal(isActionableWorkStatus(requirement.workStatus), false);
    assert.equal(isActionableWorkStatus("view"), false);
    assert.equal(isActionableWorkStatus("preview"), false);
    assert.equal(isActionableWorkStatus("prompt"), true);
    assert.equal(isActionableWorkStatus("unknown"), true);
  });

  test("keeps assignments whose deadline cannot be parsed", () => {
    const item = buildSyncItem(
      {
        sourceTitle: "高等数学作业",
        sourceSendTime: null,
        sourceContent: null,
        entryUrl: "https://mooc1.chaoxing.com/work?workId=9",
        finalUrl: "https://mooc1.chaoxing.com/work?workId=9",
        pageTitle: "作业",
        status: 200,
        courseId: "1",
        classId: "2",
        workId: "9",
        answerId: null,
        workStatus: "answering",
        timeWindowStart: null,
        timeWindowEnd: null,
        source: "inbox",
      },
      new Date(2026, 6, 16),
    );
    assert.equal(item.id, "assignment-9");
    assert.equal(item.dueAt, null);
    assert.equal(item.kind, SyncItemKind.assignment);
  });

  test("parses chaoxing time without year using source send time", () => {
    const parsed = parseChaoxingDateTime(
      "01-02 08:30",
      "2025-12-01 00:30:00",
      new Date("2025-12-31T12:00:00Z"),
    );
    assert.equal(parsed?.toISOString(), "2026-01-02T00:30:00.000Z");
  });

  test("extracts time windows from chaoxing text fixtures", () => {
    const fixtures = [
      {
        html: "<div>作答时间：<em>2026年6月1日 08:00</em>\n至<em>2026年6月2日 23:59</em></div>",
        content: null,
        start: "2026-6-1 08:00",
        end: "2026-6-2 23:59",
      },
      {
        html: "",
        content: "开始时间：06-01 08:00\n结束时间：06-02 23:59",
        start: "06-01 08:00",
        end: "06-02 23:59",
      },
      {
        html: "<p>提交截止时间&nbsp;：&nbsp;2026年6月10日&nbsp;23:59</p>",
        content: null,
        start: null,
        end: "2026-6-10 23:59",
      },
      {
        html: "",
        content: "结束时间：06月12日 18:30",
        start: null,
        end: "06-12 18:30",
      },
    ];
    for (const fixture of fixtures) {
      const window = extractTimeWindow(fixture.html, fixture.content);
      assert.equal(window.start, fixture.start);
      assert.equal(window.end, fixture.end);
    }
  });

  test("resolves relative inbox links against the notice host", () => {
    assert.equal(
      findInboxUrl(
        '<a href="/pc/notice/myNotice?s=abc123">收件箱</a>',
        "https://i.chaoxing.com/base",
      ),
      "https://notice.chaoxing.com/pc/notice/myNotice?s=abc123",
    );
  });

  test("filters 待办 notices and extracts work links", () => {
    assert.equal(
      isAssignmentOrExamRelated({
        id: "2",
        uuid: null,
        title: "普通消息",
        sender: null,
        sendTime: null,
        isRead: false,
        content: "请完成作业",
        detailUrl: null,
        sendTag: 0,
      }),
      true,
    );
    assert.equal(
      isAssignmentOrExamRelated({
        id: "3",
        uuid: null,
        title: "作业结束提醒",
        sender: null,
        sendTime: null,
        isRead: false,
        content: null,
        detailUrl: null,
        sendTag: 0,
      }),
      false,
    );
    assert.deepEqual(
      extractNoticeLinks(
        '<a href="//mooc1.chaoxing.com/work?workId=88">查看作业</a>',
      ),
      ["https://mooc1.chaoxing.com/work?workId=88"],
    );
  });

  test("extracts links from nested notice detail JSON", () => {
    const summary = parseNoticeDetailSummary({
      message: {
        id: "nested-detail",
        uuid: null,
        title: "作业通知",
        sender: null,
        sendTime: null,
        isRead: false,
        content: null,
        detailUrl: null,
        sendTag: 0,
      },
      decoded: {
        success: "1",
        data: {
          detail: {
            rtfContent:
              '<a href="//mooc1.chaoxing.com/work?workId=88">查看作业</a>',
          },
        },
      },
    });
    assert.deepEqual(summary.assignmentLinks, [
      "https://mooc1.chaoxing.com/work?workId=88",
    ]);
  });

  test("resolves relative interaction entries but rejects foreign hosts", () => {
    assert.equal(
      findCourseInteractionUrl(
        '<div dataurl="/visit/interaction?courseId=1&amp;clazzId=2"></div>',
      ),
      "https://mooc1-1.chaoxing.com/visit/interaction?courseId=1&clazzId=2",
    );
    assert.equal(
      findCourseInteractionUrl(
        '<div dataurl="https://evil.example/visit/interaction"></div>',
      ),
      null,
    );
  });
});
