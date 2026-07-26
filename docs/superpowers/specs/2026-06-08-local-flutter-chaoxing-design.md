# Local Flutter Chaoxing Design

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:writing-plans` before turning this design into an implementation plan, then use `superpowers:subagent-driven-development` or `superpowers:executing-plans` to implement task-by-task.

**Goal:** 将学习通待办工具从 Cloudflare Worker + Bun helper 架构迁移为纯 Flutter/Dart 本地实现，Windows 桌面 App 直接完成登录 Cookie 采集、Cookie 安全保存、HTTP 抓取、页面解析、同步展示、托盘常驻和 Windows 通知。

**Architecture:** Flutter Windows App 是唯一运行时进程。所有学习通网络请求、HTML/JSON 解析、作业考试标准化、提醒调度和通知去重都在 Dart 本地完成；现有 TypeScript Worker 代码只作为迁移参考和行为对照，不作为运行时依赖。

**Tech Stack:** Flutter/Dart、Flutter Windows desktop、`http`、`flutter_secure_storage`、`shared_preferences` 或本地轻量持久化、Windows 托盘插件、Windows 本地通知插件、可控 WebView/浏览器登录组件。

---

## 目标

- 移除运行时对 Cloudflare Worker、Wrangler、Bun、Node、本地 helper script 和 `/app/sync` HTTP 服务的依赖。
- 在 Flutter App 内直接保存学习通 Cookie，并以该 Cookie 访问学习通页面和接口。
- 第一阶段从学习通收件箱通知抓取作业和考试信息，复刻现有 Worker 的核心处理链路：认证检查、收件箱抓取、通知详情解析、作业/考试链接提取、要求页解析、同步模型生成。
- Windows 形态为 Flutter Windows 桌面 App + 系统托盘常驻工具。
- App 窗口关闭时不退出进程，而是最小化到托盘；只要进程在托盘中运行，就按配置定时同步并弹 Windows 通知。
- 真正退出后不做后台同步，不安装系统服务，不创建独立后台守护进程。
- 登录方式支持“弹出的浏览器界面中采集 chaoxing 的 Cookie”：App 打开可控浏览器/WebView 或外部浏览器让用户登录学习通，登录成功后采集 `chaoxing.com` 相关 Cookie 并保存到 `flutter_secure_storage`。
- 如果 Windows WebView Cookie 提取不稳定，提供手动 Cookie 导入 fallback。
- 提醒配置完整覆盖作业和考试两个类型，包括多个提前提醒时间、重复提醒、免打扰时间段，以及本地记录 `itemId + remindRule` 的去重。
- 第二阶段补课程空间、作业列表、考试列表抓取，解决只依赖通知导致的漏项。

## 非目标

- 不在第一阶段实现 Cloudflare Worker、CalDAV、Google Calendar 或 ICS 订阅迁移。
- 不在第一阶段支持 App 退出后的后台同步、Windows 服务、自启动常驻守护进程或系统级计划任务。
- 不绕过学习通登录、验证码、二次验证或风控流程；只保存用户正常登录后的 Cookie。
- 不上传 Cookie、同步数据或提醒历史到远端服务。
- 不把现有 TypeScript 代码编译进 Flutter App，也不通过本地 Bun/Node helper 调用现有脚本。
- 不保证学习通页面结构变化时无需维护解析规则；解析器需要通过测试样例和错误降级降低风险。

## 当前系统迁移背景

现有仓库的 Worker 侧模块提供了可迁移的行为参考：

- `src/auth.ts`：通过访问学习通首页判断 Cookie 是否仍登录，提取页面标题和登录页信号。
- `src/inbox.ts`：进入学习通首页，定位收件箱 URL，读取页面配置，调用 `https://notice.chaoxing.com/pc/notice/getNoticeList` 分页获取通知。
- `src/processor.ts`：筛选作业/考试相关通知，读取通知详情接口，解码详情中的链接和 iframe 附件，收集作业/考试入口 URL。
- `src/requirements.ts`：抓取作业/考试页面，解析课程、班级、作业、答案 ID，作答状态、时间窗口、题目摘要和提示页。
- `src/sync.ts`：将 requirement 转换为稳定的 `SyncItem`，推断作业/考试类型、时间、状态和 ID。
- `src/app-sync.ts`：为 App 生成显示状态、截止剩余小时、排序和失败列表。

