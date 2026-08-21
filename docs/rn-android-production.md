# Android RN 生产路径

Android 出货路径是 `apps/chaoxing_rn`。Flutter 已迁到 `legacy/chaoxing_app`，不再作为 Android 生产应用。

## 已接通

| 产品行为 | 落点 |
|---|---|
| 应用内登录、可信主机、Keystore Cookie | `apps/chaoxing_rn/src/auth` + WebView |
| Cookie 感知 HTTP（OkHttp + CookieManager，fetch 回退） | `packages/chaoxing-android-http` + `createSessionHttpClient` |
| 课程目录 / 已见通知 / 上次同步 | `src/persist/app-store.ts`（不含 Cookie） |
| 待办列表 + 详情 + URL 信任 | `HomeScreen` / `DetailScreen` |
| 设置 + 受监控课程勾选 | `SettingsScreen`；新课默认纳入 |
| 诊断导出（脱敏） | `exportDiagnostics` / `DiagnosticsScreen` |
| 真同步后 `rescheduleAll` | `ProductionAppController` |
| 认证失效横幅、只通知一次、停自动同步 | `SessionController` |

## 本环境仍缺的硬件证明

没有 Android SDK / 真机：Doze、开机重排、通知点击进详情未在本机跑过。源码与单测已落地。
