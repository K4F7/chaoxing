export type AuthCheckResult = {
  authenticated: boolean;
  statusCode: number;
  loginDetected: boolean;
  finalUrl: string;
  title: string | null;
};

export function detectLoginSignals(url: string, html: string): boolean {
  const loginHost = /passport2\.chaoxing\.com\/login/i;
  return (
    loginHost.test(url) ||
    loginHost.test(html) ||
    /<title[^>]*>\s*用户登录\s*<\/title>/i.test(html) ||
    /\bid=["']loginBtn["']/i.test(html)
  );
}

export function extractPageTitle(html: string): string | null {
  const match = html.match(/<title[^>]*>([\s\S]*?)<\/title>/i);
  if (!match) {
    return null;
  }
  const title = decodeBasicHtmlEntities(match[1] ?? "")
    .replace(/\s+/g, " ")
    .trim();
  return title.length > 0 ? title : null;
}

export function evaluateAuth(input: {
  statusCode: number;
  finalUrl: string;
  html: string;
}): AuthCheckResult {
  const loginDetected = detectLoginSignals(input.finalUrl, input.html);
  return {
    authenticated:
      input.statusCode >= 200 && input.statusCode < 300 && !loginDetected,
    statusCode: input.statusCode,
    loginDetected,
    finalUrl: input.finalUrl,
    title: extractPageTitle(input.html),
  };
}

function decodeBasicHtmlEntities(value: string): string {
  return value
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;/g, "'");
}
