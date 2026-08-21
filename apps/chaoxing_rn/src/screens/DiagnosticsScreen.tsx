import { Pressable, ScrollView, StyleSheet, Text } from "react-native";

type Props = {
  report: string;
  failureCount: number;
  onClose: () => void;
};

export function DiagnosticsScreen({ report, failureCount, onClose }: Props) {
  return (
    <ScrollView contentContainerStyle={styles.container}>
      <Text style={styles.title}>同步诊断</Text>
      <Text style={styles.meta}>
        {failureCount > 0
          ? `本轮有 ${failureCount} 处来源失败，列表可能不完整。`
          : "没有记录到解析失败。"}
      </Text>
      <Text style={styles.hint}>
        诊断已脱敏 Cookie、token 和账号参数。复制前请再看一眼。
      </Text>
      <Text selectable style={styles.report}>
        {report}
      </Text>
      <Pressable style={styles.secondary} onPress={onClose}>
        <Text style={styles.secondaryLabel}>返回</Text>
      </Pressable>
    </ScrollView>
  );
}

const styles = StyleSheet.create({
  container: { padding: 24, paddingTop: 64, backgroundColor: "#f6f7fb" },
  title: { fontSize: 26, fontWeight: "700", color: "#1b1f24" },
  meta: { marginTop: 10, fontSize: 15, color: "#9a3412" },
  hint: { marginTop: 8, marginBottom: 12, fontSize: 13, color: "#6b7280" },
  report: {
    fontFamily: "monospace",
    fontSize: 12,
    lineHeight: 18,
    color: "#111827",
    backgroundColor: "#fff",
    padding: 12,
    borderRadius: 10,
  },
  secondary: {
    marginTop: 16,
    paddingVertical: 12,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: "#93c5fd",
    alignItems: "center",
    backgroundColor: "#eff6ff",
  },
  secondaryLabel: { color: "#1d4ed8", fontWeight: "600" },
});
