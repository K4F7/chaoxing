import { useState } from "react";
import {
  Pressable,
  StyleSheet,
  Text,
  TextInput,
  View,
} from "react-native";

import { CookieSourceError } from "../auth";

type Props = {
  hasSavedCookie: boolean;
  onImport: (input: string) => Promise<void>;
  onClose: () => void;
};

export function ManualCookieScreen({
  hasSavedCookie,
  onImport,
  onClose,
}: Props) {
  const [value, setValue] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [saving, setSaving] = useState(false);

  const save = async () => {
    if (saving) {
      return;
    }
    setSaving(true);
    setError(null);
    try {
      await onImport(value);
      setValue("");
      onClose();
    } catch (caught) {
      setError(
        caught instanceof CookieSourceError
          ? caught.message
          : "Cookie 未能保存，请检查输入后重试。",
      );
      setSaving(false);
    }
  };

  return (
    <View style={styles.screen}>
      <Text style={styles.title}>手动导入 Cookie</Text>
      <Text style={styles.body}>
        内置登录失灵时，可粘贴已登录请求的 Cookie header。保存成功后输入框会清空，设置页不会回填完整
        Cookie。
      </Text>
      <TextInput
        value={value}
        onChangeText={setValue}
        multiline
        autoCapitalize="none"
        autoCorrect={false}
        secureTextEntry={false}
        placeholder="UID=…; vc3=…"
        style={styles.input}
      />
      {hasSavedCookie ? (
        <Text style={styles.saved}>已保存 Cookie。这里保持为空；只在输入新 Cookie 时覆盖。</Text>
      ) : null}
      {error ? <Text style={styles.error}>{error}</Text> : null}
      <Pressable
        disabled={saving}
        onPress={() => {
          void save();
        }}
        style={styles.primary}
      >
        <Text style={styles.primaryLabel}>{saving ? "正在验证" : "保存并验证"}</Text>
      </Pressable>
      <Pressable onPress={onClose} style={styles.secondary}>
        <Text style={styles.secondaryLabel}>返回</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  screen: {
    flex: 1,
    padding: 24,
    paddingTop: 64,
    backgroundColor: "#f6f7fb",
  },
  title: {
    fontSize: 24,
    fontWeight: "700",
    color: "#1b1f24",
  },
  body: {
    marginTop: 10,
    marginBottom: 16,
    fontSize: 15,
    lineHeight: 22,
    color: "#4b5563",
  },
  input: {
    minHeight: 120,
    padding: 12,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: "#d1d5db",
    backgroundColor: "#ffffff",
    textAlignVertical: "top",
    fontSize: 14,
  },
  saved: {
    marginTop: 10,
    fontSize: 13,
    color: "#166534",
  },
  error: {
    marginTop: 10,
    fontSize: 14,
    color: "#9f1239",
  },
  primary: {
    marginTop: 18,
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
    marginTop: 12,
    alignItems: "center",
    paddingVertical: 10,
  },
  secondaryLabel: {
    color: "#1d4ed8",
    fontWeight: "600",
  },
});
