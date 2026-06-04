import { checkChaoxingAuth } from "./auth";
import { buildAppSyncResponse } from "./app-sync";
import { handleCalDav } from "./caldav";
import { syncGoogleCalendar } from "./google-calendar";
import { processAssignments } from "./processor";
import { buildCalendarIcs, buildSyncItems, buildTodoIcs } from "./sync";

type WorkerEnv = {
  CHAOXING_COOKIE?: string;
  CHAOXING_HOME_URL?: string;
  PROCESS_DETAILS_LIMIT?: string;
  PROCESS_INBOX_LIMIT?: string;
  PROCESS_REQUIREMENTS_LIMIT?: string;
  RUN_TOKEN?: string;
  GOOGLE_CALENDAR_ID?: string;
  GOOGLE_SERVICE_ACCOUNT_EMAIL?: string;
  GOOGLE_PRIVATE_KEY?: string;
  GOOGLE_SERVICE_ACCOUNT_JSON?: string;
  GOOGLE_OAUTH_CLIENT_ID?: string;
  GOOGLE_OAUTH_CLIENT_SECRET?: string;
  GOOGLE_OAUTH_REFRESH_TOKEN?: string;
};

export default {
  async fetch(request: Request, env: WorkerEnv): Promise<Response> {
    const url = new URL(request.url);

    if (!isKnownPath(url.pathname)) {
      return jsonResponse({ error: "not_found" }, 404);
    }

    if (url.pathname === "/.well-known/caldav") {
      return handleCalDav({
        request,
        itemsLoader: () => Promise.resolve([]),
      });
    }

    if (!isAllowedMethod(url.pathname, request.method)) {
      return jsonResponse({ error: "method_not_allowed" }, 405, {
        Allow: allowedMethods(url.pathname),
      });
    }

    const authorization = request.headers.get("Authorization");
    const authorized = await isAuthorized(
      authorization,
      env.RUN_TOKEN,
      url.searchParams.get("token") || url.searchParams.get("access_token"),
    );
    if (!authorized) {
      return jsonResponse({ error: "unauthorized" }, 401, unauthorizedHeaders());
    }

    if (url.pathname.startsWith("/caldav/")) {
      return handleCalDav({
        request,
        itemsLoader: async () => {
          const result = await processAssignments({
            cookie: env.CHAOXING_COOKIE,
            homeUrl: env.CHAOXING_HOME_URL,
            inboxLimit: readNumberParam(url, "inboxLimit", env.PROCESS_INBOX_LIMIT),
            detailsLimit: readNumberParam(
              url,
              "detailsLimit",
              env.PROCESS_DETAILS_LIMIT,
            ),
            requirementsLimit: readNumberParam(
              url,
              "requirementsLimit",
              env.PROCESS_REQUIREMENTS_LIMIT,
            ),
          });
          return buildSyncItems(result.requirements);
        },
      });
    }

    if (
      url.pathname === "/process" ||
      url.pathname === "/sync" ||
      url.pathname === "/app/sync" ||
      url.pathname === "/google/calendar/sync" ||
      url.pathname === "/calendar.ics" ||
      url.pathname === "/todos.ics"
    ) {
      try {
        const result = await processAssignments({
          cookie: env.CHAOXING_COOKIE,
          homeUrl: env.CHAOXING_HOME_URL,
          inboxLimit: readNumberParam(url, "inboxLimit", env.PROCESS_INBOX_LIMIT),
          detailsLimit: readNumberParam(
            url,
            "detailsLimit",
            env.PROCESS_DETAILS_LIMIT,
          ),
          requirementsLimit: readNumberParam(
            url,
            "requirementsLimit",
            env.PROCESS_REQUIREMENTS_LIMIT,
          ),
        });

        if (url.pathname === "/sync") {
          return jsonResponse({
            ...result,
            syncItems: buildSyncItems(result.requirements),
          });
        }

        if (url.pathname === "/app/sync") {
          return jsonResponse(
            buildAppSyncResponse(result, buildSyncItems(result.requirements)),
          );
        }

        if (url.pathname === "/google/calendar/sync") {
          const syncItems = buildSyncItems(result.requirements);
          return jsonResponse({
            ...result,
            syncItems,
            googleCalendar: await syncGoogleCalendar(
              syncItems,
              googleCalendarConfig(env),
            ),
          });
        }

        if (url.pathname === "/calendar.ics") {
          return textResponse(
            buildCalendarIcs(buildSyncItems(result.requirements)),
            "text/calendar; charset=utf-8",
          );
        }

        if (url.pathname === "/todos.ics") {
          return textResponse(
            buildTodoIcs(buildSyncItems(result.requirements)),
            "text/calendar; charset=utf-8",
          );
        }

        return jsonResponse(result);
      } catch (error) {
        return jsonResponse(
          {
            processed: false,
            failureReason: "process_failed",
            message: error instanceof Error ? error.message : "unknown error",
          },
          502,
        );
      }
    }

    try {
      const result = await checkChaoxingAuth({
        cookie: env.CHAOXING_COOKIE,
        homeUrl: env.CHAOXING_HOME_URL,
      });

      return jsonResponse(result);
    } catch (error) {
      return jsonResponse(
        {
          authenticated: false,
          failureReason: "request_failed",
          message: error instanceof Error ? error.message : "unknown error",
        },
        502,
      );
    }
  },

  async scheduled(
    _controller: ScheduledController,
    env: WorkerEnv,
    _ctx: ExecutionContext,
  ): Promise<void> {
    const result = await processAssignments({
      cookie: env.CHAOXING_COOKIE,
      homeUrl: env.CHAOXING_HOME_URL,
      inboxLimit: readOptionalInteger(env.PROCESS_INBOX_LIMIT),
      detailsLimit: readOptionalInteger(env.PROCESS_DETAILS_LIMIT),
      requirementsLimit: readOptionalInteger(env.PROCESS_REQUIREMENTS_LIMIT),
    });
    const syncItems = buildSyncItems(result.requirements);
    const googleCalendar = hasGoogleCalendarConfig(env)
      ? await syncGoogleCalendar(syncItems, googleCalendarConfig(env))
      : null;

    console.log(
      JSON.stringify({
        event: "chaoxing_process_completed",
        processedAt: result.processedAt,
        inbox: result.inbox,
        totalUniqueActivityLinks: result.totalUniqueActivityLinks,
        totalUniqueWorkLinks: result.totalUniqueWorkLinks,
        fetchedRequirements: result.fetchedRequirements,
        failedRequirements: result.failedRequirements.length,
        googleCalendar,
      }),
    );
  },
} satisfies ExportedHandler<WorkerEnv>;

