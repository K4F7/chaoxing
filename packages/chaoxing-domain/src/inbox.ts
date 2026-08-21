import { NOTICE_ORIGIN } from "./constants";
import {
  decodeBase64Utf8,
  decodeBasicHtmlEntities,
  extractPageTitle,
  findTaggedElements,
  stripHtml,
} from "./html";
import {
  asRecord,
  collectStringValues,
  isTruthy,
  mapValue,
  nullableString,
  stringOrEmpty,
} from "./json";
import { buildNoticeDetailPageUrl, isWorkOrExamLink, resolveTrustedUrl } from "./urls";
import { isTrustedChaoxingUrl } from "./url-policy";

export type InboxMessage = {
  id: string;
  uuid: string | null;
  title: string;
  sender: string | null;
  sendTime: string | null;
  isRead: boolean;
  content: string | null;
  detailUrl: string | null;
  sendTag: unknown;
};

export type DetailSummary = {
  title: string;
  sendTime: string | null;
  content: string | null;
  assignmentLinks: readonly string[];
};

export type InboxPageConfig = {
  type: string;
  noticeType: string;
  year: string;
  folderUuid: string;
  fidsCode: string;
};

export type NoticePage = {
  items: unknown[];
  topNotices: unknown[];
  urgentNotices: unknown[];
  lastGetId: string;
  lastPage: boolean;
};

export function inboxMessageIdentity(message: InboxMessage): string {
  return message.uuid ?? message.id;
}

export function isAssignmentOrExamRelated(message: InboxMessage): boolean {
  if (message.title.includes("结束提醒")) {
    return false;
  }
  return /作业|考试|测验|测试|截止|结束提醒|答题|试卷|练习/.test(
    `${message.title}\n${message.content ?? ""}`,
  );
}

