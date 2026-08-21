import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";

import type { HomeViewModel } from "../auth/home-view-model";
import type { ReminderPreview } from "../preview";
import { AuthExpiryBanner } from "./AuthExpiryBanner";

type Props = {
  viewModel: HomeViewModel;
  preview: ReminderPreview;
  onOpenLogin: () => void;
  onOpenManualCookie: () => void;
};

export function HomeScreen({
  viewModel,
  preview,
  onOpenLogin,
  onOpenManualCookie,
}: Props) {
  return (
    <ScrollView contentContainerStyle={styles.container}>
      <Text style={styles.title}>学习通待办</Text>
      <Text style={styles.subtitle}>
        Android 可在 App 内登录学习通。Cookie 只写入设备安全存储；认证失效会停掉自动同步并显示横幅。
      </Text>
      <Text style={styles.status}>{viewModel.statusLine}</Text>

      {viewModel.expiryBanner ? (
        <AuthExpiryBanner
          banner={viewModel.expiryBanner}
          onRelogin={onOpenLogin}
        />
      ) : null}

      {viewModel.error && !viewModel.expiryBanner ? (
        <View style={styles.errorCard}>
          <Text style={styles.errorText}>{viewModel.error}</Text>
        </View>
      ) : null}

      {viewModel.emptySetup ? (
        <View style={styles.setupCard}>
          <Text style={styles.section}>{viewModel.emptySetup.title}</Text>
          <Text style={styles.body}>{viewModel.emptySetup.body}</Text>
          <Pressable onPress={onOpenLogin} style={styles.primary}>
            <Text style={styles.primaryLabel}>{viewModel.emptySetup.loginLabel}</Text>
          </Pressable>
          <Pressable onPress={onOpenManualCookie} style={styles.secondary}>
            <Text style={styles.secondaryLabel}>
              {viewModel.emptySetup.manualLabel}
            </Text>
          </Pressable>
        </View>
      ) : (
        <View style={styles.actions}>
          <Pressable onPress={onOpenLogin} style={styles.secondary}>
            <Text style={styles.secondaryLabel}>
              {viewModel.expiryBanner ? "重新登录" : "在 App 内重新登录"}
            </Text>
          </Pressable>
          <Pressable onPress={onOpenManualCookie} style={styles.secondary}>
            <Text style={styles.secondaryLabel}>手动导入 Cookie</Text>
          </Pressable>
        </View>
      )}

      <Text style={styles.section}>计划提醒</Text>
      {preview.reminders.map((row) => (
        <View key={row.key} style={styles.card}>
          <Text style={styles.cardTitle}>{row.title}</Text>
          <Text style={styles.cardMeta}>
            {row.ruleId} · {row.intensityLabel}
          </Text>
        </View>
      ))}

      <Text style={styles.section}>URL 信任分级</Text>
      {preview.urlChecks.map((row) => (
        <Text key={row.url} style={styles.urlRow}>
          {row.trusted ? "可信" : "不可信"} · {row.url}
        </Text>
      ))}
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: {
    padding: 24,
    paddingTop: 64,
    backgroundColor: "#f6f7fb",
  },
  title: {
    fontSize: 28,
    fontWeight: "700",
    color: "#1b1f24",
  },
  subtitle: {
    marginTop: 8,
    fontSize: 15,
    lineHeight: 22,
    color: "#4b5563",
  },
  status: {
    marginTop: 10,
    marginBottom: 16,
    fontSize: 14,
    fontWeight: "600",
    color: "#1e3a8a",
  },
  setupCard: {
    marginBottom: 20,
    padding: 16,
    borderRadius: 12,
    backgroundColor: "#ffffff",
  },
  actions: {
    marginBottom: 20,
    gap: 8,
  },
  section: {
    marginBottom: 8,
    fontSize: 18,
    fontWeight: "600",
    color: "#1b1f24",
  },
  body: {
    marginBottom: 14,
    fontSize: 15,
    lineHeight: 22,
    color: "#4b5563",
  },
  card: {
    marginBottom: 12,
    padding: 14,
    borderRadius: 12,
    backgroundColor: "#ffffff",
  },
  cardTitle: {
    fontSize: 16,
    fontWeight: "600",
    color: "#111827",
  },
  cardMeta: {
    marginTop: 4,
    fontSize: 14,
    color: "#4b5563",
  },
  urlRow: {
    marginBottom: 8,
    fontSize: 13,
    color: "#374151",
  },
  primary: {
    paddingVertical: 12,
    borderRadius: 10,
    backgroundColor: "#1d4ed8",
    alignItems: "center",
  },
  primaryLabel: {
    color: "#f8fafc",
    fontWeight: "700",
  },
  secondary: {
    paddingVertical: 12,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: "#93c5fd",
    alignItems: "center",
    backgroundColor: "#eff6ff",
  },
  secondaryLabel: {
    color: "#1d4ed8",
    fontWeight: "600",
  },
  errorCard: {
    marginBottom: 16,
    padding: 12,
    borderRadius: 10,
    backgroundColor: "#fff7ed",
  },
  errorText: {
    color: "#9a3412",
    fontSize: 14,
  },
});
