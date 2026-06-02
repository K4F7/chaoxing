import { fetchInboxMessages, type InboxMessage } from "./inbox";
import {
  parseAssignmentRequirement,
  type AssignmentRequirement,
} from "./requirements";

const DEFAULT_INBOX_LIMIT = 100;
const DEFAULT_DETAILS_LIMIT = 10;
const DEFAULT_REQUIREMENTS_LIMIT = 40;

export type ProcessingOptions = {
  cookie?: string;
  homeUrl?: string;
  inboxLimit?: number;
  detailsLimit?: number;
  requirementsLimit?: number;
  fetcher?: typeof fetch;
};

export type DetailSummary = {
  title: string;
  sendTime: string | null;
  detailStatus: number;
  apiStatus: boolean;
  detailTitle: string | null;
  sourceType: unknown;
  content: string | null;
  assignmentLinks: string[];
  decodedAttachments: unknown[];
};

export type RequirementFetchFailure = {
  entryUrl: string;
  sourceTitle: string;
  message: string;
};

export type ProcessingResult = {
  processedAt: string;
  inbox: {
    fetched: number;
    relevant: number;
    inspectedDetails: number;
  };
  totalUniqueActivityLinks: number;
  totalUniqueWorkLinks: number;
  fetchedRequirements: number;
  failedRequirements: RequirementFetchFailure[];
  requirements: AssignmentRequirement[];
};

export async function processAssignments(
  options: ProcessingOptions,
): Promise<ProcessingResult> {
  const cookie = options.cookie?.trim();
  if (!cookie) {
    throw new Error("missing CHAOXING_COOKIE");
  }

  const fetcher = options.fetcher ?? fetch;
  const inboxLimit = normalizeLimit(options.inboxLimit, DEFAULT_INBOX_LIMIT, 500);
  const detailsLimit = normalizeLimit(
    options.detailsLimit,
    DEFAULT_DETAILS_LIMIT,
    100,
  );
  const requirementsLimit = normalizeLimit(
    options.requirementsLimit,
    DEFAULT_REQUIREMENTS_LIMIT,
    100,
  );
  const result = await fetchInboxMessages({
    cookie,
    homeUrl: options.homeUrl,
    limit: inboxLimit,
    fetcher,
  });

  const relevant = result.messages.filter(isAssignmentOrExamRelated);
  const summaries: DetailSummary[] = [];
  for (const message of relevant.slice(0, detailsLimit)) {
    summaries.push(await fetchDetailSummary({ message, cookie, fetcher }));
  }

  const unique = collectUniqueWorkLinks(summaries);
  const requirements: AssignmentRequirement[] = [];
  const failedRequirements: RequirementFetchFailure[] = [];

  for (const [entryUrl, summary] of unique) {
    if (requirements.length >= requirementsLimit) {
      break;
    }

    try {
      requirements.push(
        await fetchAssignmentRequirement({ entryUrl, summary, cookie, fetcher }),
      );
    } catch (error) {
      failedRequirements.push({
        entryUrl,
        sourceTitle: summary.title,
        message: error instanceof Error ? error.message : "unknown error",
      });
    }
  }

  return {
    processedAt: new Date().toISOString(),
    inbox: {
      fetched: result.totalFetched,
      relevant: relevant.length,
      inspectedDetails: summaries.length,
    },
    totalUniqueActivityLinks: unique.size,
    totalUniqueWorkLinks: unique.size,
    fetchedRequirements: requirements.length,
    failedRequirements,
    requirements,
  };
}

export function isAssignmentOrExamRelated(message: InboxMessage): boolean {
  return /作业|考试|测验|测试|截止|结束提醒|答题|试卷|练习/.test(
    `${message.title}\n${message.content || ""}`,
  );
}

