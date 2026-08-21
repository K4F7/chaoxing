import { COOKIE_STORE_FORMAT } from "./constants";
import {
  isTrustedChaoxingCookieDomain,
  normalizeChaoxingDomain,
} from "./url-policy";

const identityCookieNames = new Set([
  "_uid",
  "UID",
  "vc3",
  "uf",
  "p_auth_token",
  "cx_p_token",
  "xxtenc",
]);

export type ChaoxingCookieRecord = {
  name: string;
  value: string;
  domain: string;
  path: string;
  secure: boolean;
  hostOnly: boolean;
};

export function encodeChaoxingCookieStore(
  cookies: Iterable<ChaoxingCookieRecord>,
): string {
  return JSON.stringify({
    format: COOKIE_STORE_FORMAT,
    cookies: [...cookies].map((cookie) => ({
      name: cookie.name,
      value: cookie.value,
      domain: cookie.domain,
      path: cookie.path,
      secure: cookie.secure,
      hostOnly: cookie.hostOnly,
    })),
  });
}

export function decodeChaoxingCookieStore(
  source: string,
): ChaoxingCookieRecord[] | null {
  const trimmed = source.trim();
  if (!trimmed.startsWith("{")) {
    return null;
  }
  try {
    const decoded: unknown = JSON.parse(trimmed);
    if (
      decoded === null ||
      typeof decoded !== "object" ||
      !("format" in decoded) ||
      decoded.format !== COOKIE_STORE_FORMAT
    ) {
      return null;
    }
    const rawCookies = "cookies" in decoded ? decoded.cookies : null;
    if (!Array.isArray(rawCookies)) {
      return null;
    }
    return rawCookies
      .filter((cookie): cookie is Record<string, unknown> =>
        cookie !== null && typeof cookie === "object" && !Array.isArray(cookie),
      )
      .map((cookie) => ({
        name: typeof cookie.name === "string" ? cookie.name : "",
        value: typeof cookie.value === "string" ? cookie.value : "",
        domain: typeof cookie.domain === "string" ? cookie.domain : "",
        path: typeof cookie.path === "string" ? cookie.path : "/",
        secure: cookie.secure !== false,
        hostOnly: cookie.hostOnly === true,
      }))
      .filter(isValidCookieRecord);
  } catch {
    return null;
  }
}

export function isSafeChaoxingCookieSource(source: string): boolean {
  if (source.includes("\r") || source.includes("\n")) {
    return false;
  }
  const structured = decodeChaoxingCookieStore(source);
  if (structured !== null) {
    return structured.length > 0;
  }
  return parseLegacyCookieHeader(source).length > 0;
}

export function hasChaoxingIdentityCookieSource(source: string): boolean {
  if (!isSafeChaoxingCookieSource(source)) {
    return false;
  }
  const structured = decodeChaoxingCookieStore(source);
  const records = structured ?? parseLegacyCookieHeader(source);
  return records.some((cookie) => identityCookieNames.has(cookie.name));
}

export function chaoxingCookieSecrets(source: string): string[] {
  const secrets = source.trim().length > 0 ? [source] : [];
  const records = decodeChaoxingCookieStore(source);
  if (records !== null) {
    secrets.push(
      ...records
        .map((cookie) => cookie.value)
        .filter((value) => value.length > 0),
    );
  }
  return secrets;
}

export function cookieHeaderForChaoxingUri(source: string, uri: URL): string {
  if (
    !isSafeChaoxingCookieSource(source) ||
    uri.protocol !== "https:" ||
    uri.hostname.toLowerCase() === "passport2.chaoxing.com"
  ) {
    return "";
  }
  const records =
    decodeChaoxingCookieStore(source) ?? parseLegacyCookieHeader(source);
  const applicable = records
    .filter((cookie) => {
      if (cookie.secure && uri.protocol !== "https:") {
        return false;
      }
      return (
        domainMatches(uri.hostname, cookie.domain, cookie.hostOnly) &&
        pathMatches(uri.pathname, cookie.path)
      );
    })
    .sort((left, right) => {
      const pathOrder = right.path.length - left.path.length;
      return pathOrder !== 0 ? pathOrder : left.name.localeCompare(right.name);
    });
  return applicable
    .map((cookie) => `${cookie.name}=${cookie.value}`)
    .join("; ");
}

