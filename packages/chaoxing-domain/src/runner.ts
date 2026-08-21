import type { AppSyncFailure, AppSyncResponse, SeenNotice } from "./app-sync";
import { buildAppSyncResponse, emptySyncStats } from "./app-sync";
import {
  buildLoadingItem,
  buildSyncItem,
  isActionableWorkStatus,
  parseAssignmentRequirement,
} from "./assignment";
import type { AuthCheckResult } from "./auth";
import { evaluateHomeAuth } from "./auth";
import {
  ASSIGNMENT_DETAIL_CONCURRENCY,
  COURSE_DETAIL_CONCURRENCY,
  COURSE_LIST_CONCURRENCY,
  DEFAULT_CHAOXING_HOME_URL,
  DEFAULT_REQUEST_TIMEOUT_MS,
  LEGACY_COURSE_LIST_URL,
  MAX_COOKIE_REDIRECTS,
  MODERN_COURSE_LIST_ORIGIN,
  MODERN_COURSE_LIST_URL,
  NOTICE_DETAIL_CONCURRENCY,
  NOTICE_ORIGIN,
} from "./constants";
import {
  cookieHeaderForChaoxingUri,
  chaoxingCookieSecrets,
  mergeChaoxingResponseCookies,
} from "./cookie";
import {
  catalogHasRecords,
  emptyCourseCatalog,
  mergeDiscoveredCourses,
  monitoredCourses,
  shouldDiscoverCourses,
  type CourseCatalog,
  type CourseSpace,
} from "./course-catalog";
import {
  findCourseInteractionUrl,
  isActionableCourseTask,
  parseCourseSpaces,
  parseCourseTaskLinks,
  type CourseTaskLink,
} from "./course-parse";
import {
  AuthenticationExpiredException,
  headerValue,
  LocalSyncException,
  SyncPhase,
  type ChaoxingHttpClient,
  type ChaoxingHttpMethod,
  type ChaoxingHttpRequest,
  type ChaoxingHttpResponse,
  type SyncProgressCallback,
} from "./http";
import {
  collectUniqueWorkLinks,
  extractInboxPageConfig,
  extractNoticePage,
  findInboxUrl,
  inboxMessageIdentity,
  isAssignmentOrExamRelated,
  normalizeNotice,
  parseNoticeDetailSummary,
  type DetailSummary,
  type InboxMessage,
} from "./inbox";
import { asRecord, hasSuccessfulApiStatus, normalizeLimit } from "./json";
import { redactSensitiveText, redactSensitiveUrl } from "./redaction";
import {
  carriedSeenNotices,
  mergeSeenNotices,
  summaryFromSeenNotice,
} from "./seen-notices";
import type { SyncConfig } from "./sync-config";
import type { SyncItem } from "./sync-item";
import { isTrustedChaoxingUrl } from "./url-policy";
import { buildCourseTaskListUrl, tryParseUrl } from "./urls";

export type InboxFetchResult = {
  inboxUrl: string;
  pagesFetched: number;
  totalFetched: number;
  messages: InboxMessage[];
  stoppedAtSeenNotice: boolean;
};

export type SyncRunInput = {
  config: SyncConfig;
  previous?: AppSyncResponse | null;
  courseCatalog?: CourseCatalog;
  forceCourseDiscovery?: boolean;
  onProgress?: SyncProgressCallback;
  onCourseCatalogChanged?: (catalog: CourseCatalog) => Promise<void> | void;
};

export type LocalSyncRunner = {
  run(input: SyncRunInput): Promise<AppSyncResponse>;
  checkAuth(cookie: string): Promise<AuthCheckResult>;
  fetchInboxMessages(input: {
    cookie: string;
    itemLimit: number;
    pageLimit: number;
    homeHtml?: string;
    seenNoticeIds?: ReadonlySet<string>;
  }): Promise<InboxFetchResult>;
  fetchDetailSummary(input: {
    message: InboxMessage;
    cookie: string;
  }): Promise<DetailSummary>;
  fetchAssignmentRequirement(input: {
    entryUrl: string;
    summary: DetailSummary;
    cookie: string;
    source?: string;
  }): ReturnType<typeof parseAssignmentRequirement> extends infer R
    ? Promise<R>
    : never;
  fetchCourseSpaces(cookie: string): Promise<CourseSpace[]>;
};

