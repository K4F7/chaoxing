# Product Requirements Document: 学习通本地同步与 Windows App 工具

**Version**: 1.0
**Date**: 2026-06-09
**Author**: Sarah (Product Owner)
**Quality Score**: 94/100

---

## Executive Summary

本 PRD 定义“学习通作业/考试待办”的本地化 App 与 Windows 工具形态：用户在本机保存学习通 Cookie，由 Flutter App 直接同步学习通收件箱、通知详情和作业/考试页面，生成即将到来的作业和考试列表，并在 Windows 上提供持续同步与提醒能力。

Phase 1 MVP 已完成核心迁移：Flutter App 已从 Worker URL + RUN_TOKEN 客户端迁移为本地学习通 Cookie 同步；Windows 平台目录已生成；Windows release build 已通过。当前 App 已具备认证检查、收件箱定位/分页、通知关键词筛选、详情链接提取、作业/考试时间解析、`AppSyncResponse` 构建、排序、`displayStatus`、`dueInHours` 等本地同步能力。

后续 Phase 2/3 聚焦把 Windows 工具形态补完整，包括真实 Windows toast、系统托盘、内置登录或 Cookie 自动导入、课程空间/考试列表补漏、Windows CI 与打包发布。安全要求贯穿所有阶段：Cookie 必须进入安全存储，带 Cookie 请求必须受学习通域名 allowlist 和重定向校验约束，错误与诊断信息必须脱敏。

---

## Problem Statement

**Current Situation**: 用户需要及时看到学习通即将截止的作业和考试。早期架构依赖 Cloudflare Worker、Bun/Node helper 或 `/app/sync` 远端接口，对个人本地使用和 Windows 常驻提醒不够直接；同时，只依赖收件箱通知可能漏掉课程空间中存在但未发通知的作业或考试。

**Proposed Solution**: 将学习通同步链路迁移到 Flutter/Dart 本地实现，在 App 内安全保存学习通 Cookie，直接访问学习通可信域名并解析作业/考试数据；在 Windows 上提供桌面工具形态，支持定时刷新、提醒去重、系统通知和托盘常驻。

**Business Impact**: 对个人用户而言，减少漏交作业或错过考试的风险；对项目维护而言，降低 Worker 部署、密钥管理和远端依赖成本；对后续扩展而言，统一 App、Windows 工具、提醒与诊断能力的产品边界。

---

## Success Metrics

**Primary KPIs:**
- 本地同步可用率：在有效学习通 Cookie 下，App 能完成收件箱同步并返回标准化 `AppSyncResponse`；通过 fixture 单元测试和后续真实账号端到端验证衡量。
- 提醒准确性：同一 `itemId + remindRule + dueAtSnapshot` 不重复提醒；作业和考试能按截止时间计算 `displayStatus` 和 `dueInHours`；通过提醒调度测试和 Windows 手动验证衡量。
- 安全合规性：Cookie 不出现在 shared_preferences、UI 回填、日志、诊断导出或非学习通请求中；通过代码审核、测试和安全检查清单衡量。
- Windows 可交付性：`flutter build windows` 成功生成 release exe；通过构建命令和产物路径验证。

**Validation**:
- Worker 验证：`bun run typecheck`、`bun test` 已通过，共 32 tests。
- Flutter 验证：`flutter analyze`、`flutter test` 已通过，共 23 tests。
- Windows 构建验证：`flutter build windows` 已通过。
- Windows 构建产物：`apps/chaoxing_app/build/windows/x64/runner/Release/chaoxing_app.exe`。
- 剩余验证：尚未使用真实学习通账号完成端到端网络同步；Windows toast 和托盘仍需实现并手动验收。

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
- [ ] 使用真实学习通账号完成端到端网络同步验收。

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
- [x] Cookie-bearing 请求在 Flutter 侧限制为 `https://chaoxing.com` 和 `https://*.chaoxing.com`。
- [x] Cookie-bearing 请求在 Worker 侧同样限制为 `https://chaoxing.com` 和 `https://*.chaoxing.com`。
- [x] 手动校验 redirect，避免自动跟随到非 allowlist 域名并携带 Cookie。
- [x] 错误信息和诊断摘要不得包含 Cookie 明文。
- [x] 手动 Cookie 输入保存成功后不在设置页明文回填。
- [ ] 诊断导出功能需继续确保 URL query token、Cookie 片段、个人敏感字段脱敏。

