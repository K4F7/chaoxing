# Android RN 生产路径

这一轮把三条未合并增量接到同一条 Android 生产候选路径上，并补上登录 → 真同步 → 待办 → 预排闹钟的胶水。Flutter 仍是 Windows 生产应用，也是 Android 回退，**没有删除**。

## 已接通

| 产品行为 | 落点 |
|---|---|
| 应用内登录、可信主机、Keystore Cookie | `apps/chaoxing_rn/src/auth` + WebView |
| 注入 HTTP `fetch`（手动重定向） | `src/http/fetch-client.ts` → `createLocalSyncRunner` |
| 课程目录 / 已见通知 / 上次同步 | `src/persist/app-store.ts`（AsyncStorage，不含 Cookie） |
| 待办列表 + 详情 + URL 信任 | `src/screens/HomeScreen.tsx` / `DetailScreen.tsx` |
| 真同步后 `rescheduleAll` | `src/sync/app-controller.ts` |
| 登录后请求 `POST_NOTIFICATIONS` | 闹钟 native module |
| 提醒历史（响铃后持久化 + 领域裁剪） | `ChaoxingAlarmStore` delivered + `pruneReminderHistory` |
| 认证失效横幅、只通知一次、停自动同步、冷启动仍可见 | `SessionController` + 系统通知 |
| 通知点击带 `itemId` | launch extras → 待办详情（冷启动） |

## 与 Flutter Android 的对照

| 能力 | Flutter Android | RN Android | 备注 |
|---|---|---|---|
| 本机直连学习通 | 有 | 有 | 无自建服务端 |
| 应用内登录 | 有 | 有 | WebView + 可信主机 |
| 真同步 / 已见通知 / 受监控课程 | 有 | 有 | 同一套 TypeScript runner |
| 待办列表与详情 | 有 | 有 | 只打开可信链接 |
| 预排 AlarmManager | 有 | 有 | 不再是 fixture-only |
| 开机重排 | 有 | 已声明接收器 | 未做真机证明 |
| Doze 穿透 | 规格要求 | 代码用 `setExactAndAllowWhileIdle` | **无设备、无 ANDROID_HOME，未证明** |
| 设置页 / 课程勾选 UI | 有 | 缺 | 新课默认纳入；持久化已有 |
| 诊断导出 | 有 | 缺 | 失败数量在首页可见 |
| Windows 托盘 / 自启 / 安装器 | 有 | 不做 | Windows 仍走 Flutter |

## 明确还不能切换全部 Android 用户的原因

1. 本环境没有 Android SDK，Kotlin/plugin 已落地，但 **没有 Gradle 绿构建**。
2. 没有真机：Doze、厂商省电、开机后闹钟、通知权限弹窗、通知点击进详情，都还没手工验收。
3. RN `fetch` 常常读不到 `Set-Cookie`。同步主要依赖登录时写入的 Cookie 罐；会话续期弱于 Flutter 的 `http` 客户端。失败会变成可见错误，而不是假装成功。
4. 设置 / 课程勾选 / 诊断导出还短一截。默认 opt-out 监控已经在领域层，但用户还不能在 RN 里取消勾选。
5. Windows 仍然只能用 Flutter。

在上述缺口补上之前，不要把 Flutter Android 卸掉。
