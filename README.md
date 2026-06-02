# Chaoxing Auth Check Worker

第一阶段只验证学习通 Cookie 认证是否跑通，不抓收件箱，也不发邮件。

## 准备 Bun

本项目只使用 Bun，不使用 npm。确认命令：

```sh
bun --version
```

如果当前 shell 找不到 `bun`，先安装 Bun 或把 Bun 所在目录加入 `PATH`。

## 安装依赖

```sh
bun install
```

## 推荐启动流程

```sh
bun run start
```

这个命令会先验证 `.dev.vars` 里的 `CHAOXING_COOKIE`：

- Cookie 可用：直接提示可以进入主界面。
- Cookie 缺失或过期：自动打开一个独立的 Chrome 登录窗口。
- 你在窗口里完成学习通扫码、验证码或账号登录后，程序会自动提取新的学习通 Cookie，写回 `.dev.vars`，然后继续启动流程。

这个 Chrome 窗口使用项目本地的 `.auth/chrome-profile`，不会读取你日常 Chrome 的 Cookie。

## 自动获取学习通 Cookie

也可以只运行登录引导：

```sh
bun run auth:login
```

登录成功后，脚本会更新 `.dev.vars` 里的 `CHAOXING_COOKIE`。如果现有 Cookie 已经可用，脚本会直接退出，不会打开浏览器。

## 手动获取学习通 Cookie

1. 在浏览器登录学习通。
2. 打开 DevTools 的 Network 面板。
3. 刷新 `https://i.chaoxing.com/base?ws=1&t=1780231212848`。
4. 找到发往 `i.chaoxing.com` 的请求，复制完整 `Cookie` 请求头值。
5. 复制 `.dev.vars.example` 为 `.dev.vars`，填入 `CHAOXING_COOKIE`。

不要把 `.dev.vars` 提交到 Git。

## 本地认证检查

```sh
bun run auth:check
```

结果里不会输出完整 Cookie。

- `authenticated: true`：Cookie 仍有效。
- `authenticated: false` 且 `failureReason: "missing CHAOXING_COOKIE"`：没有配置 Cookie。
- `authenticated: false` 且 `failureReason: "redirected_or_rendered_login_page"`：Cookie 无效或已过期。

## Worker 手动接口

本地启动：

```sh
bun run dev
```

调用认证接口：

```sh
curl -H "Authorization: Bearer $RUN_TOKEN" \
  http://localhost:8787/auth/check
```

接口只支持 `GET /auth/check`，并用 `RUN_TOKEN` 保护。

手动触发一次收件箱和作业要求处理：

```sh
curl -H "Authorization: Bearer $RUN_TOKEN" \
  "http://localhost:8787/process?inboxLimit=100&detailsLimit=10&requirementsLimit=40"
```

`/process` 支持 `GET` 和 `POST`，返回本次抓到的相关通知数量、作业链接数量、作业要求解析结果和失败项。

获取可同步到日历/待办的数据：

```sh
curl -H "Authorization: Bearer $RUN_TOKEN" \
  "http://localhost:8787/sync?inboxLimit=100&detailsLimit=10&requirementsLimit=40"
```

`/sync` 会在 `/process` 的结果上额外返回 `syncItems`，其中包含标准化后的作业/考试标题、来源、链接、开始时间和截止时间。

日历订阅地址：

```text
http://localhost:8787/calendar.ics?token=$RUN_TOKEN
```

待办订阅地址：

```text
http://localhost:8787/todos.ics?token=$RUN_TOKEN
```

很多日历客户端订阅 URL 时不能设置 `Authorization` 请求头，所以 `.ics` 接口支持 `?token=` 或 `?access_token=`。公开部署时不要把带 token 的订阅地址分享给别人。

说明：

- `/calendar.ics` 输出 `VEVENT`，每个作业/考试会以截止时间生成一个日历事件。
- `/todos.ics` 输出 `VTODO`，支持 VTODO 的待办客户端可以按截止时间显示待办。
- 如果某条通知没有解析出截止时间，它不会进入 `.ics`，但仍会保留在 `/process` 结果里。

## Google Calendar 同步

推荐使用用户 OAuth 授权：它会弹出浏览器让你登录 Google 并同意 Calendar 权限，然后把 refresh token 写入 `.dev.vars`。Worker 后续会用 refresh token 自动刷新 access token。

先在 Google Cloud 里启用 Calendar API，配置 OAuth consent screen，然后创建一个 OAuth Client。客户端类型可以选 Desktop app，下载 JSON 后保存为项目根目录的 `google-oauth-client.json`。

推荐用单独日历，例如“学习通作业考试”，不要直接写入主日历。拿到日历 ID 后，本地 `.dev.vars` 先配置：

```sh
GOOGLE_CALENDAR_ID="your_calendar_id_or_primary"
```

然后运行：

```sh
bun run google:login
```

脚本会打开浏览器，授权完成后写入：

- `GOOGLE_OAUTH_CLIENT_ID`
- `GOOGLE_OAUTH_CLIENT_SECRET`
- `GOOGLE_OAUTH_REFRESH_TOKEN`

