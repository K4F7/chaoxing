import {
  cookieHeaderForChaoxingUri,
  mergeChaoxingResponseCookies,
} from "./cookie";
import {
  headerValue,
  type ChaoxingHttpClient,
  type ChaoxingHttpRequest,
  type ChaoxingHttpResponse,
} from "./http";
import { isTrustedChaoxingUrl } from "./url-policy";

export type CookieSessionPort = {
  getSource(): string;
  persist(source: string): Promise<void> | void;
};

export type NativeCookieJar = {
  /**
   * Cookies the native jar already holds for this URL, formatted as one
   * or more Set-Cookie lines. Used when JS `fetch` hides Set-Cookie.
   */
  snapshot(url: string): Promise<string | null> | string | null;
  remember?(url: string, setCookie: string): Promise<void> | void;
};

export type CookieAwareHttpOptions = {
  session: CookieSessionPort;
  inner: ChaoxingHttpClient;
  nativeJar?: NativeCookieJar;
  clock?: () => Date;
};

/**
 * Wraps any Chaoxing HTTP client so session cookies stay in the vault/jar.
 * Cookie is only attached to trusted 学习通 HTTPS hosts (never passport2).
 * Set-Cookie is merged through {@link mergeChaoxingResponseCookies}.
 */
export function createCookieAwareHttpClient(
  options: CookieAwareHttpOptions,
): ChaoxingHttpClient {
  const clock = options.clock ?? (() => new Date());
  return {
    async send(request: ChaoxingHttpRequest): Promise<ChaoxingHttpResponse> {
      const uri = new URL(request.url);
      const source = options.session.getSource();
      const headers = { ...request.headers };
      if (isTrustedChaoxingUrl(request.url)) {
        const cookie = cookieHeaderForChaoxingUri(source, uri);
        if (cookie.length > 0 && headerValue(headers, "cookie") == null) {
          headers.Cookie = cookie;
        }
      }
      const response = await options.inner.send({ ...request, headers });
      const headerSetCookie = headerValue(response.headers, "set-cookie") ?? "";
      const nativeSetCookie =
        (await options.nativeJar?.snapshot(response.url || request.url)) ?? "";
      const combined = [headerSetCookie, nativeSetCookie]
        .filter((value) => value.trim().length > 0)
        .join(", ");
      if (combined.length > 0) {
        await options.nativeJar?.remember?.(response.url || request.url, combined);
        const next = mergeChaoxingResponseCookies(
          source,
          new URL(response.url || request.url),
          combined,
          clock(),
        );
        if (next !== source) {
          await options.session.persist(next);
        }
      }
      return response;
    },
  };
}

export function collectSetCookieHeader(headers: {
  get(name: string): string | null;
  getSetCookie?(): string[];
  forEach?(callback: (value: string, key: string) => void): void;
}): string {
  const fromGetter = headers.getSetCookie?.() ?? [];
  if (fromGetter.length > 0) {
    return fromGetter.join(", ");
  }
  const collected: string[] = [];
  if (typeof headers.forEach === "function") {
    headers.forEach((value, key) => {
      if (key.toLowerCase() === "set-cookie" && value.trim().length > 0) {
        collected.push(value);
      }
    });
  }
  if (collected.length > 0) {
    return collected.join(", ");
  }
  return headers.get("set-cookie") ?? "";
}
