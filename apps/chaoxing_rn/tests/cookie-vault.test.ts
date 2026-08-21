import assert from "node:assert/strict";
import { describe, test } from "node:test";

import {
  AUTH_STATE_VAULT_KEY,
  COOKIE_VAULT_KEY,
  CookieVault,
} from "../src/auth/cookie-vault";
import { UNSAFE_COOKIE_MESSAGE } from "../src/auth/cookie-store";
import {
  createSecureStoreAdapter,
  MemorySecureStore,
  WEB_COOKIE_STORE_REJECTED,
  type ExpoSecureStoreLike,
} from "../src/auth/secure-store";

describe("cookie vault", () => {
  test("persists cookie and auth state only in the injected secure store", async () => {
    const store = new MemorySecureStore();
    const prefs = new MemorySecureStore();
    const vault = new CookieVault(store);

    await vault.saveCookieSource("UID=42; vc3=secret");
    await vault.saveAuthenticationState("valid");

    assert.equal(store.peek(COOKIE_VAULT_KEY), "UID=42; vc3=secret");
    assert.equal(store.peek(AUTH_STATE_VAULT_KEY), "valid");
    assert.deepEqual(prefs.keys(), []);

    const loaded = await vault.load();
    assert.equal(loaded.cookieSource, "UID=42; vc3=secret");
    assert.equal(loaded.authenticationState, "valid");
  });

  test("refuses newline injection and does not write it", async () => {
    const store = new MemorySecureStore();
    const vault = new CookieVault(store);

    await assert.rejects(
      () => vault.saveCookieSource("UID=1\r\nSet-Cookie: evil=1"),
      { message: UNSAFE_COOKIE_MESSAGE },
    );
    assert.equal(store.peek(COOKIE_VAULT_KEY), undefined);
  });

  test("clearing removes cookie without leaving a plaintext residue", async () => {
    const store = new MemorySecureStore();
    const vault = new CookieVault(store);
    await vault.saveCookieSource("UID=42");
    await vault.clear();

    const loaded = await vault.load();
    assert.equal(loaded.cookieSource, "");
    assert.equal(loaded.authenticationState, "unknown");
    assert.deepEqual(store.keys(), []);
  });

  test("expo adapter never writes through on web", async () => {
    const writes: string[] = [];
    const fake: ExpoSecureStoreLike = {
      async getItemAsync() {
        return null;
      },
      async setItemAsync(key, value) {
        writes.push(`${key}=${value}`);
      },
      async deleteItemAsync() {},
    };
    const adapter = createSecureStoreAdapter(fake, "web");
    await assert.rejects(() => adapter.setItem(COOKIE_VAULT_KEY, "UID=1"), {
      message: WEB_COOKIE_STORE_REJECTED,
    });
    assert.deepEqual(writes, []);
  });

  test("expo adapter writes to the native secure store on android", async () => {
    const writes: string[] = [];
    const fake: ExpoSecureStoreLike = {
      async getItemAsync(key) {
        return key === COOKIE_VAULT_KEY ? "UID=1" : null;
      },
      async setItemAsync(key, value) {
        writes.push(`${key}=${value}`);
      },
      async deleteItemAsync() {},
    };
    const adapter = createSecureStoreAdapter(fake, "android");
    await adapter.setItem(COOKIE_VAULT_KEY, "UID=2");
    assert.equal(await adapter.getItem(COOKIE_VAULT_KEY), "UID=1");
    assert.deepEqual(writes, [`${COOKIE_VAULT_KEY}=UID=2`]);
  });
});