export function createLocalSyncRunner(options: {
  http: ChaoxingHttpClient;
  clock?: () => Date;
  requestTimeoutMs?: number;
  homeUrl?: string;
}): LocalSyncRunner {
  const clock = options.clock ?? (() => new Date());
  const requestTimeoutMs = options.requestTimeoutMs ?? DEFAULT_REQUEST_TIMEOUT_MS;
  const homeUrl = options.homeUrl ?? DEFAULT_CHAOXING_HOME_URL;

  const sendWithCookie = async (
    method: ChaoxingHttpMethod,
    url: string,
    headers: Record<string, string>,
    form?: Record<string, string>,
    session?: { source: string },
  ): Promise<ChaoxingHttpResponse> => {
    let currentUrl = url;
    let currentMethod = method;
    let currentForm = form;
    let redirects = 0;
    let cookieSource = session?.source ?? headers.Cookie ?? "";
    const startedAt = Date.now();

    const remainingTimeout = (): number => {
      const remaining = requestTimeoutMs - (Date.now() - startedAt);
      if (remaining <= 0) {
        const host = tryParseUrl(currentUrl)?.hostname ?? currentUrl;
        throw new LocalSyncException(
          `请求 ${host} 超时（${Math.round(requestTimeoutMs / 1000)} 秒），请检查网络后重试`,
        );
      }
      return remaining;
    };

    while (true) {
      ensureTrusted(currentUrl);
      const requestHeaders = { ...headers };
      const scopedCookie = cookieHeaderForChaoxingUri(
        cookieSource,
        mustParseUrl(currentUrl),
      );
      if (scopedCookie.length === 0) {
        delete requestHeaders.Cookie;
      } else {
        requestHeaders.Cookie = scopedCookie;
      }
      const request: ChaoxingHttpRequest = {
        method: currentMethod,
        url: currentUrl,
        headers: requestHeaders,
        ...(currentForm && currentMethod === "POST" ? { form: currentForm } : {}),
      };
      const response = await withTimeout(
        options.http.send(request),
        remainingTimeout(),
        mustParseUrl(currentUrl).hostname,
        requestTimeoutMs,
      );
      cookieSource = mergeChaoxingResponseCookies(
        cookieSource,
        mustParseUrl(currentUrl),
        headerValue(response.headers, "set-cookie"),
        clock(),
      );
      if (session) {
        session.source = cookieSource;
      }
      if (!isRedirect(response.status)) {
        return { ...response, url: response.url || currentUrl };
      }
      const location = headerValue(response.headers, "location");
      if (location == null || location.trim().length === 0) {
        return { ...response, url: response.url || currentUrl };
      }
      if (redirects >= MAX_COOKIE_REDIRECTS) {
        throw new LocalSyncException("学习通页面重定向次数过多");
      }
      const next = new URL(location, currentUrl);
      ensureTrusted(next.toString());
      currentUrl = next.toString();
      redirects += 1;
      if (
        response.status === 303 ||
        ((response.status === 301 || response.status === 302) &&
          currentMethod === "POST")
      ) {
        currentMethod = "GET";
        currentForm = undefined;
      }
    }
  };

  const fetchHomePage = async (
    cookie: string,
  ): Promise<{
    html: string;
    finalUrl: string;
    statusCode: number;
    cookie: string;
  }> => {
    const session = { source: cookie };
    const response = await sendWithCookie(
      "GET",
      homeUrl,
      htmlHeaders(cookie, homeUrl),
      undefined,
      session,
    );
    return {
      html: response.body,
      finalUrl: response.url || homeUrl,
      statusCode: response.status,
      cookie: session.source,
    };
  };

  const checkAuth = async (cookie: string): Promise<AuthCheckResult> => {
    const home = await fetchHomePage(cookie);
    return evaluateHomeAuth(home);
  };

  const fetchPageText = async (
    url: string,
    referer: string,
    cookie: string,
  ): Promise<string> => {
    const response = await sendWithCookie("GET", url, htmlHeaders(cookie, referer));
    if (response.status < 200 || response.status >= 300) {
      throw new LocalSyncException(`页面抓取失败 (${response.status})`);
    }
    return response.body;
  };

  const fetchInboxMessages = async (input: {
    cookie: string;
    itemLimit: number;
    pageLimit: number;
    homeHtml?: string;
    seenNoticeIds?: ReadonlySet<string>;
  }): Promise<InboxFetchResult> => {
    const itemLimit = normalizeLimit(input.itemLimit, 20, 500);
    const pageLimit = normalizeLimit(input.pageLimit, 1, 20);
    const homeHtml =
      input.homeHtml ?? (await fetchPageText(homeUrl, homeUrl, input.cookie));
    const inboxUrl = findInboxUrl(homeHtml, homeUrl);
    if (inboxUrl === null) {
      throw new LocalSyncException("未能在学习通首页找到收件箱入口");
    }
    const inboxHtml = await fetchPageText(inboxUrl, homeUrl, input.cookie);
    const pageConfig = extractInboxPageConfig(inboxHtml, clock());
    const messages: InboxMessage[] = [];
    let lastGetId = "";
    let lastPage = false;
    let pagesFetched = 0;
    let stoppedAtSeenNotice = false;
    const seenNoticeIds = input.seenNoticeIds ?? new Set<string>();

    while (
      messages.length < itemLimit &&
      !lastPage &&
      !stoppedAtSeenNotice &&
      pagesFetched < pageLimit
    ) {
      const response = await sendWithCookie(
        "POST",
        `${NOTICE_ORIGIN}/pc/notice/getNoticeList`,
        {
          ...jsonHeaders(input.cookie, inboxUrl),
          "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
          Origin: NOTICE_ORIGIN,
          "X-Requested-With": "XMLHttpRequest",
        },
        {
          type: pageConfig.type,
          notice_type: pageConfig.noticeType,
          lastValue: lastGetId,
          sort: "",
          folderUUID: pageConfig.folderUuid,
          kw: "",
          startTime: "",
          endTime: "",
          gKw: "",
          gName: "",
          year: pageConfig.year,
          tag: "",
          fidsCode: pageConfig.fidsCode,
          queryFolderNoticePrevYear: "0",
          filterSenderPuids: "",
          filterTags: "",
        },
      );
      if (response.status < 200 || response.status >= 300) {
        throw new LocalSyncException(`通知列表抓取失败 (${response.status})`);
      }
      pagesFetched += 1;
      const decoded = parseJsonObject(response.body, "通知列表返回格式不正确");
      if (!hasSuccessfulApiStatus(decoded)) {
        const message =
          typeof decoded.msg === "string" && decoded.msg.length > 0
            ? decoded.msg
            : "通知列表抓取失败";
        throw new LocalSyncException(message);
      }
      const page = extractNoticePage(decoded);
      const rawMessages = [
        ...(lastGetId.length === 0 ? page.topNotices : []),
        ...(lastGetId.length === 0 ? page.urgentNotices : []),
        ...page.items,
      ];
      for (const notice of rawMessages) {
        if (messages.length >= itemLimit) {
          break;
        }
        const record = asRecord(notice);
        if (record === null) {
          continue;
        }
        const message = normalizeNotice(record);
        messages.push(message);
        if (seenNoticeIds.has(inboxMessageIdentity(message))) {
          stoppedAtSeenNotice = true;
        }
      }
      lastGetId = page.lastGetId;
      lastPage = page.lastPage || rawMessages.length === 0 || lastGetId.length === 0;
    }

    return {
      inboxUrl,
      pagesFetched,
      totalFetched: messages.length,
      messages,
      stoppedAtSeenNotice: stoppedAtSeenNotice && !lastPage,
    };
  };

  const fetchDetailSummary = async (input: {
    message: InboxMessage;
    cookie: string;
  }): Promise<DetailSummary> => {
    const id = inboxMessageIdentity(input.message);
    const sendTag = input.message.sendTag ?? 0;
    const url = `${NOTICE_ORIGIN}/pc/notice/${id}/getNoticeDetail?sendTag=${sendTag}`;
    const response = await sendWithCookie("GET", url, {
      ...jsonHeaders(
        input.cookie,
        input.message.detailUrl ?? `${NOTICE_ORIGIN}/pc/notice/myNotice`,
      ),
      "X-Requested-With": "XMLHttpRequest",
    });
    if (response.status < 200 || response.status >= 300) {
      throw new LocalSyncException(`通知详情抓取失败 (${response.status})`);
    }
    const decoded = parseJsonObject(response.body, "通知详情返回格式不正确");
    if (!hasSuccessfulApiStatus(decoded)) {
      throw new LocalSyncException("通知详情接口返回失败");
    }
    return parseNoticeDetailSummary({ message: input.message, decoded });
  };

  const fetchAssignmentRequirement = async (input: {
    entryUrl: string;
    summary: DetailSummary;
    cookie: string;
    source?: string;
  }) => {
    ensureTrusted(input.entryUrl);
    const response = await sendWithCookie(
      "GET",
      input.entryUrl,
      htmlHeaders(input.cookie, `${NOTICE_ORIGIN}/pc/notice/myNotice`),
    );
    if (response.status < 200 || response.status >= 300) {
      throw new LocalSyncException(`作业页面抓取失败 (${response.status})`);
    }
    const finalUrl = response.url || input.entryUrl;
    ensureTrusted(finalUrl);
    return parseAssignmentRequirement({
      html: response.body,
      entryUrl: input.entryUrl,
      finalUrl,
      status: response.status,
      sourceTitle: input.summary.title,
      sourceSendTime: input.summary.sendTime,
      sourceContent: input.summary.content,
      source: input.source ?? "inbox",
    });
  };

  const fetchCourseDiscovery = async (
    cookie: string,
    home?: { html: string; cookie: string },
  ): Promise<{ courses: CourseSpace[]; cookie: string }> => {
    let modernError: unknown;
    const session = { source: home?.cookie ?? cookie };
    try {
      const homeHtml =
        home?.html ??
        (
          await sendWithCookie(
            "GET",
            homeUrl,
            htmlHeaders(session.source, homeUrl),
            undefined,
            session,
          )
        ).body;
      const interactionUrl = findCourseInteractionUrl(homeHtml);
      if (interactionUrl !== null) {
        await sendWithCookie(
          "GET",
          interactionUrl,
          htmlHeaders(session.source, homeUrl),
          undefined,
          session,
        );
      }
      const response = await sendWithCookie(
        "POST",
        MODERN_COURSE_LIST_URL,
        {
          ...htmlHeaders(
            session.source,
            interactionUrl ?? `${MODERN_COURSE_LIST_ORIGIN}/visit/interaction`,
          ),
          "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
          Origin: MODERN_COURSE_LIST_ORIGIN,
          "X-Requested-With": "XMLHttpRequest",
        },
        {
          courseType: "1",
          courseFolderId: "0",
          baseEducation: "0",
          superstarClass: "",
          courseFolderSize: "0",
        },
        session,
      );
      if (response.status < 200 || response.status >= 300) {
        throw new LocalSyncException(`新版课程列表抓取失败 (${response.status})`);
      }
      return {
        courses: parseCourseSpaces(response.body),
        cookie: session.source,
      };
    } catch (error) {
      modernError = error;
    }

    try {
      const response = await sendWithCookie(
        "GET",
        LEGACY_COURSE_LIST_URL,
        jsonHeaders(session.source, homeUrl),
        undefined,
        session,
      );
      if (response.status < 200 || response.status >= 300) {
        throw new LocalSyncException(`旧版课程列表抓取失败 (${response.status})`);
      }
      return {
        courses: parseCourseSpaces(response.body),
        cookie: session.source,
      };
    } catch (legacyError) {
      const modernMessage =
        modernError instanceof LocalSyncException
          ? modernError.message
          : "新版课程列表不可用";
      const legacyMessage =
        legacyError instanceof LocalSyncException
          ? legacyError.message
          : "旧版课程列表不可用";
      throw new LocalSyncException(`${modernMessage}；${legacyMessage}`);
    }
  };

  const run = async (input: SyncRunInput): Promise<AppSyncResponse> => {
    const startedAt = Date.now();
    let phaseStartedAt = startedAt;
    const cookie = input.config.cookie.trim();
    if (cookie.length === 0) {
      throw new LocalSyncException("请先在设置中填入学习通 Cookie");
    }
    input.onProgress?.({ phase: SyncPhase.authentication, completed: 0, total: 1 });
    const home = await fetchHomePage(cookie);
    const auth = evaluateHomeAuth(home);
    if (!auth.authenticated) {
      throw new AuthenticationExpiredException();
    }
    input.onProgress?.({ phase: SyncPhase.authentication, completed: 1, total: 1 });
    const authenticationMs = Date.now() - startedAt;
    phaseStartedAt = Date.now();

    const previousNotices = input.previous?.seenNotices ?? [];
    const seenNotices = new Map(previousNotices.map((notice) => [notice.id, notice]));
    input.onProgress?.({ phase: SyncPhase.inbox, completed: 0, total: 1 });
    const inbox = await fetchInboxMessages({
      cookie,
      itemLimit: input.config.inboxItemLimit,
      pageLimit: input.config.inboxPageLimit,
      homeHtml: home.html,
      seenNoticeIds: new Set(seenNotices.keys()),
    });
    input.onProgress?.({ phase: SyncPhase.inbox, completed: 1, total: 1 });
    const inboxMs = Date.now() - phaseStartedAt;
    phaseStartedAt = Date.now();

    const relevant = inbox.messages.filter(isAssignmentOrExamRelated);
    const summaries: DetailSummary[] = [];
    const failures: AppSyncFailure[] = [];
    const listedNoticesToParse = relevant.slice(0, input.config.inboxItemLimit);
    const carried = carriedSeenNotices({
      seen: previousNotices,
      listed: new Set(inbox.messages.map(inboxMessageIdentity)),
      limit: input.config.inboxItemLimit - listedNoticesToParse.length,
      includeParsed: inbox.stoppedAtSeenNotice,
    });
    const noticesToParse = [
      ...listedNoticesToParse,
      ...carried
        .filter((notice) => !notice.detailParsed)
        .map((notice) => messageFromSeen(notice)),
    ];
    input.onProgress?.({
      phase: SyncPhase.noticeDetails,
      completed: 0,
      total: noticesToParse.length,
    });
    const parsedNotices = new Map<string, SeenNotice>();
    let completedNoticeDetails = 0;
    await forEachConcurrent(noticesToParse, NOTICE_DETAIL_CONCURRENCY, async (message) => {
      const identity = inboxMessageIdentity(message);
      const seen = seenNotices.get(identity);
      try {
        if (seen?.detailParsed) {
          summaries.push(
            summaryFromSeenNotice(seen, {
              title: message.title,
              sendTime: message.sendTime,
            }),
          );
        } else {
          const summary = await fetchDetailSummary({ message, cookie });
          summaries.push(summary);
          if (identity.length > 0) {
            parsedNotices.set(identity, {
              id: identity,
              detailParsed: true,
              sendTag: message.sendTag,
              title: summary.title,
              sendTime: summary.sendTime,
              content: summary.content,
              taskLinks: summary.assignmentLinks,
            });
          }
        }
      } catch (error) {
        failures.push({
          entryUrl: redactSensitiveUrl(message.detailUrl ?? `notice:${message.id}`),
          sourceTitle: redactSensitiveText(message.title),
          message:
            error instanceof LocalSyncException
              ? redactSensitiveText(error.message, chaoxingCookieSecrets(cookie))
              : "通知详情解析失败",
        });
      }
      completedNoticeDetails += 1;
      input.onProgress?.({
        phase: SyncPhase.noticeDetails,
        completed: completedNoticeDetails,
        total: noticesToParse.length,
      });
    });
    summaries.push(
      ...carried.filter((notice) => notice.detailParsed).map((notice) =>
        summaryFromSeenNotice(notice),
      ),
    );
    const noticeDetailsMs = Date.now() - phaseStartedAt;
    phaseStartedAt = Date.now();

    const unique = collectUniqueWorkLinks(summaries);
    const uniqueEntries = [...unique.entries()].sort(([left], [right]) =>
      buildLoadingItem({
        url: left,
        title: unique.get(left)?.title ?? "",
        sendTime: unique.get(left)?.sendTime ?? null,
      }).id.localeCompare(
        buildLoadingItem({
          url: right,
          title: unique.get(right)?.title ?? "",
          sendTime: unique.get(right)?.sendTime ?? null,
        }).id,
      ),
    );
    const items: SyncItem[] = [];
    let statusFilteredItems = 0;
    input.onProgress?.({
      phase: SyncPhase.assignmentDetails,
      completed: 0,
      total: uniqueEntries.length,
    });
    let completedAssignmentDetails = 0;
    await forEachConcurrent(
      uniqueEntries,
      ASSIGNMENT_DETAIL_CONCURRENCY,
      async ([entryUrl, summary]) => {
        try {
          const requirement = await fetchAssignmentRequirement({
            entryUrl,
            summary,
            cookie,
          });
          if (isActionableWorkStatus(requirement.workStatus)) {
            items.push(buildSyncItem(requirement, clock()));
          } else {
            statusFilteredItems += 1;
          }
        } catch (error) {
          failures.push({
            entryUrl: redactSensitiveUrl(entryUrl),
            sourceTitle: redactSensitiveText(summary.title),
            message:
              error instanceof LocalSyncException
                ? redactSensitiveText(error.message, chaoxingCookieSecrets(cookie))
                : "作业详情解析失败",
          });
        }
        completedAssignmentDetails += 1;
        input.onProgress?.({
          phase: SyncPhase.assignmentDetails,
          completed: completedAssignmentDetails,
          total: uniqueEntries.length,
        });
      },
    );
    const assignmentDetailsMs = Date.now() - phaseStartedAt;
    phaseStartedAt = Date.now();

    let courseStats = {
      courses: 0,
      taskLinksDiscovered: 0,
      taskLinks: 0,
      statusFiltered: 0,
    };
    if (input.config.courseSourcesEnabled) {
      courseStats = await appendCourseSourceItems({
        cookie,
        courseLimit: input.config.courseLimit,
        itemLimit: input.config.inboxItemLimit,
        items,
        failures,
        catalog: input.courseCatalog ?? emptyCourseCatalog,
        forceDiscovery: input.forceCourseDiscovery === true,
        home,
        onProgress: input.onProgress,
        onCatalogChanged: input.onCourseCatalogChanged,
        sendWithCookie,
        fetchAssignmentRequirement,
        clock,
      });
    }
    const coursesMs = Date.now() - phaseStartedAt;
    input.onProgress?.({ phase: SyncPhase.finalizing, completed: 0, total: 0 });
    const now = clock();
    return buildAppSyncResponse({
      now,
      lastSyncedAt: now,
      items,
      failures,
      stats: {
        ...emptySyncStats,
        durationMs: Date.now() - startedAt,
        authenticationMs,
        inboxMs,
        noticeDetailsMs,
        assignmentDetailsMs,
        coursesMs,
        inboxMessages: inbox.messages.length,
        relevantNotices: relevant.length,
        detailSummaries: summaries.length,
        inboxTaskLinks: unique.size,
        inboxTaskDetails: uniqueEntries.length,
        statusFilteredItems,
        courses: courseStats.courses,
        courseTaskLinksDiscovered: courseStats.taskLinksDiscovered,
        courseTaskLinks: courseStats.taskLinks,
        courseTaskStatusFiltered: courseStats.statusFiltered,
        itemCandidates: new Set(items.map((item) => item.id)).size,
        courseSourcesEnabled: input.config.courseSourcesEnabled,
      },
      seenNotices: mergeSeenNotices({
        previous: previousNotices,
        listed: inbox.messages,
        parsed: parsedNotices,
      }),
    });
  };

  return {
    run,
    checkAuth,
    fetchInboxMessages,
    fetchDetailSummary,
    fetchAssignmentRequirement,
    fetchCourseSpaces: async (cookie) =>
      (await fetchCourseDiscovery(cookie)).courses,
  };
}

