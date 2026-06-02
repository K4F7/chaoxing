import type { SyncItem } from "./sync";

const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";
const GOOGLE_CALENDAR_API = "https://www.googleapis.com/calendar/v3";
const GOOGLE_CALENDAR_SCOPE = "https://www.googleapis.com/auth/calendar.events";
const DEADLINE_EVENT_MINUTES = 30;

export type GoogleCalendarConfig = {
  calendarId?: string;
  serviceAccountEmail?: string;
  privateKey?: string;
  serviceAccountJson?: string;
  oauthClientId?: string;
  oauthClientSecret?: string;
  oauthRefreshToken?: string;
};

export type GoogleCalendarSyncOptions = {
  fetcher?: typeof fetch;
  now?: Date;
  accessToken?: string;
};

export type GoogleCalendarSyncResult = {
  calendarId: string;
  attempted: number;
  created: number;
  updated: number;
  skipped: number;
  failed: GoogleCalendarSyncFailure[];
};

export type GoogleCalendarSyncFailure = {
  itemId: string;
  title: string;
  message: string;
};

type NormalizedGoogleCalendarConfig = {
  calendarId: string;
} & (
  | {
      authType: "service_account";
      serviceAccountEmail: string;
      privateKey: string;
    }
  | {
      authType: "oauth";
      oauthClientId: string;
      oauthClientSecret: string;
      oauthRefreshToken: string;
    }
);

type GoogleCalendarEvent = {
  id: string;
  summary: string;
  description: string;
  source: {
    title: string;
    url: string;
  };
  start: {
    dateTime: string;
    timeZone: string;
  };
  end: {
    dateTime: string;
    timeZone: string;
  };
  transparency: "transparent";
  reminders: {
    useDefault: boolean;
  };
  extendedProperties: {
    private: Record<string, string>;
  };
};

export async function syncGoogleCalendar(
  items: SyncItem[],
  config: GoogleCalendarConfig,
  options: GoogleCalendarSyncOptions = {},
): Promise<GoogleCalendarSyncResult> {
  const normalized = normalizeConfig(config);
  const fetcher = options.fetcher || fetch;
  const accessToken =
    options.accessToken ||
    (normalized.authType === "service_account"
      ? await fetchGoogleServiceAccountAccessToken(normalized, {
          fetcher,
          now: options.now,
        })
      : await refreshGoogleOAuthAccessToken(normalized, { fetcher }));
  const result: GoogleCalendarSyncResult = {
    calendarId: normalized.calendarId,
    attempted: 0,
    created: 0,
    updated: 0,
    skipped: 0,
    failed: [],
  };

  for (const item of items) {
    if (!item.dueAt) {
      result.skipped += 1;
      continue;
    }

    result.attempted += 1;
    try {
      const event = await buildGoogleCalendarEvent(item);
      const action = await upsertGoogleCalendarEvent({
        calendarId: normalized.calendarId,
        event,
        accessToken,
        fetcher,
      });
      result[action] += 1;
    } catch (error) {
      result.failed.push({
        itemId: item.id,
        title: item.title,
        message: error instanceof Error ? error.message : "unknown error",
      });
    }
  }

  return result;
}

export async function fetchGoogleServiceAccountAccessToken(
  config: GoogleCalendarConfig,
  options: { fetcher?: typeof fetch; now?: Date } = {},
): Promise<string> {
  const normalized = normalizeConfig(config);
  if (normalized.authType !== "service_account") {
    throw new Error("missing_google_service_account_config");
  }
  const now = Math.floor((options.now || new Date()).getTime() / 1000);
  const assertion = await signJwt(
    {
      alg: "RS256",
      typ: "JWT",
    },
    {
      iss: normalized.serviceAccountEmail,
      scope: GOOGLE_CALENDAR_SCOPE,
      aud: GOOGLE_TOKEN_URL,
      exp: now + 3600,
      iat: now,
    },
    normalized.privateKey,
  );

  const response = await (options.fetcher || fetch)(GOOGLE_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion,
    }),
  });
  const data = (await response.json()) as {
    access_token?: string;
    error?: string;
    error_description?: string;
  };

  if (!response.ok || !data.access_token) {
    throw new Error(
      data.error_description || data.error || `google_token_failed_${response.status}`,
    );
  }

  return data.access_token;
}