### Story 4: 补漏课程空间和考试列表

**As a** 学习通学生  
**I want to** App 不只依赖收件箱通知，还能检查课程空间和考试列表  
**So that** 未发通知或通知被清理的作业/考试也能进入待办

**Acceptance Criteria:**
- [ ] App 能抓取课程空间中的课程/班级列表。
- [ ] App 能抓取课程作业列表并解析未完成作业、入口 URL 和截止时间。
- [ ] App 能抓取考试/测验列表并解析可作答状态、入口 URL 和截止时间。
- [ ] 同一事项来自收件箱和课程列表时不重复展示、不重复提醒。
- [ ] item 保留来源列表，例如 inbox、course_work、course_exam。

### Story 5: 打包、发布和回归验证

**As a** 项目维护者  
**I want to** 有稳定的 Windows CI、打包和验证流程  
**So that** 每次修改后都能确认 Windows App 可交付

**Acceptance Criteria:**
- [ ] CI 增加 Windows job，至少运行 `flutter analyze`、`flutter test`、`flutter build windows`。
- [ ] 发布产物包含 Windows release exe 或安装包。
- [ ] 发布说明明确 Cookie 存储、安全边界、真实账号端到端验证状态和已知限制。
- [ ] 打包流程不包含 `.dev.vars`、真实 Cookie、个人账号数据或 fixture 中的敏感内容。

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
- Current status: 自动刷新定时器、提醒去重结构已完成；真实 Windows toast 和托盘未完成。

**Feature 5: Windows toast 与托盘工具形态**
- Description: Windows App 关闭窗口后隐藏到托盘并继续按进程内定时器运行；系统通知用于提醒截止事项。
- User flow: 用户启动 App -> 登录并同步 -> 关闭窗口 -> App 隐藏到托盘 -> 定时同步和通知继续 -> 用户从托盘恢复或退出。
- Edge cases: 用户真正退出、Windows 通知权限不足、托盘插件初始化失败、重复点击立即同步。
- Error handling: 退出后停止定时器和通知；托盘/通知失败需要有错误摘要和可恢复入口。
- Current status: Phase 2 必做，尚未完成真实 Windows toast 和托盘。

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
- UI 应优先展示缓存结果；网络失败或认证失败时不得清空已缓存 items。

### Security

- Cookie 必须保存到 `flutter_secure_storage` 或等价平台安全存储，不得保存到 shared_preferences、日志、诊断导出、通知正文或 UI 明文回填。
- 普通配置、同步缓存、提醒历史、提醒配置可以保存到 `shared_preferences`。
- 所有带 Cookie 请求必须使用统一 HTTP 客户端，并限制目标为 `https://chaoxing.com` 或 `https://*.chaoxing.com`。
- Flutter 侧和 Worker 侧均需保持 Cookie-bearing request allowlist。
- Redirect 必须手动校验；不得自动跟随到非 allowlist 域名并继续携带 Cookie。
- 错误摘要、失败列表、诊断导出必须脱敏 Cookie、token、个人敏感 query 和可能包含账号信息的正文。
- 手动 Cookie 输入不得接受换行注入；保存成功后清空输入框。

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
- Cookie-bearing 请求在 Flutter 和 Worker 两侧均限制 `https://chaoxing.com` / `https://*.chaoxing.com`，并手动校验 redirect。
- Windows 工具第一阶段已实现自动刷新定时器和提醒去重结构。
- 验证已通过：`bun run typecheck`、`bun test`、`flutter analyze`、`flutter test`、`flutter build windows`。