手动同步到 Google Calendar：

```sh
curl -H "Authorization: Bearer $RUN_TOKEN" \
  "http://localhost:8787/google/calendar/sync?inboxLimit=100&detailsLimit=10&requirementsLimit=40"
```

这个接口会：

1. 抓取学习通作业/考试通知。
2. 把有截止时间的条目转换成 Google Calendar 事件。
3. 用稳定事件 ID 创建或更新事件，避免重复写入。

部署到 Cloudflare 后，定时任务也会在检测到 `GOOGLE_CALENDAR_ID` 和 Google OAuth 或 service account 凭据时自动同步。

也支持 Service Account：创建 Service Account 和 JSON key 后，在 Google Calendar 的日历设置里，把目标日历共享给 service account 的 `client_email`，权限给“更改活动”。然后配置：

```sh
GOOGLE_CALENDAR_ID="your_calendar_id_or_primary"
GOOGLE_SERVICE_ACCOUNT_JSON='{"client_email":"...","private_key":"-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"}'
```

## CalDAV 同步

Worker 也提供只读 CalDAV，可以把截止日期同步到支持 CalDAV 的日历/待办客户端，不需要 Google Cloud 或 OAuth。

服务地址：

```text
https://chaoxing-auth-check.1901603866.workers.dev/caldav/
```

认证方式：

- 用户名：任意，例如 `chaoxing`
- 密码：`.dev.vars` 或 Cloudflare secret 里的 `RUN_TOKEN`

集合路径：

- 截止日期日历：`/caldav/calendars/me/deadlines/`
- 待办：`/caldav/calendars/me/todos/`

macOS/iOS 可以添加“其他 CalDAV 账号”，服务器填 Worker 域名，账号 URL 如果客户端支持可直接填完整 `/caldav/` 地址。某些客户端不支持待办 `VTODO`，这种情况下会只显示日历事件。

## Worker 自动处理

`wrangler.jsonc` 已配置 Cloudflare Cron Triggers：

```json
"triggers": {
  "crons": ["0 * * * *"]
}
```

部署后 Worker 会每小时自动执行一次处理流程，并把摘要写入 Cloudflare Worker 日志。默认处理范围：

- `PROCESS_INBOX_LIMIT=100`
- `PROCESS_DETAILS_LIMIT=10`
- `PROCESS_REQUIREMENTS_LIMIT=40`

这些值可以在 `wrangler.jsonc` 的 `vars` 里调整。

## Cloudflare Secrets

部署前把敏感值写入 Cloudflare secrets：

```sh
bunx wrangler secret put CHAOXING_COOKIE
bunx wrangler secret put RUN_TOKEN
bunx wrangler secret put GOOGLE_OAUTH_CLIENT_ID
bunx wrangler secret put GOOGLE_OAUTH_CLIENT_SECRET
bunx wrangler secret put GOOGLE_OAUTH_REFRESH_TOKEN
bunx wrangler secret put GOOGLE_SERVICE_ACCOUNT_JSON
```

如果不用 `GOOGLE_SERVICE_ACCOUNT_JSON`，也可以分别写入：

```sh
bunx wrangler secret put GOOGLE_SERVICE_ACCOUNT_EMAIL
bunx wrangler secret put GOOGLE_PRIVATE_KEY
```

日历 ID 不是密钥，可以放在 `wrangler.jsonc` 的 `vars`，也可以作为 secret：

```sh
bunx wrangler secret put GOOGLE_CALENDAR_ID
```

生成 Worker 类型：

```sh
bun run types
```

部署：

```sh
bun run deploy
```

## 验证

```sh
bun run typecheck
bun test
```

认证跑通后，下一阶段再定位学习通收件箱真实页面或接口。

## 本地获取收件箱

认证通过后，可以先在本地抓取收件箱，不经过 Worker：

```sh
bun run inbox:fetch --limit=5
```

这个命令会：

1. 使用 `.dev.vars` 里的 `CHAOXING_COOKIE` 请求个人空间。
2. 自动定位 `notice.chaoxing.com/pc/notice/myNotice` 收件箱入口。
3. 请求 `POST https://notice.chaoxing.com/pc/notice/getNoticeList`。
4. 输出标准化后的消息列表：标题、发件人、发送时间、已读状态、正文摘要和详情链接。

调试接口发现过程可以运行：

```sh
bun run inbox:probe
```

探测 HTML 和接口响应会保存到 `/tmp/chaoxing-probe`，不会写入项目目录。

## 本地获取作业要求

先抓取收件箱详情，提取作业/考试详情入口：

```sh
bun run inbox:details --limit=100 --details=92
```

再抓取去重后的作业要求：

```sh
bun run assignments:requirements --limit=40
```

结果会写入 `/tmp/chaoxing-probe/assignment-requirements.json`，包含来源通知、作业页面状态、作答时间、题型、题干和题干图片。脚本只在本地使用 `.dev.vars` 里的 Cookie，不经过 Worker。
