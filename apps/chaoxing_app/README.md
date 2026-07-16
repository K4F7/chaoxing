# 学习通待办 App

Flutter Windows 桌面客户端。本 App 在本机使用学习通 Cookie 同步收件箱里的作业和考试待办，并可选择从课程空间补抓作业/考试列表，不再把 Worker URL 或 RUN_TOKEN 作为 App 的主配置入口。

## 首次配置

1. 在 Windows App 首页点击“登录学习通”。
2. 在内置登录窗口完成登录，进入学习通后点击右上角“完成登录”。
3. App 会从 WebView2 Cookie Store 导入登录态、写入本机安全存储并自动同步。
4. 如需补抓未发通知的事项，在设置中启用“课程空间补充同步”并设置最多扫描课程数。

如果内置登录不可用，仍可在“手动导入 Cookie”中粘贴已登录请求的 Cookie header。

Cookie 只会发送给 App 明确列出的学习通 HTTPS 主机，保存位置是本机安全存储。设置页不会回填完整 Cookie；已经保存时只显示“已保存 Cookie”，输入框保持为空。可以覆盖或明确清除旧 Cookie。

## Windows 运行

推荐使用 Scoop 安装 Flutter，并启用 Windows 桌面支持：

```powershell
scoop install flutter
flutter config --enable-windows-desktop
flutter doctor
```

内置登录需要 Microsoft Edge WebView2 Runtime。Windows 10/11 通常已经安装；缺失时 App 会显示明确错误。

在 App 目录运行：

```sh
cd apps/chaoxing_app
flutter pub get
flutter run -d windows
```

## Windows 构建

```sh
cd apps/chaoxing_app
flutter build windows
```

构建产物位于：

```text
build/windows/x64/runner/Release/
```

GitHub Actions 会在 Windows runner 上执行 `flutter analyze`、`flutter test` 和
`flutter build windows --release`，然后把完整的 Release 目录打包为
`chaoxing-app-windows-x64.zip`。main 分支推送构建还会在同一个 GitHub Release
中发布 Windows 压缩包和 Android APK；功能分支、PR 和手动触发只上传临时
artifact，不创建正式 Release。正式 Release 还会生成覆盖 APK 与 Windows ZIP
的 `SHA256SUMS`，并使用 GitHub Actions `run_number` 作为 Android versionCode
和 Windows build suffix；同一分支的新构建会取消仍在运行的旧构建。

两个平台的产物在上传前都会执行内容审计：拒绝 `.dev.vars`、环境文件、
测试/fixture 目录以及本地运行时数据库进入发布包。CI 只从干净 checkout
构建，不会注入本机 Cookie 或账号缓存。

Android 正式发布需要仓库 Secrets `ANDROID_KEYSTORE_BASE64` 和
`ANDROID_KEY_PROPERTIES_BASE64`。前者是固定 upload keystore 的 Base64，后者
是 `key.properties` 的 Base64（其中 `storeFile=upload-keystore.jks`）。main
缺少密钥会直接失败；本地、功能分支和 PR 无密钥时只生成 debug-signed 临时
APK。所有 APK 上传前都会执行 `apksigner verify`，keystore 与属性文件被忽略且
不会进入 artifact。

Android 包名、namespace 和入口 Activity 统一为 `com.sein.chaoxingapp`；CI 在
构建前检查 Gradle、Manifest 与 Kotlin package 一致，避免 APK 构建成功但启动时
找不到 `.MainActivity`。

Android Manifest 显式关闭系统备份和明文网络，只声明 HTTPS 外部浏览能力；普通
待办缓存与提醒历史不会通过 Android backup 迁移，HTTP query 也不能绕过 App 的
统一 URL 策略。CI 会持续检查这三项约束。

## 安全边界与已知限制

