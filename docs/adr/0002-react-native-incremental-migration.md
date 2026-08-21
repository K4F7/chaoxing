# 增量迁到 React Native，先移植可共享领域切片

当前唯一产品形态是 Flutter App（`apps/chaoxing_app`），跑在 Windows 与 Android 上。仓库里没有既有的 React Native ADR、issue 或半成品脚手架。用户要求迁到 React Native 之后，我们选择**增量替换**，而不是一次重写全部功能。

**为什么不一次重写。** Flutter 已经覆盖同步、提醒规则、认证失效可见性、Windows 托盘 / 自启 / 安装器。这些行为的核心风险是[静默失效](../../CONTEXT.md)：换皮过程中若漏掉截止提醒或 URL 信任校验，界面仍可能看起来正常。一次切栈会把已验证的生产路径整段换成未验证实现，正好踩中这条风险。

**先迁什么。** [日常可用规格](../specs/2026-07-26-日常可用的学习通待办工具.md)已经把[提醒规则](../../CONTEXT.md)抽成无 I/O 纯函数，[URL 信任分级](../../CONTEXT.md)也是独立模块。两端共用同一套规则：Windows 消费「此刻该触发的」，Android 消费「未来该排的」。这两块不依赖托盘、闹钟或 WebView，是最小完整切片。

**平台顺序。** React Native 第一目标是 Android。ticket 19–22（应用内登录、通知渠道、[预排本地闹钟](./0001-android-prescheduled-alarms.md)）在 Flutter 侧仍被 Windows 日常使用闸门挡住；闹钟最终要落在 Android 原生能力上，RN 从这里起步不会和 ADR-0001 打架。Windows 在 RN 能对等托盘、开机自启、安装器和 WebView2 登录之前，继续以 Flutter 为生产形态。

**代码落点。**

- 可移植切片用 TypeScript 写在 `packages/chaoxing-domain`，供 RN 直接引用。
- `apps/chaoxing_rn` 是 Expo 脚手架，这一轮只接线领域切片，不做登录、抓取或通知。
- Flutter 的 Dart 副本在对应产品面被 RN 替换前继续作为生产实现。本轮不双写、不让 Flutter 去调 TypeScript。
- 根目录 `src/` 仍是早期 Worker 遗留，只作解析对照，不作为 RN 运行时。

**不变的约束。** 本机直连学习通、不经过自建服务端；Windows 与 Android 各自独立完成抓取、存储和提醒；宁可犯可见的错，不可犯静默的漏；Android 提醒继续走预排闹钟，不走后台定期抓取。