function isKnownPath(pathname: string): boolean {
  return [
    "/auth/check",
    "/process",
    "/sync",
    "/app/sync",
    "/google/calendar/sync",
    "/calendar.ics",
    "/todos.ics",
    "/.well-known/caldav",
  ].includes(pathname) || pathname.startsWith("/caldav/");
}

function isAllowedMethod(pathname: string, method: string): boolean {
  return allowedMethods(pathname).split(", ").includes(method);
}

function allowedMethods(pathname: string): string {
  if (pathname === "/.well-known/caldav") {
    return "GET";
  }
  if (pathname.startsWith("/caldav/")) {
    return "OPTIONS, PROPFIND, REPORT, GET, HEAD";
  }
  if (
    pathname === "/process" ||
    pathname === "/sync" ||
    pathname === "/app/sync" ||
    pathname === "/google/calendar/sync" ||
    pathname === "/calendar.ics" ||
    pathname === "/todos.ics"
  ) {
    return "GET, POST";
  }

  return "GET";
}

function jsonResponse(
  value: unknown,
  status = 200,
  extraHeaders: HeadersInit = {},
): Response {
  const headers = new Headers({
    "Content-Type": "application/json; charset=utf-8",
    "Cache-Control": "no-store",
  });

  new Headers(extraHeaders).forEach((headerValue, headerName) => {
    headers.set(headerName, headerValue);
  });

  return new Response(JSON.stringify(value, null, 2), {
    status,
    headers,
  });
}

