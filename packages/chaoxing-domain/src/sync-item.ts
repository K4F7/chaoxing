import { readNullableString, readString } from "./json";

export const SyncItemKind = {
  assignment: "assignment",
  exam: "exam",
} as const;

export type SyncItemKind = (typeof SyncItemKind)[keyof typeof SyncItemKind];

export const SyncDisplayStatus = {
  overdue: "overdue",
  today: "today",
  upcoming: "upcoming",
  unscheduled: "unscheduled",
} as const;

export type SyncDisplayStatus =
  (typeof SyncDisplayStatus)[keyof typeof SyncDisplayStatus];

export type SyncItem = {
  id: string;
  kind: SyncItemKind;
  title: string;
  url: string;
  sourceTitle: string;
  dueAt: Date | null;
  sourceSendTime?: string | null;
  startAt?: Date | null;
  status?: string;
  displayStatus?: SyncDisplayStatus;
  dueInHours?: number | null;
  courseId?: string | null;
  classId?: string | null;
  workId?: string | null;
  examId?: string | null;
  answerId?: string | null;
  sources?: readonly string[];
};

export function parseSyncItemKind(value: unknown): SyncItemKind {
  return value === SyncItemKind.exam
    ? SyncItemKind.exam
    : SyncItemKind.assignment;
}

export function parseDisplayStatus(value: unknown): SyncDisplayStatus {
  return value === SyncDisplayStatus.overdue ||
    value === SyncDisplayStatus.today ||
    value === SyncDisplayStatus.upcoming
    ? value
    : SyncDisplayStatus.unscheduled;
}

export function parseDueAt(value: unknown): Date | null {
  if (typeof value !== "string" || value.length === 0) {
    return null;
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

export function syncItemFromJson(json: Record<string, unknown>): SyncItem {
  const rawSources = json.sources;
  return {
    id: readString(json, "id"),
    kind: parseSyncItemKind(json.kind),
    title: readString(json, "title"),
    url: readString(json, "url"),
    sourceTitle: readString(json, "sourceTitle"),
    sourceSendTime: readNullableString(json, "sourceSendTime"),
    startAt: parseDueAt(json.startAt),
    dueAt: parseDueAt(json.dueAt),
    status: readString(json, "status"),
    displayStatus: parseDisplayStatus(json.displayStatus),
    dueInHours: typeof json.dueInHours === "number" ? Math.round(json.dueInHours) : null,
    courseId: readNullableString(json, "courseId"),
    classId: readNullableString(json, "classId"),
    workId: readNullableString(json, "workId"),
    examId: readNullableString(json, "examId"),
    answerId: readNullableString(json, "answerId"),
    sources: Array.isArray(rawSources)
      ? rawSources.filter(
          (source): source is string =>
            typeof source === "string" && source.length > 0,
        )
      : [],
  };
}

export function syncItemToJson(item: SyncItem): Record<string, unknown> {
  return {
    id: item.id,
    kind: item.kind,
    title: item.title,
    url: item.url,
    sourceTitle: item.sourceTitle,
    sourceSendTime: item.sourceSendTime ?? null,
    startAt: item.startAt?.toISOString() ?? null,
    dueAt: item.dueAt?.toISOString() ?? null,
    status: item.status ?? "",
    displayStatus: item.displayStatus ?? SyncDisplayStatus.unscheduled,
    dueInHours: item.dueInHours ?? null,
    courseId: item.courseId ?? null,
    classId: item.classId ?? null,
    workId: item.workId ?? null,
    examId: item.examId ?? null,
    answerId: item.answerId ?? null,
    sources: [...(item.sources ?? [])],
  };
}

export function copySyncItem(
  item: SyncItem,
  patch: Partial<SyncItem>,
): SyncItem {
  return { ...item, ...patch };
}
