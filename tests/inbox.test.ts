import { describe, expect, test } from "bun:test";

import {
  extractInboxPageConfig,
  findInboxUrl,
  normalizeNotice,
} from "../src/inbox";

describe("inbox parsing", () => {
  test("finds inbox URL from personal space HTML", () => {
    expect(
      findInboxUrl(
        `onclick="setUrl('637140','https://notice.chaoxing.com/pc/notice/myNotice?s=abc123',this)"`,
        "https://i.chaoxing.com/base",
      ),
    ).toBe("https://notice.chaoxing.com/pc/notice/myNotice?s=abc123");
  });

  test("extracts inbox page config defaults", () => {
    expect(
      extractInboxPageConfig(`
window.type = '2';
window.folderUUID = '';
window.nowYear = '2026';
window.noticeType= '';
window.fidsCode = '';
`),
    ).toEqual({
      type: "2",
      noticeType: "",
      year: "2026",
      folderUUID: "",
      fidsCode: "",
      queryFolderNoticePrevYear: "0",
    });
  });

  test("normalizes a raw notice", () => {
    expect(
      normalizeNotice({
        idCode: "abc",
        uuid: "$CACG$uuid",
        title: "作业通知",
        createrName: "学习通知",
        sendTime: "2026-05-31 12:00:06",
        isread: 0,
        content: "<p>课程名称：线性代数</p>",
        sendTag: 0,
      }),
    ).toEqual({
      id: "abc",
      uuid: "$CACG$uuid",
      title: "作业通知",
      sender: "学习通知",
      sendTime: "2026-05-31 12:00:06",
      isRead: false,
      content: "课程名称：线性代数",
      detailUrl:
        "https://notice.chaoxing.com/pc/notice/$CACG$uuid/detail?sendTag=0",
      sendTag: 0,
    });
  });
});
