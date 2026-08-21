import {
  type ChaoxingHttpClient,
  type ChaoxingHttpRequest,
  type ChaoxingHttpResponse,
} from "@chaoxinghelper/domain";

import { CHAOXING_USER_AGENT } from "../auth/homepage-probe";

export type FetchLike = (
  input: string,
  init: {
    method: string;
    redirect: "manual";
    headers: Record<string, string>;
    body?: string;
  },
) => Promise<{
  status: number;
  url?: string;
  headers: {
    get(name: string): string | null;
    forEach?(callback: (value: string, key: string) => void): void;
  };
  text(): Promise<string>;
}>;

/**
 * Injected HTTP client for {@link createLocalSyncRunner}.
 * Redirects stay manual so the runner can refuse untrusted hops
 * and keep Cookie off hosts outside the 学习通 whitelist.
 */
export function createFetchChaoxingClient(
  fetchImpl: FetchLike,
  userAgent: string = CHAOXING_USER_AGENT,
): ChaoxingHttpClient {
  return {
    async send(request: ChaoxingHttpRequest): Promise<ChaoxingHttpResponse> {
      const headers: Record<string, string> = {
        Accept: "text/html,application/xhtml+xml,application/json",
        "User-Agent": userAgent,
        ...request.headers,
      };
      let body: string | undefined;
      if (request.method === "POST" && request.form) {
        body = new URLSearchParams(request.form).toString();
        if (!headerHas(headers, "content-type")) {
          headers["Content-Type"] = "application/x-www-form-urlencoded";
        }
      }
      const response = await fetchImpl(request.url, {
        method: request.method,
        redirect: "manual",
        headers,
        ...(body !== undefined ? { body } : {}),
      });
      return {
        status: response.status,
        url: response.url && response.url.length > 0 ? response.url : request.url,
        headers: collectHeaders(response.headers),
        body: await response.text(),
      };
    },
  };
}

function headerHas(headers: Record<string, string>, name: string): boolean {
  const expected = name.toLowerCase();
  return Object.keys(headers).some((key) => key.toLowerCase() === expected);
}

function collectHeaders(headers: {
  get(name: string): string | null;
  forEach?(callback: (value: string, key: string) => void): void;
}): Record<string, string> {
  const collected: Record<string, string> = {};
  if (typeof headers.forEach === "function") {
    headers.forEach((value, key) => {
      collected[key] = value;
    });
  }
  for (const name of ["set-cookie", "location", "content-type"]) {
    const value = headers.get(name);
    if (value != null && value.length > 0 && !headerHas(collected, name)) {
      collected[name] = value;
    }
  }
  return collected;
}
