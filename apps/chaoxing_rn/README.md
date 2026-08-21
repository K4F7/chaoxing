# 学习通待办（React Native / Android）

Expo 57 应用。**Android 的预期生产候选**；Windows 生产形态仍是 Flutter。Flutter Android 在真机验收（含 Doze）完成前继续作为回退。

本机直连学习通：登录 → 真同步 → 待办列表 → 按 ADR-0001 预排 AlarmManager。Cookie 只进 Keystore。

## 日常路径

1. 未配置时首页提供「登录学习通」和「手动导入 Cookie」。
2. 登录页用 WebView 打开学习通，顶层导航只允许[可信主机](../../CONTEXT.md)。
3. 登录成功后请求通知权限，立刻跑 `createLocalSyncRunner`。
4. 首页展示合并后的待办；详情只打开可信学习通链接。
5. 同步成功后按 `planReminders` 全量重排闹钟。闹钟响铃会记下提醒历史。
6. [认证失效](../../CONTEXT.md) 出横幅、系统通知一次、停止自动同步，冷启动仍可见。

## 安全

- Cookie 只写入 `expo-secure-store`。课程目录 / 已见通知 / 提醒历史走 AsyncStorage，**不含 Cookie**。
- 带 Cookie 的请求由领域 runner 限制在显式学习通 HTTPS 主机内。
- 手动导入整份拒绝含换行的输入。

## 本应用不做

- Windows RN 托盘 / WebView2 / 安装器 / 开机自启
- 删除 Flutter
- 后台定期抓取（提醒只走预排闹钟）

## 验证

```sh
npm test
npm run typecheck
```

应用内 WebView 登录和 AlarmManager 需要 Android 开发构建（`npx expo run:android`）。本仓库 CI 不跑 Gradle：环境没有 `ANDROID_HOME`，不能把未证明的设备行为写成已通过。
