import {
  CookieSourceError,
  hasChaoxingIdentityCookieSource,
  isSafeChaoxingCookieSource,
  parseManualCookieInput,
  UNSAFE_COOKIE_MESSAGE,
} from "./cookie-store";
import { CookieVault } from "./cookie-vault";
import {
  AUTH_EXPIRED_REFRESH_MESSAGE,
  LOGIN_AUTH_FAILED_MESSAGE,
  LOGIN_IDENTITY_MISSING_MESSAGE,
  UNSAFE_STORED_COOKIE_MESSAGE,
  type AuthenticationState,
  type ChaoxingSessionSnapshot,
  type ChaoxingSyncSession,
  type CookieAuthenticator,
  type SyncRequestDecision,
  type SyncRequestKind,
  cookieHeaderFromSession,
} from "./session";
import { createIdentityAuthenticator } from "./homepage-probe";

export type SessionControllerState = ChaoxingSessionSnapshot & {
  loading: boolean;
  error: string | null;
  autoSyncStopped: boolean;
};

export type SessionControllerOptions = {
  vault: CookieVault;
  authenticator?: CookieAuthenticator;
  onExpiryEntered?: () => void;
};

export class SessionController implements ChaoxingSyncSession {
  private readonly vault: CookieVault;
  private readonly authenticator: CookieAuthenticator;
  private readonly onExpiryEntered?: () => void;
  private readonly listeners = new Set<() => void>();
  private expiryNotified = false;

  private current: SessionControllerState = {
    cookieSource: "",
    authenticationState: "unconfigured",
    loading: true,
    error: null,
    autoSyncStopped: false,
  };

  constructor(options: SessionControllerOptions) {
    this.vault = options.vault;
    this.authenticator = options.authenticator ?? createIdentityAuthenticator();
    this.onExpiryEntered = options.onExpiryEntered;
  }

  get state(): SessionControllerState {
    return this.current;
  }

  subscribe(listener: () => void): () => void {
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  getCookieSource(): string {
    return this.current.cookieSource;
  }

  getCookieHeader(url: string): string {
    return cookieHeaderFromSession(this.snapshot(), url);
  }

  getAuthenticationState(): AuthenticationState {
    return this.current.authenticationState;
  }

  snapshot(): ChaoxingSessionSnapshot {
    return {
      cookieSource: this.current.cookieSource,
      authenticationState: this.current.authenticationState,
    };
  }

  asSyncSession(): ChaoxingSyncSession {
    return this;
  }

  async load(): Promise<void> {
    this.patch({ loading: true });
    try {
      const loaded = await this.vault.load();
      const unsafe =
        loaded.cookieSource.length > 0 &&
        !isSafeChaoxingCookieSource(loaded.cookieSource);
      if (unsafe) {
        try {
          await this.vault.clearCookie();
        } catch {
          // Memory quarantine stays authoritative if Keystore is briefly down.
        }
        this.expiryNotified = false;
        this.patch({
          cookieSource: "",
          authenticationState: "unconfigured",
          loading: false,
          error: UNSAFE_STORED_COOKIE_MESSAGE,
          autoSyncStopped: false,
        });
        return;
      }
      if (loaded.cookieSource.trim().length === 0) {
        this.expiryNotified = false;
        this.patch({
          cookieSource: "",
          authenticationState: "unconfigured",
          loading: false,
          error: null,
          autoSyncStopped: false,
        });
        return;
      }
      const expired = loaded.authenticationState === "expired";
      this.expiryNotified = expired;
      this.patch({
        cookieSource: loaded.cookieSource,
        authenticationState: expired ? "expired" : loaded.authenticationState,
        loading: false,
        error: null,
        autoSyncStopped: expired,
      });
    } catch (error) {
      this.patch({
        loading: false,
        error: error instanceof Error ? error.message : "加载本地登录态失败",
      });
    }
  }

  async importCookieSource(source: string): Promise<void> {
    const trimmed = source.trim();
    if (!isSafeChaoxingCookieSource(trimmed)) {
      throw new CookieSourceError(UNSAFE_COOKIE_MESSAGE);
    }
    if (!hasChaoxingIdentityCookieSource(trimmed)) {
      throw new CookieSourceError(LOGIN_IDENTITY_MISSING_MESSAGE);
    }
    const auth = await this.authenticator(trimmed);
    if (!auth.authenticated) {
      throw new CookieSourceError(LOGIN_AUTH_FAILED_MESSAGE);
    }
    await this.vault.saveCookieSource(trimmed);
    await this.vault.saveAuthenticationState("valid");
    this.expiryNotified = false;
    this.patch({
      cookieSource: trimmed,
      authenticationState: "valid",
      error: null,
      autoSyncStopped: false,
    });
  }

  async importManualCookie(input: string): Promise<void> {
    await this.importCookieSource(parseManualCookieInput(input));
  }

  /**
   * Persist a rotated cookie jar after sync. Does not re-authenticate;
   * identity cookies must still be present. Never used for manual paste.
   */
  async replaceCookieSource(source: string): Promise<void> {
    const trimmed = source.trim();
    if (trimmed === this.current.cookieSource) {
      return;
    }
    if (!isSafeChaoxingCookieSource(trimmed) || !hasChaoxingIdentityCookieSource(trimmed)) {
      return;
    }
    await this.vault.saveCookieSource(trimmed);
    this.patch({ cookieSource: trimmed });
  }


  markExpired(): void {
    if (this.current.authenticationState === "expired") {
      return;
    }
    if (this.current.authenticationState === "unconfigured") {
      return;
    }
    this.patch({
      authenticationState: "expired",
      autoSyncStopped: true,
      error: AUTH_EXPIRED_REFRESH_MESSAGE,
    });
    void this.vault.saveAuthenticationState("expired");
    if (!this.expiryNotified) {
      this.expiryNotified = true;
      this.onExpiryEntered?.();
    }
  }

  markValid(): void {
    if (this.current.cookieSource.trim().length === 0) {
      return;
    }
    this.expiryNotified = false;
    this.patch({
      authenticationState: "valid",
      autoSyncStopped: false,
      error: null,
    });
    void this.vault.saveAuthenticationState("valid");
  }

  requestSync(kind: SyncRequestKind): SyncRequestDecision {
    if (this.current.authenticationState === "unconfigured") {
      return {
        allowed: false,
        reason: "unconfigured",
        message: kind === "manual" ? "请先登录学习通" : null,
      };
    }
    if (this.current.authenticationState === "expired") {
      const message =
        kind === "manual" ? AUTH_EXPIRED_REFRESH_MESSAGE : null;
      if (kind === "manual") {
        this.patch({ error: AUTH_EXPIRED_REFRESH_MESSAGE });
      }
      return { allowed: false, reason: "expired", message };
    }
    return { allowed: true };
  }

  async clearSession(): Promise<void> {
    await this.vault.clear();
    this.expiryNotified = false;
    this.patch({
      cookieSource: "",
      authenticationState: "unconfigured",
      error: null,
      autoSyncStopped: false,
    });
  }

  private patch(partial: Partial<SessionControllerState>): void {
    this.current = { ...this.current, ...partial };
    for (const listener of this.listeners) {
      listener();
    }
  }
}
