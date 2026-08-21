import { useCallback, useRef, useState } from "react";
import {
  ActivityIndicator,
  Platform,
  Pressable,
  StyleSheet,
  Text,
  View,
} from "react-native";
import { WebView, type WebViewNavigation } from "react-native-webview";

import {
  captureLoginCookieSource,
  CHAOXING_LOGIN_URL,
  classifyLoginNavigation,
  CookieSourceError,
  LOGIN_IDENTITY_MISSING_MESSAGE,
  type NativeCookieCollector,
} from "../auth";

type Props = {
  collector: NativeCookieCollector;
  onCookieCaptured: (source: string) => Promise<void>;
  onClose: () => void;
};

export function LoginScreen({ collector, onCookieCaptured, onClose }: Props) {
  const webViewRef = useRef<WebView>(null);
  const [capturing, setCapturing] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [loginUrl, setLoginUrl] = useState(CHAOXING_LOGIN_URL);

  const returnToTrustedLogin = useCallback(() => {
    setLoginUrl(CHAOXING_LOGIN_URL);
    webViewRef.current?.stopLoading();
    webViewRef.current?.injectJavaScript(
      `window.location.replace(${JSON.stringify(CHAOXING_LOGIN_URL)}); true;`,
    );
  }, []);

  const onShouldStartLoadWithRequest = useCallback(
    (request: { url: string }) => {
      const decision = classifyLoginNavigation(request.url);
      if (decision === "block") {
        returnToTrustedLogin();
        return false;
      }
      return true;
    },
    [returnToTrustedLogin],
  );

  const onNavigationStateChange = useCallback(
    (nav: WebViewNavigation) => {
      if (classifyLoginNavigation(nav.url) === "block") {
        returnToTrustedLogin();
      }
    },
    [returnToTrustedLogin],
  );

  const finishLogin = useCallback(async () => {
    if (capturing) {
      return;
    }
    setCapturing(true);
    setError(null);
    try {
      const source = await captureLoginCookieSource(collector);
      if (!source) {
        throw new CookieSourceError(LOGIN_IDENTITY_MISSING_MESSAGE);
      }
      await onCookieCaptured(source);
      onClose();
    } catch (caught) {
      setError(
        caught instanceof CookieSourceError
          ? caught.message
          : LOGIN_IDENTITY_MISSING_MESSAGE,
      );
      setCapturing(false);
    }
  }, [capturing, collector, onClose, onCookieCaptured]);

  if (Platform.OS !== "android") {
    return (
      <View style={styles.screen}>
        <Text style={styles.title}>登录学习通</Text>
        <Text style={styles.hint}>
          当前增量只提供 Android 应用内登录。请改用手动导入 Cookie，或在 Android
          设备上打开。
        </Text>
        <Pressable onPress={onClose} style={styles.secondary}>
          <Text style={styles.secondaryLabel}>返回</Text>
        </Pressable>
      </View>
    );
  }

  return (
    <View style={styles.screen}>
      <View style={styles.toolbar}>
        <Pressable onPress={onClose} style={styles.secondary}>
          <Text style={styles.secondaryLabel}>取消</Text>
        </Pressable>
        <Text style={styles.title}>登录学习通</Text>
        <Pressable
          disabled={capturing}
          onPress={() => {
            void finishLogin();
          }}
          style={[styles.primary, capturing ? styles.disabled : null]}
        >
          {capturing ? (
            <ActivityIndicator color="#fff" size="small" />
          ) : (
            <Text style={styles.primaryLabel}>完成登录</Text>
          )}
        </Pressable>
      </View>
      <View style={styles.hintBar}>
        <Text style={styles.hint}>
          {error ?? "请在下方登录。成功进入学习通后，点击右上角“完成登录”。"}
        </Text>
      </View>
      <WebView
        ref={webViewRef}
        source={{ uri: loginUrl }}
        sharedCookiesEnabled
        thirdPartyCookiesEnabled
        setSupportMultipleWindows={false}
        javaScriptEnabled
        onShouldStartLoadWithRequest={onShouldStartLoadWithRequest}
        onNavigationStateChange={onNavigationStateChange}
        style={styles.webview}
      />
    </View>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    backgroundColor: "#f6f7fb",
    paddingTop: 48,
  },
  toolbar: {
    flexDirection: "row",
    alignItems: "center",
    justifyContent: "space-between",
    paddingHorizontal: 16,
    paddingBottom: 8,
    gap: 8,
  },
  title: {
    flex: 1,
    textAlign: "center",
    fontSize: 18,
    fontWeight: "700",
    color: "#1b1f24",
  },
  hintBar: {
    paddingHorizontal: 16,
    paddingVertical: 10,
    backgroundColor: "#eef2ff",
  },
  hint: {
    fontSize: 14,
    lineHeight: 20,
    color: "#3730a3",
  },
  webview: {
    flex: 1,
    backgroundColor: "#ffffff",
  },
  primary: {
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 8,
    backgroundColor: "#1d4ed8",
    minWidth: 88,
    alignItems: "center",
  },
  primaryLabel: {
    color: "#f8fafc",
    fontWeight: "600",
  },
  secondary: {
    paddingHorizontal: 10,
    paddingVertical: 8,
  },
  secondaryLabel: {
    color: "#1d4ed8",
    fontWeight: "600",
  },
  disabled: {
    opacity: 0.6,
  },
});
