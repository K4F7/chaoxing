export type JsonKeyValueStore = {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  deleteItem(key: string): Promise<void>;
};

export class MemoryJsonStore implements JsonKeyValueStore {
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
    return [...this.values.keys()].sort();
  }
}

type AsyncStorageLike = {
  getItem(key: string): Promise<string | null>;
  setItem(key: string, value: string): Promise<void>;
  removeItem(key: string): Promise<void>;
};

/**
 * Non-secret persistence (课程目录 / 已见通知 / 提醒历史).
 * Cookie never enters this store — it stays in the Keystore vault.
 */
export function createAsyncStorageJsonStore(
  storage: AsyncStorageLike,
): JsonKeyValueStore {
  return {
    getItem: (key) => storage.getItem(key),
    setItem: (key, value) => storage.setItem(key, value),
    deleteItem: (key) => storage.removeItem(key),
  };
}
