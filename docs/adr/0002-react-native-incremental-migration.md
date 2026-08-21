# 增量迁到 React Native，先移植可共享领域切片

当前生产形态是：

- Android：`apps/chaoxing_rn`（Expo / React Native）
- Windows：`apps/chaoxing_windows`（TypeScript 本机宿主 + C# 外壳，见 [ADR-0003](./0003-windows-native-host.md)）

Flutter 参考实现已移到 `legacy/chaoxing_app`，**不再是任何平台的出货路径**。默认 CI 验证 TypeScript 领域包、Android 闹钟、Cookie 感知 HTTP、RN Android 与 Windows 宿主；Flutter 只在 `legacy/` 变更时跑分析与测试，不发布 APK / setup.exe。

**为什么当初增量。** Flutter 已经覆盖同步、提醒规则、认证失效可见性、Windows 托盘 / 自启 / 安装器。换皮过程中若漏掉截止提醒或 URL 信任校验，界面仍可能看起来正常。一次切栈会把已验证的生产路径整段换成未验证实现，正好踩中[静默失效](../../CONTEXT.md)。

**先迁了什么。** [日常可用规格](../specs/2026-07-26-日常可用的学习通待办工具.md)里的提醒规则与 URL 信任分级先落到 `packages/chaoxing-domain`，再接同步 / 解析 / 认证，再接 Android 登录与预排闹钟，最后补设置、诊断导出、Cookie 感知 HTTP，并新增 Windows 宿主。

**不变的约束。** 本机直连学习通、不经过自建服务端；Windows 与 Android 各自独立完成抓取、存储和提醒；宁可犯可见的错，不可犯静默的漏；Android 提醒继续走预排闹钟，不走后台定期抓取；Windows 提醒消费「此刻该触发的」。
