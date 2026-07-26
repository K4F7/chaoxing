# Product Requirements Document: 学习通本地同步与 Windows App 工具

**Version**: 1.0
**Date**: 2026-06-09
**Author**: Sarah (Product Owner)
**Quality Score**: 94/100

---

## Executive Summary

本 PRD 定义“学习通作业/考试待办”的本地化 App 与 Windows 工具形态：用户在本机保存学习通 Cookie，由 Flutter App 直接同步学习通收件箱、通知详情和作业/考试页面，生成即将到来的作业和考试列表，并在 Windows 上提供持续同步与提醒能力。

Phase 1 MVP 已完成核心迁移：Flutter App 已从 Worker URL + RUN_TOKEN 客户端迁移为本地学习通 Cookie 同步；Windows 平台目录已生成；Windows release build 已通过。当前 App 已具备认证检查、收件箱定位/分页、通知关键词筛选、详情链接提取、作业/考试时间解析、`AppSyncResponse` 构建、排序、`displayStatus`、`dueInHours` 等本地同步能力。

后续 Phase 2/3 聚焦完成 Windows toast/托盘、内置 WebView2 登录和课程空间补漏的真实环境验收。Windows CI、双平台打包发布、内置登录及 HttpOnly Cookie Store 导入、诊断页面、统一脱敏导出和可选课程作业/考试补充源已接入。安全要求贯穿所有阶段：Cookie 必须进入安全存储，带 Cookie 请求必须受显式主机 allowlist 和重定向校验约束，错误与诊断信息必须脱敏。

---

## Problem Statement

**Current Situation**: 用户需要及时看到学习通即将截止的作业和考试。早期架构依赖 Cloudflare Worker、Bun/Node helper 或 `/app/sync` 远端接口，对个人本地使用和 Windows 常驻提醒不够直接；同时，只依赖收件箱通知可能漏掉课程空间中存在但未发通知的作业或考试。

**Proposed Solution**: 将学习通同步链路迁移到 Flutter/Dart 本地实现，在 App 内安全保存学习通 Cookie，直接访问学习通可信域名并解析作业/考试数据；在 Windows 上提供桌面工具形态，支持定时刷新、提醒去重、系统通知和托盘常驻。

**Business Impact**: 对个人用户而言，减少漏交作业或错过考试的风险；对项目维护而言，降低 Worker 部署、密钥管理和远端依赖成本；对后续扩展而言，统一 App、Windows 工具、提醒与诊断能力的产品边界。

---

## Success Metrics

**Primary KPIs:**
- 本地同步可用率：在有效学习通 Cookie 下，App 能完成收件箱同步并返回标准化 `AppSyncResponse`；通过 fixture 单元测试和真实账号端到端回归衡量。
- 提醒准确性：同一 `itemId + remindRule + dueAtSnapshot` 不重复提醒；作业和考试能按截止时间计算 `displayStatus` 和 `dueInHours`；通过提醒调度测试和 Windows 手动验证衡量。
- 安全合规性：Cookie 不出现在 shared_preferences、UI 回填、日志、诊断导出或非学习通请求中；通过代码审核、测试和安全检查清单衡量。
- Windows 可交付性：`flutter build windows` 成功生成 release exe；Windows CI 持续执行 analyze/test/build，并发布完整 Windows x64 压缩包。

