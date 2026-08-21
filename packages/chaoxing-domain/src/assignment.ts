import { decodeBasicHtmlEntities, extractPageTitle, stripHtml } from "./html";
import type { InboxMessage } from "./inbox";
import {
  copySyncItem,
  SyncDisplayStatus,
  SyncItemKind,
  type SyncItem,
} from "./sync-item";
import { buildNoticeDetailPageUrl, readUrlParam } from "./urls";

export type AssignmentRequirement = {
  sourceTitle: string;
  sourceSendTime: string | null;
  sourceContent: string | null;
  entryUrl: string;
  finalUrl: string;
  pageTitle: string | null;
  status: number;
  courseId: string | null;
  classId: string | null;
  workId: string | null;
  answerId: string | null;
  workStatus: string;
  timeWindowStart: string | null;
  timeWindowEnd: string | null;
  source: string;
};

const nonActionableStatuses = new Set([
  "completed",
  "submitted",
  "expired",
  "view",
  "preview",
]);

export function isActionableWorkStatus(status: string): boolean {
  return !nonActionableStatuses.has(status.toLowerCase());
}

export function parseAssignmentRequirement(input: {
  html: string;
  entryUrl: string;
  finalUrl: string;
  status: number;
  sourceTitle: string;
  sourceSendTime: string | null;
  sourceContent: string | null;
  source?: string;
}): AssignmentRequirement {
  const source = input.source ?? "inbox";
  const pageTitle = extractPageTitle(input.html);
  const timeWindow = extractTimeWindow(input.html, input.sourceContent);
  return {
    sourceTitle: input.sourceTitle,
    sourceSendTime: input.sourceSendTime,
    sourceContent: input.sourceContent,
    entryUrl: input.entryUrl,
    finalUrl: input.finalUrl,
    pageTitle,
    status: input.status,
    courseId: readUrlParam(input.finalUrl, "courseId"),
    classId: readUrlParam(input.finalUrl, "classId"),
    workId:
      readUrlParam(input.finalUrl, "workId") ??
      readHiddenValue(input.html, "workId") ??
      (source === "course_work"
        ? (readUrlParam(input.finalUrl, "taskrefId") ??
          readUrlParam(input.entryUrl, "taskrefId"))
        : null),
    answerId:
      readUrlParam(input.finalUrl, "answerId") ??
      readHiddenValue(input.html, "answerId"),
    workStatus: inferWorkStatus(pageTitle, input.finalUrl, input.html),
    timeWindowStart: timeWindow.start,
    timeWindowEnd: timeWindow.end,
    source,
  };
}

export function buildSyncItem(
  requirement: AssignmentRequirement,
  generatedAt: Date,
): SyncItem {
  const dueAt = parseChaoxingDateTime(
    requirement.timeWindowEnd,
    requirement.sourceSendTime,
    generatedAt,
  );
  const startAt = parseChaoxingDateTime(
    requirement.timeWindowStart,
    requirement.sourceSendTime,
    generatedAt,
  );
  const kind = inferKind(requirement);
  const examId =
    readUrlParam(requirement.finalUrl, "examId") ??
    readUrlParam(requirement.finalUrl, "taskrefId") ??
    readUrlParam(requirement.entryUrl, "examId") ??
    readUrlParam(requirement.entryUrl, "taskrefId");
  const stableId =
    requirement.workId ??
    examId ??
    hashString(
      requirement.finalUrl.length > 0
        ? requirement.finalUrl
        : requirement.entryUrl,
    );
  return {
    id: `${kind}-${stableId}`,
    kind,
    title: requirement.sourceTitle
      ? requirement.sourceTitle
      : (requirement.pageTitle ?? (kind === SyncItemKind.exam ? "考试" : "作业")),
    url:
      requirement.finalUrl.length > 0
        ? requirement.finalUrl
        : requirement.entryUrl,
    sourceTitle: requirement.sourceTitle,
    sourceSendTime: requirement.sourceSendTime,
    startAt,
    dueAt,
    status: requirement.workStatus,
    displayStatus: SyncDisplayStatus.unscheduled,
    courseId: requirement.courseId,
    classId: requirement.classId,
    workId: requirement.workId,
    examId: kind === SyncItemKind.exam ? examId : null,
    answerId: requirement.answerId,
    sources: [requirement.source],
  };
}

