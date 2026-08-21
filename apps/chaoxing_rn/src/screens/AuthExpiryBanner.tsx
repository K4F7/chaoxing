import { Pressable, StyleSheet, Text, View } from "react-native";

import type { AuthExpiryBannerModel } from "../auth/home-view-model";

type Props = {
  banner: AuthExpiryBannerModel;
  onRelogin: () => void;
};

export function AuthExpiryBanner({ banner, onRelogin }: Props) {
  return (
    <View accessibilityRole="alert" style={styles.banner}>
      <Text style={styles.title}>{banner.title}</Text>
      <Text style={styles.body}>自动同步已停止。请重新登录，不要把它当成「没有新作业」。</Text>
      <Pressable
        accessibilityRole="button"
        onPress={onRelogin}
        style={styles.button}
      >
        <Text style={styles.buttonLabel}>{banner.actionLabel}</Text>
      </Pressable>
    </View>
  );
}

const styles = StyleSheet.create({
  banner: {
    marginBottom: 16,
    padding: 14,
    borderRadius: 12,
    backgroundColor: "#fff1f2",
    borderWidth: 1,
    borderColor: "#fecdd3",
  },
  title: {
    fontSize: 17,
    fontWeight: "700",
    color: "#9f1239",
  },
  body: {
    marginTop: 6,
    fontSize: 14,
    lineHeight: 20,
    color: "#881337",
  },
  button: {
    alignSelf: "flex-start",
    marginTop: 12,
    paddingHorizontal: 12,
    paddingVertical: 8,
    borderRadius: 8,
    backgroundColor: "#9f1239",
  },
  buttonLabel: {
    color: "#fff7f8",
    fontWeight: "600",
  },
});
