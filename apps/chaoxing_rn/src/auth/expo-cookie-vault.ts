import { Platform } from "react-native";
import * as SecureStore from "expo-secure-store";

import { CookieVault } from "./cookie-vault";
import { createSecureStoreAdapter } from "./secure-store";

export function createExpoCookieVault(): CookieVault {
  return new CookieVault(createSecureStoreAdapter(SecureStore, Platform.OS));
}