**Validation**:
- Worker 验证：`bun run typecheck`、`bun test` 已通过，共 32 tests。
- Flutter 验证：`flutter analyze`、`flutter test` 已通过，共 126 tests。
- Windows 构建验证：`flutter build windows` 已通过。
- Android 本地构建验证：Windows 上将 `PUB_CACHE` 设为项目同盘目录后，`flutter build apk --release --build-number 1004`、`apksigner verify` 和 APK 内容审计已通过；本地未提供正式 keystore，因此该产物使用 Debug 证书签名，仅用于构建验证。
- Windows 单实例回归：Release 构建后运行 `tool/verify_windows_single_instance.ps1`，自动验证隐藏窗口恢复、第二实例退出以及目标路径下只保留一个主进程。
- 托盘回归：菜单状态更新必须串行且合并为最新状态，退出动作必须幂等，插件事件中的异步失败必须进入统一错误处理；对应 fake bridge 测试持续覆盖。
- Windows 构建产物：`apps/chaoxing_app/build/windows/x64/runner/Release/chaoxing_app.exe`。
- Windows CI：Windows runner 执行 `flutter analyze`、`flutter test`、`flutter build windows --release`，并上传 `chaoxing-app-windows-x64.zip`。
- CI action 基线：checkout、Java setup、artifact upload/download 使用基于 Node 24 的当前官方主版本，避免 GitHub Hosted Runner 移除 Node 20 后在 Flutter 构建前失败。
- 发布流程：main 分支推送时使用 `github.run_number` 作为 Android versionCode 和 Windows build suffix，由单个 GitHub Release 同时发布 Android APK、Windows x64 压缩包和覆盖两者的 `SHA256SUMS`；生成校验和前显式确认两个产物存在，并列明 Cookie 安全边界、端到端验证状态和已知限制。功能分支、PR 和手动构建只上传临时 artifact。
- Android main 发布必须从 `ANDROID_KEYSTORE_BASE64` 与 `ANDROID_KEY_PROPERTIES_BASE64` Secrets 恢复固定 release keystore，并通过 `apksigner verify`；缺失 secret 时正式发布失败。本地、功能分支与 PR 可回退 debug 签名，仅作为临时 artifact，密钥文件不得提交或上传。
- Android `namespace`、`applicationId`、Manifest `.MainActivity` 与 Kotlin package 统一为 `com.sein.chaoxingapp`，CI 在构建前执行入口一致性检查，避免可构建但无法启动的 APK。
- Android Manifest 必须设置 `allowBackup=false`、`usesCleartextTraffic=false`，并且不声明 HTTP VIEW query；CI 持续检查，防止普通待办缓存/提醒历史进入系统备份或明文网络能力绕过统一 HTTPS 策略。
- 剩余验证：真实账号端到端网络同步、关闭隐藏保持后台进程、隐藏窗口重复启动恢复、单进程约束和测试通知后端调用已通过；Windows 通知肉眼可见性、通知点击和托盘菜单/退出仍需手动验收。

---

## User Personas

### Primary: 学习通重度使用学生

- **Role**: 需要频繁查看课程作业、考试和测验截止时间的学生。
- **Goals**: 在 App 或 Windows 桌面上快速看到即将到来的作业和考试，并在截止前收到提醒。
- **Pain Points**: 学习通通知分散、截止时间容易漏看；浏览器或手机通知不稳定；课程空间中未发通知的作业可能被遗漏。
- **Technical Level**: Intermediate。可以完成登录，也可以在必要时手动导入 Cookie，但不希望长期维护 Worker、token 或部署服务。

### Secondary: 项目维护者

- **Role**: 维护学习通待办同步和提醒工具的开发者。
- **Goals**: 保持本地同步链路可测试、可诊断、可扩展，减少远端运行依赖。
- **Pain Points**: 学习通页面结构变化会导致解析失败；Cookie 和隐私数据处理要求高；Windows 桌面能力涉及平台插件、打包和手动验收。
- **Technical Level**: Advanced。

---

## User Stories & Acceptance Criteria

### Story 1: 本地 Cookie 同步作业和考试

**As a** 学习通学生  
**I want to** 在 App 中使用本机保存的学习通 Cookie 同步作业和考试  
**So that** 我不需要配置 Worker URL 或 RUN_TOKEN，也能看到待办列表