- Cookie Store 会连同域、路径、Secure 和 host-only 作用域一起保存在设备安全存储中，不会写入普通配置、同步缓存或发布产物；旧的手动 Cookie 字符串仍兼容。
- 手动 Cookie Source 只要包含 CR/LF 换行就整份拒绝，不会静默保留其中一部分、发起认证或写入安全存储；设置页会显示安全校验原因，其他保存异常仅显示通用错误，不渲染底层敏感信息。
- 从旧版或替换存储加载到不安全 Cookie 时，控制器会在内存中隔离该值、视为未配置并要求重新登录，同时通过专用存储操作删除该凭据而不改其他设置；不会启动同步、传给自定义 fetcher 或在提示中回显原文。平台凭据删除暂时失败时，内存隔离仍然生效。
- 带 Cookie 的请求只允许访问 App 显式列出的学习通主机，会按目标主机和路径筛选 Cookie、吸收每一跳的 `Set-Cookie`，并校验每次重定向目标。
- 详情页交给系统浏览器的外链也必须命中同一显式学习通 HTTPS allowlist；缓存中第三方、HTTP 或畸形 URL 的按钮会禁用，启动失败只显示通用提示，不回显完整链接。
- 可信请求主机、Cookie Domain、WebView 顶层导航和详情外链共用独立 URL 策略模块；Cookie Domain 额外允许根域作为作用域，实际请求仍只允许显式主机，避免多个模块的 allowlist 漂移。
- 内置登录拒绝弹窗和浏览器权限请求，顶层页面离开可信学习通主机时会停止导航并返回登录页。
- 设置页不会回填 Cookie，错误摘要也会对 Cookie 等敏感内容脱敏。
- 已使用真实学习通账号完成登录、Cookie 自动导入、通知/课程同步和耗时统计验证。
- Windows 系统通知和托盘常驻已经接入；关闭窗口会隐藏到托盘，选择“退出”后才结束进程。
- Windows runner 使用用户会话级命名 Mutex 保证单实例；重复启动不会创建第二套托盘、同步定时器或通知服务，并会尝试恢复、聚焦已有主窗口。
- 正式提醒去重历史在每轮提醒处理前自动清理：保留最近 90 天、最多 1000 条，并丢弃异常未来时间；正常的 `itemId + kind + dueAtSnapshot` 去重不受影响，长期托盘运行不会无限扩大偏好数据。
- 关闭隐藏并保持后台进程、测试通知后端调用均已在真实 Windows 环境验证；通知肉眼可见性、点击打开详情和托盘菜单/退出仍需手动验收。
- 设置页提供“发送测试通知”，可重复验证 Windows 通知显示以及点击后恢复主窗口，不写入正式提醒去重历史。
- “课程空间补充同步”默认开启；会优先使用当前课程列表接口，并在失败时回退旧接口，抓取的作业和考试按业务 ID 与收件箱结果合并。可在设置中关闭。
- 课程列表与详情页会过滤明确标记为已完成、已提交/待批阅、已过期/已结束或只能查看/预览的事项；状态不明确的事项仍会保留，避免误删真正待办。
- 课程任务接口和页面结构可能变化；单通知、单课程或单任务失败会写入诊断但不阻断其他来源。未识别到截止时间的事项会保留在独立分组中。
- 通知详情、收件箱任务详情和课程任务详情最多 6 路并发；课程列表按 3 门课程并发、每门作业/考试两个列表并行，因此总列表请求不超过 6。并发抓取后仍按原课程顺序应用条目上限。真实账号验证表明提高到 8 路会触发明显拥塞和失败，因此保持 6 路。
- 同步界面会显示认证、通知、详情和课程扫描阶段；每条请求（包含其完整重定向链）共享默认 20 秒总超时，避免重定向逐跳重复计时导致导入长期等待。
- 启动时若本地缓存是在 5 分钟内生成，直接展示缓存并等待定时刷新；用户仍可手动刷新，避免频繁重启造成重复全量同步和服务端限流。
- 一次同步成功或部分成功后，60 秒内重复点击手动刷新会显示剩余等待时间；配置变更、失败后的重试和后台定时刷新不受影响，避免连续操作扩大短期限流。
- 每次默认同步和登录校验使用独立 HTTP 客户端并在完成后关闭；从托盘明确退出时会关闭仍活跃的客户端，使未完成的真实网络请求随进程退出路径停止。
- 重新登录或保存新的同步配置时会立即关闭旧配置仍在运行的默认客户端，并排队启动新配置同步；旧结果继续被丢弃，避免新 Cookie 长时间等待旧账号抓取结束。
- 同步失败摘要出现 HTTP 429、Too Many Requests、请求过频或限流信号时，客户端进入 5 分钟内存退避；期间手动刷新显示剩余时间，静默刷新直接跳过，保存新配置会清除旧账号退避。
- App 重启时会根据缓存中的同步时间和限流失败恢复剩余退避，同时恢复一分钟内的手动刷新冷却；未来时间戳会被忽略，避免异常缓存造成无限等待。
- 配置在存储读取、保存以及控制器加载/应用边界统一规范化：通知页数 1–20、条目数 1–500、课程数 1–100，非法低值恢复安全默认；自动刷新允许 0 表示关闭，否则限制为 15–180 分钟。旧版、损坏偏好或替换的存储实现都不能绕过请求上限。

## 同步诊断

主界面右上角的“诊断”入口会显示认证状态、最近同步、同步总耗时以及认证/通知/通知详情/任务详情/课程五个阶段耗时，还会显示收件箱/课程发现链接、完成状态过滤、可行动去重项、待办数量和最近失败。待办为空时会给出分阶段原因判断，底部“复制脱敏诊断”按钮始终可见。
同步返回部分结果但存在阶段失败时，主界面会直接显示失败数量和“查看诊断”入口；提示不展示课程名、失败 URL 或错误正文，避免用户把不完整结果误认为完整同步。
“复制脱敏诊断”只导出运行摘要与失败摘要，不包含 Cookie、通知正文或完整敏感
query。导出前会统一隐藏 token、Bearer、Cookie 片段和账号类参数；发送给他人前仍建议
人工检查一次内容。

## 开发验证

在仓库根目录运行 Worker/TypeScript 侧验证：

```sh
bun run typecheck
bun test
```

在 App 目录运行 Flutter 侧验证：

```sh
flutter analyze
flutter test
flutter build windows
```

## 旧配置说明

早期版本通过 Cloudflare Worker 的 `/app/sync` 接口同步，并需要 Worker URL 与 RUN_TOKEN。当前 Windows App 的主路径已经迁移为本地 Cookie 同步；检测到旧 Worker 配置时，App 只提示旧配置已不再使用，保存本地 Cookie 后会清理旧值。
