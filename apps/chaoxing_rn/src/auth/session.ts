import { cookieHeaderForChaoxingUri } from "./cookie-store";
import type { AuthCheckResult } from "./login-signals";

/**
 * Visible 认证失效 states. `expired` must never look like a healthy idle
 * session — the later sync package reads this instead of inferring from
 * empty results.
 */
export type AuthenticationState =
  | "unconfigured"
  | "unknown"
  | "valid"
  | "expired";

export type ChaoxingSessionSnapshot = {
  cookieSource: string;
  authenticationState: AuthenticationState;
};

/**
 * Thin session the later sync / parsing package can consume.
 * Sync must not persist Cookie itself; it asks for a scoped header and
 * reports 认证失效 through {@link ChaoxingSyncSession.markExpired}.
 */
export type ChaoxingSyncSession = {
  getCookieSource(): string;
  getCookieHeader(url: string): string;
  getAuthenticationState(): AuthenticationState;
  markExpired(): void;
  markValid(): void;
};

export type CookieAuthenticator = (
  cookieSource: string,
) => Promise<AuthCheckResult>;

export type SyncRequestKind = "manual" | "auto";

export type SyncRequestDecision =
  | { allowed: true }
  | {
      allowed: false;
      reason: "unconfigured" | "expired";
      message: string | null;
    };

export const AUTH_EXPIRED_REFRESH_MESSAGE =
  "登录已失效，请重新登录后再刷新";

export const AUTH_EXPIRED_BANNER_TITLE = "登录已失效";
export const AUTH_EXPIRED_BANNER_ACTION = "重新登录";
export const LOGIN_IDENTITY_MISSING_MESSAGE =
  "尚未读取到有效登录态，请完成登录后再试。";
export const LOGIN_AUTH_FAILED_MESSAGE = "登录态验证失败，请在登录成功后重试。";
export const UNSAFE_STORED_COOKIE_MESSAGE =
  "本地 Cookie 格式不安全，已忽略，请重新登录";

export function cookieHeaderFromSession(
  snapshot: ChaoxingSessionSnapshot,
  url: string,
): string {
  if (snapshot.authenticationState === "unconfigured") {
    return "";
  }
  return cookieHeaderForChaoxingUri(snapshot.cookieSource, url);
}