**Acceptance Criteria:**
- [x] Cookie 保存到 secure storage，不进入普通配置或缓存。
- [x] App 能执行认证检查、收件箱定位/分页、通知筛选、详情链接提取、作业/考试页解析。
- [x] 同步结果构建为 `AppSyncResponse`，包含 items、failures、authStatus、lastSyncedAt。
- [x] items 按截止时间排序，并计算 `displayStatus` 和 `dueInHours`。
- [x] 设置页不明文回填 Cookie。
- [x] 使用真实学习通账号完成端到端网络同步验收。

### Story 2: Windows 桌面工具展示和刷新

**As a** Windows 用户  
**I want to** 在 Windows 上运行学习通待办工具并自动刷新  
**So that** 我可以在电脑上持续关注即将截止的事项

**Acceptance Criteria:**
- [x] Flutter Windows 平台目录已生成。
- [x] Windows release build 成功。
- [x] 自动刷新定时器已实现。
- [x] 提醒去重结构已实现。
- [ ] 真实 Windows toast 通知可显示、点击可打开 App 或目标详情。
- [ ] 系统托盘可常驻，支持打开窗口、立即同步、暂停/恢复通知、查看登录状态、退出。
- [ ] 退出托盘后进程结束，不继续后台同步或发送通知。

### Story 3: 安全处理 Cookie 和学习通请求

**As a** 用户  
**I want to** Cookie 只保存在本机并只发给学习通可信域名  
**So that** 我的账号凭据不会被泄漏到第三方域名、日志或诊断文件

**Acceptance Criteria:**
- [x] Cookie-bearing 请求在 Flutter 侧限制为显式学习通 HTTPS 主机 allowlist，不接受任意子域。
- [x] Cookie-bearing 请求在 Worker 侧同样限制为 `https://chaoxing.com` 和 `https://*.chaoxing.com`。
- [x] 手动校验 redirect，避免自动跟随到非 allowlist 域名并携带 Cookie。
- [x] 错误信息和诊断摘要不得包含 Cookie 明文。
- [x] 手动 Cookie 输入保存成功后不在设置页明文回填。
- [x] Windows 内置 WebView2 登录可从 Cookie Store 导入 HttpOnly Cookie，且不在 UI 或日志展示 Cookie。
- [x] 诊断导出统一脱敏 URL query token、Cookie 片段和账号类参数。

### Story 4: 补漏课程空间和考试列表

**As a** 学习通学生  
**I want to** App 不只依赖收件箱通知，还能检查课程空间和考试列表  
**So that** 未发通知或通知被清理的作业/考试也能进入待办

**Acceptance Criteria:**
- [x] App 能抓取课程空间中的课程/班级列表。
- [x] App 能抓取课程作业列表并解析未完成作业、入口 URL 和截止时间。
- [x] App 能抓取考试/测验列表并解析可作答状态、入口 URL 和截止时间。
- [x] 同一业务 ID 的事项来自收件箱和课程列表时合并展示并复用提醒 ID。
- [x] item 保留来源列表，例如 inbox、course_work、course_exam。

### Story 5: 打包、发布和回归验证

**As a** 项目维护者  
**I want to** 有稳定的 Windows CI、打包和验证流程  
**So that** 每次修改后都能确认 Windows App 可交付

**Acceptance Criteria:**
- [x] CI 增加 Windows job，至少运行 `flutter analyze`、`flutter test`、`flutter build windows`。
- [x] 发布产物包含 Windows release exe 或安装包。
- [x] 发布说明明确 Cookie 存储、安全边界、真实账号端到端验证状态和已知限制。
- [x] 打包流程在上传前审计 APK 和 Windows Release 内容，拒绝 `.dev.vars`、环境文件、测试/fixture 目录和本地运行时数据库；CI 从干净 checkout 构建，不注入真实 Cookie 或个人账号数据。

---

## Functional Requirements

### Core Features

