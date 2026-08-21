import { enrichSyncItem } from "./assignment";
import { MAX_SEEN_NOTICES } from "./constants";
import { asRecord, readString } from "./json";
import { redactSensitiveText, redactSensitiveUrl } from "./redaction";
import {
  copySyncItem,
  parseDueAt,
  syncItemFromJson,
  syncItemToJson,
  type SyncItem,
} from "./sync-item";

export type SyncStats = {
  durationMs: number;
  authenticationMs: number;
  inboxMs: number;
  noticeDetailsMs: number;
  assignmentDetailsMs: number;
  coursesMs: number;
  inboxMessages: number;
  relevantNotices: number;
  detailSummaries: number;
  inboxTaskLinks: number;
  inboxTaskDetails: number;
  statusFilteredItems: number;
  courses: number;
  courseTaskLinksDiscovered: number;
  courseTaskLinks: number;
  courseTaskStatusFiltered: number;
  itemCandidates: number;
  courseSourcesEnabled: boolean;
};

export const emptySyncStats: SyncStats = {
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
};

export type SeenNotice = {
  id: string;
  detailParsed: boolean;
  sendTag?: unknown;
  title: string;
  sendTime: string | null;
  content: string | null;
  taskLinks: readonly string[];
};

export type AppSyncFailure = {
  entryUrl: string;
  sourceTitle: string;
  message: string;
};

export type AppSyncResponse = {
  lastSyncedAt: Date | null;
  authStatus: string;
  items: SyncItem[];
  failures: AppSyncFailure[];
  stats: SyncStats;
  seenNotices: SeenNotice[];
};

export function isRateLimited(response: AppSyncResponse): boolean {
  return response.failures.some((failure) => {
    const message = failure.message.toLowerCase();
    return (
      message.includes("429") ||
      message.includes("too many requests") ||
      message.includes("请求过于频繁") ||
      message.includes("请求频繁") ||
      message.includes("限流")
    );
  });
}

export function seenNoticeFromJson(json: Record<string, unknown>): SeenNotice {
  const rawLinks = json.taskLinks;
  return {
    id: readString(json, "id"),
    detailParsed: json.detailParsed === true,
    sendTag: json.sendTag,
    title: readString(json, "title"),
    sendTime:
      typeof json.sendTime === "string" && json.sendTime.length > 0
        ? json.sendTime
        : null,
    content:
      typeof json.content === "string" && json.content.length > 0
        ? json.content
        : null,
    taskLinks: Array.isArray(rawLinks)
      ? rawLinks.filter(
          (link): link is string => typeof link === "string" && link.length > 0,
        )
      : [],
  };
}

export function seenNoticeToJson(notice: SeenNotice): Record<string, unknown> {
  return {
    id: notice.id,
    detailParsed: notice.detailParsed,
    ...(notice.sendTag != null ? { sendTag: notice.sendTag } : {}),
    title: notice.title,
    ...(notice.sendTime != null ? { sendTime: notice.sendTime } : {}),
    ...(notice.content != null ? { content: notice.content } : {}),
    taskLinks: [...notice.taskLinks],
  };
}

export function boundSeenNotices(notices: readonly SeenNotice[]): SeenNotice[] {
  const bounded = new Map<string, SeenNotice>();
  for (const notice of notices) {
    if (notice.id.length === 0 || bounded.size >= MAX_SEEN_NOTICES) {
      continue;
    }
    if (!bounded.has(notice.id)) {
      bounded.set(notice.id, notice);
    }
  }
  return [...bounded.values()];
}

