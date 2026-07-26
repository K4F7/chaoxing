import { DEFAULT_CHAOXING_HOME_URL } from "./auth";
import { fetchChaoxingWithCookie } from "./safe-fetch";

const NOTICE_ORIGIN = "https://notice.chaoxing.com";

export type InboxFetchOptions = {
  cookie: string;
  homeUrl?: string;
  limit?: number;
  fetcher?: typeof fetch;
};

export type InboxMessage = {
  id: string;
  uuid: string | null;
  title: string;
  sender: string | null;
  sendTime: string | null;
  isRead: boolean;
  content: string | null;
  detailUrl: string | null;
  sendTag: number | string | null;
};

export type InboxFetchResult = {
  inboxUrl: string;
  apiUrl: string;
  year: string;
  lastGetId: string | null;
  lastPage: boolean;
  pagesFetched: number;
  totalFetched: number;
  messages: InboxMessage[];
};

type NoticeListResponse = {
  status?: boolean;
  msg?: string;
  notices?: {
    list?: RawNotice[];
    lastGetId?: string;
    lastPage?: boolean | number;
  };
  topNotices?: RawNotice[];
  urgentNotices?: RawNotice[];
};

type RawNotice = {
  id?: string | number;
  idCode?: string;
  uuid?: string;
  title?: string;
  noticeTitle?: string;
  createrName?: string;
  senderName?: string;
  sendTime?: string;
  createTime?: string;
  insertTime?: string | number;
  isread?: number | boolean;
  content?: string;
  rtf_content?: string;
  sendTag?: number | string;
};

export async function fetchInboxMessages(
  options: InboxFetchOptions,
): Promise<InboxFetchResult> {
  if (!options.cookie.trim()) {
    throw new Error("missing CHAOXING_COOKIE");
  }

  const fetcher = options.fetcher ?? fetch;
  const homeUrl = options.homeUrl || DEFAULT_CHAOXING_HOME_URL;
  const homeHtml = await fetchPageText(fetcher, homeUrl, homeUrl, options.cookie);
  const inboxUrl = findInboxUrl(homeHtml, homeUrl);
  if (!inboxUrl) {
    throw new Error("inbox_url_not_found");
  }

  const inboxHtml = await fetchPageText(fetcher, inboxUrl, homeUrl, options.cookie);
  const config = extractInboxPageConfig(inboxHtml);
  const apiUrl = new URL("/pc/notice/getNoticeList", NOTICE_ORIGIN).toString();
  const limit = normalizeLimit(options.limit);
  const messages: InboxMessage[] = [];
  let lastGetId: string | null = null;
  let lastPage = false;
  let pagesFetched = 0;

  while (messages.length < limit && !lastPage) {
    const data = await postNoticeList(
      fetcher,
      apiUrl,
      inboxUrl,
      options.cookie,
      config,
      lastGetId,
    );
    pagesFetched += 1;

    if (!data.status) {
      throw new Error(data.msg || "getNoticeList_failed");
    }

    const rawMessages = [
      ...(lastGetId ? [] : data.topNotices || []),
      ...(lastGetId ? [] : data.urgentNotices || []),
      ...(data.notices?.list || []),
    ];
    for (const notice of rawMessages) {
      if (messages.length >= limit) {
        break;
      }
      messages.push(normalizeNotice(notice));
    }

    lastGetId = data.notices?.lastGetId || null;
    lastPage = Boolean(data.notices?.lastPage) || rawMessages.length === 0;
    if (!lastGetId) {
      lastPage = true;
    }
  }

  return {
    inboxUrl,
    apiUrl,
    year: config.year,
    lastGetId,
    lastPage,
    pagesFetched,
    totalFetched: messages.length,
    messages,
  };
}

