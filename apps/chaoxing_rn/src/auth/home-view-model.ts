import {
  AUTH_EXPIRED_BANNER_ACTION,
  AUTH_EXPIRED_BANNER_TITLE,
  type AuthenticationState,
} from "./session";

export type AuthExpiryBannerModel = {
  visible: true;
  title: typeof AUTH_EXPIRED_BANNER_TITLE;
  actionLabel: typeof AUTH_EXPIRED_BANNER_ACTION;
};

export type EmptySetupModel = {
  title: string;
  body: string;
  loginLabel: string;
  manualLabel: string;
};

export type HomeViewModel = {
  configured: boolean;
  authenticationState: AuthenticationState;
  expiryBanner: AuthExpiryBannerModel | null;
  emptySetup: EmptySetupModel | null;
  autoSyncStopped: boolean;
  statusLine: string;
  error: string | null;
};

export function buildHomeViewModel(input: {
  authenticationState: AuthenticationState;
  hasCookie: boolean;
  autoSyncStopped: boolean;
  error?: string | null;
}): HomeViewModel {
  const configured = input.hasCookie;
  const expired = input.authenticationState === "expired";
  return {
    configured,
    authenticationState: input.authenticationState,
    expiryBanner: expired
      ? {
          visible: true,
          title: AUTH_EXPIRED_BANNER_TITLE,
          actionLabel: AUTH_EXPIRED_BANNER_ACTION,
        }
      : null,
    emptySetup: configured
      ? null
      : {
          title: "配置学习通 Cookie",
          body: "在 App 内登录学习通后，将自动导入登录态并开始本地同步。",
          loginLabel: "登录学习通",
          manualLabel: "手动导入 Cookie",
        },
    autoSyncStopped: expired || input.autoSyncStopped,
    statusLine: statusLineFor(input.authenticationState, configured),
    error: input.error ?? null,
  };
}

function statusLineFor(
  state: AuthenticationState,
  configured: boolean,
): string {
  if (!configured || state === "unconfigured") {
    return "尚未登录";
  }
  if (state === "expired") {
    return "登录已失效，自动同步已停止";
  }
  if (state === "valid") {
    return "登录态有效";
  }
  return "登录态待确认";
}
