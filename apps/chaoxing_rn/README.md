# 学习通待办（React Native / Android）

Expo 57 应用。生产形态仍是 Flutter；这一轮在 Android 上补齐应用内登录、Cookie 安全存储和可见的[认证失效](../../CONTEXT.md)。

提醒规则与 URL 信任分级来自 [`packages/chaoxing-domain`](../../packages/chaoxing-domain)。课程同步 / 解析和预排闹钟由并行工作流负责，本应用只提供它们能消费的会话接口。

## Android 应用内登录

1. 未配置时首页提供「登录学习通」和「手动导入 Cookie」。
2. 登录页用 WebView 打开 `https://passport2.chaoxing.com/login`，顶层导航只允许[可信学习通主机](../../CONTEXT.md)。离开白名单会停导航并回到登录页。
3. 用户点「完成登录」后，从 Android `CookieManager` 读取 **name / value / domain / path**（没有 Secure、host-only，与 Flutter Android 侧约定一致），编码为 `chaoxing-cookie-store-v1` 或兼容的扁平 Cookie 字符串。
4. 必须带有身份 Cookie（`UID` / `vc3` 等）才会保存。可选的首页探测拒绝仍停在登录页的会话。
5. 内置登录失灵时，手动导入整份拒绝含换行的输入；保存成功后清空输入，界面不回填 Cookie。

## Cookie 安全存储

- 只写入 `expo-secure-store`（Android Keystore / EncryptedSharedPreferences）。
- 不写普通 SharedPreferences、AsyncStorage、日志或界面回填。
- Web 平台直接拒绝保存，避免落到明文 `localStorage`。
- 密钥：`chaoxing_cookie`、`chaoxing_auth_state`。

## 可见的认证失效

认证失效是有状态的事件，不能看起来像「没有新作业」：

- 首页醒目横幅：「登录已失效」+「重新登录」。
- 自动同步请求被拒绝且不提示（避免拿失效 Cookie 空转）；手动刷新给出「登录已失效，请重新登录后再刷新」。
- 同一次失效只进入一次回调（给后续通知渠道用）。
- 失效标记持久化，冷启动仍看得到横幅，直到重新登录成功。

## 给后续同步包的会话接口

`SessionController` 实现 `ChaoxingSyncSession`：

```ts
getCookieSource(): string
getCookieHeader(url: string): string
getAuthenticationState(): "unconfigured" | "unknown" | "valid" | "expired"
markExpired(): void
markValid(): void
requestSync("manual" | "auto")
```

同步包不要自己存 Cookie。带 Cookie 的请求仍必须限制在显式学习通 HTTPS 主机内；本模块的 `cookieHeaderForChaoxingUri` 不会给 `passport2.chaoxing.com` 或白名单外主机拼 Cookie。

## 本轮不做

- 完整课程 / 收件箱同步与解析
- Android 预排闹钟或通知渠道
- Windows RN 托盘 / WebView2 / 安装器

## 验证

```sh
npm test
npm run typecheck
```

应用内 WebView 登录需要 Android 开发构建（`npx expo run:android`），Expo Go 读不到 HttpOnly Cookie。