export async function refreshGoogleOAuthAccessToken(
  config: GoogleCalendarConfig,
  options: { fetcher?: typeof fetch } = {},
): Promise<string> {
  const normalized = normalizeConfig(config);
  if (normalized.authType !== "oauth") {
    throw new Error("missing_google_oauth_config");
  }

  const response = await (options.fetcher || fetch)(GOOGLE_TOKEN_URL, {
    method: "POST",
    headers: {
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams({
      client_id: normalized.oauthClientId,
      client_secret: normalized.oauthClientSecret,
      refresh_token: normalized.oauthRefreshToken,
      grant_type: "refresh_token",
    }),
  });
  const data = (await response.json()) as {
    access_token?: string;
    error?: string;
    error_description?: string;
  };

  if (!response.ok || !data.access_token) {
    throw new Error(
      data.error_description || data.error || `google_refresh_failed_${response.status}`,
    );
  }

  return data.access_token;
}

export async function buildGoogleCalendarEvent(
  item: SyncItem,
): Promise<GoogleCalendarEvent> {
  const dueAt = item.dueAt;
  if (!dueAt) {
    throw new Error("missing_due_time");
  }

  const start = new Date(dueAt);
  if (Number.isNaN(start.getTime())) {
    throw new Error("missing_due_time");
  }

  const end = new Date(start.getTime() + DEADLINE_EVENT_MINUTES * 60 * 1000);
  const kindLabel = item.kind === "exam" ? "考试" : "作业";

  return {
    id: await buildGoogleEventId(item.id),
    summary: `${kindLabel}截止：${item.title}`,
    description: [
      `来源：${item.sourceTitle}`,
      item.sourceSendTime ? `通知时间：${item.sourceSendTime}` : "",
      item.startAt ? `开始：${item.startAt}` : "",
      `截止：${dueAt}`,
      `学习通链接：${item.url}`,
    ]
      .filter(Boolean)
      .join("\n"),
    source: {
      title: "学习通",
      url: item.url,
    },
    start: {
      dateTime: dueAt,
      timeZone: "Asia/Shanghai",
    },
    end: {
      dateTime: end.toISOString(),
      timeZone: "Asia/Shanghai",
    },
    transparency: "transparent",
    reminders: {
      useDefault: true,
    },
    extendedProperties: {
      private: {
        chaoxingItemId: item.id,
        chaoxingKind: item.kind,
        chaoxingCourseId: item.courseId || "",
        chaoxingClassId: item.classId || "",
        chaoxingWorkId: item.workId || "",
      },
    },
  };
}

function normalizeConfig(
  config: GoogleCalendarConfig,
): NormalizedGoogleCalendarConfig {
  const parsed = config.serviceAccountJson
    ? (JSON.parse(config.serviceAccountJson) as {
        client_email?: string;
        private_key?: string;
      })
    : null;
  const calendarId = config.calendarId?.trim();
  const oauthClientId = config.oauthClientId?.trim();
  const oauthClientSecret = config.oauthClientSecret?.trim();
  const oauthRefreshToken = config.oauthRefreshToken?.trim();
  const serviceAccountEmail =
    config.serviceAccountEmail?.trim() || parsed?.client_email?.trim();
  const privateKey = normalizePrivateKey(config.privateKey || parsed?.private_key);

  if (!calendarId) {
    throw new Error("missing_GOOGLE_CALENDAR_ID");
  }

  if (oauthClientId && oauthClientSecret && oauthRefreshToken) {
    return {
      authType: "oauth",
      calendarId,
      oauthClientId,
      oauthClientSecret,
      oauthRefreshToken,
    };
  }

  if (!serviceAccountEmail) {
    throw new Error("missing_GOOGLE_SERVICE_ACCOUNT_EMAIL");
  }
  if (!privateKey) {
    throw new Error("missing_GOOGLE_PRIVATE_KEY");
  }

  return {
    authType: "service_account",
    calendarId,
    serviceAccountEmail,
    privateKey,
  };
}

async function upsertGoogleCalendarEvent(input: {
  calendarId: string;
  event: GoogleCalendarEvent;
  accessToken: string;
  fetcher: typeof fetch;
}): Promise<"created" | "updated"> {
  const calendarId = encodeURIComponent(input.calendarId);
  const eventId = encodeURIComponent(input.event.id);
  const updateResponse = await input.fetcher(
    `${GOOGLE_CALENDAR_API}/calendars/${calendarId}/events/${eventId}?sendUpdates=none`,
    {
      method: "PUT",
      headers: googleJsonHeaders(input.accessToken),
      body: JSON.stringify(input.event),
    },
  );

  if (updateResponse.ok) {
    return "updated";
  }
  if (updateResponse.status !== 404) {
    throw new Error(await readGoogleError(updateResponse, "google_event_update_failed"));
  }

  const insertResponse = await input.fetcher(
    `${GOOGLE_CALENDAR_API}/calendars/${calendarId}/events?sendUpdates=none`,
    {
      method: "POST",
      headers: googleJsonHeaders(input.accessToken),
      body: JSON.stringify(input.event),
    },
  );

  if (!insertResponse.ok) {
    throw new Error(await readGoogleError(insertResponse, "google_event_insert_failed"));
  }

  return "created";
}

async function signJwt(
  header: Record<string, unknown>,
  payload: Record<string, unknown>,
  privateKey: string,
): Promise<string> {
  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(privateKey),
    {
      name: "RSASSA-PKCS1-v1_5",
      hash: "SHA-256",
    },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput),
  );

  return `${signingInput}.${base64UrlEncode(signature)}`;
}

async function buildGoogleEventId(itemId: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(`chaoxing:${itemId}`),
  );
  return `cx${toHex(new Uint8Array(digest))}`;
}

function googleJsonHeaders(accessToken: string): Record<string, string> {
  return {
    Authorization: `Bearer ${accessToken}`,
    "Content-Type": "application/json; charset=utf-8",
  };
}

async function readGoogleError(
  response: Response,
  fallback: string,
): Promise<string> {
  const text = await response.text();
  try {
    const data = JSON.parse(text) as {
      error?: {
        message?: string;
      };
    };
    return data.error?.message || `${fallback}_${response.status}`;
  } catch {
    return text || `${fallback}_${response.status}`;
  }
}

function normalizePrivateKey(value: string | undefined): string | null {
  if (!value?.trim()) {
    return null;
  }

  return value.replace(/\\n/g, "\n").trim();
}

function pemToArrayBuffer(pem: string): ArrayBuffer {
  const base64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");
  const binary = atob(base64);
  const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
  return bytes.buffer;
}

function base64UrlEncode(value: string | ArrayBuffer): string {
  const bytes =
    typeof value === "string"
      ? new TextEncoder().encode(value)
      : new Uint8Array(value);
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function toHex(bytes: Uint8Array): string {
  return [...bytes].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}
