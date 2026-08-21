import CookieManager from "@react-native-cookies/cookies";

import type { NativeCookieBag, NativeCookieCollector } from "./android-cookies";

export function createAndroidCookieCollector(): NativeCookieCollector {
  return {
    async get(url, includeHttpOnly = true) {
      return (await CookieManager.get(url, includeHttpOnly)) as NativeCookieBag;
    },
    async getAll(useWebKit = true) {
      return (await CookieManager.getAll(useWebKit)) as NativeCookieBag;
    },
  };
}