**Feature 1: 本地学习通认证与 Cookie 存储**
- Description: App 使用用户提供或采集的学习通 Cookie 检查登录状态，并将 Cookie 保存到 secure storage。
- User flow: 用户打开 App -> 登录或导入 Cookie -> App 校验 Cookie -> 校验成功后保存 -> App 开始本地同步。
- Edge cases: Cookie 缺失、Cookie 过期、学习通返回登录页、网络不可用、风控页面。
- Error handling: 认证失败时停止本轮抓取，保留缓存，提示重新登录；错误信息不得包含 Cookie 明文。
- Current status: Phase 1 已实现认证检查、Cookie 安全存储、设置页不明文回填。

**Feature 2: 收件箱通知同步链路**
- Description: App 本地定位学习通收件箱，分页抓取通知，筛选作业/考试相关消息，提取详情中的入口链接。
- User flow: 定时器或手动刷新触发 -> 认证检查 -> 获取收件箱配置 -> 分页通知列表 -> 筛选关键词 -> 抓取详情 -> 提取作业/考试入口。
- Edge cases: 收件箱入口缺失、通知接口分页异常、单条详情失败、详情中链接重复或无效。
- Error handling: 单条失败进入 failures，不中断整体同步；对非学习通 URL 不携带 Cookie 请求。
- Current status: Phase 1 已实现收件箱定位/分页、关键词筛选、通知详情链接提取。

**Feature 3: 作业/考试页面解析和 AppSyncResponse 构建**
- Description: App 抓取作业/考试入口页，解析时间窗口、状态、业务 ID，并构建标准化 items。
- User flow: 入口链接 -> 安全请求 -> HTML 解析 -> 生成 Requirement -> 生成 SyncItem -> 构建 AppSyncResponse -> UI 展示和缓存。
- Edge cases: 页面结构变化、时间格式不完整、workId/examId 缺失、已截止或无截止时间。
- Error handling: 解析失败写入 failures；无 `dueAt` 的事项不参与截止提醒；保留可展示的部分数据。
- Current status: Phase 1 已实现时间解析、排序、`displayStatus`、`dueInHours`、`AppSyncResponse` 构建。

**Feature 4: 自动刷新和提醒去重**
- Description: App 按配置周期刷新同步结果，并使用提醒历史避免重复提醒。
- User flow: App 启动或隐藏到托盘 -> 定时器触发 -> 本地同步 -> 计算提醒候选 -> 去重 -> 发送通知 -> 写入提醒历史。
- Edge cases: 同步并发、网络失败、通知发送失败、截止时间变化、用户暂停通知。
- Error handling: 同步失败时保留缓存；通知失败不阻断同步缓存保存；去重 key 包含 `itemId + remindRule + dueAtSnapshot`。
- Current status: 自动刷新定时器、提醒去重、Windows toast 和托盘代码已完成；关闭隐藏保持后台进程与测试通知后端调用已验证，通知可见性/点击和托盘菜单仍待手动验收。

**Feature 5: Windows toast 与托盘工具形态**
- Description: Windows App 关闭窗口后隐藏到托盘并继续按进程内定时器运行；系统通知用于提醒截止事项。
- User flow: 用户启动 App -> 登录并同步 -> 关闭窗口 -> App 隐藏到托盘 -> 定时同步和通知继续 -> 用户从托盘恢复或退出。
- Edge cases: 用户真正退出、Windows 通知权限不足、托盘插件初始化失败、重复点击立即同步。
- Error handling: 退出后停止定时器和通知；托盘/通知失败需要有错误摘要和可恢复入口。
- Current status: Windows toast、通知点击恢复/打开详情、关闭隐藏和五项托盘菜单已接入；设置页提供不污染去重历史的可重复测试通知。关闭隐藏保持后台进程已验证，toast 可见性、通知点击和托盘菜单/退出尚待手动验收。

### Out of Scope

