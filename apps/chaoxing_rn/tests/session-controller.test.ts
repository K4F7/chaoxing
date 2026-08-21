import assert from "node:assert/strict";
import { describe, test } from "node:test";

import { CookieVault } from "../src/auth/cookie-vault";
import { MemorySecureStore } from "../src/auth/secure-store";
import {
  AUTH_EXPIRED_REFRESH_MESSAGE,
  LOGIN_AUTH_FAILED_MESSAGE,
  LOGIN_IDENTITY_MISSING_MESSAGE,
  UNSAFE_STORED_COOKIE_MESSAGE,
} from "../src/auth/session";
import { SessionController } from "../src/auth/session-controller";
import { UNSAFE_COOKIE_MESSAGE } from "../src/auth/cookie-store";
import type { CookieAuthenticator } from "../src/auth/session";

function controllerWith(
  store: MemorySecureStore,
  authenticator?: CookieAuthenticator,
  onExpiryEntered?: () => void,
) {
  return new SessionController({
    vault: new CookieVault(store),
    authenticator,
    onExpiryEntered,
  });
}

describe("session controller", () => {
  test("marks 认证失效 once, stops auto sync, and keeps the cookie for re-login", async () => {
    const store = new MemorySecureStore();
    let expiryEvents = 0;
    const controller = controllerWith(store, undefined, () => {
      expiryEvents += 1;
    });
    await controller.importCookieSource("UID=1; vc3=secret");
    const sync = controller.asSyncSession();

    controller.markExpired();
    controller.markExpired();

    assert.equal(sync.getAuthenticationState(), "expired");
    assert.equal(controller.state.autoSyncStopped, true);
    assert.equal(expiryEvents, 1);
    assert.match(sync.getCookieHeader("https://i.chaoxing.com/"), /UID=1/);
    assert.deepEqual(controller.requestSync("auto"), {
      allowed: false,
      reason: "expired",
      message: null,
    });
    assert.deepEqual(controller.requestSync("manual"), {
      allowed: false,
      reason: "expired",
      message: AUTH_EXPIRED_REFRESH_MESSAGE,
    });
    assert.equal(controller.state.error, AUTH_EXPIRED_REFRESH_MESSAGE);
    assert.equal((await new CookieVault(store).load()).authenticationState, "expired");
  });

  test("re-login resets 认证失效 and allows sync again", async () => {
    const store = new MemorySecureStore();
    const controller = controllerWith(store);
    await controller.importCookieSource("UID=old; vc3=old");
    controller.markExpired();

    await controller.importCookieSource("UID=new; vc3=new");

    assert.equal(controller.getAuthenticationState(), "valid");
    assert.equal(controller.state.autoSyncStopped, false);
    assert.equal(controller.requestSync("auto").allowed, true);
    assert.match(controller.getCookieHeader("https://i.chaoxing.com/"), /UID=new/);
  });

  test("loads a persisted expired session as visible expiry", async () => {
    const store = new MemorySecureStore();
    const first = controllerWith(store);
    await first.importCookieSource("UID=1; vc3=secret");
    first.markExpired();

    const restored = controllerWith(store);
    await restored.load();

    assert.equal(restored.getAuthenticationState(), "expired");
    assert.equal(restored.state.autoSyncStopped, true);
    assert.equal(restored.state.cookieSource.includes("UID=1"), true);
  });

  test("quarantines an unsafe stored cookie and asks for re-login", async () => {
    const store = new MemorySecureStore();
    await store.setItem("chaoxing_cookie", "UID=1\nX-Evil: 1");
    const controller = controllerWith(store);
    await controller.load();

    assert.equal(controller.getAuthenticationState(), "unconfigured");
    assert.equal(controller.state.error, UNSAFE_STORED_COOKIE_MESSAGE);
    assert.equal(store.peek("chaoxing_cookie"), undefined);
  });

  test("manual import rejects newline injection before authenticate or save", async () => {
    const store = new MemorySecureStore();
    let authenticated = 0;
    const controller = controllerWith(store, async () => {
      authenticated += 1;
      return {
        authenticated: true,
        statusCode: 200,
        loginDetected: false,
        finalUrl: "",
        title: null,
      };
    });

    await assert.rejects(
      () => controller.importManualCookie("UID=1\r\nAuthorization: bad"),
      { message: UNSAFE_COOKIE_MESSAGE },
    );
    assert.equal(authenticated, 0);
    assert.deepEqual(store.keys(), []);
  });

  test("rejects a captured jar that has no identity cookie", async () => {
    const controller = controllerWith(new MemorySecureStore());
    await assert.rejects(() => controller.importCookieSource("theme=dark; route=1"), {
      message: LOGIN_IDENTITY_MISSING_MESSAGE,
    });
  });

  test("does not persist when authenticator says the session is still a login page", async () => {
    const store = new MemorySecureStore();
    const controller = controllerWith(store, async () => ({
      authenticated: false,
      statusCode: 200,
      loginDetected: true,
      finalUrl: "https://passport2.chaoxing.com/login",
      title: "用户登录",
    }));

    await assert.rejects(() => controller.importCookieSource("UID=invalid; vc3=x"), {
      message: LOGIN_AUTH_FAILED_MESSAGE,
    });
    assert.deepEqual(store.keys(), []);
  });
});
