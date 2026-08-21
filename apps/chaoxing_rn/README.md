# 学习通待办（React Native / Android 生产）

Expo 57 应用，**Android 生产路径**。Windows 生产应用是 [`apps/chaoxing_windows`](../chaoxing_windows)。

提醒规则、同步、URL 信任分级来自 [`packages/chaoxing-domain`](../../packages/chaoxing-domain)。预排闹钟见 [`packages/chaoxing-android-alarms`](../../packages/chaoxing-android-alarms)。会话续期走 [`packages/chaoxing-android-http`](../../packages/chaoxing-android-http)（OkHttp + CookieManager），避免 JS `fetch` 丢掉 `Set-Cookie`。

## 功能

- 应用内 WebView 登录与手动导入 Cookie（含换行整份拒绝，界面不回填）
- 打开即看缓存，前台同步，失败保留列表
- 设置：提醒开关、通知详情、课程空间同步、受监控课程勾选、手动刷新课程列表
- 诊断导出脱敏 Cookie / token / 账号参数
- 同步后全量重排 AlarmManager；认证失效横幅并停止自动同步

## 验证

```sh
npm test
npm run typecheck
```

应用内 WebView 登录需要 Android 开发构建（`npx expo run:android`）。

GitHub Actions 在 `ubuntu-latest` 上 `expo prebuild` 后打 APK：没有 `ANDROID_KEYSTORE_BASE64` / `ANDROID_KEY_PROPERTIES_BASE64` 时是 debug-signed dry-run；两个 Secret 都齐才打 release。详见 [docs/rn-production.md](../../docs/rn-production.md)。
