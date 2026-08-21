import { SyncDisplayStatus, SyncItemKind, type SyncItem } from "../src/index";

export function assignmentItem(input: {
  dueAt: Date | null;
  id?: string;
  title?: string;
  sources?: readonly string[];
}): SyncItem {
  return {
    id: input.id ?? "assignment-1",
    kind: SyncItemKind.assignment,
    title: input.title ?? "作业",
    url: "https://mooc1.chaoxing.com/work",
    sourceTitle: "作业通知",
    dueAt: input.dueAt,
    status: "answering",
    displayStatus: SyncDisplayStatus.unscheduled,
    sources: input.sources ?? [],
  };
}

export function jsonResponse(
  body: unknown,
  url = "https://notice.chaoxing.com/pc/notice/getNoticeList",
): { status: number; url: string; headers: Record<string, string>; body: string } {
  return {
    status: 200,
    url,
    headers: { "content-type": "application/json; charset=utf-8" },
    body: JSON.stringify(body),
  };
}

export function htmlResponse(
  body: string,
  url: string,
  headers: Record<string, string> = {},
): { status: number; url: string; headers: Record<string, string>; body: string } {
  return {
    status: 200,
    url,
    headers: { "content-type": "text/html; charset=utf-8", ...headers },
    body,
  };
}