- Phase 1 不要求实现 Cloudflare Worker、CalDAV、Google Calendar 或 ICS 订阅迁移。
- 不实现 App 退出后的后台服务、Windows Service、系统计划任务或远端推送。
- 不绕过学习通验证码、二次验证或风控。
- 不上传 Cookie、同步数据、提醒历史到远端服务。
- 不在 PRD 更新任务中修改业务代码或提交 git。

---

## Technical Constraints

### Performance

- 单次自动同步默认应避免并发；已有同步运行时新触发应跳过或合并。
- 收件箱、详情、requirements 抓取需要受 limit 控制，避免频繁访问学习通触发风控。
- App 在隐藏到托盘时继续运行进程内定时器，但真正退出后不得继续同步。
- Windows runner 必须使用用户会话级命名 Mutex 保证单实例；重复启动不得创建第二套托盘、同步定时器或通知服务。第二实例通过 Windows 注册消息请求主实例恢复和聚焦，不依赖窗口标题；隐藏窗口恢复与单进程约束必须在真实 Release 上验证。
- UI 应优先展示缓存结果；网络失败或认证失败时不得清空已缓存 items。

### Security

- Cookie 必须保存到 `flutter_secure_storage` 或等价平台安全存储，不得保存到 shared_preferences、日志、诊断导出、通知正文或 UI 明文回填。
- Windows 通知默认只显示通用截止提醒，不含课程名、任务名和具体截止时间；用户可在设置中显式开启详情展示，偏好只保存布尔值。
- 普通配置、同步缓存、提醒历史、提醒配置可以保存到 `shared_preferences`。
- 所有 Flutter 带 Cookie 请求必须使用统一 HTTP 客户端，并限制目标为显式学习通 HTTPS 主机 allowlist；不得信任任意子域。
- Flutter 侧和 Worker 侧均需保持 Cookie-bearing request allowlist。
- Redirect 必须手动校验；不得自动跟随到非 allowlist 域名并继续携带 Cookie。
- 详情页外部浏览器启动同样只允许显式学习通 HTTPS 主机；缓存中的第三方、HTTP 或畸形 URL 不得形成可点击外链，启动失败提示不得回显完整 URL。
- 同步请求、WebView 顶层导航、详情外链和 Cookie Domain 必须复用独立 URL 策略模块；根域只可作为 Cookie Domain 作用域，实际网络与外链目标仍需命中显式请求主机集合。
- 错误摘要、失败列表、诊断导出必须脱敏 Cookie、token、个人敏感 query 和可能包含账号信息的正文。
- 手动 Cookie 输入不得接受换行注入；保存成功后清空输入框。
- Cookie Source 在解析前执行源级 CR/LF 检查，命中后整份拒绝且不认证、不保存、不发送；设置页只展示预定义安全原因或通用保存失败消息。
- 控制器加载历史配置时再次校验 Cookie Source；不安全值在内存中隔离为未配置，并通过专用 `clearCookie()` 删除凭据而不改其他偏好；清理失败不削弱内存隔离，不启动同步、不传入自定义 fetcher，提示仅要求重新登录且不回显原文。

### Integration

- **Flutter App**: 本地同步、UI 展示、缓存、提醒、Windows build。
- **学习通 Web 页面/API**: 认证检查、收件箱页面、通知列表接口、通知详情接口、作业/考试入口页。
- **Windows 桌面能力**: 系统通知、系统托盘、关闭隐藏、真正退出。
- **Worker 代码**: Phase 1 后 App 主流程不依赖 Worker；Worker 可继续作为行为参考和测试对照，不作为 App runtime。

### Technology Stack

- Flutter/Dart。
- Flutter Windows desktop。
- `flutter_secure_storage` 用于 Cookie。
- `shared_preferences` 用于普通配置、缓存和提醒历史。
- Dart HTTP/HTML 解析能力用于学习通页面抓取。
- 后续 Windows toast 和托盘插件需与 Flutter Windows release build 兼容。
- Worker 侧仍使用 Bun/TypeScript 进行既有测试和行为对照。

---

## MVP Scope & Phasing