Flutter 侧当前模型和 UI 可继续承载标准化同步结果，但现有配置仍是 Worker URL + token，需要改为本地账号状态、同步配置和提醒配置。

## 架构

目标架构分为六层：

1. UI 和状态层：Flutter 页面、详情页、设置页、登录页、托盘动作入口和 AppController。
2. 本地账号与 Cookie 层：登录浏览器/WebView、Cookie 采集、Cookie 校验、Cookie 安全存储、手动导入。
3. 学习通 HTTP 客户端层：统一封装 Cookie header、User-Agent、Referer、重定向、超时、重试、错误分类。
4. 抓取与解析层：`auth`、`inbox`、`processor`、`requirements` 的 Dart 重写模块。
5. 同步模型层：本地构建 `SyncItem`、失败项、同步元数据、展示状态和缓存。
6. 提醒调度层：定时同步、提醒规则计算、免打扰判断、去重记录、Windows 通知发送和托盘菜单控制。

运行时数据流：

```text
用户登录
  -> 采集 chaoxing Cookie
  -> flutter_secure_storage 保存 Cookie
  -> 定时器或手动同步触发
  -> AuthClient 校验 Cookie
  -> InboxClient 抓取通知列表
  -> Processor 筛选通知并抓取详情
  -> RequirementsParser 解析作业/考试页面
  -> SyncModelBuilder 生成 SyncItem 列表
  -> 本地缓存覆盖/合并
  -> NotificationScheduler 计算应提醒规则
  -> WindowsNotifier 弹通知
  -> UI 和托盘状态更新
```

## 模块边界

### `auth`

职责：

- 提供 `checkAuth(cookie)`，访问学习通首页并判断 Cookie 是否有效。
- 识别登录页信号，例如 `passport2.chaoxing.com/login`、登录页标题、登录按钮。
- 输出 `AuthStatus`：`authenticated`、`expired`、`missingCookie`、`networkError`、`unknown`。
- 提供登录流程协调：打开 WebView/浏览器、等待登录成功、采集 Cookie、保存 Cookie、重新校验。

不负责：

- 不解析作业或通知。
- 不直接展示 UI，只提供状态和错误原因给 UI。

### `inbox`

职责：

- 用 Cookie 访问学习通首页，定位通知/收件箱入口。
- 读取收件箱页面中的必要配置：`type`、`noticeType`、`nowYear`、`folderUUID`、`fidsCode` 等。
- 调用 `notice.chaoxing.com` 的通知列表接口并分页。
- 将原始通知归一化为 `InboxMessage`，保留 `id`、`uuid`、`title`、`sender`、`sendTime`、`content`、`detailUrl`、`sendTag`、`isRead`。

不负责：

- 不判断具体作业截止时间。
- 不触发通知。

### `processor`

职责：

- 用关键词和结构信号筛选作业/考试相关通知：作业、考试、测验、测试、截止、结束提醒、答题、试卷、练习。
- 调用通知详情接口，提取纯文本内容、富文本、附件、iframe 名称和候选 URL。
- 解码 URL encoded 和 base64-url encoded 的 iframe 数据。
- 收集唯一作业/考试入口链接。
- 对单条详情或 requirement 抓取失败进行隔离，保留失败列表，不让一次失败中断整体同步。

不负责：

- 不持久化提醒历史。
- 不直接决定 UI 展示分组。

### `requirements`

职责：

- 抓取作业/考试入口页 HTML。
- 解析 `courseId`、`classId`、`workId`、`answerId`、`examId` 等标识。
- 从页面和通知内容中解析开始时间、截止时间、页面标题、作答状态、提示文本和题目摘要。
- 输出 `AssignmentRequirement` 或统一的 `Requirement` 数据结构。

不负责：

- 不决定提醒是否发送。
- 不依赖 TypeScript 正则实现，Dart 中可使用等价正则、HTML parser 或 DOM 解析库。

### `sync model`

职责：