function textResponse(
  value: string,
  contentType: string,
  status = 200,
): Response {
  return new Response(value, {
    status,
    headers: {
      "Content-Type": contentType,
      "Cache-Control": "no-store",
    },
  });
}

async function isAuthorized(
  authorizationHeader: string | null,
  expectedToken?: string,
  queryToken?: string | null,
): Promise<boolean> {
  const actualToken =
    extractBearerToken(authorizationHeader) ||
    extractBasicPassword(authorizationHeader) ||
    queryToken;
  if (!actualToken || !expectedToken) {
    return false;
  }

  const encoder = new TextEncoder();
  const [actualDigest, expectedDigest] = await Promise.all([
    crypto.subtle.digest("SHA-256", encoder.encode(actualToken)),
    crypto.subtle.digest("SHA-256", encoder.encode(expectedToken)),
  ]);

  return equalBytes(new Uint8Array(actualDigest), new Uint8Array(expectedDigest));
}

function extractBearerToken(authorizationHeader: string | null): string | null {
  const match = authorizationHeader?.match(/^Bearer\s+(.+)$/i);
  return match?.[1]?.trim() || null;
}

function extractBasicPassword(authorizationHeader: string | null): string | null {
  const match = authorizationHeader?.match(/^Basic\s+(.+)$/i);
  if (!match) {
    return null;
  }

  try {
    const decoded = atob(match[1]);
    const separatorIndex = decoded.indexOf(":");
    return separatorIndex >= 0 ? decoded.slice(separatorIndex + 1) : null;
  } catch {
    return null;
  }
}

function unauthorizedHeaders(): HeadersInit {
  return {
    "WWW-Authenticate": 'Basic realm="Chaoxing CalDAV", charset="UTF-8"',
  };
}

function equalBytes(left: Uint8Array, right: Uint8Array): boolean {
  if (left.length !== right.length) {
    return false;
  }

  let diff = 0;
  for (let index = 0; index < left.length; index += 1) {
    diff |= left[index] ^ right[index];
  }

  return diff === 0;
}

function readNumberParam(
  url: URL,
  name: string,
  fallback?: string,
): number | undefined {
  return readOptionalInteger(url.searchParams.get(name) || fallback);
}

function readOptionalInteger(value?: string | null): number | undefined {
  if (!value) {
    return undefined;
  }

  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? parsed : undefined;
}

function googleCalendarConfig(env: WorkerEnv) {
  return {
    calendarId: env.GOOGLE_CALENDAR_ID,
    serviceAccountEmail: env.GOOGLE_SERVICE_ACCOUNT_EMAIL,
    privateKey: env.GOOGLE_PRIVATE_KEY,
    serviceAccountJson: env.GOOGLE_SERVICE_ACCOUNT_JSON,
    oauthClientId: env.GOOGLE_OAUTH_CLIENT_ID,
    oauthClientSecret: env.GOOGLE_OAUTH_CLIENT_SECRET,
    oauthRefreshToken: env.GOOGLE_OAUTH_REFRESH_TOKEN,
  };
}

function hasGoogleCalendarConfig(env: WorkerEnv): boolean {
  return Boolean(
    env.GOOGLE_CALENDAR_ID &&
      ((env.GOOGLE_OAUTH_CLIENT_ID &&
        env.GOOGLE_OAUTH_CLIENT_SECRET &&
        env.GOOGLE_OAUTH_REFRESH_TOKEN) ||
        env.GOOGLE_SERVICE_ACCOUNT_JSON ||
        (env.GOOGLE_SERVICE_ACCOUNT_EMAIL && env.GOOGLE_PRIVATE_KEY)),
  );
}
