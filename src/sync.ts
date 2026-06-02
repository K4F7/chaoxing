import type { AssignmentRequirement } from "./requirements";

const DEFAULT_TIME_ZONE_OFFSET = "+08:00";
const DEADLINE_EVENT_MINUTES = 30;
const DEFAULT_REMINDER_MINUTES = 60;

export type SyncItemKind = "assignment" | "exam";

export type SyncItem = {
  id: string;
  kind: SyncItemKind;
  title: string;
  url: string;
  sourceTitle: string;
  sourceSendTime: string | null;
  startAt: string | null;
  dueAt: string | null;
  status: AssignmentRequirement["workStatus"];
  courseId: string | null;
  classId: string | null;
  workId: string | null;
  answerId: string | null;
};

export function buildSyncItems(
  requirements: AssignmentRequirement[],
  options: { generatedAt?: Date } = {},
): SyncItem[] {
  return requirements
    .map((requirement) => buildSyncItem(requirement, options.generatedAt || new Date()))
    .filter((item): item is SyncItem => item !== null);
}

export function buildCalendarIcs(
  items: SyncItem[],
  options: { generatedAt?: Date; calendarName?: string } = {},
): string {
  const generatedAt = options.generatedAt || new Date();
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Chaoxing Worker//Assignments//ZH-CN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    `X-WR-CALNAME:${escapeIcsText(options.calendarName || "学习通作业考试")}`,
  ];

  for (const item of items) {
    if (!item.dueAt) {
      continue;
    }

    lines.push(...buildCalendarEventLines(item, generatedAt));
  }

  lines.push("END:VCALENDAR");
  return foldIcsLines(lines).join("\r\n") + "\r\n";
}

export function buildTodoIcs(
  items: SyncItem[],
  options: { generatedAt?: Date; calendarName?: string } = {},
): string {
  const generatedAt = options.generatedAt || new Date();
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Chaoxing Worker//Todos//ZH-CN",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    `X-WR-CALNAME:${escapeIcsText(options.calendarName || "学习通待办")}`,
  ];

  for (const item of items) {
    if (!item.dueAt) {
      continue;
    }

    lines.push(...buildTodoLines(item, generatedAt));
  }

  lines.push("END:VCALENDAR");
  return foldIcsLines(lines).join("\r\n") + "\r\n";
}

export function buildCalendarObjectIcs(
  item: SyncItem,
  options: { generatedAt?: Date } = {},
): string {
  const generatedAt = options.generatedAt || new Date();
  return wrapCalendarObject(buildCalendarEventLines(item, generatedAt));
}

export function buildTodoObjectIcs(
  item: SyncItem,
  options: { generatedAt?: Date } = {},
): string {
  const generatedAt = options.generatedAt || new Date();
  return wrapCalendarObject(buildTodoLines(item, generatedAt));
}

function buildCalendarEventLines(item: SyncItem, generatedAt: Date): string[] {
  if (!item.dueAt) {
    return [];
  }

  const start = new Date(item.dueAt);
  const end = new Date(start.getTime() + DEADLINE_EVENT_MINUTES * 60 * 1000);
  return [
    "BEGIN:VEVENT",
    `UID:${escapeIcsText(`${item.id}@chaoxing-worker`)}`,
    `DTSTAMP:${formatIcsDate(generatedAt)}`,
    `CREATED:${formatIcsDate(generatedAt)}`,
    `LAST-MODIFIED:${formatIcsDate(generatedAt)}`,
    `DTSTART:${formatIcsDate(start)}`,
    `DTEND:${formatIcsDate(end)}`,
    `SUMMARY:${escapeIcsText(`${kindLabel(item.kind)}截止：${item.title}`)}`,
    `DESCRIPTION:${escapeIcsText(buildDescription(item))}`,
    `CATEGORIES:${escapeIcsText(kindLabel(item.kind))}`,
    `URL:${escapeIcsText(item.url)}`,
    ...buildAlarmLines(`距离${kindLabel(item.kind)}截止还有 1 小时`),
    "END:VEVENT",
  ];
}

function buildTodoLines(item: SyncItem, generatedAt: Date): string[] {
  if (!item.dueAt) {
    return [];
  }

  return [
    "BEGIN:VTODO",
    `UID:${escapeIcsText(`${item.id}.todo@chaoxing-worker`)}`,
    `DTSTAMP:${formatIcsDate(generatedAt)}`,
    `CREATED:${formatIcsDate(generatedAt)}`,
    `LAST-MODIFIED:${formatIcsDate(generatedAt)}`,
    ...(item.startAt ? [`DTSTART:${formatIcsDate(new Date(item.startAt))}`] : []),
    `DUE:${formatIcsDate(new Date(item.dueAt))}`,
    "STATUS:NEEDS-ACTION",
    "PERCENT-COMPLETE:0",
    "PRIORITY:5",
    `SUMMARY:${escapeIcsText(`${kindLabel(item.kind)}：${item.title}`)}`,
    `DESCRIPTION:${escapeIcsText(buildDescription(item))}`,
    `CATEGORIES:${escapeIcsText(kindLabel(item.kind))}`,
    `URL:${escapeIcsText(item.url)}`,
    ...buildAlarmLines(`距离${kindLabel(item.kind)}截止还有 1 小时`),
    "END:VTODO",
  ];
}

function buildAlarmLines(description: string): string[] {
  return [
    "BEGIN:VALARM",
    "ACTION:DISPLAY",
    `DESCRIPTION:${escapeIcsText(description)}`,
    `TRIGGER:-PT${DEFAULT_REMINDER_MINUTES}M`,
    "END:VALARM",
  ];
}