function messageFromSeen(notice: SeenNotice): InboxMessage {
  return {
    id: notice.id,
    uuid: null,
    title: notice.title,
    sender: null,
    sendTime: notice.sendTime,
    isRead: false,
    content: notice.content,
    detailUrl: `${NOTICE_ORIGIN}/pc/notice/${notice.id}/detail${
      notice.sendTag == null ? "" : `?sendTag=${notice.sendTag}`
    }`,
    sendTag: notice.sendTag,
  };
}

async function appendCourseSourceItems(input: {
  cookie: string;
  courseLimit: number;
  itemLimit: number;
  items: SyncItem[];
  failures: AppSyncFailure[];
  catalog: CourseCatalog;
  forceDiscovery: boolean;
  home: { html: string; cookie: string };
  onProgress?: SyncProgressCallback;
  onCatalogChanged?: (catalog: CourseCatalog) => Promise<void> | void;
  sendWithCookie: (
    method: ChaoxingHttpMethod,
    url: string,
    headers: Record<string, string>,
    form?: Record<string, string>,
    session?: { source: string },
  ) => Promise<ChaoxingHttpResponse>;
  fetchAssignmentRequirement: (input: {
    entryUrl: string;
    summary: DetailSummary;
    cookie: string;
    source?: string;
  }) => Promise<ReturnType<typeof parseAssignmentRequirement>>;
  clock: () => Date;
}): Promise<{
  courses: number;
  taskLinksDiscovered: number;
  taskLinks: number;
  statusFiltered: number;
}> {
  input.onProgress?.({ phase: SyncPhase.courses, completed: 0, total: 0 });
  let activeCatalog = input.catalog;
  let courseCookie = input.home.cookie;
  const today = input.clock();
  if (
    shouldDiscoverCourses({
      catalog: input.catalog,
      now: today,
      forceDiscovery: input.forceDiscovery,
    })
  ) {
    try {
      const discovery = await discoverCourses(
        input.cookie,
        input.home,
        input.sendWithCookie,
      );
      activeCatalog = mergeDiscoveredCourses(
        input.catalog,
        discovery.courses,
        today,
      );
      courseCookie = discovery.cookie;
      await input.onCatalogChanged?.(activeCatalog);
    } catch (error) {
      input.failures.push({
        entryUrl: MODERN_COURSE_LIST_URL,
        sourceTitle: "课程空间",
        message:
          error instanceof LocalSyncException
            ? redactSensitiveText(
                error.message,
                chaoxingCookieSecrets(input.cookie),
              )
            : "课程列表解析失败",
      });
      if (!catalogHasRecords(input.catalog)) {
        return {
          courses: 0,
          taskLinksDiscovered: 0,
          taskLinks: 0,
          statusFiltered: 0,
        };
      }
    }
  }

  const courseLimit = normalizeLimit(input.courseLimit, 20, 100);
  const itemLimit = normalizeLimit(input.itemLimit, 60, 500);
  const coursesToScan = monitoredCourses(activeCatalog).slice(0, courseLimit);
  input.onProgress?.({
    phase: SyncPhase.courses,
    completed: 0,
    total: coursesToScan.length,
  });
  const sourcePagesByCourse: Array<
    Array<{ source: "course_work" | "course_exam"; links: CourseTaskLink[] }>
  > = Array.from({ length: coursesToScan.length }, () => []);
  let completedCourseLists = 0;
  await forEachConcurrent(coursesToScan, COURSE_LIST_CONCURRENCY, async (course, courseIndex) => {
    sourcePagesByCourse[courseIndex] = await Promise.all(
      (["course_work", "course_exam"] as const).map(async (source) => {
        const listUrl = buildCourseTaskListUrl(course, source);
        try {
          const response = await input.sendWithCookie(
            "GET",
            listUrl,
            htmlHeaders(courseCookie, MODERN_COURSE_LIST_URL),
          );
          if (response.status < 200 || response.status >= 300) {
            throw new LocalSyncException(`任务列表抓取失败 (${response.status})`);
          }
          return {
            source,
            links: parseCourseTaskLinks(response.body, listUrl, course.title),
          };
        } catch (error) {
          input.failures.push({
            entryUrl: listUrl,
            sourceTitle: course.title,
            message:
              error instanceof LocalSyncException
                ? redactSensitiveText(
                    error.message,
                    chaoxingCookieSecrets(input.cookie),
                  )
                : "任务列表解析失败",
          });
          return { source, links: [] };
        }
      }),
    );
    completedCourseLists += 1;
    input.onProgress?.({
      phase: SyncPhase.courses,
      completed: completedCourseLists,
      total: coursesToScan.length,
    });
  });

  let processedTasks = 0;
  let discoveredTaskLinks = 0;
  let statusFilteredTasks = 0;
  const visitedUrls = new Set<string>();
  const pendingDetails: Array<{
    source: "course_work" | "course_exam";
    link: CourseTaskLink;
  }> = [];
  outer: for (const sourcePages of sourcePagesByCourse) {
    for (const page of sourcePages) {
      for (const link of page.links) {
        if (processedTasks >= itemLimit) {
          break outer;
        }
        if (visitedUrls.has(link.url)) {
          continue;
        }
        visitedUrls.add(link.url);
        discoveredTaskLinks += 1;
        if (!isActionableCourseTask(link)) {
          statusFilteredTasks += 1;
          continue;
        }
        processedTasks += 1;
        pendingDetails.push({ source: page.source, link });
      }
    }
  }

  const totalCourseUnits = coursesToScan.length + pendingDetails.length;
  input.onProgress?.({
    phase: SyncPhase.courses,
    completed: coursesToScan.length,
    total: totalCourseUnits,
  });
  let completedCourseDetails = 0;
  await forEachConcurrent(pendingDetails, COURSE_DETAIL_CONCURRENCY, async (pending) => {
    try {
      const requirement = await input.fetchAssignmentRequirement({
        entryUrl: pending.link.url,
        summary: {
          title: pending.link.title,
          sendTime: null,
          content: null,
          assignmentLinks: [],
        },
        cookie: courseCookie,
        source: pending.source,
      });
      if (isActionableWorkStatus(requirement.workStatus)) {
        input.items.push(buildSyncItem(requirement, input.clock()));
      } else {
        statusFilteredTasks += 1;
      }
    } catch (error) {
      input.failures.push({
        entryUrl: pending.link.url,
        sourceTitle: pending.link.title,
        message:
          error instanceof LocalSyncException
            ? redactSensitiveText(
                error.message,
                chaoxingCookieSecrets(input.cookie),
              )
            : "任务详情解析失败",
      });
    }
    completedCourseDetails += 1;
    input.onProgress?.({
      phase: SyncPhase.courses,
      completed: coursesToScan.length + completedCourseDetails,
      total: totalCourseUnits,
    });
  });
  return {
    courses: coursesToScan.length,
    taskLinksDiscovered: discoveredTaskLinks,
    taskLinks: processedTasks,
    statusFiltered: statusFilteredTasks,
  };
}