- 将 requirements 转换为 App 使用的 `SyncItem`。
- 生成稳定 `itemId`：优先使用作业/考试业务 ID，缺失时使用最终 URL 或入口 URL 的稳定 hash。
- 推断 `kind`：`assignment` 或 `exam`。
- 计算 `startAt`、`dueAt`、`displayStatus`、`dueInHours`、排序键和失败信息。
- 维护本地缓存，使无网络或登录失效时仍能查看上次同步结果。

不负责：

- 不生成 ICS、CalDAV 或 Google Calendar 数据。

### `notification scheduler`

职责：

- 根据同步结果、提醒配置、当前时间和已提醒记录计算要发送的 Windows 通知。
- 支持作业和考试分别配置。
- 支持多个提前提醒时间，例如截止前 7 天、3 天、1 天、6 小时、1 小时、15 分钟。
- 支持重复提醒，例如首次命中后每 N 分钟/小时重复，直到截止、完成、关闭或达到最大次数。
- 支持免打扰时间段，跨午夜时间段必须正确处理。
- 使用 `itemId + remindRule` 去重；重复提醒规则需要把重复序号或 repeat window 纳入 rule key，避免每次同步都重复弹同一条。
- 通知点击后打开 App 并定位到对应详情页。

不负责：

- 不在进程退出后继续运行。
- 不使用远端推送服务。

## 登录和 Cookie 流程

主流程：

1. 用户点击“登录学习通”。
2. App 打开可控 WebView 或浏览器窗口，目标地址为学习通首页或登录页。
3. 用户在真实学习通页面完成账号密码、验证码或二次验证。
4. App 监听导航变化或定时检查当前 URL，发现已从登录页进入 `chaoxing.com` 已登录页面。
5. App 采集 `chaoxing.com`、`*.chaoxing.com`、`passport2.chaoxing.com`、`notice.chaoxing.com` 相关 Cookie，拼接成 HTTP 请求可用的 Cookie header。
6. App 调用 `auth.checkAuth(cookie)` 访问学习通首页，确认不是登录页且页面特征包含个人空间、收件箱、消息或课程信号。
7. 校验成功后，将 Cookie header 保存到 `flutter_secure_storage`。
8. UI 显示登录状态、最后校验时间和账号可用状态。

Windows WebView Cookie fallback：

1. 如果 WebView Cookie API 在 Windows 上无法稳定读取或读到的 Cookie 不完整，登录页显示“手动导入 Cookie”入口。
2. 用户从浏览器 DevTools 或扩展复制 `chaoxing.com` 请求的 Cookie header。
3. App 对输入做基本校验：非空、包含多个 `name=value` 片段、不得包含换行注入字符。
4. App 使用该 Cookie 执行 `auth.checkAuth`。
5. 校验成功后保存；校验失败时提示 Cookie 过期、不完整或仍处于登录页。

Cookie 更新：

- 每次同步前如果距离上次认证检查超过配置阈值，先进行轻量认证检查。
- 认证失败时暂停抓取，保留缓存，标记登录过期，并通过 Windows 通知提示重新登录。
- 用户重新登录成功后覆盖旧 Cookie，清除认证错误状态，不清除历史同步缓存和提醒去重记录。

## 数据流

### 第一阶段：收件箱通知链路

1. `SyncRunner` 根据手动触发或定时触发启动一次同步，若已有同步在运行则合并或跳过新触发。
2. `AuthClient` 校验 Cookie 是否存在且有效。
3. `InboxClient` 获取学习通首页 HTML，定位收件箱 URL。
4. `InboxClient` 获取收件箱页面配置，调用通知列表接口，按 `inboxLimit` 分页。
5. `Processor` 筛选作业/考试通知，按 `detailsLimit` 抓取详情。
6. `Processor` 从详情内容和附件中提取作业/考试入口链接，按 URL 去重。
7. `RequirementsClient` 按 `requirementsLimit` 抓取入口页并解析 requirement。
8. `SyncModelBuilder` 构建 `SyncItem` 列表和失败列表。
9. `SyncStore` 保存 `lastSyncedAt`、`authStatus`、items、failures、meta。
10. `NotificationScheduler` 对最新 items 计算提醒并调用 Windows 通知。
11. UI 和托盘状态刷新。

### 第二阶段：课程空间补漏链路

第二阶段新增独立数据源，仍在 Dart 本地运行：