function wrapCalendarObject(lines: string[]): string {
  return (
    foldIcsLines([
      "BEGIN:VCALENDAR",
      "VERSION:2.0",
      "PRODID:-//Chaoxing Worker//CalDAV//ZH-CN",
      "CALSCALE:GREGORIAN",
      ...lines,
      "END:VCALENDAR",
    ]).join("\r\n") + "\r\n"
  );
}

function buildSyncItem(
  requirement: AssignmentRequirement,
  generatedAt: Date,
): SyncItem | null {
  const dueAt = parseChaoxingDateTime(
    requirement.timeWindow.end,
    requirement.sourceSendTime,
    generatedAt,
  );
  const startAt = parseChaoxingDateTime(
    requirement.timeWindow.start,
    requirement.sourceSendTime,
    generatedAt,
  );

  if (!dueAt) {
    return null;
  }

  const kind = inferKind(requirement);
  const stableId =
    requirement.workId ||
    readUrlParam(requirement.finalUrl, "examId") ||
    readUrlParam(requirement.entryUrl, "examId") ||
    hashString(requirement.finalUrl || requirement.entryUrl);

  return {
    id: `${kind}-${stableId}`,
    kind,
    title:
      requirement.sourceTitle ||
      requirement.pageTitle ||
      (kind === "exam" ? "考试" : "作业"),
    url: requirement.finalUrl || requirement.entryUrl,
    sourceTitle: requirement.sourceTitle,
    sourceSendTime: requirement.sourceSendTime,
    startAt: startAt?.toISOString() || null,
    dueAt: dueAt.toISOString(),
    status: requirement.workStatus,
    courseId: requirement.courseId,
    classId: requirement.classId,
    workId: requirement.workId,
    answerId: requirement.answerId,
  };
}

function parseChaoxingDateTime(
  value: string | null,
  sourceSendTime: string | null,
  fallbackDate: Date,
): Date | null {
  if (!value) {
    return null;
  }

  const normalized = value.trim().replace(/\//g, "-");
  const withYear = normalized.match(
    /^(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?$/,
  );
  if (withYear) {
    return dateFromParts(withYear[1], withYear[2], withYear[3], withYear[4], withYear[5], withYear[6]);
  }

  const withoutYear = normalized.match(
    /^(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?$/,
  );
  if (withoutYear) {
    const year = inferYear(Number(withoutYear[1]), sourceSendTime, fallbackDate);
    return dateFromParts(String(year), withoutYear[1], withoutYear[2], withoutYear[3], withoutYear[4], withoutYear[5]);
  }

  const parsed = new Date(normalized);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}

function inferYear(
  month: number,
  sourceSendTime: string | null,
  fallbackDate: Date,
): number {
  const source = sourceSendTime ? parseChaoxingDateTime(sourceSendTime, null, fallbackDate) : null;
  const base = source || fallbackDate;
  const year = base.getUTCFullYear();
  const sourceMonth = base.getUTCMonth() + 1;
  return sourceMonth === 12 && month === 1 ? year + 1 : year;
}

function dateFromParts(
  year: string,
  month: string,
  day: string,
  hour: string,
  minute: string,
  second = "0",
): Date {
  const padded = [month, day, hour, minute, second].map((part) =>
    part.padStart(2, "0"),
  );
  return new Date(
    `${year}-${padded[0]}-${padded[1]}T${padded[2]}:${padded[3]}:${padded[4]}${DEFAULT_TIME_ZONE_OFFSET}`,
  );
}

function inferKind(requirement: AssignmentRequirement): SyncItemKind {
  const text = `${requirement.entryUrl}\n${requirement.finalUrl}\n${requirement.sourceTitle}\n${requirement.pageTitle || ""}`;
  return /workOrExam=exam|\/exam\b|考试|测验|测试|试卷/i.test(text)
    ? "exam"
    : "assignment";
}

function kindLabel(kind: SyncItemKind): string {
  return kind === "exam" ? "考试" : "作业";
}

function buildDescription(item: SyncItem): string {
  return [
    `来源：${item.sourceTitle}`,
    item.sourceSendTime ? `通知时间：${item.sourceSendTime}` : "",
    item.startAt ? `开始：${item.startAt}` : "",
    item.dueAt ? `截止：${item.dueAt}` : "",
    `链接：${item.url}`,
  ]
    .filter(Boolean)
    .join("\n");
}

function formatIcsDate(date: Date): string {
  return date.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
}

function escapeIcsText(value: string): string {
  return value
    .replace(/\\/g, "\\\\")
    .replace(/\n/g, "\\n")
    .replace(/,/g, "\\,")
    .replace(/;/g, "\\;");
}

function foldIcsLines(lines: string[]): string[] {
  return lines.flatMap((line) => {
    if (line.length <= 75) {
      return [line];
    }

    const folded: string[] = [];
    for (let index = 0; index < line.length; index += 74) {
      folded.push(index === 0 ? line.slice(index, index + 74) : ` ${line.slice(index, index + 74)}`);
    }
    return folded;
  });
}

function readUrlParam(url: string, key: string): string | null {
  try {
    return new URL(url).searchParams.get(key);
  } catch {
    return null;
  }
}

function hashString(value: string): string {
  let hash = 5381;
  for (let index = 0; index < value.length; index += 1) {
    hash = (hash * 33) ^ value.charCodeAt(index);
  }
  return (hash >>> 0).toString(36);
}