### Phase 1: MVP 已实现和验证

- Flutter App 从 Worker URL + token 客户端迁移为本地学习通 Cookie 同步。
- Windows 平台目录已生成。
- Windows release build 已通过。
- Cookie 进入 secure storage；普通配置、缓存、提醒历史进入 shared_preferences。
- 设置页不明文回填 Cookie。
- App 本地同步能力已实现：认证检查、收件箱定位/分页、通知关键词筛选、通知详情链接提取、作业/考试页时间解析、`AppSyncResponse` 构建、排序、`displayStatus`、`dueInHours`。
- Flutter Cookie-bearing 请求使用显式学习通主机 allowlist 并手动校验 redirect；Worker 侧维持原有学习通域名限制。
- Windows 工具第一阶段已实现自动刷新定时器和提醒去重结构。
- 验证已通过：`bun run typecheck`、`bun test`、`flutter analyze`、`flutter test`、`flutter build windows`；2026-07-16 已完成真实账号登录、Cookie 自动导入与本地网络同步验收。

**MVP Definition**: 在不依赖 Worker runtime 的前提下，Flutter App 能用本机学习通 Cookie 同步并展示作业/考试待办，Windows release build 可生成，核心安全边界和测试验证已到位。

### Phase 2: Windows 工具补齐和本地登录增强

- Windows toast 通知与点击打开 App/定位详情代码已接入；真实环境测试通知后端调用成功，通知可见性和点击行为仍待人工观察。
- Windows 系统托盘五项菜单代码已接入，待真实环境验收。
- 关闭隐藏并保持托盘后台进程已通过真实环境验证；托盘菜单和明确退出仍待验收。
- Windows 内置 WebView2 登录与 Cookie Store 自动导入已接入并通过真实账号验收；保留手动 Cookie 导入 fallback。
- 真实学习通账号端到端网络同步已验证：通知与课程空间均成功同步，阶段失败数为 0，明确完成/只读事项能够过滤。
- Windows CI job 已覆盖 analyze/test/build。
- Windows x64 压缩包与 Android APK 已接入统一发布流程。

### Phase 3: 数据源补漏和诊断增强