**MVP Definition**: 在不依赖 Worker runtime 的前提下，Flutter App 能用本机学习通 Cookie 同步并展示作业/考试待办，Windows release build 可生成，核心安全边界和测试验证已到位。

### Phase 2: Windows 工具补齐和本地登录增强

- 实现真实 Windows toast 通知，支持通知点击打开 App 或定位详情。
- 实现 Windows 系统托盘，支持打开窗口、立即同步、暂停/恢复通知、查看登录状态、退出。
- 实现关闭窗口隐藏到托盘，托盘运行时继续同步，托盘退出后停止同步和通知。
- 提供内置登录或 Cookie 自动导入能力；保留手动 Cookie 导入 fallback。
- 增加真实学习通账号端到端网络同步验证。
- 增加 Windows CI job，覆盖 analyze/test/build。
- 增加 Windows 打包发布流程。

### Phase 3: 数据源补漏和诊断增强

- 抓取课程空间课程/班级列表。
- 抓取课程作业列表，补齐未发通知或通知被清理的作业。
- 抓取考试/测验列表，补齐未发通知或通知被清理的考试。
- 多数据源合并，避免重复展示和重复提醒。
- 增加诊断页面和脱敏诊断导出。
- 完善 fixture 管理和真实账号回归流程。

---

## Risk Assessment

| Risk | Probability | Impact | Mitigation Strategy |
|------|-------------|--------|---------------------|
| 没有真实学习通账号端到端网络同步验证 | High | High | Phase 2 将真实账号 E2E 验收列为必做；保留 fixture 测试作为回归基础，但不能替代真实网络验收。 |
| Windows toast/托盘插件兼容性问题 | Medium | High | 先实现抽象层和 fake 测试，再做 Windows 手动验收；CI 增加 Windows build；失败时提供降级错误摘要。 |
| 学习通页面结构变化导致解析失败 | Medium | High | 使用 fixture 覆盖关键页面；局部失败进入 failures；诊断导出脱敏后辅助定位；Phase 3 扩展多数据源补漏。 |
| Cookie 泄漏到第三方域名、日志或诊断文件 | Low | High | 统一 HTTP 客户端 allowlist、手动 redirect 校验、secure storage、错误脱敏、安全审核清单。 |
| 只依赖收件箱导致漏项 | High | Medium | Phase 3 增加课程空间、作业列表、考试列表补漏，并以稳定业务 ID 合并。 |
| 通知重复轰炸 | Medium | Medium | 已实现提醒去重结构；后续 Windows toast 接入时必须使用 `itemId + remindRule + dueAtSnapshot` 写入历史。 |
| 风控、验证码或登录失效 | Medium | Medium | 不绕过风控；认证失败提示重新登录；降低自动同步频率；缓存保留。 |
| Windows 打包产物包含敏感数据 | Low | High | 发布流程显式检查 `.dev.vars`、真实 Cookie、个人 fixture；CI/打包脚本不得注入本地 secrets。 |

---

## Dependencies & Blockers

**Dependencies:**
- Flutter Windows desktop 工具链：用于 `flutter build windows` 和后续 CI。
- 学习通账号与有效 Cookie：用于真实端到端网络同步验收。
- Windows 通知和托盘插件：用于 Phase 2 工具形态补齐。
- 学习通页面/API 稳定性：影响收件箱、详情、作业/考试页、课程空间和考试列表解析。
- CI 环境：需要 Windows runner 执行 Flutter analyze/test/build。

**Known Blockers:**
- 真实学习通账号端到端验收尚未完成：当前只能确认 fixture、单元测试和构建通过。
- 真实 Windows toast 尚未完成：无法验证系统通知显示、点击行为和通知权限问题。
- 系统托盘尚未完成：无法验证关闭隐藏、托盘菜单和真正退出后的进程行为。
- 内置登录或 Cookie 自动导入尚未完成：当前仍需依赖已有 Cookie 同步路径或手动输入能力。
- 课程空间/考试列表补漏尚未完成：当前仍有只靠收件箱通知漏项的产品风险。

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

Expected: analyze pass; 23 tests pass; Windows release build pass.

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