- 课程空间列表：从学习通课程空间获取用户课程和班级。
- 作业列表：按课程/班级抓取作业列表，解析未完成、已完成、截止时间和入口 URL。
- 考试列表：按课程/班级抓取考试或测验列表，解析可作答状态和截止时间。
- 合并策略：以业务 ID 优先合并，URL hash 兜底；同一 `itemId` 同时来自通知和课程空间时，保留来源列表和更完整字段。

第二阶段的目标是解决“学习通没有发通知或通知被清理导致漏项”的问题，不改变第一阶段的收件箱链路。

## 提醒和通知规则

配置模型按类型拆分：

```text
ReminderConfig
  assignment:
    enabled: bool
    advanceRules: List<AdvanceRule>
    repeatRule: RepeatRule
  exam:
    enabled: bool
    advanceRules: List<AdvanceRule>
    repeatRule: RepeatRule
  quietHours:
    enabled: bool
    startLocalTime: HH:mm
    endLocalTime: HH:mm
  notificationsPaused: bool
```

`AdvanceRule` 字段：

- `id`：稳定规则 ID，例如 `advance_1440m`。
- `minutesBeforeDue`：截止前分钟数。
- `enabled`：是否启用。

`RepeatRule` 字段：

- `enabled`：是否启用。
- `intervalMinutes`：重复间隔。
- `startMinutesBeforeDue`：进入重复提醒窗口的时间，例如截止前 24 小时。
- `stopAtDue`：默认 true。
- `maxCountPerItem`：每个 item 每条重复规则的最大提醒次数。

调度判断：

- 没有 `dueAt` 的 item 不触发截止提醒。
- 已过期 item 默认不再触发提前提醒；如果后续需要“逾期提醒”，必须作为独立规则显式配置。
- `notificationsPaused` 为 true 时不发送通知，但仍允许同步和缓存更新。
- 当前时间落入免打扰时间段时不发送通知；调度器记录“被免打扰延后”的候选，并在免打扰结束后的下一次 tick 重新评估。
- 每条发送记录保存 `itemId`、`remindRule`、`sentAt`、`dueAtSnapshot`、`titleSnapshot`。
- 如果同一 item 的 `dueAt` 改变，提前提醒规则可重新评估；去重 key 使用 `itemId + remindRule + dueAtSnapshot`，避免旧截止时间的提醒记录压制新截止时间。
- 重复提醒的 `remindRule` 格式为 `repeat:<intervalMinutes>:<dueAtIso>:<sequence>` 或等价稳定格式，确保不会在每次同步中重复发送同一序号。

通知内容：

- 标题包含类型和时间关系，例如 `作业截止提醒` 或 `考试截止提醒`。
- 正文包含课程/来源、标题、截止时间和剩余时间。
- 通知点击打开 App 详情页。
- 通知发送失败时记录错误，不阻断同步缓存保存。

## Windows 托盘行为

窗口生命周期：

- 点击窗口关闭按钮时拦截关闭事件，隐藏窗口并保留进程。
- 隐藏后 App 在系统托盘显示图标，托盘 tooltip 展示登录和同步摘要。
- 从托盘“打开窗口”恢复主窗口并聚焦。
- 真正退出只能通过托盘菜单“退出”或 App 内明确退出动作触发。

托盘菜单：

- `打开窗口`：显示并聚焦主窗口。
- `立即同步`：触发一次同步；如果已有同步进行中，显示“同步中”状态并避免并发。
- `暂停通知` 或 `恢复通知`：切换 `notificationsPaused`，不影响同步。
- `查看登录状态`：打开登录/账号状态页面，显示 Cookie 校验状态、最后同步时间和错误。
- `退出`：停止定时器、保存必要状态、关闭托盘图标、退出进程。

同步运行规则：

- App 启动后加载配置，如果 Cookie 可用且用户没有关闭自动同步，则启动定时器。
- App 隐藏到托盘时定时器继续运行。
- App 真正退出后不运行同步、不发送通知。
- Windows 重启或用户未启动 App 时不做任何后台同步；是否增加开机自启动属于独立后续需求。

## 配置和存储

安全存储：

- `flutter_secure_storage` 保存 Cookie header 和登录相关敏感数据。
- 不把 Cookie 写入日志、普通 shared preferences、崩溃报告或通知内容。
- 提供“退出登录”操作，删除 Cookie 并将认证状态置为未登录。

