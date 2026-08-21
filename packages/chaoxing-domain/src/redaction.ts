const REDACTED = "[已隐藏]";

const sensitiveQueryKeys = new Set([
  "access_token",
  "account",
  "accountid",
  "auth",
  "authorization",
  "cookie",
  "enc",
  "id_token",
  "key",
  "puid",
  "refresh_token",
  "session",
  "sessionid",
  "sid",
  "token",
  "uid",
  "user_id",
  "userid",
]);

const sensitiveCookieNames = new Set([
  "_uid",
  "fid",
  "jsessionid",
  "route",
  "uid",
  "vc",
]);

function isSensitiveKey(key: string): boolean {
  const normalized = key.toLowerCase().replaceAll("-", "_");
  return (
    sensitiveQueryKeys.has(normalized) ||
    normalized.endsWith("_token") ||
    normalized.endsWith("_secret")
  );
}

function redactStructuredText(value: string): string {
  let result = value.replaceAll(
    /\b(?:Cookie|Set-Cookie|Authorization)\s*[:=]\s*[^\r\n]+/gi,
    (match) => `${match.split(/[:=]/)[0]}: ${REDACTED}`,
  );
  result = result.replaceAll(/\bBearer\s+[^\s,;]+/gi, `Bearer ${REDACTED}`);
  return result.replaceAll(
    /\b([a-zA-Z_][a-zA-Z0-9_-]*)\s*([:=])\s*([^\s&,;]+)/g,
    (match, key: string, separator: string) => {
      if (!isSensitiveKey(key) && !sensitiveCookieNames.has(key.toLowerCase())) {
        return match;
      }
      return `${key}${separator}${REDACTED}`;
    },
  );
}

export function redactSensitiveUrl(value: string): string {
  try {
    const uri = new URL(value);
    if (uri.username || uri.password) {
      uri.username = REDACTED;
      uri.password = "";
    }
    for (const key of [...uri.searchParams.keys()]) {
      if (isSensitiveKey(key)) {
        uri.searchParams.set(key, REDACTED);
      }
    }
    if (uri.hash.length > 0) {
      uri.hash = REDACTED;
    }
    return uri.toString();
  } catch {
    return redactStructuredText(value);
  }
}

export function redactSensitiveText(
  value: string,
  secrets: Iterable<string> = [],
): string {
  let result = value;
  for (const secret of secrets) {
    const trimmed = secret.trim();
    if (trimmed.length === 0) {
      continue;
    }
    result = result.replaceAll(trimmed, REDACTED);
    const encoded = encodeURIComponent(trimmed);
    if (encoded !== trimmed) {
      result = result.replaceAll(encoded, REDACTED);
    }
  }
  result = result.replaceAll(/https?:\/\/[^\s"'<>]+/gi, (match) =>
    redactSensitiveUrl(match),
  );
  return redactStructuredText(result);
}