export function findInboxUrl(html: string, _baseUrl: string): string | null {
  const exact = html.match(
    /https:\/\/notice\.chaoxing\.com\/pc\/notice\/myNotice\?s=[^"'\s<)]+/,
  )?.[0];
  if (exact !== undefined) {
    return exact;
  }
  const relative = html.match(/\/pc\/notice\/myNotice\?s=[^"'\s<)]+/)?.[0];
  if (relative === undefined) {
    return null;
  }
  return new URL(relative, NOTICE_ORIGIN).toString();
}

export function extractInboxPageConfig(
  html: string,
  now: Date = new Date(),
): InboxPageConfig {
  return {
    type: extractWindowString(html, "type") ?? "2",
    noticeType: extractWindowString(html, "noticeType") ?? "",
    year: extractWindowString(html, "nowYear") ?? String(now.getFullYear()),
    folderUuid: extractWindowString(html, "folderUUID") ?? "",
    fidsCode: extractWindowString(html, "fidsCode") ?? "",
  };
}

export function extractNoticePage(data: Record<string, unknown>): NoticePage {
  const containers: Record<string, unknown>[] = [data];
  let cursor = 0;
  while (cursor < containers.length && containers.length < 12) {
    const current = containers[cursor];
    cursor += 1;
    for (const key of ["notices", "data", "result", "page", "payload"]) {
      const child = asRecord(mapValue(current, key));
      if (child !== null && !containers.includes(child)) {
        containers.push(child);
      }
    }
  }

  const readFirstList = (keys: readonly string[]): unknown[] => {
    for (const container of containers) {
      for (const key of keys) {
        const value = mapValue(container, key);
        if (Array.isArray(value)) {
          return value;
        }
      }
    }
    return [];
  };

  const directData = mapValue(data, "data");
  const items = Array.isArray(directData)
    ? directData
    : readFirstList(["list", "rows", "records", "items", "notices"]);

  const firstText = (keys: readonly string[]): string => {
    for (const container of containers) {
      for (const key of keys) {
        const value = nullableString(mapValue(container, key));
        if (value !== null) {
          return value;
        }
      }
    }
    return "";
  };

  const firstTruthy = (keys: readonly string[]): boolean => {
    for (const container of containers) {
      for (const key of keys) {
        const value = mapValue(container, key);
        if (value != null && isTruthy(value)) {
          return true;
        }
      }
    }
    return false;
  };

  return {
    items,
    topNotices: readFirstList(["topNotices", "topList"]),
    urgentNotices: readFirstList(["urgentNotices", "urgentList"]),
    lastGetId: firstText([
      "lastGetId",
      "lastId",
      "nextId",
      "nextValue",
      "cursor",
      "nextCursor",
    ]),
    lastPage: firstTruthy(["lastPage", "isLastPage", "finished"]),
  };
}

export function extractNoticeDetail(
  decoded: Record<string, unknown>,
): Record<string, unknown> {
  const containers: Record<string, unknown>[] = [decoded];
  let cursor = 0;
  while (cursor < containers.length && containers.length < 12) {
    const current = containers[cursor];
    cursor += 1;
    if (
      mapValue(current, "content") != null ||
      mapValue(current, "rtf_content") != null ||
      mapValue(current, "rtfContent") != null
    ) {
      return current;
    }
    for (const key of ["msg", "data", "detail", "notice", "result"]) {
      const child = asRecord(mapValue(current, key));
      if (child !== null && !containers.includes(child)) {
        containers.push(child);
      }
    }
  }
  return containers.length > 1 ? containers[1] : decoded;
}

export function normalizeNotice(notice: Record<string, unknown>): InboxMessage {
  const id = stringOrEmpty(notice.idCode)
    ? stringOrEmpty(notice.idCode)
    : stringOrEmpty(notice.id)
      ? stringOrEmpty(notice.id)
      : stringOrEmpty(notice.uuid);
  const uuid = nullableString(notice.uuid);
  const sendTag = notice.sendTag;
  const content = stripHtml(
    stringOrEmpty(notice.content)
      ? stringOrEmpty(notice.content)
      : stringOrEmpty(notice.rtf_content),
  );
  return {
    id,
    uuid,
    title: stringOrEmpty(notice.title)
      ? stringOrEmpty(notice.title)
      : typeof notice.noticeTitle === "string" && notice.noticeTitle.length > 0
        ? notice.noticeTitle
        : "(无标题)",
    sender: nullableString(notice.createrName) ?? nullableString(notice.senderName),
    sendTime:
      nullableString(notice.sendTime) ??
      nullableString(notice.createTime) ??
      normalizeTimestamp(notice.insertTime),
    isRead: notice.isread === true || notice.isread === 1,
    content: content.length === 0 ? null : content,
    detailUrl:
      id.length === 0 && uuid === null
        ? null
        : buildNoticeDetailPageUrl(uuid ?? id, sendTag),
    sendTag,
  };
}

export function extractNoticeLinks(text: string): string[] {
  const seen = new Set<string>();
  const links: string[] = [];
  const decoded = decodeBasicHtmlEntities(text)
    .replaceAll("\\/", "/")
    .replaceAll("\\u0026", "&");

  const addCandidate = (raw: string): void => {
    const resolved = resolveTrustedUrl(raw, NOTICE_ORIGIN);
    if (resolved === null) {
      return;
    }
    const link = resolved.toString();
    if (isWorkOrExamLink(link) && !seen.has(link)) {
      seen.add(link);
      links.push(link);
    }
  };

  for (const match of decoded.matchAll(/(?:https?:)?\/\/[^"'\s<>)\[\]\\]+/gi)) {
    addCandidate(match[0]);
  }

  for (const element of findTaggedElements(
    decoded,
    (_tag, attrs) =>
      attrs.href !== undefined ||
      attrs.src !== undefined ||
      attrs.data !== undefined ||
      attrs.dataurl !== undefined ||
      attrs["data-url"] !== undefined,
  )) {
    for (const name of ["href", "src", "data", "dataurl", "data-url"]) {
      const value = element.attrs[name];
      if (value !== undefined) {
        addCandidate(value);
      }
    }
  }

  for (const match of decoded.matchAll(
    /["']((?:\/|\.\.?\/)[^"']*(?:work|exam)[^"']*)["']/gi,
  )) {
    addCandidate(match[1]);
  }
  return links;
}

export function collectUniqueWorkLinks(
  summaries: readonly DetailSummary[],
): Map<string, DetailSummary> {
  const unique = new Map<string, DetailSummary>();
  for (const summary of summaries) {
    for (const link of summary.assignmentLinks) {
      if (isWorkOrExamLink(link) && !unique.has(link)) {
        unique.set(link, summary);
      }
    }
  }
  return unique;
}

export function parseNoticeDetailSummary(input: {
  message: InboxMessage;
  decoded: Record<string, unknown>;
}): DetailSummary {
  const detail = extractNoticeDetail(input.decoded);
  const rawContent = stringOrEmpty(mapValue(detail, "content"));
  const rawRtf = stringOrEmpty(
    mapValue(detail, "rtf_content") ?? mapValue(detail, "rtfContent"),
  );
  const content = stripHtml(rawContent.length > 0 ? rawContent : rawRtf);
  const decodedAttachments = decodeIframeNames(rawRtf);
  const links = extractNoticeLinks(
    `${rawRtf}\n${collectStringValues(decodedAttachments).join("\n")}\n${collectStringValues(input.decoded).join("\n")}`,
  );
  return {
    title: input.message.title,
    sendTime: input.message.sendTime,
    content: content.length === 0 ? null : content,
    assignmentLinks: links,
  };
}

export function decodeIframeNames(html: string): unknown[] {
  const names = [...html.matchAll(/<iframe\b[^>]*\bname=["']([^"']+)["'][^>]*>/gi)].map(
    (match) => match[1],
  );
  const decoded: unknown[] = [];
  for (const name of names) {
    const candidates = [
      () => JSON.parse(decodeURIComponent(name)) as unknown,
      () => JSON.parse(decodeBase64Utf8(decodeURIComponent(name))) as unknown,
    ];
    for (const decode of candidates) {
      try {
        decoded.push(decode());
        break;
      } catch {
        // Try the next encoding.
      }
    }
  }
  return decoded;
}

function extractWindowString(html: string, key: string): string | null {
  return (
    html.match(new RegExp(`window\\.${key}\\s*=\\s*['"]([^'"]*)['"]`, "i"))?.[1] ??
    null
  );
}

function normalizeTimestamp(value: unknown): string | null {
  if (value == null) {
    return null;
  }
  const parsed = new Date(String(value));
  return Number.isNaN(parsed.getTime()) ? String(value) : parsed.toISOString();
}

export { extractPageTitle, isTrustedChaoxingUrl };
