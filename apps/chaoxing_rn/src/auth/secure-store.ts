/**
 * Small key/value surface so cookie persistence can be tested without
 * Keystore / Expo SecureStore.
 */
export type SecureKeyValueStore = {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  deleteItem(key: string): Promise<void>;
};

export type ExpoSecureStoreLike = {
  getItemAsync(key: string): Promise<string | null>;
  setItemAsync(key: string, value: string): Promise<void>;
  deleteItemAsync(key: string): Promise<void>;
};

export const WEB_COOKIE_STORE_REJECTED =
  "拒绝在 Web 上保存学习通 Cookie：安全存储只用于 Android Keystore / iOS Keychain。";

export function createSecureStoreAdapter(
  secureStore: ExpoSecureStoreLike,
  platform: string,
): SecureKeyValueStore {
  return {
    async getItem(key) {
      assertNativePlatform(platform);
      return secureStore.getItemAsync(key);
    },
    async setItem(key, value) {
      assertNativePlatform(platform);
      await secureStore.setItemAsync(key, value);
    },
    async deleteItem(key) {
      assertNativePlatform(platform);
      await secureStore.deleteItemAsync(key);
    },
  };
}

export class MemorySecureStore implements SecureKeyValueStore {
  private readonly values = new Map<string, string>();

  async getItem(key: string): Promise<string | null> {
    return this.values.get(key) ?? null;
  }

  async setItem(key: string, value: string): Promise<void> {
    this.values.set(key, value);
  }

  async deleteItem(key: string): Promise<void> {
    this.values.delete(key);
  }

  peek(key: string): string | undefined {
    return this.values.get(key);
  }

  keys(): string[] {
    return [...this.values.keys()];
  }
}

function assertNativePlatform(platform: string): void {
  if (platform === "web") {
    throw new Error(WEB_COOKIE_STORE_REJECTED);
  }
}