async function discoverCourses(
  cookie: string,
  home: { html: string; cookie: string },
  sendWithCookie: (
    method: ChaoxingHttpMethod,
    url: string,
    headers: Record<string, string>,
    form?: Record<string, string>,
    session?: { source: string },
  ) => Promise<ChaoxingHttpResponse>,
): Promise<{ courses: CourseSpace[]; cookie: string }> {
  let modernError: unknown;
  const session = { source: home.cookie };
  try {
    const interactionUrl = findCourseInteractionUrl(home.html);
    if (interactionUrl !== null) {
      await sendWithCookie(
        "GET",
        interactionUrl,
        htmlHeaders(session.source, DEFAULT_CHAOXING_HOME_URL),
        undefined,
        session,
      );
    }
    const response = await sendWithCookie(
      "POST",
      MODERN_COURSE_LIST_URL,
      {
        ...htmlHeaders(
          session.source,
          interactionUrl ?? `${MODERN_COURSE_LIST_ORIGIN}/visit/interaction`,
        ),
        "Content-Type": "application/x-www-form-urlencoded; charset=UTF-8",
        Origin: MODERN_COURSE_LIST_ORIGIN,
        "X-Requested-With": "XMLHttpRequest",
      },
      {
        courseType: "1",
        courseFolderId: "0",
        baseEducation: "0",
        superstarClass: "",
        courseFolderSize: "0",
      },
      session,
    );
    if (response.status < 200 || response.status >= 300) {
      throw new LocalSyncException(`新版课程列表抓取失败 (${response.status})`);
    }
    return { courses: parseCourseSpaces(response.body), cookie: session.source };
  } catch (error) {
    modernError = error;
  }
  try {
    const response = await sendWithCookie(
      "GET",
      LEGACY_COURSE_LIST_URL,
      jsonHeaders(session.source, DEFAULT_CHAOXING_HOME_URL),
      undefined,
      session,
    );
    if (response.status < 200 || response.status >= 300) {
      throw new LocalSyncException(`旧版课程列表抓取失败 (${response.status})`);
    }
    return { courses: parseCourseSpaces(response.body), cookie: session.source };
  } catch (legacyError) {
    const modernMessage =
      modernError instanceof LocalSyncException
        ? modernError.message
        : "新版课程列表不可用";
    const legacyMessage =
      legacyError instanceof LocalSyncException
        ? legacyError.message
        : "旧版课程列表不可用";
    throw new LocalSyncException(`${modernMessage}；${legacyMessage}`);
  }
}