export function syncStatsFromJson(json: Record<string, unknown>): SyncStats {
  const count = (key: keyof SyncStats): number =>
    typeof json[key] === "number" ? Math.round(json[key]) : 0;
  return {
    durationMs: count("durationMs"),
    authenticationMs: count("authenticationMs"),
    inboxMs: count("inboxMs"),
    noticeDetailsMs: count("noticeDetailsMs"),
    assignmentDetailsMs: count("assignmentDetailsMs"),
    coursesMs: count("coursesMs"),
    inboxMessages: count("inboxMessages"),
    relevantNotices: count("relevantNotices"),
    detailSummaries: count("detailSummaries"),
    inboxTaskLinks: count("inboxTaskLinks"),
    inboxTaskDetails: count("inboxTaskDetails"),
    statusFilteredItems: count("statusFilteredItems"),
    courses: count("courses"),
    courseTaskLinksDiscovered: count("courseTaskLinksDiscovered"),
    courseTaskLinks: count("courseTaskLinks"),
    courseTaskStatusFiltered: count("courseTaskStatusFiltered"),
    itemCandidates: count("itemCandidates"),
    courseSourcesEnabled: json.courseSourcesEnabled === true,
  };
}

export function failureFromJson(json: Record<string, unknown>): AppSyncFailure {
  return {
    entryUrl: redactSensitiveUrl(readString(json, "entryUrl")),
    sourceTitle: redactSensitiveText(readString(json, "sourceTitle")),
    message: redactSensitiveText(readString(json, "message")),
  };
}

export function failureToJson(failure: AppSyncFailure): Record<string, unknown> {
  return {
    entryUrl: redactSensitiveUrl(failure.entryUrl),
    sourceTitle: redactSensitiveText(failure.sourceTitle),
    message: redactSensitiveText(failure.message),
  };
}

export function appSyncResponseFromJson(
  json: Record<string, unknown>,
): AppSyncResponse {
  const rawItems = json.items;
  const rawFailures = json.failures;
  return {
    lastSyncedAt: parseDueAt(json.lastSyncedAt),
    authStatus: readString(json, "authStatus"),
    items: Array.isArray(rawItems)
      ? rawItems
          .map((item) => asRecord(item))
          .filter((item): item is Record<string, unknown> => item !== null)
          .map(syncItemFromJson)
      : [],
    failures: Array.isArray(rawFailures)
      ? rawFailures
          .map((failure) => asRecord(failure))
          .filter((failure): failure is Record<string, unknown> => failure !== null)
          .map(failureFromJson)
      : [],
    stats: asRecord(json.stats) ? syncStatsFromJson(asRecord(json.stats)!) : emptySyncStats,
    seenNotices: readSeenNotices(json.seenNotices),
  };
}

export function appSyncResponseToJson(
  response: AppSyncResponse,
): Record<string, unknown> {
  return {
    lastSyncedAt: response.lastSyncedAt?.toISOString() ?? null,
    authStatus: response.authStatus,
    items: response.items.map(syncItemToJson),
    failures: response.failures.map(failureToJson),
    stats: { ...response.stats },
    seenNotices: response.seenNotices.map(seenNoticeToJson),
  };
}

export function buildAppSyncResponse(input: {
  now: Date;
  lastSyncedAt: Date;
  items: readonly SyncItem[];
  failures: readonly AppSyncFailure[];
  authStatus?: string;
  stats?: SyncStats;
  seenNotices?: readonly SeenNotice[];
}): AppSyncResponse {
  const enriched = mergeItems(input.items)
    .map((item) => enrichSyncItem(item, input.now))
    .sort(compareAppSyncItems);
  const sanitizedFailures = input.failures
    .map((failure) => ({
      entryUrl: redactSensitiveUrl(failure.entryUrl),
      sourceTitle: redactSensitiveText(failure.sourceTitle),
      message: redactSensitiveText(failure.message),
    }))
    .sort(compareFailures);
  return {
    lastSyncedAt: input.lastSyncedAt,
    authStatus: input.authStatus ?? "ok",
    items: enriched,
    stats: input.stats ?? emptySyncStats,
    failures: sanitizedFailures,
    seenNotices: boundSeenNotices(input.seenNotices ?? []),
  };
}