- 可选课程空间数据源已能抓取课程/班级列表。
- 课程作业与考试任务页补抓、详情时间解析、明确完成状态过滤和逐课程/逐任务失败隔离已接入并通过真实账号验证；课程列表采用最多 6 个请求的有限并发，并在抓取后按原课程顺序确定性处理，仍需随页面变化持续补充 fixture。
- 2026-07-16 同一真实账号对比：课程列表有限并发将完整同步从 26.5 秒降至 17.7 秒（缩短 33.2%），待办数、过滤统计和失败数保持一致。
- 作业考试日历默认定位当前月，支持返回今天、选择日期查看当日完整事项，并在单日超过 3 项时显示溢出数量；历史过期事项不会再让初始视图跳离当前月。
- 阶段耗时真实验证：总计 18.6 秒，认证 0.5 秒、通知列表 2.7 秒、通知详情 2.9 秒、任务详情 6.8 秒、课程扫描 5.7 秒；阶段之和等于总耗时，当前主要瓶颈为收件箱任务详情请求。
- 收件箱任务详情并发从 6 提高到 8 的真实实验被回退：总耗时恶化到 113.9 秒、任务详情阶段升至 32.9 秒并产生 3 个失败，说明服务端或连接侧出现拥塞/限流；生产配置固定为 6 路。
- 启动流程增加 5 分钟缓存新鲜期：近期缓存直接展示且不立即重复全量同步，保留手动刷新与原定时器，降低频繁重启触发服务端限流的风险。
- 成功或部分成功同步后增加 60 秒手动刷新冷却，并显示剩余等待时间；配置变更、同步失败后的重试和静默定时刷新不受影响，阻止连续点击放大短期限流。
- 默认同步与登录校验采用单次操作独立 HTTP 客户端，完成后必定关闭；桌面明确退出时关闭所有活跃客户端，停止未完成的真实网络请求并避免托盘长时间运行累积连接资源。
- 重新登录或保存新同步配置会关闭旧配置的活跃默认客户端，新配置同步按现有单轮队列立即接管；旧响应仍按配置 revision 丢弃，缩短新 Cookie 导入等待并减少无效旧账号请求。
- 同步失败摘要命中 HTTP 429、Too Many Requests、请求过频或限流信号时进入 5 分钟内存退避，手动刷新显示剩余等待、静默刷新跳过；保存新配置清除旧账号退避，避免服务端限流窗口被自动请求延长。
- 启动加载缓存时按最近同步时间恢复未结束的限流退避和一分钟手动刷新冷却；未来时间戳不参与恢复，防止重启绕过保护或异常缓存造成无限等待。
- `AppConfig` 在持久化读取、保存以及控制器加载/应用边界统一规范化：通知页数 1–20、条目数 1–500、课程数 1–100，非法低值回退安全默认；刷新周期允许 0 关闭，否则钳制为 15–180 分钟，防止损坏旧偏好或替换的存储实现绕过请求上限、创建过密定时器。
- 多数据源按稳定业务 ID 合并并保留来源列表，避免重复展示和重复提醒。
- 诊断页面、同步总耗时及认证/通知/通知详情/任务详情/课程五段耗时、失败摘要和脱敏复制导出已接入并通过 Flutter widget/test 验证；空结果可区分无消息、未命中通知、未发现任务入口、状态过滤和阶段失败。
- 部分成功的同步会在主界面显示失败数量和诊断入口，但不直接渲染失败 URL、课程名或错误正文，避免用户误判同步完整性并减少敏感信息暴露。
- 完善 fixture 管理和真实账号回归流程。

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation Strategy |
|------|-------------|--------|---------------------|
| 学习通真实页面变体覆盖仍有限 | Medium | High | 已完成真实账号 E2E 验收；保留脱敏阶段统计与 fixture 回归，遇到新页面变体时按精确失败阶段补样本。 |
| Windows toast/托盘插件兼容性问题 | Medium | High | 先实现抽象层和 fake 测试，再做 Windows 手动验收；CI 增加 Windows build；失败时提供降级错误摘要。 |
| 学习通页面结构变化导致解析失败 | Medium | High | 使用 fixture 覆盖关键页面；局部失败进入 failures；诊断导出脱敏后辅助定位；Phase 3 扩展多数据源补漏。 |
| Cookie 泄漏到第三方域名、日志或诊断文件 | Low | High | 统一 HTTP 客户端 allowlist、手动 redirect 校验、secure storage、错误脱敏、安全审核清单。 |
| 只依赖收件箱导致漏项 | High | Medium | Phase 3 增加课程空间、作业列表、考试列表补漏，并以稳定业务 ID 合并。 |
| 通知重复轰炸 | Medium | Medium | Windows toast 仅在系统通知调用成功后写入 `itemId + kind + dueAtSnapshot` 去重历史；处理前保留最近 90 天且最多 1000 条、丢弃异常未来时间；后续增加多规则提醒时需把规则 ID 纳入 key。 |
| 风控、验证码或登录失效 | Medium | Medium | 不绕过风控；认证失败提示重新登录；降低自动同步频率；缓存保留。 |
| Windows 打包产物包含敏感数据 | Low | High | APK 和 Windows Release 在上传前拒绝 `.dev.vars`、环境文件、测试/fixture 目录和本地数据库；CI 从干净 checkout 构建且不注入本地 secrets。 |

---

## Dependencies & Blockers

**Dependencies:**
- Flutter Windows desktop 工具链：用于 `flutter build windows` 和后续 CI。
- 学习通账号与有效 Cookie：用于真实端到端网络同步验收。
- Windows 通知和托盘插件：用于 Phase 2 工具形态补齐。
- 学习通页面/API 稳定性：影响收件箱、详情、作业/考试页、课程空间和考试列表解析。
- CI 环境：需要 Windows runner 执行 Flutter analyze/test/build。

