import {
  CookieRequestSecurityError,
  fetchChaoxingWithCookie,
  type CookieFetcher,
} from "./safe-fetch";

export const DEFAULT_CHAOXING_HOME_URL =
  "https://i.chaoxing.com/base?ws=1&t=1780231212848";

const MAX_AUTH_BODY_BYTES = 512 * 1024;

export type AuthFetcher = CookieFetcher;

export type LoginSignals = {
  hasPassportLoginUrl: boolean;
  hasLoginTitle: boolean;
  hasLoginButton: boolean;
};

export type PageFeatures = LoginSignals & {
  hasLikelySpaceText: boolean;
  hasInboxText: boolean;
  hasCourseText: boolean;
  bodyLength: number;
  bodyTruncated: boolean;
};

export type ChaoxingAuthResult = {
  authenticated: boolean;
  checkedAt: string;
  targetUrl: string;
  finalUrl: string;
  status: number;
  redirected: boolean;
  title: string | null;
  features: PageFeatures;
  failureReason?: string;
};

export type ChaoxingAuthOptions = {
  cookie?: string;
  homeUrl?: string;
  fetcher?: AuthFetcher;
};

export async function checkChaoxingAuth(
  options: ChaoxingAuthOptions,
): Promise<ChaoxingAuthResult> {
  const targetUrl = options.homeUrl?.trim() || DEFAULT_CHAOXING_HOME_URL;
  const checkedAt = new Date().toISOString();
  const emptyFeatures = buildFeatures("", false, targetUrl);

  if (!options.cookie?.trim()) {
    return {
      authenticated: false,
      checkedAt,
      targetUrl,
      finalUrl: targetUrl,
      status: 0,
      redirected: false,
      title: null,
      features: emptyFeatures,
      failureReason: "missing CHAOXING_COOKIE",
    };
  }

  const fetcher = options.fetcher ?? fetch;
  let response: Response;
  try {
    response = await fetchChaoxingWithCookie(fetcher, targetUrl, {
      method: "GET",
      headers: {
        Accept:
          "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.7",
        "Cache-Control": "no-cache",
        Cookie: options.cookie,
        Pragma: "no-cache",
        "User-Agent":
          "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125 Safari/537.36",
      },
    });
  } catch (error) {
    if (!(error instanceof CookieRequestSecurityError)) {
      throw error;
    }

    return {
      authenticated: false,
      checkedAt,
      targetUrl,
      finalUrl: targetUrl,
      status: 0,
      redirected: false,
      title: null,
      features: emptyFeatures,
      failureReason: error.message,
    };
  }

  const finalUrl = response.url || targetUrl;
  const { text, truncated } = await readTextWithLimit(
    response,
    MAX_AUTH_BODY_BYTES,
  );
  const title = extractPageTitle(text);
  const features = buildFeatures(text, truncated, finalUrl);
  const loginDetected =
    features.hasPassportLoginUrl ||
    features.hasLoginTitle ||
    features.hasLoginButton;

  let failureReason: string | undefined;
  if (loginDetected) {
    failureReason = "redirected_or_rendered_login_page";
  } else if (!response.ok) {
    failureReason = `http_status_${response.status}`;
  }

  return {
    authenticated: response.ok && !loginDetected,
    checkedAt,
    targetUrl,
    finalUrl,
    status: response.status,
    redirected: response.redirected,
    title,
    features,
    failureReason,
  };
}

export function extractPageTitle(html: string): string | null {
  const match = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  if (!match?.[1]) {
    return null;
  }

  return decodeBasicHtmlEntities(match[1]).replace(/\s+/g, " ").trim() || null;
}

export function detectLoginSignals(url: string, html: string): LoginSignals {
  return {
    hasPassportLoginUrl:
      /passport2\.chaoxing\.com\/login/i.test(url) ||
      /passport2\.chaoxing\.com\/login/i.test(html),
    hasLoginTitle: /<title[^>]*>\s*用户登录\s*<\/title>/i.test(html),
    hasLoginButton: /\bid=["']loginBtn["']/i.test(html),
  };
}

function buildFeatures(
  html: string,
  bodyTruncated: boolean,
  finalUrl: string,
): PageFeatures {
  const signals = detectLoginSignals(finalUrl, html);

  return {
    ...signals,
    hasLikelySpaceText: /个人空间|学习空间|空间首页|我的主页/.test(html),
    hasInboxText: /收件箱|消息|通知/.test(html),
    hasCourseText: /课程|我的课程|我学的课/.test(html),
    bodyLength: html.length,
    bodyTruncated,
  };
}

async function readTextWithLimit(
  response: Response,
  maxBytes: number,
): Promise<{ text: string; truncated: boolean }> {
  if (!response.body) {
    return { text: await response.text(), truncated: false };
  }

  const reader = response.body.getReader();
  const decoder = new TextDecoder();
  let text = "";
  let bytesRead = 0;
  let truncated = false;

  for (;;) {
    const { done, value } = await reader.read();
    if (done) {
      break;
    }

    const remaining = maxBytes - bytesRead;
    if (remaining <= 0) {
      truncated = true;
      await reader.cancel();
      break;
    }

    bytesRead += value.byteLength;
    if (value.byteLength > remaining) {
      text += decoder.decode(value.slice(0, remaining), { stream: true });
      truncated = true;
      await reader.cancel();
      break;
    }

    text += decoder.decode(value, { stream: true });
  }

  text += decoder.decode();
  return { text, truncated };
}

function decodeBasicHtmlEntities(value: string): string {
  return value
    .replace(/&nbsp;/g, " ")
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}
