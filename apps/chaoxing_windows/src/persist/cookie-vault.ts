/**
 * Cookie never goes to the JSON settings store. Windows production
 * encrypts with DPAPI via the native shell; tests use this memory vault.
 */
export type CookieVaultSnapshot = {
  cookieSource: string;
  authenticationState: "unconfigured" | "unknown" | "valid" | "expired";
};

export type ProtectedStore = {
  read(): Promise<string | null>;
  write(value: string): Promise<void>;
  clear(): Promise<void>;
};

export class MemoryProtectedStore implements ProtectedStore {
  private value: string | null = null;

  async read(): Promise<string | null> {
    return this.value;
  }

  async write(value: string): Promise<void> {
    this.value = value;
  }

  async clear(): Promise<void> {
    this.value = null;
  }
}

export class CookieVault {
  constructor(private readonly store: ProtectedStore) {}

  async load(): Promise<CookieVaultSnapshot> {
    const raw = await this.store.read();
    if (raw == null || raw.length === 0) {
      return { cookieSource: "", authenticationState: "unconfigured" };
    }
    try {
      const parsed = JSON.parse(raw) as CookieVaultSnapshot;
      return {
        cookieSource: typeof parsed.cookieSource === "string" ? parsed.cookieSource : "",
        authenticationState: parsed.authenticationState ?? "unknown",
      };
    } catch {
      await this.store.clear();
      return { cookieSource: "", authenticationState: "unconfigured" };
    }
  }

  async saveCookieSource(source: string): Promise<void> {
    const current = await this.load();
    await this.store.write(
      JSON.stringify({ ...current, cookieSource: source, authenticationState: "valid" }),
    );
  }

  async saveAuthenticationState(
    authenticationState: CookieVaultSnapshot["authenticationState"],
  ): Promise<void> {
    const current = await this.load();
    await this.store.write(JSON.stringify({ ...current, authenticationState }));
  }

  async clear(): Promise<void> {
    await this.store.clear();
  }
}
