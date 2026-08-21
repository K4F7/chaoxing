import { StatusBar } from "expo-status-bar";
import { ScrollView, StyleSheet, Text, View } from "react-native";

import { buildReminderPreview } from "./src/preview";

const preview = buildReminderPreview(new Date());

export default function App() {
  return (
    <ScrollView contentContainerStyle={styles.container}>
      <Text style={styles.title}>学习通待办</Text>
      <Text style={styles.subtitle}>
        React Native 脚手架。生产形态仍是 Flutter；这里只接线提醒规则和 URL
        信任分级。
      </Text>

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
    marginBottom: 24,
    fontSize: 15,
    lineHeight: 22,
    color: "#4b5563",
  },
  section: {
    marginBottom: 8,
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
  urlRow: {
    marginBottom: 8,
    fontSize: 13,
    color: "#374151",
  },
});
