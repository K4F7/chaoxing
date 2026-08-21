import { Pressable, ScrollView, StyleSheet, Text, View } from "react-native";

import type { HomeViewModel } from "../auth/home-view-model";
import type { ProductionAppState } from "../sync/app-controller";
import {
  formatDueAt,
  groupTodoItems,
  kindLabel,
} from "../sync/todo-groups";
import { AuthExpiryBanner } from "./AuthExpiryBanner";

type Props = {
  viewModel: HomeViewModel;
  todo: ProductionAppState;
  onOpenLogin: () => void;
  onOpenManualCookie: () => void;
  onRefresh: () => void;
  onOpenItem: (itemId: string) => void;
  onOpenSettings: () => void;
  onOpenDiagnostics: () => void;
};

export function HomeScreen({
  viewModel,
  todo,
  onOpenLogin,
  onOpenManualCookie,
  onRefresh,
  onOpenItem,
  onOpenSettings,
  onOpenDiagnostics,
}: Props) {
  const groups = groupTodoItems(todo.items);
  return (
    <ScrollView contentContainerStyle={styles.container}>
      <Text style={styles.title}>学习通待办</Text>
      <Text style={styles.subtitle}>
        Android 可在 App 内登录学习通。同步在本机直连学习通；提醒走预排 AlarmManager。
      </Text>
      <Text style={styles.status}>{viewModel.statusLine}</Text>
      <Text style={styles.meta}>{syncStatusLine(todo)}</Text>

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

      {todo.alarmError ? (
        <View style={styles.errorCard}>
          <Text style={styles.errorText}>{todo.alarmError}</Text>
        </View>
      ) : null}

      {todo.failures.length > 0 ? (
        <View style={styles.warnCard}>
          <Text style={styles.warnText}>
            本轮有 {todo.failures.length} 处来源失败，列表可能不完整。
          </Text>
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
          <Pressable
            onPress={onRefresh}
            style={styles.primary}
            disabled={todo.refreshing}
          >
            <Text style={styles.primaryLabel}>
              {todo.refreshing ? "正在同步…" : "立即同步"}
            </Text>
          </Pressable>
          <Pressable onPress={onOpenLogin} style={styles.secondary}>
            <Text style={styles.secondaryLabel}>
              {viewModel.expiryBanner ? "重新登录" : "在 App 内重新登录"}
            </Text>
          </Pressable>
          <Pressable onPress={onOpenManualCookie} style={styles.secondary}>
            <Text style={styles.secondaryLabel}>手动导入 Cookie</Text>
          </Pressable>
          <Pressable onPress={onOpenSettings} style={styles.secondary}>
            <Text style={styles.secondaryLabel}>设置与受监控课程</Text>
          </Pressable>
          <Pressable onPress={onOpenDiagnostics} style={styles.secondary}>
            <Text style={styles.secondaryLabel}>
              {todo.failures.length > 0
                ? `诊断导出（${todo.failures.length} 处失败）`
                : "诊断导出"}
            </Text>
          </Pressable>
        </View>
      )}

      {groups.length === 0 && viewModel.configured ? (
        <Text style={styles.empty}>
          {todo.lastSyncedAt
            ? "当前没有待办事项。"
            : "登录后会从学习通抓取作业和考试。"}
        </Text>
      ) : null}

      {groups.map((group) => (
        <View key={group.id}>
          <Text style={styles.section}>
            {group.title} · {group.items.length}
          </Text>
          {group.items.map((item) => (
            <Pressable
              key={item.id}
              style={styles.card}
              onPress={() => onOpenItem(item.id)}
            >
              <Text style={styles.cardKind}>{kindLabel(item)}</Text>
              <Text style={styles.cardTitle}>{item.title}</Text>
              <Text style={styles.cardMeta}>
                {formatDueAt(item.dueAt)}
                {item.sourceTitle ? ` · ${item.sourceTitle}` : ""}
              </Text>
            </Pressable>
          ))}
        </View>
      ))}
    </ScrollView>
  );
}

function syncStatusLine(todo: ProductionAppState): string {
  const parts: string[] = [];
  if (todo.lastSyncedAt) {
    parts.push(`上次同步 ${todo.lastSyncedAt.toLocaleString()}`);
  }
  if (todo.refreshing) {
    parts.push(
      todo.progress
        ? `正在同步 ${todo.progress.phase} ${todo.progress.completed}/${todo.progress.total}`
        : "正在同步",
    );
  }
  if (todo.scheduledCount > 0) {
    parts.push(`已预排 ${todo.scheduledCount} 条闹钟`);
  }
  if (todo.catalog.courses.length > 0) {
    parts.push(`监控 ${todo.catalog.courses.filter((row) => row.monitored).length} 门课`);
  }
  return parts.join(" · ") || "尚未同步";
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
    fontSize: 14,
    fontWeight: "600",
    color: "#1e3a8a",
  },
  meta: {
    marginTop: 4,
    marginBottom: 16,
    fontSize: 13,
    color: "#4b5563",
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
  empty: {
    marginBottom: 16,
    fontSize: 15,
    color: "#4b5563",
  },
  card: {
    marginBottom: 12,
    padding: 14,
    borderRadius: 12,
    backgroundColor: "#ffffff",
  },
  cardKind: {
    fontSize: 13,
    fontWeight: "700",
    color: "#1e3a8a",
  },
  cardTitle: {
    marginTop: 4,
    fontSize: 16,
    fontWeight: "600",
    color: "#111827",
  },
  cardMeta: {
    marginTop: 4,
    fontSize: 14,
    color: "#4b5563",
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
  warnCard: {
    marginBottom: 16,
    padding: 12,
    borderRadius: 10,
    backgroundColor: "#fef3c7",
  },
  warnText: {
    color: "#92400e",
    fontSize: 14,
  },
});