export function mergeChaoxingResponseCookies(
  source: string,
  requestUri: URL,
  setCookieHeader: string | null | undefined,
  now: Date = new Date(),
): string {
  if (setCookieHeader == null || setCookieHeader.trim().length === 0) {
    return source;
  }
  if (requestUri.hostname.toLowerCase() === "passport2.chaoxing.com") {
    return source;
  }
  const records = [
    ...(decodeChaoxingCookieStore(source) ?? parseLegacyCookieHeader(source)),
  ];
  for (const rawCookie of splitSetCookieHeader(setCookieHeader)) {
    const parts = rawCookie.split(";");
    if (parts.length === 0) {
      continue;
    }
    const separator = parts[0].indexOf("=");
    if (separator <= 0) {
      continue;
    }
    const name = parts[0].slice(0, separator).trim();
    const value = parts[0].slice(separator + 1).trim();
    let domain = requestUri.hostname.toLowerCase();
    let path = defaultCookiePath(requestUri.pathname);
    let secure = false;
    let hostOnly = true;
    let deleteCookie = value.length === 0;
    let expires: Date | null = null;
    for (const attribute of parts.slice(1)) {
      const attributeSeparator = attribute.indexOf("=");
      const attributeName = (
        attributeSeparator < 0
          ? attribute
          : attribute.slice(0, attributeSeparator)
      )
        .trim()
        .toLowerCase();
      const attributeValue =
        attributeSeparator < 0
          ? ""
          : attribute.slice(attributeSeparator + 1).trim();
      if (attributeName === "domain" && attributeValue.length > 0) {
        domain = normalizeChaoxingDomain(attributeValue);
        hostOnly = false;
      } else if (attributeName === "path" && attributeValue.startsWith("/")) {
        path = attributeValue;
      } else if (attributeName === "secure") {
        secure = true;
      } else if (attributeName === "max-age" && attributeValue === "0") {
        deleteCookie = true;
      } else if (attributeName === "max-age") {
        const seconds = Number.parseInt(attributeValue, 10);
        if (!Number.isNaN(seconds) && seconds <= 0) {
          deleteCookie = true;
        }
      } else if (attributeName === "expires") {
        const parsed = Date.parse(attributeValue);
        expires = Number.isNaN(parsed) ? null : new Date(parsed);
      }
    }
    if (expires !== null && expires.getTime() <= now.getTime()) {
      deleteCookie = true;
    }
    if (
      !isSafeCookieName(name) ||
      !domainMatches(requestUri.hostname, domain, hostOnly) ||
      !isTrustedChaoxingCookieDomain(domain)
    ) {
      continue;
    }
    const nextRecords = records.filter(
      (cookie) =>
        !(
          cookie.name === name &&
          normalizeChaoxingDomain(cookie.domain) === domain &&
          cookie.path === path &&
          cookie.hostOnly === hostOnly
        ),
    );
    records.length = 0;
    records.push(...nextRecords);
    if (!deleteCookie && isSafeCookieValue(value)) {
      records.push({
        name,
        value,
        domain,
        path,
        secure,
        hostOnly,
      });
    }
  }
  return encodeChaoxingCookieStore(records.filter(isValidCookieRecord));
}

function parseLegacyCookieHeader(header: string): ChaoxingCookieRecord[] {
  const records: ChaoxingCookieRecord[] = [];
  for (const part of header.split(";")) {
    const separator = part.indexOf("=");
    if (separator <= 0) {
      continue;
    }
    const name = part.slice(0, separator).trim();
    const value = part.slice(separator + 1).trim();
    if (isSafeCookieName(name) && isSafeCookieValue(value)) {
      records.push({
        name,
        value,
        domain: "chaoxing.com",
        path: "/",
        secure: true,
        hostOnly: false,
      });
    }
  }
  return records;
}

function splitSetCookieHeader(header: string): string[] {
  const starts = [
    ...header.matchAll(/(?:^|,\s*)([!#$%&'*+\-.^_`|~0-9A-Za-z]+)=/g),
  ];
  if (starts.length === 0) {
    return [];
  }
  return starts.map((match, index) => {
    const start =
      match.index + (header[match.index] === "," ? 1 : 0);
    const end = index + 1 < starts.length ? starts[index + 1].index : header.length;
    return header.slice(start, end).trim().replace(/,$/, "");
  });
}

function isValidCookieRecord(cookie: ChaoxingCookieRecord): boolean {
  return (
    isSafeCookieName(cookie.name) &&
    isSafeCookieValue(cookie.value) &&
    isTrustedChaoxingCookieDomain(cookie.domain) &&
    cookie.path.startsWith("/")
  );
}

function isSafeCookieName(name: string): boolean {
  return /^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$/.test(name);
}

function isSafeCookieValue(value: string): boolean {
  return (
    value.length > 0 &&
    !value.includes(";") &&
    !value.includes("\r") &&
    !value.includes("\n")
  );
}

function domainMatches(host: string, domain: string, hostOnly: boolean): boolean {
  const normalizedHost = host.toLowerCase();
  const normalizedDomain = normalizeChaoxingDomain(domain);
  return (
    normalizedHost === normalizedDomain ||
    (!hostOnly && normalizedHost.endsWith(`.${normalizedDomain}`))
  );
}

function defaultCookiePath(requestPath: string): string {
  if (!requestPath.startsWith("/") || requestPath === "/") {
    return "/";
  }
  const lastSlash = requestPath.lastIndexOf("/");
  return lastSlash <= 0 ? "/" : requestPath.slice(0, lastSlash);
}

function pathMatches(requestPath: string, cookiePath: string): boolean {
  const normalizedPath = cookiePath.length === 0 ? "/" : cookiePath;
  if (requestPath === normalizedPath) {
    return true;
  }
  if (!requestPath.startsWith(normalizedPath)) {
    return false;
  }
  return (
    normalizedPath.endsWith("/") ||
    requestPath.slice(normalizedPath.length).startsWith("/")
  );
}