export function mergeItems(items: readonly SyncItem[]): SyncItem[] {
  const candidates = [...items].sort(compareMergeCandidates);
  const merged = new Map<string, SyncItem>();
  for (const item of candidates) {
    const current = merged.get(item.id);
    if (current === undefined) {
      merged.set(item.id, item);
      continue;
    }
    const sources = [...new Set([...(current.sources ?? []), ...(item.sources ?? [])])].sort();
    merged.set(
      item.id,
      copySyncItem(current, {
        title: preferText(current.title, item.title),
        url: preferText(current.url, item.url),
        sourceTitle: preferText(current.sourceTitle, item.sourceTitle),
        sourceSendTime: current.sourceSendTime ?? item.sourceSendTime,
        startAt: current.startAt ?? item.startAt,
        dueAt: current.dueAt ?? item.dueAt,
        status: preferText(current.status ?? "", item.status ?? ""),
        courseId: current.courseId ?? item.courseId,
        classId: current.classId ?? item.classId,
        workId: current.workId ?? item.workId,
        examId: current.examId ?? item.examId,
        answerId: current.answerId ?? item.answerId,
        sources,
      }),
    );
  }
  return [...merged.values()];
}

function readSeenNotices(raw: unknown): SeenNotice[] {
  if (!Array.isArray(raw)) {
    return [];
  }
  return boundSeenNotices(
    raw
      .map((notice) => asRecord(notice))
      .filter((notice): notice is Record<string, unknown> => notice !== null)
      .map(seenNoticeFromJson),
  );
}

function preferText(current: string, candidate: string): string {
  const currentTrimmed = current.trim();
  const candidateTrimmed = candidate.trim();
  if (currentTrimmed.length === 0) {
    return candidate;
  }
  if (candidateTrimmed.length === 0) {
    return current;
  }
  const lengthComparison = candidateTrimmed.length - currentTrimmed.length;
  if (lengthComparison !== 0) {
    return lengthComparison > 0 ? candidate : current;
  }
  return candidate < current ? candidate : current;
}

function compareMergeCandidates(left: SyncItem, right: SyncItem): number {
  const sourceComparison = mergeSourceRank(left) - mergeSourceRank(right);
  if (sourceComparison !== 0) {
    return sourceComparison;
  }
  return mergeFingerprint(left).localeCompare(mergeFingerprint(right));
}

function mergeSourceRank(item: SyncItem): number {
  const sources = item.sources ?? [];
  if (sources.some((source) => source === "course_work" || source === "course_exam")) {
    return 0;
  }
  return sources.includes("inbox") ? 1 : 2;
}

function mergeFingerprint(item: SyncItem): string {
  const sources = [...(item.sources ?? [])].sort();
  return [
    item.id,
    item.kind,
    item.title,
    item.url,
    item.sourceTitle,
    item.sourceSendTime ?? "",
    item.startAt?.toISOString() ?? "",
    item.dueAt?.toISOString() ?? "",
    item.status ?? "",
    item.courseId ?? "",
    item.classId ?? "",
    item.workId ?? "",
    item.examId ?? "",
    item.answerId ?? "",
    sources.join("\u0000"),
  ].join("\u0001");
}

function compareAppSyncItems(left: SyncItem, right: SyncItem): number {
  if (left.dueAt === null && right.dueAt === null) {
    return compareTitleThenId(left, right);
  }
  if (left.dueAt === null) {
    return 1;
  }
  if (right.dueAt === null) {
    return -1;
  }
  const dueComparison = left.dueAt.getTime() - right.dueAt.getTime();
  return dueComparison !== 0 ? dueComparison : compareTitleThenId(left, right);
}

function compareTitleThenId(left: SyncItem, right: SyncItem): number {
  const titleComparison = left.title.localeCompare(right.title);
  return titleComparison !== 0 ? titleComparison : left.id.localeCompare(right.id);
}

function compareFailures(left: AppSyncFailure, right: AppSyncFailure): number {
  const urlComparison = left.entryUrl.localeCompare(right.entryUrl);
  if (urlComparison !== 0) {
    return urlComparison;
  }
  const sourceComparison = left.sourceTitle.localeCompare(right.sourceTitle);
  return sourceComparison !== 0
    ? sourceComparison
    : left.message.localeCompare(right.message);
}
