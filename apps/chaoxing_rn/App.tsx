import { StatusBar } from "expo-status-bar";
import { useEffect, useMemo, useState } from "react";
import { ActivityIndicator, StyleSheet, View } from "react-native";

import { createAndroidCookieCollector } from "./src/auth/android-cookie-collector";
import { createExpoCookieVault } from "./src/auth/expo-cookie-vault";
import {
  createHomepageAuthProbe,
  createLoginAuthenticator,
} from "./src/auth/homepage-probe";
import { buildHomeViewModel } from "./src/auth/home-view-model";
import { SessionController } from "./src/auth/session-controller";
import { buildReminderPreview } from "./src/preview";
import { HomeScreen } from "./src/screens/HomeScreen";
import { LoginScreen } from "./src/screens/LoginScreen";
import { ManualCookieScreen } from "./src/screens/ManualCookieScreen";

type ScreenName = "home" | "login" | "manual";

const preview = buildReminderPreview(new Date());

export default function App() {
  const controller = useMemo(() => {
    return new SessionController({
      vault: createExpoCookieVault(),
      authenticator: createLoginAuthenticator(createHomepageAuthProbe(fetch)),
    });
  }, []);
  const collector = useMemo(() => createAndroidCookieCollector(), []);
  const [, setTick] = useState(0);
  const [screen, setScreen] = useState<ScreenName>("home");

  useEffect(() => {
    const unsubscribe = controller.subscribe(() => {
      setTick((value) => value + 1);
    });
    void controller.load();
    return unsubscribe;
  }, [controller]);

  const viewModel = buildHomeViewModel({
    authenticationState: controller.state.authenticationState,
    hasCookie: controller.state.cookieSource.trim().length > 0,
    autoSyncStopped: controller.state.autoSyncStopped,
    error: controller.state.error,
  });

  if (controller.state.loading) {
    return (
      <View style={styles.loading}>
        <ActivityIndicator size="large" />
        <StatusBar style="auto" />
      </View>
    );
  }

  if (screen === "login") {
    return (
      <>
        <LoginScreen
          collector={collector}
          onCookieCaptured={(source) => controller.importCookieSource(source)}
          onClose={() => setScreen("home")}
        />
        <StatusBar style="auto" />
      </>
    );
  }

  if (screen === "manual") {
    return (
      <>
        <ManualCookieScreen
          hasSavedCookie={controller.state.cookieSource.trim().length > 0}
          onImport={(input) => controller.importManualCookie(input)}
          onClose={() => setScreen("home")}
        />
        <StatusBar style="auto" />
      </>
    );
  }

  return (
    <>
      <HomeScreen
        viewModel={viewModel}
        preview={preview}
        onOpenLogin={() => setScreen("login")}
        onOpenManualCookie={() => setScreen("manual")}
      />
      <StatusBar style="auto" />
    </>
  );
}

const styles = StyleSheet.create({
  loading: {
    flex: 1,
    alignItems: "center",
    justifyContent: "center",
    backgroundColor: "#f6f7fb",
  },
});