function htmlHeaders(cookie: string, referer: string): Record<string, string> {
  return {
    Accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.7",
    "Cache-Control": "no-cache",
    Cookie: cookie,
    Pragma: "no-cache",
    Referer: referer,
    "User-Agent":
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125 Safari/537.36",
  };
}

function jsonHeaders(cookie: string, referer: string): Record<string, string> {
  return {
    Accept: "application/json, text/javascript, */*; q=0.01",
    "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.7",
    Cookie: cookie,
    Referer: referer,
    "User-Agent": "Mozilla/5.0",
  };
}

function ensureTrusted(url: string): void {
  if (!isTrustedChaoxingUrl(url)) {
    throw new LocalSyncException("已跳过非学习通域名请求");
  }
}

function mustParseUrl(url: string): URL {
  const parsed = tryParseUrl(url);
  if (parsed === null) {
    throw new LocalSyncException("已跳过非学习通域名请求");
  }
  return parsed;
}

function isRedirect(statusCode: number): boolean {
  return (
    statusCode === 301 ||
    statusCode === 302 ||
    statusCode === 303 ||
    statusCode === 307 ||
    statusCode === 308
  );
}

function parseJsonObject(
  body: string,
  fallbackMessage: string,
): Record<string, unknown> {
  try {
    const decoded: unknown = JSON.parse(body);
    const record = asRecord(decoded);
    if (record === null) {
      throw new LocalSyncException(fallbackMessage);
    }
    return record;
  } catch (error) {
    if (error instanceof LocalSyncException) {
      throw error;
    }
    throw new LocalSyncException(fallbackMessage);
  }
}

async function withTimeout<T>(
  promise: Promise<T>,
  remainingMs: number,
  host: string,
  totalMs: number,
): Promise<T> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => {
      reject(
        new LocalSyncException(
          `请求 ${host} 超时（${Math.round(totalMs / 1000)} 秒），请检查网络后重试`,
        ),
      );
    }, remainingMs);
  });
  try {
    return await Promise.race([promise, timeout]);
  } finally {
    if (timer !== undefined) {
      clearTimeout(timer);
    }
  }
}

async function forEachConcurrent<T>(
  values: readonly T[],
  concurrency: number,
  action: (value: T, index: number) => Promise<void>,
): Promise<void> {
  if (values.length === 0) {
    return;
  }
  let nextIndex = 0;
  const worker = async (): Promise<void> => {
    while (nextIndex < values.length) {
      const index = nextIndex;
      nextIndex += 1;
      await action(values[index], index);
    }
  };
  await Promise.all(
    Array.from(
      { length: Math.min(Math.max(concurrency, 1), values.length) },
      () => worker(),
    ),
  );
}