普通本地存储：

- 同步配置：刷新间隔、抓取 limit、是否自动同步。
- 提醒配置：作业/考试规则、重复提醒、免打扰、暂停通知状态。
- 缓存数据：最后一次 `AppSyncResponse` 或本地等价模型。
- 提醒历史：已提醒记录，按时间或容量做清理。
- 运行状态：最后同步时间、最后成功同步时间、最后错误摘要。

建议存储键从现有 Worker 配置迁移：

- 废弃：`worker_base_url`、`run_token`。
- 新增：`chaoxing_cookie`、`refresh_minutes`、`sync_limits`、`reminder_config`、`cached_local_sync`、`reminder_history`、`auth_status_cache`。

数据兼容：

- 如果检测到旧 Worker URL/token 配置，只在 UI 提示“旧配置已不再使用”，不自动迁移为 Cookie。
- 保留现有 `SyncItem` 字段，新增字段应向后兼容，避免破坏当前列表、日历和详情页。

## 安全

- Cookie 只保存在本机安全存储中，只用于访问学习通域名。
- 所有 HTTP 请求由统一客户端创建，默认限制目标域名在学习通相关域名内，避免解析到的恶意 URL 被自动带 Cookie 访问。
- 从通知内容提取 URL 后必须校验 scheme 和 host，只允许 `http`/`https` 且属于学习通可信域或已明确需要的学习通子域。
- 日志中对 Cookie、完整 URL query 中的敏感 token、响应体中的个人信息做脱敏。
- 手动 Cookie 输入框不在 UI 中长期明文展示，保存后清空输入内容。
- 导出诊断信息时默认不包含 Cookie、题目正文、个人账号信息；如需包含，必须由用户显式确认。

## 错误处理

错误分类：

- `missingCookie`：未登录或 Cookie 被删除。
- `authExpired`：Cookie 存在但访问学习通后进入登录页。
- `networkUnavailable`：DNS、TLS、超时、无网络。
- `httpStatus`：学习通返回非 2xx。
- `inboxNotFound`：首页中未找到收件箱入口。
- `parseFailed`：页面结构变化或 HTML 不符合预期。
- `rateLimitedOrRiskControl`：疑似风控、验证码、访问过快或异常页面。
- `notificationFailed`：Windows 通知发送失败。

处理策略：

- 同步过程允许局部失败，失败项进入 `failures`，整体仍保存成功解析出的 items。
- 认证失败时停止本轮抓取并提示重新登录，不清空已有缓存。
- 网络失败时保留上次缓存，记录最后错误和失败时间。
- 解析失败时保存失败 URL、来源标题和错误摘要，避免无限重复噪声日志。
- 连续失败达到配置阈值后降低同步频率或只在用户手动触发时重试，防止频繁访问。
- 所有用户可见错误使用可操作文案：重新登录、检查网络、稍后重试、手动导入 Cookie。

## 测试策略

单元测试：

- `auth`：登录页信号识别、个人空间页面识别、空 Cookie、HTTP 错误。
- `inbox`：收件箱 URL 提取、页面配置提取、通知列表分页、通知归一化。
- `processor`：作业/考试关键词筛选、详情 JSON 解析、iframe name 解码、候选链接去重。
- `requirements`：时间窗口解析、题目块解析、状态推断、URL 参数和 hidden input 读取。
- `sync model`：稳定 ID、类型推断、截止时间解析、排序、displayStatus、dueInHours。
- `notification scheduler`：多个提前提醒、重复提醒、跨午夜免打扰、暂停通知、`itemId + remindRule + dueAtSnapshot` 去重。

集成测试：

- 使用录制的学习通 HTML/JSON fixture，不依赖真实账号。
- 覆盖“收件箱列表 -> 详情 -> requirement -> SyncItem -> 通知候选”的完整第一阶段链路。
- 覆盖部分 requirement 抓取失败但整体同步成功的场景。
- 覆盖 Cookie 过期时 UI 状态和缓存保留。

Windows 手动验证：

- 关闭窗口后进入托盘，进程仍在，定时同步继续。
- 托盘菜单五项均可用：打开窗口、立即同步、暂停/恢复通知、查看登录状态、退出。
- 退出后进程结束，不再同步，不再弹通知。
- WebView 登录能采集 Cookie；如果失败，手动 Cookie 导入可完成登录。
- Windows 通知能显示、点击能打开详情页。