export async function fetchDetailSummary(input: {
  message: InboxMessage;
  cookie: string;
  fetcher?: typeof fetch;
}): Promise<DetailSummary> {
  const fetcher = input.fetcher ?? fetch;
  const id = input.message.uuid || input.message.id;
  const sendTag = input.message.sendTag ?? 0;
  const url = `https://notice.chaoxing.com/pc/notice/${id}/getNoticeDetail?sendTag=${sendTag}`;
  const response = await fetcher(url, {
    headers: {
      Accept: "application/json, text/javascript, */*; q=0.01",
      Cookie: input.cookie,
      Referer:
        input.message.detailUrl ||
        "https://notice.chaoxing.com/pc/notice/myNotice",
      "User-Agent": "Mozilla/5.0",
      "X-Requested-With": "XMLHttpRequest",
    },
  });
  if (!response.ok) {
    throw new Error(`notice_detail_fetch_failed_${response.status}`);
  }

  const data = (await response.json()) as {
    status?: boolean;
    msg?: Record<string, unknown>;
  };
  const detail = (data.msg || {}) as Record<string, unknown>;
  const content =
    stripHtml(toStringValue(detail.content) || toStringValue(detail.rtf_content)) ||
    null;
  const rtf = String(detail.rtf_content || "");
  const decodedAttachments = decodeIframeNames(rtf);
  const assignmentLinks = [
    ...extractUrls(rtf),
    ...extractUrls(JSON.stringify(decodedAttachments)),
  ].filter((link, index, array) => {
    return (
      /(exam|work|homework|task|mooc1|course|clazz|classId|courseId|examOrWork)/i.test(
        link,
      ) && array.indexOf(link) === index
    );
  });

  return {
    title: input.message.title,
    sendTime: input.message.sendTime,
    detailStatus: response.status,
    apiStatus: Boolean(data.status),
    detailTitle: toStringValue(detail.title) || null,
    sourceType: detail.sourceType,
    content,
    assignmentLinks,
    decodedAttachments,
  };
}

export function collectUniqueWorkLinks(
  summaries: DetailSummary[],
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

function isWorkOrExamLink(link: string): boolean {
  return /workOrExam=(?:work|exam)/i.test(link) || /\/(?:work|exam)\b/i.test(link);
}

async function fetchAssignmentRequirement(input: {
  entryUrl: string;
  summary: DetailSummary;
  cookie: string;
  fetcher: typeof fetch;
}): Promise<AssignmentRequirement> {
  const response = await input.fetcher(input.entryUrl, {
    redirect: "follow",
    headers: {
      Accept: "text/html,application/xhtml+xml",
      Cookie: input.cookie,
      Referer: "https://notice.chaoxing.com/pc/notice/myNotice",
      "User-Agent": "Mozilla/5.0",
    },
  });
  if (!response.ok) {
    throw new Error(`assignment_fetch_failed_${response.status}`);
  }

  const html = await response.text();
  return parseAssignmentRequirement({
    html,
    entryUrl: input.entryUrl,
    finalUrl: response.url,
    status: response.status,
    sourceTitle: input.summary.title,
    sourceSendTime: input.summary.sendTime,
    sourceContent: input.summary.content,
  });
}

function decodeIframeNames(html: string): unknown[] {
  const names = [
    ...html.matchAll(/<iframe\b[^>]*\bname=["']([^"']+)["'][^>]*>/gi),
  ].map((match) => match[1]);
  const decoded: unknown[] = [];

  for (const name of names) {
    const candidates = [
      () => JSON.parse(decodeURIComponent(name)),
      () => JSON.parse(decodeBase64UrlEncoded(name)),
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

function decodeBase64UrlEncoded(value: string): string {
  const decoded = atob(decodeURIComponent(value));
  const bytes = Uint8Array.from(decoded, (character) => character.charCodeAt(0));
  return new TextDecoder().decode(bytes);
}

function extractUrls(text: string): string[] {
  return [...text.matchAll(/https?:\\?\/\\?\/[^"' <>)\\]+/g)].map((match) =>
    match[0].replace(/\\\//g, "/"),
  );
}

function stripHtml(value: string): string {
  return value
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/\s+/g, " ")
    .trim();
}

function toStringValue(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function normalizeLimit(
  value: number | undefined,
  fallback: number,
  maximum: number,
): number {
  if (!value || !Number.isFinite(value) || value < 1) {
    return fallback;
  }

  return Math.min(Math.floor(value), maximum);
}