**Known Blockers:**
- Windows 测试通知后端调用已成功；仍需人工确认系统通知肉眼可见、点击行为和通知权限问题。
- 系统托盘手动验收部分完成：关闭隐藏后进程继续运行已验证；仍需验证托盘菜单和真正退出后的进程行为。
- 内置登录与 Cookie 自动导入已通过真实账号验证；后续仍需关注登录页面变体和 WebView2 运行时兼容性。
- 课程空间补漏默认开启，使用当前 `courselistdata` 接口并回退旧 `backclazzdata`；真实账号已验证明确完成、已提交、已过期和只能查看/预览状态的过滤，仍需覆盖更多页面变体。

---

## Acceptance Test Plan

### Existing Verified Commands

Worker:

```powershell
bun run typecheck
bun test
```

Expected: typecheck pass; 32 tests pass.

Flutter:

```powershell
Set-Location apps/chaoxing_app
flutter analyze
flutter test
flutter build windows
```

Expected: analyze pass; 126 tests pass; Windows release build pass.

Windows artifact:

```text
apps/chaoxing_app/build/windows/x64/runner/Release/chaoxing_app.exe
```

Expected: file exists after `flutter build windows`.

### Phase 2 Acceptance Tests

- Run `flutter run -d windows`; close main window; expected: window hides to tray and process remains running.
- Tray menu contains: 打开窗口、立即同步、暂停/恢复通知、查看登录状态、退出。
- Click 打开窗口; expected: main window restores and focuses.
- Click 立即同步 while not syncing; expected: one sync starts and concurrent sync is prevented.
- Click 暂停通知; expected: automatic sync continues but no toast is sent.
- Click 退出; expected: process exits and no further sync or notification happens.
- Create or mock a due item matching a reminder rule; expected: Windows toast appears once and reminder history records the dedupe key.
- Click toast; expected: App opens or focuses and can navigate to relevant item/detail.

### Phase 3 Acceptance Tests

- 使用有效 Cookie 并启用课程空间数据源时，没有收件箱通知的课程作业也能出现在待办中。
- 使用有效 Cookie 并启用考试列表数据源时，没有收件箱通知的考试/测验也能出现在待办中。
- Same business item from inbox and course list appears once.
- Same business item from multiple sources triggers at most one reminder for the same rule and dueAt snapshot.
- Diagnostics export contains failure summary but not Cookie, token, account ID, or private response body.

---

## Appendix

### Glossary

- **学习通 / Chaoxing**: 作业、考试、课程和通知来源平台。
- **Cookie header**: 用于代表用户登录态的 HTTP Cookie 字符串，属于敏感凭据。
- **AppSyncResponse**: App 展示层使用的标准化同步响应，包含 items、failures、authStatus、lastSyncedAt 等。
- **SyncItem**: 单个作业或考试待办项。
- **displayStatus**: App 展示状态，例如 overdue、today、upcoming、unscheduled。
- **dueInHours**: 距离截止时间的小时数。
- **Reminder dedupe key**: 提醒去重键，要求包含 `itemId + remindRule + dueAtSnapshot`。
- **Windows toast**: Windows 系统通知。
- **Tray**: Windows 系统托盘常驻入口。

### References

- `README.md`: 项目结构、Worker/Flutter 验证命令和既有同步接口说明。
- `docs/superpowers/specs/2026-06-08-local-flutter-chaoxing-design.md`: 本地 Flutter 学习通设计说明。
- `docs/superpowers/plans/2026-06-08-local-flutter-chaoxing.md`: 本地 Flutter 学习通实现计划。

---

*This PRD was created through requirements consolidation with quality scoring to ensure comprehensive coverage of business, functional, UX, and technical dimensions.*