回归对照：

- 用现有 TypeScript Worker 测试 fixture 或新增相同 fixture 对比 Dart 输出，确认核心字段一致。
- 迁移期间保留 TypeScript 模块作为参考测试数据来源，但 Flutter App 运行时不得调用这些模块。

## 阶段划分

### 阶段 1：本地收件箱同步和 Windows 常驻

交付：

- Flutter Windows App 本地登录和 Cookie 保存。
- Dart 版 `auth`、`inbox`、`processor`、`requirements`、`sync model`、`notification scheduler`。
- 本地同步缓存和 UI 展示。
- Windows 托盘常驻、关闭最小化到托盘、托盘菜单。
- 定时同步、手动同步、暂停/恢复通知、登录状态查看、退出。
- 作业/考试完整提醒配置、免打扰、重复提醒、去重记录。
- Worker URL/token 配置从主流程移除。

验收标准：

- 不启动 Worker、不安装 Bun、不运行 Node helper，Flutter Windows App 能独立登录、同步并展示作业/考试。
- App 隐藏到托盘后仍能按配置同步和通知。
- App 退出后不再同步。
- Cookie 过期时提示重新登录并保留缓存。
- 单元测试和 Windows 手动验证覆盖关键链路。

### 阶段 2：课程空间、作业列表和考试列表补漏

交付：

- Dart 本地抓取课程空间。
- Dart 本地抓取课程作业列表。
- Dart 本地抓取考试/测验列表。
- 多数据源合并和冲突处理。
- UI 显示 item 来源：通知、课程空间、作业列表、考试列表。

验收标准：

- 没有收件箱通知但课程列表存在的作业/考试可以进入待办。
- 同一 item 来自多个数据源时不重复展示、不重复提醒。

### 阶段 3：体验和诊断增强

交付：

- 同步诊断页面，展示最近失败、解析失败样本摘要、最后成功同步时间。
- 可选开机启动设置，仍只是在用户登录后启动 App，不实现退出后的后台服务。
- 数据导出和隐私脱敏诊断包。
- 更完善的解析 fixture 管理。

验收标准：

- 用户能判断失败原因并执行重新登录、手动同步或导出诊断。
- 开机启动关闭时行为仍符合“不启动 App 就不后台同步”。

## 风险和缓解

- Windows WebView Cookie 提取不稳定：提供手动 Cookie 导入作为第一阶段必须 fallback；登录成功后统一用 `auth.checkAuth` 验证。
- 学习通页面结构变化：解析器使用 fixture 测试覆盖关键页面；解析失败进入 failures，不中断整体同步。
- 学习通风控或验证码：不绕过风控；降低自动同步频率，提示用户重新登录或稍后重试。
- Cookie 安全风险：只存安全存储，日志脱敏，限制带 Cookie 请求域名。
- 通知重复轰炸：用 `itemId + remindRule + dueAtSnapshot` 去重，重复提醒设置最大次数，支持暂停通知和免打扰。
- 只靠收件箱漏项：阶段 2 增加课程空间、作业列表和考试列表。
- App 退出后用户误以为仍会提醒：UI 和托盘文案明确“退出后不再同步”，关闭窗口只隐藏到托盘。
- Dart 与 TypeScript 行为不一致：用同一 fixture 对照核心模型字段，迁移时优先保持现有 `SyncItem` 语义。

## 自检

- 已覆盖目标、非目标、架构、模块边界、登录/Cookie 流程、数据流、提醒/通知规则、Windows 托盘行为、配置/存储、安全、错误处理、测试策略、阶段划分和风险。
- 文档明确运行时不依赖 Cloudflare Worker、Bun、Node helper；TypeScript Worker 逻辑只作为迁移参考。
- 文档明确第一阶段从收件箱通知入手，第二阶段补课程空间、作业列表、考试列表。
- 文档明确关闭窗口最小化到托盘、托盘运行时继续同步通知、真正退出后不做后台同步。
- 文档明确登录 Cookie 采集流程和 Windows WebView Cookie 提取不稳定时的手动导入 fallback。
- 文档未保留占位内容。
