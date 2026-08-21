import { createAsyncStorageJsonStore, type JsonKeyValueStore } from "./json-store";

type AsyncStorageModule = {
  default: {
    getItem(key: string): Promise<string | null>;
    setItem(key: string, value: string): Promise<void>;
    removeItem(key: string): Promise<void>;
  };
};

export function createDeviceJsonStore(): JsonKeyValueStore | null {
  try {
    const loaded = require("@react-native-async-storage/async-storage") as AsyncStorageModule;
    return createAsyncStorageJsonStore(loaded.default);
  } catch {
    return null;
  }
}