export function buildLoadingItem(input: {
  url: string;
  title: string;
  sendTime: string | null;
}): SyncItem {
  const isExam = /workOrExam=exam|\/exam\b|examId=/i.test(input.url);
  const kind = isExam ? SyncItemKind.exam : SyncItemKind.assignment;
  const stableId = isExam
    ? (readUrlParam(input.url, "examId") ?? readUrlParam(input.url, "taskrefId"))
    : (readUrlParam(input.url, "workId") ?? readUrlParam(input.url, "taskrefId"));
  return {
    id: `${kind}-${stableId ?? hashString(input.url)}`,
    kind,
    title: input.title.length === 0 ? (isExam ? "考试" : "作业") : input.title,
    url: input.url,
    sourceTitle: input.title,
    sourceSendTime: input.sendTime,
    dueAt: null,
    status: "details_loading",
    displayStatus: SyncDisplayStatus.unscheduled,
    workId: isExam ? null : stableId,
    examId: isExam ? stableId : null,
    sources: ["inbox"],
  };
}

export function parseChaoxingDateTime(
  value: string | null | undefined,
  sourceSendTime: string | null | undefined,
  fallbackDate: Date,
): Date | null {
  if (value == null || value.trim().length === 0) {
    return null;
  }
  const normalized = value.trim().replaceAll("/", "-");
  const withYear = normalized.match(
    /^(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?$/,
  );
  if (withYear) {
    return dateFromParts(
      withYear[1],
      withYear[2],
      withYear[3],
      withYear[4],
      withYear[5],
      withYear[6] ?? "0",
    );
  }
  const withoutYear = normalized.match(
    /^(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?$/,
  );
  if (withoutYear) {
    const year = inferYear(
      Number.parseInt(withoutYear[1], 10),
      sourceSendTime,
      fallbackDate,
    );
    return dateFromParts(
      String(year),
      withoutYear[1],
      withoutYear[2],
      withoutYear[3],
      withoutYear[4],
      withoutYear[5] ?? "0",
    );
  }
  const parsed = new Date(normalized);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

export function extractTimeWindow(
  html: string,
  sourceContent: string | null,
): { start: string | null; end: string | null } {
  const htmlWindow = html.match(
    /作答时间[:：]\s*<em>([^<]+)<\/em>\s*至\s*<em>([^<]+)<\/em>/,
  );
  if (htmlWindow) {
    return {
      start: normalizeChaoxingDateText(htmlWindow[1]),
      end: normalizeChaoxingDateText(htmlWindow[2]),
    };
  }

  const text = [stripHtml(html), stripHtml(sourceContent ?? "")]
    .filter((value) => value.length > 0)
    .join("\n")
    .replace(/\s+/g, " ");
  const dateTime =
    "((?:\\d{4}\\s*[-/年]\\s*)?\\d{1,2}\\s*[-/月]\\s*\\d{1,2}\\s*(?:日)?\\s+\\d{1,2}:\\d{2}(?::\\d{2})?)";

  const contentWindow = text.match(
    new RegExp(
      `开始时间\\s*[:：]?\\s*${dateTime}[\\s\\S]*?结束时间\\s*[:：]?\\s*${dateTime}`,
    ),
  );
  if (contentWindow) {
    return {
      start: normalizeChaoxingDateText(contentWindow[1]),
      end: normalizeChaoxingDateText(contentWindow[2]),
    };
  }

  const answerWindow = text.match(
    new RegExp(
      `作答时间\\s*[:：]?\\s*${dateTime}\\s*(?:至|-|到)\\s*${dateTime}`,
    ),
  );
  if (answerWindow) {
    return {
      start: normalizeChaoxingDateText(answerWindow[1]),
      end: normalizeChaoxingDateText(answerWindow[2]),
    };
  }

  const singleDue = text.match(
    new RegExp(`(?:提交截止时间|截止时间|结束时间|截止|结束)\\s*[:：]?\\s*${dateTime}`),
  );
  if (singleDue) {
    return { start: null, end: normalizeChaoxingDateText(singleDue[1]) };
  }
  return { start: null, end: null };
}

export function messageFromSeenNotice(notice: {
  id: string;
  title: string;
  sendTime: string | null | undefined;
  content: string | null | undefined;
  sendTag?: unknown;
}): InboxMessage {
  return {
    id: notice.id,
    uuid: null,
    title: notice.title,
    sender: null,
    sendTime: notice.sendTime ?? null,
    isRead: false,
    content: notice.content ?? null,
    detailUrl: buildNoticeDetailPageUrl(notice.id, notice.sendTag),
    sendTag: notice.sendTag,
  };
}

export function classifyDueDate(dueAt: Date, now: Date): typeof SyncDisplayStatus[keyof typeof SyncDisplayStatus] {
  if (dueAt.getTime() < now.getTime()) {
    return SyncDisplayStatus.overdue;
  }
  return localDateKey(dueAt) === localDateKey(now)
    ? SyncDisplayStatus.today
    : SyncDisplayStatus.upcoming;
}

export function enrichSyncItem(item: SyncItem, now: Date): SyncItem {
  const dueAt = item.dueAt;
  const dueInHours =
    dueAt === null
      ? null
      : Math.round((dueAt.getTime() - now.getTime()) / (60 * 60 * 1000));
  return copySyncItem(item, {
    displayStatus:
      dueAt === null ? SyncDisplayStatus.unscheduled : classifyDueDate(dueAt, now),
    dueInHours,
  });
}

function inferWorkStatus(
  pageTitle: string | null,
  finalUrl: string,
  html: string,
): string {
  const pageText = stripHtml(html);
  if (/已过期|已结束|不可作答/.test(pageText)) {
    return "expired";
  }
  if (/待批阅|已提交/.test(pageText)) {
    return "submitted";
  }
  if (/已完成|已批阅|查看答案/.test(pageText)) {
    return "completed";
  }
  if (finalUrl.includes("dowork") || pageTitle === "作业作答") {
    return "answering";
  }
  if (finalUrl.includes("/work/view") || pageTitle === "作业详情") {
    return "view";
  }
  if (finalUrl.includes("/work/preview") || pageTitle === "查看详情") {
    return "preview";
  }
  if (pageTitle === "提示") {
    return "prompt";
  }
  return "unknown";
}

function inferKind(requirement: AssignmentRequirement): SyncItemKind {
  const text = `${requirement.entryUrl}\n${requirement.finalUrl}\n${requirement.sourceTitle}\n${requirement.pageTitle ?? ""}`;
  return /workOrExam=exam|\/exam\b|考试|测验|测试|试卷/i.test(text)
    ? SyncItemKind.exam
    : SyncItemKind.assignment;
}

function dateFromParts(
  year: string,
  month: string,
  day: string,
  hour: string,
  minute: string,
  second: string,
): Date {
  const pad = (value: string): string => value.padStart(2, "0");
  return new Date(
    `${year}-${pad(month)}-${pad(day)}T${pad(hour)}:${pad(minute)}:${pad(second)}+08:00`,
  );
}

function inferYear(
  month: number,
  sourceSendTime: string | null | undefined,
  fallbackDate: Date,
): number {
  const normalized = sourceSendTime?.trim().replaceAll("/", "-");
  const sourceParts = normalized?.match(/^(\d{4})-(\d{1,2})-/);
  const year =
    sourceParts == null
      ? fallbackDate.getFullYear()
      : Number.parseInt(sourceParts[1], 10);
  const sourceMonth =
    sourceParts == null
      ? fallbackDate.getMonth() + 1
      : Number.parseInt(sourceParts[2], 10);
  return sourceMonth === 12 && month === 1 ? year + 1 : year;
}

function readHiddenValue(html: string, id: string): string | null {
  return (
    html.match(
      new RegExp(
        `<input[^>]+id=["']${id.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}["'][^>]+value=["']([^"']*)["']`,
        "i",
      ),
    )?.[1] ?? null
  );
}

export function hashString(value: string): string {
  let hash = 5381;
  for (const code of value) {
    hash = ((hash * 33) ^ code.charCodeAt(0)) >>> 0;
  }
  return hash.toString(36);
}

function normalizeChaoxingDateText(value: string): string {
  return decodeBasicHtmlEntities(value)
    .replace(/\s+/g, " ")
    .trim()
    .replace(/^(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日?/, "$1-$2-$3")
    .replace(/^(\d{1,2})\s*月\s*(\d{1,2})\s*日?/, "$1-$2")
    .replaceAll("/", "-");
}

function localDateKey(value: Date): string {
  return `${value.getFullYear()}-${String(value.getMonth() + 1).padStart(2, "0")}-${String(value.getDate()).padStart(2, "0")}`;
}
