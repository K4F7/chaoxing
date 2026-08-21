import { StatusBar } from "expo-status-bar";
import { useMemo, useState } from "react";
import {
  Pressable,
  ScrollView,
  StyleSheet,
  Text,
  View,
} from "react-native";

import {
  ReminderAlarmScheduler,
  UnsupportedAlarmBackend,
  type AndroidAlarmPlan,
} from "@chaoxinghelper/android-alarms";

import { createProductionAlarmBackend } from "./src/alarm-module";
import {
  planFixtureAlarms,
  registerFixtureAlarms,
  summarizeAlarmPlan,
} from "./src/alarms";
import { buildReminderPreview } from "./src/preview";

const now = new Date();
const preview = buildReminderPreview(now);
const fixtureAlarms = planFixtureAlarms(now, true);

function formatWhen(ms: number): string {
  return new Date(ms).toLocaleString();
}

export default function App() {
  const scheduler = useMemo(
    () =>
      new ReminderAlarmScheduler(
        createProductionAlarmBackend() ?? new UnsupportedAlarmBackend(),
      ),
    [],
  );
  const [scheduled, setScheduled] = useState<AndroidAlarmPlan[]>([]);
  const [error, setError] = useState<string | null>(null);
  const [status, setStatus] = useState(
    "尚未登记。登记会调用 AlarmManager.setExactAndAllowWhileIdle，不会用 setTimeout。",
  );

  async function run(action: () => Promise<string>): Promise<void> {
    try {
      setError(null);
      setStatus(await action());
    } catch (caught) {
      const message =
        caught instanceof Error ? caught.message : String(caught);
      setError(message);
    }
  }

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <Text style={styles.title}>学习通待办</Text>
      <Text style={styles.subtitle}>
        React Native 脚手架。生产形态仍是 Flutter。这里用 fixture
        待办事项把领域规划器接到 ADR-0001 预排闹钟。
      </Text>

      {error ? <Text style={styles.error}>{error}</Text> : null}
      <Text style={styles.status}>{status}</Text>

      <View style={styles.actions}>
        <Pressable
          style={styles.button}
          onPress={() =>
            run(async () => {
              const result = await registerFixtureAlarms(scheduler, now, true);
              setScheduled(result.scheduled);
              return `已向 AlarmManager 登记 ${result.scheduled.length} 条，跳过 ${result.skipped.length} 条。`;
            })
          }
        >
          <Text style={styles.buttonLabel}>登记 fixture 闹钟</Text>
        </Pressable>
        <Pressable
          style={styles.button}
          onPress={() =>
            run(async () => {
              const listed = await scheduler.list();
              setScheduled(listed);
              return `当前已排 ${listed.length} 条。`;
            })
          }
        >
          <Text style={styles.buttonLabel}>列出已排闹钟</Text>
        </Pressable>
        <Pressable
          style={styles.buttonSecondary}
          onPress={() =>
            run(async () => {
              await scheduler.rescheduleAll([], { now });
              setScheduled([]);
              return "已取消全部预排闹钟。";
            })
          }
        >
          <Text style={styles.buttonLabel}>取消全部</Text>
        </Pressable>
      </View>

      <Text style={styles.section}>将登记的闹钟计划</Text>
      {fixtureAlarms.mapping.accepted.map((plan) => (
        <View key={plan.key} style={styles.card}>
          <Text style={styles.cardTitle}>{plan.title}</Text>
          <Text style={styles.cardMeta}>{summarizeAlarmPlan(plan)}</Text>
          <Text style={styles.cardMeta}>触发 {formatWhen(plan.triggerAtMs)}</Text>
        </View>
      ))}
      {fixtureAlarms.mapping.skipped.map((skip) => (
        <Text key={skip.key} style={styles.skip}>
          跳过 · {skip.reason} · {skip.detail}
        </Text>
      ))}

      <Text style={styles.section}>已登记（系统闹钟）</Text>
      {scheduled.length === 0 ? (
        <Text style={styles.cardMeta}>无</Text>
      ) : (
        scheduled.map((plan) => (
          <Text key={plan.key} style={styles.urlRow}>
            {plan.itemId} · {plan.ruleId} · {plan.tier}
          </Text>
        ))
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
      <StatusBar style="auto" />
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
    marginBottom: 16,
    fontSize: 15,
    lineHeight: 22,
    color: "#4b5563",
  },
  error: {
    marginBottom: 12,
    padding: 12,
    borderRadius: 10,
    backgroundColor: "#fee2e2",
    color: "#991b1b",
    fontSize: 14,
    lineHeight: 20,
  },
  status: {
    marginBottom: 16,
    fontSize: 14,
    lineHeight: 20,
    color: "#1f2937",
  },
  actions: {
    marginBottom: 24,
    gap: 8,
  },
  button: {
    paddingVertical: 12,
    paddingHorizontal: 14,
    borderRadius: 10,
    backgroundColor: "#1d4ed8",
  },
  buttonSecondary: {
    paddingVertical: 12,
    paddingHorizontal: 14,
    borderRadius: 10,
    backgroundColor: "#334155",
  },
  buttonLabel: {
    color: "#ffffff",
    fontSize: 15,
    fontWeight: "600",
    textAlign: "center",
  },
  section: {
    marginBottom: 8,
    marginTop: 8,
    fontSize: 18,
    fontWeight: "600",
    color: "#1b1f24",
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
  skip: {
    marginBottom: 8,
    fontSize: 13,
    color: "#92400e",
  },
  urlRow: {
    marginBottom: 8,
    fontSize: 13,
    color: "#374151",
  },
});
