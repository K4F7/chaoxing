# 学习通作业考试待办

这个项目会从学习通收件箱中识别作业和考试通知，解析开始/截止时间，并输出给日历、待办客户端和自用 Flutter App。

## 项目结构

- `src/`：Cloudflare Worker 后端，负责认证检查、收件箱抓取、作业/考试解析、同步接口。
- `scripts/`：本地登录、调试和同步辅助脚本。
- `tests/`：Worker 单元测试。
- `apps/chaoxing_app/`：Flutter 自用 App，支持 Android 和 macOS。

## 准备 Bun

本项目的 Worker 部分使用 Bun：

```sh
bun --version
bun install
```

## 配置学习通 Cookie

推荐运行登录引导：

```sh
bun run auth:login
```

脚本会打开一个独立 Chrome 登录窗口。登录成功后，会把 `CHAOXING_COOKIE` 写入本地 `.dev.vars`。

也可以手动复制 `.dev.vars.example` 为 `.dev.vars`，填入：

```sh
CHAOXING_COOKIE="..."
RUN_TOKEN="..."
```

不要把 `.dev.vars` 提交到 Git。

## Worker 本地开发

启动 Worker：

```sh
bun run dev
```

认证检查：

```sh
curl -H "Authorization: Bearer $RUN_TOKEN" \
  http://localhost:8787/auth/check
```

获取完整处理结果：

```sh
curl -H "Authorization: Bearer $RUN_TOKEN" \
  "http://localhost:8787/process?inboxLimit=100&detailsLimit=10&requirementsLimit=40"
```

获取标准化同步数据：

```sh
curl -H "Authorization: Bearer $RUN_TOKEN" \
  "http://localhost:8787/sync?inboxLimit=100&detailsLimit=10&requirementsLimit=40"
```

Flutter App 使用的轻量接口：

```sh
curl -H "Authorization: Bearer $RUN_TOKEN" \
  "http://localhost:8787/app/sync?inboxLimit=100&detailsLimit=10&requirementsLimit=40"
```

`/app/sync` 返回：

- `items`：作业/考试列表，包含标题、类型、来源、开始时间、截止时间、状态和链接。
- `lastSyncedAt`：本次同步完成时间。
- `failures`：抓取失败的作业/考试链接。
- `authStatus`：当前 Worker 认证状态，第一版为 `ok`。

## 日历和待办订阅

日历订阅：

```text
http://localhost:8787/calendar.ics?token=$RUN_TOKEN
```

待办订阅：

```text
http://localhost:8787/todos.ics?token=$RUN_TOKEN
```

CalDAV 服务：

```text
https://your-worker-domain/caldav/
```

认证方式：

- 用户名：任意，例如 `chaoxing`
- 密码：`RUN_TOKEN`

集合路径：

- 截止日期日历：`/caldav/calendars/me/deadlines/`
- 待办：`/caldav/calendars/me/todos/`

## Google Calendar 同步

配置单独日历 ID：

```sh
GOOGLE_CALENDAR_ID="your_calendar_id_or_primary"
```

OAuth 登录：

```sh
bun run google:login
```

手动同步：

```sh
curl -H "Authorization: Bearer $RUN_TOKEN" \
  "http://localhost:8787/google/calendar/sync?inboxLimit=100&detailsLimit=10&requirementsLimit=40"
```

部署到 Cloudflare 后，`wrangler.jsonc` 里的 Cron Trigger 会每小时自动处理一次。

## Flutter App

App 位于：

```sh
apps/chaoxing_app
```

运行 macOS 版：

```sh
cd apps/chaoxing_app
flutter run -d macos
```

运行 Android 版：

```sh
cd apps/chaoxing_app
flutter run -d android
```

首次打开 App 后填写：

- Worker URL，例如 `https://your-worker.workers.dev`
- `RUN_TOKEN`
- 刷新间隔

App 会调用 `/app/sync`，并在本地缓存上次同步结果。无网络时仍可查看缓存中的作业和考试。

第一版 App 提供：

- 待办列表：区分已过期、今日截止和未来待办。
- 作业考试日历：按截止日期展示。
- 详情页：展示标题、状态、来源、开始/截止时间和原始学习通链接。
- 课程表入口：占位保留，后续可接入真实课程表抓取或手动录入。

## 部署

生成 Worker 类型：

```sh
bun run types
```

写入 Cloudflare secrets：

```sh
bunx wrangler secret put CHAOXING_COOKIE
bunx wrangler secret put RUN_TOKEN
bunx wrangler secret put GOOGLE_OAUTH_CLIENT_ID
bunx wrangler secret put GOOGLE_OAUTH_CLIENT_SECRET
bunx wrangler secret put GOOGLE_OAUTH_REFRESH_TOKEN
bunx wrangler secret put GOOGLE_SERVICE_ACCOUNT_JSON
```

部署：

```sh
bun run deploy
```

## 验证

Worker：

```sh
bun run typecheck
bun test
```

Flutter：

```sh
cd apps/chaoxing_app
flutter analyze
flutter test
```
