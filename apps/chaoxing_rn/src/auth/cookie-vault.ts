import {
  CookieSourceError,
  isSafeChaoxingCookieSource,
  UNSAFE_COOKIE_MESSAGE,
} from "./cookie-store";
import type { SecureKeyValueStore } from "./secure-store";

export const COOKIE_VAULT_KEY = "chaoxing_cookie";
export const AUTH_STATE_VAULT_KEY = "chaoxing_auth_state";

export type PersistedAuthenticationState = "unknown" | "valid" | "expired";

export type CookieVaultSnapshot = {
  cookieSource: string;
  authenticationState: PersistedAuthenticationState;
};

/**
 * Cookie and 认证失效 flag live only in the injected secure store.
 * Never write Cookie material to SharedPreferences / AsyncStorage.
 */
export class CookieVault {
  constructor(private readonly store: SecureKeyValueStore) {}

  async load(): Promise<CookieVaultSnapshot> {
    const cookieSource = (await this.store.getItem(COOKIE_VAULT_KEY)) ?? "";
    const rawState = await this.store.getItem(AUTH_STATE_VAULT_KEY);
    return {
      cookieSource,
      authenticationState: parsePersistedState(rawState),
    };
  }

  async saveCookieSource(source: string): Promise<void> {
    const trimmed = source.trim();
    if (trimmed.length === 0) {
      await this.clearCookie();
      return;
    }
    if (!isSafeChaoxingCookieSource(trimmed)) {
      throw new CookieSourceError(UNSAFE_COOKIE_MESSAGE);
    }
    await this.store.setItem(COOKIE_VAULT_KEY, trimmed);
  }

  async saveAuthenticationState(
    state: PersistedAuthenticationState,
  ): Promise<void> {
    await this.store.setItem(AUTH_STATE_VAULT_KEY, state);
  }

  async clearCookie(): Promise<void> {
    await this.store.deleteItem(COOKIE_VAULT_KEY);
  }

  async clear(): Promise<void> {
    await this.store.deleteItem(COOKIE_VAULT_KEY);
    await this.store.deleteItem(AUTH_STATE_VAULT_KEY);
  }
}

function parsePersistedState(
  value: string | null,
): PersistedAuthenticationState {
  if (value === "valid" || value === "expired" || value === "unknown") {
    return value;
  }
  return "unknown";
}