export function findInboxUrl(html: string, baseUrl: string): string | null {
  const exact = html.match(
    /https:\/\/notice\.chaoxing\.com\/pc\/notice\/myNotice\?s=[^"'\s<)]+/,
  )?.[0];
  if (exact) {
    return exact;
  }

  const relative = html.match(/\/pc\/notice\/myNotice\?s=[^"'\s<)]+/)?.[0];
  return relative ? new URL(relative, baseUrl).toString() : null;
}

export function extractInboxPageConfig(html: string): {
  type: string;
  noticeType: string;
  year: string;
  folderUUID: string;
  fidsCode: string;
  queryFolderNoticePrevYear: string;
} {
  return {
    type: extractWindowString(html, "type") || "2",
    noticeType: extractWindowString(html, "noticeType") || "",
    year: extractWindowString(html, "nowYear") || String(new Date().getFullYear()),
    folderUUID: extractWindowString(html, "folderUUID") || "",
    fidsCode: extractWindowString(html, "fidsCode") || "",
    queryFolderNoticePrevYear: "0",
  };
}

export function normalizeNotice(notice: RawNotice): InboxMessage {
  const id = String(notice.idCode || notice.id || notice.uuid || "");
  const uuid = notice.uuid || null;
  const sendTag = notice.sendTag ?? null;

  return {
    id,
    uuid,
    title: notice.title || notice.noticeTitle || "(无标题)",
    sender: notice.createrName || notice.senderName || null,
    sendTime:
      notice.sendTime ||
      notice.createTime ||
      normalizeTimestamp(notice.insertTime) ||
      null,
    isRead: notice.isread === true || notice.isread === 1,
    content: stripHtml(notice.content || notice.rtf_content || "") || null,
    detailUrl: uuid || id ? buildDetailUrl(uuid || id, sendTag) : null,
    sendTag,
  };
}

async function fetchPageText(
  fetcher: typeof fetch,
  url: string,
  referer: string,
  cookie: string,
): Promise<string> {
  const response = await fetchChaoxingWithCookie(fetcher, url, {
    headers: buildHeaders(cookie, referer, "text/html,application/xhtml+xml"),
  });
  if (!response.ok) {
    throw new Error(`page_fetch_failed_${response.status}`);
  }

  return response.text();
}

async function postNoticeList(
  fetcher: typeof fetch,
  apiUrl: string,
  referer: string,
  cookie: string,
  config: ReturnType<typeof extractInboxPageConfig>,
  lastValue: string | null,
): Promise<NoticeListResponse> {
  const body = new URLSearchParams({
    type: config.type,
    notice_type: config.noticeType,
    lastValue: lastValue || "",
    sort: "",
    folderUUID: config.folderUUID,
    kw: "",
    startTime: "",
    endTime: "",
    gKw: "",
    gName: "",
    year: config.year,
    tag: "",
    fidsCode: config.fidsCode,
    queryFolderNoticePrevYear: config.queryFolderNoticePrevYear,
    filterSenderPuids: "",
    filterTags: "",
  });

  const response = await fetchChaoxingWithCookie(fetcher, apiUrl, {
    method: "POST",
    headers: {
      ...buildHeaders(cookie, referer, "application/json, text/javascript, */*; q=0.01"),
      "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
      Origin: NOTICE_ORIGIN,
      "X-Requested-With": "XMLHttpRequest",
    },
    body,
  });
  if (!response.ok) {
    throw new Error(`notice_list_fetch_failed_${response.status}`);
  }

  return response.json() as Promise<NoticeListResponse>;
}

function normalizeLimit(limit: number | undefined): number {
  if (!limit || !Number.isFinite(limit) || limit < 1) {
    return 20;
  }

  return Math.min(Math.floor(limit), 500);
}

function buildHeaders(
  cookie: string,
  referer: string,
  accept: string,
): Record<string, string> {
  return {
    Accept: accept,
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.7",
    Cookie: cookie,
    Referer: referer,
    "User-Agent":
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125 Safari/537.36",
  };
}

function extractWindowString(html: string, key: string): string | null {
  const pattern = new RegExp(`window\\.${key}\\s*=\\s*['"]([^'"]*)['"]`, "i");
  return html.match(pattern)?.[1] || null;
}

function normalizeTimestamp(value: string | number | undefined): string | null {
  if (!value) {
    return null;
  }

  const time = new Date(value);
  return Number.isNaN(time.getTime()) ? String(value) : time.toISOString();
}

function buildDetailUrl(id: string, sendTag: number | string | null): string {
  const url = new URL(`/pc/notice/${id}/detail`, NOTICE_ORIGIN);
  if (sendTag !== null && sendTag !== undefined) {
    url.searchParams.set("sendTag", String(sendTag));
  }
  return url.toString();
}

function stripHtml(value: string): string {
  return value
    .replace(/<style[\s\S]*?<\/style>/gi, " ")
    .replace(/<script[\s\S]*?<\/script>/gi, " ")
    .replace(/<[^>]+>/g, " ")
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'")
    .replace(/\s+/g, " ")
    .trim();
}
