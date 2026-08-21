import { extractPageTitle } from "./html";
import { redactSensitiveUrl } from "./redaction";

export const AuthStatus = {
  authenticated: "authenticated",
  expired: "expired",
  missingCookie: "missingCookie",
  networkError: "networkError",
  httpStatus: "httpStatus",
  unknown: "unknown",
} as const;

export type AuthStatus = (typeof AuthStatus)[keyof typeof AuthStatus];

export const AuthenticationState = {
  unknown: "unknown",
  valid: "valid",
  expired: "expired",
} as const;

export type AuthenticationState =
  (typeof AuthenticationState)[keyof typeof AuthenticationState];

export type LoginSignals = {
  hasPassportLoginUrl: boolean;
  hasLoginTitle: boolean;
  hasLoginButton: boolean;
};

export type AuthCheckResult = {
  authenticated: boolean;
  statusCode: number;
  loginDetected: boolean;
  finalUrl: string;
  title: string | null;
};

export type AuthSessionTransition = {
  state: AuthenticationState;
  notify: boolean;
  stopAutoSync: boolean;
};

export function detectLoginSignals(url: string, html: string): LoginSignals {
  return {
    hasPassportLoginUrl:
      /passport2\.chaoxing\.com\/login/i.test(url) ||
      /passport2\.chaoxing\.com\/login/i.test(html),
    hasLoginTitle: /<title[^>]*>\s*用户登录\s*<\/title>/i.test(html),
    hasLoginButton: /\bid=["']loginBtn["']/i.test(html),
  };
}

export function loginSignalsDetected(signals: LoginSignals): boolean {
  return (
    signals.hasPassportLoginUrl ||
    signals.hasLoginTitle ||
    signals.hasLoginButton
  );
}

export function evaluateHomeAuth(input: {
  statusCode: number;
  finalUrl: string;
  html: string;
}): AuthCheckResult {
  const signals = detectLoginSignals(input.finalUrl, input.html);
  const loginDetected = loginSignalsDetected(signals);
  return {
    authenticated:
      input.statusCode >= 200 && input.statusCode < 300 && !loginDetected,
    statusCode: input.statusCode,
    loginDetected,
    finalUrl: redactSensitiveUrl(input.finalUrl),
    title: extractPageTitle(input.html),
  };
}

export function authStatusFromCheck(
  cookie: string,
  result: AuthCheckResult | null,
): AuthStatus {
  if (cookie.trim().length === 0) {
    return AuthStatus.missingCookie;
  }
  if (result === null) {
    return AuthStatus.unknown;
  }
  if (result.authenticated) {
    return AuthStatus.authenticated;
  }
  if (result.loginDetected) {
    return AuthStatus.expired;
  }
  if (result.statusCode === 0) {
    return AuthStatus.networkError;
  }
  if (result.statusCode < 200 || result.statusCode >= 300) {
    return AuthStatus.httpStatus;
  }
  return AuthStatus.unknown;
}

export function enterAuthenticationExpired(
  state: AuthenticationState,
): AuthSessionTransition {
  if (state === AuthenticationState.expired) {
    return { state, notify: false, stopAutoSync: true };
  }
  return {
    state: AuthenticationState.expired,
    notify: true,
    stopAutoSync: true,
  };
}

export function restoreAuthentication(): AuthSessionTransition {
  return {
    state: AuthenticationState.valid,
    notify: false,
    stopAutoSync: false,
  };
}

export function shouldAutoSync(state: AuthenticationState): boolean {
  return state !== AuthenticationState.expired;
}

export { extractPageTitle };
