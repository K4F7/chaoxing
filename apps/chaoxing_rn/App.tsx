import { StatusBar } from "expo-status-bar";
import { useEffect, useMemo, useState } from "react";
import { ActivityIndicator, StyleSheet, View } from "react-native";

import {
  ReminderAlarmScheduler,
  UnsupportedAlarmBackend,
  UnsupportedAlarmRuntime,
} from "@chaoxinghelper/android-alarms";
import { createLocalSyncRunner } from "@chaoxinghelper/domain";

import {
  createProductionAlarmBackend,
  createProductionAlarmRuntime,
} from "./src/alarm-module";
import { createAndroidCookieCollector } from "./src/auth/android-cookie-collector";
import { createExpoCookieVault } from "./src/auth/expo-cookie-vault";
import {
  createHomepageAuthProbe,
  createLoginAuthenticator,
} from "./src/auth/homepage-probe";
import { buildHomeViewModel } from "./src/auth/home-view-model";
import { SessionController } from "./src/auth/session-controller";
import { createFetchChaoxingClient } from "./src/http/fetch-client";
import { AppDataStore } from "./src/persist/app-store";
import { createDeviceJsonStore } from "./src/persist/device-store";
import { MemoryJsonStore } from "./src/persist/json-store";
import { DetailScreen } from "./src/screens/DetailScreen";
import { HomeScreen } from "./src/screens/HomeScreen";
import { LoginScreen } from "./src/screens/LoginScreen";
import { ManualCookieScreen } from "./src/screens/ManualCookieScreen";
import { ProductionAppController } from "./src/sync/app-controller";

type ScreenName = "home" | "login" | "manual";

export default function App() {
  const runtime = useMemo(
    () => createProductionAlarmRuntime() ?? new UnsupportedAlarmRuntime(),
    [],
  );
  const controller = useMemo(() => {
    const session = new SessionController({
      vault: createExpoCookieVault(),
      authenticator: createLoginAuthenticator(createHomepageAuthProbe(fetch)),
      onExpiryEntered: () => {
        void runtime.notifyAuthenticationExpired();
      },
    });
    return new ProductionAppController({
      session,
      store: new AppDataStore(createDeviceJsonStore() ?? new MemoryJsonStore()),
      createRunner: () =>
        createLocalSyncRunner({
          http: createFetchChaoxingClient(fetch),
        }),
      scheduler: new ReminderAlarmScheduler(
        createProductionAlarmBackend() ?? new UnsupportedAlarmBackend(),
      ),
      runtime,
    });
  }, [runtime]);
  const collector = useMemo(() => createAndroidCookieCollector(), []);
  const [, setTick] = useState(0);
  const [screen, setScreen] = useState<ScreenName>("home");

  useEffect(() => {
    const unsubscribe = controller.subscribe(() => {
      setTick((value) => value + 1);
    });
    void controller.load();
    return () => {
      unsubscribe();
      controller.dispose();
    };
  }, [controller]);

  const viewModel = buildHomeViewModel({
    authenticationState: controller.session.state.authenticationState,
    hasCookie: controller.session.state.cookieSource.trim().length > 0,
    autoSyncStopped: controller.session.state.autoSyncStopped,
    error: controller.session.state.error ?? controller.state.error,
  });
  const selected = controller.selectedItem();

  if (controller.state.loading || controller.session.state.loading) {
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
          hasSavedCookie={controller.session.state.cookieSource.trim().length > 0}
          onImport={(input) => controller.importManualCookie(input)}
          onClose={() => setScreen("home")}
        />
        <StatusBar style="auto" />
      </>
    );
  }

  if (selected) {
    return (
      <>
        <DetailScreen item={selected} onClose={() => controller.closeItem()} />
        <StatusBar style="auto" />
      </>
    );
  }

  return (
    <>
      <HomeScreen
        viewModel={viewModel}
        todo={controller.state}
        onOpenLogin={() => setScreen("login")}
        onOpenManualCookie={() => setScreen("manual")}
        onRefresh={() => {
          void controller.refresh("manual");
        }}
        onOpenItem={(itemId) => controller.openItem(itemId)}
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
