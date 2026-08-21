# 生产路径：RN Android + Windows 本机宿主

Flutter（`legacy/chaoxing_app`）不再是任何平台的出货路径。

| 平台 | 生产应用 | 提醒消费 | 登录 | 常驻 |
|---|---|---|---|---|
| Android | `apps/chaoxing_rn` | 预排 AlarmManager | WebView + Keystore | 不用后台抓取 |
| Windows | `apps/chaoxing_windows` | 「此刻该触发的」系统通知 | WebView2 | 托盘 + 可选自启 |

两端都复用 `packages/chaoxing-domain`，本机直连学习通，Cookie 不进明文设置。

## CI / CD

生产 workflow：`.github/workflows/chaoxing-rn.yml`（GitHub-hosted runners，无自建学习通代理）。

| Job | Runner | 做什么 |
|---|---|---|
| Domain + alarms + HTTP + RN Android | `ubuntu-latest` | TypeScript typecheck + test |
| Android unsigned assemble | `ubuntu-latest` | `expo prebuild` + Gradle。无签名密钥时 `assembleDebug`（debug-signed，**不是**商店出货） |
| Windows host | `ubuntu-latest` | TypeScript typecheck + test |
| Windows native + installer | `windows-latest` | 再跑一遍 TypeScript；`dotnet publish` C# 外壳；有 Inno Setup 时打 `setup.exe`，没有则跳过安装器、不失败 |

遗留 Flutter：`.github/workflows/chaoxing-legacy.yml` 只对 `legacy/chaoxing_app` 做 `flutter analyze` / `flutter test`，**不**打 APK / `setup.exe`，**不**发 GitHub Release。

Windows 与 Android 的 job 互相独立，一边缺工具不能挡住另一边的测试。

### Android 签名密钥（仓库 Secrets，不要提交）

| Secret | 用途 |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | upload keystore（`.jks` / `.keystore`）的 base64 |
| `ANDROID_KEY_PROPERTIES_BASE64` | `key.properties` 的 base64，需含 `storePassword` / `keyPassword` / `keyAlias`（`storeFile` 由 CI 写成 `upload-keystore.jks`） |

两个都在时，assemble job 走 `assembleRelease` 并上传 `app-release.apk`。缺任一则 dry-run：`assembleDebug`，artifact 里的 `SIGNING.txt` 会写明缺了哪个名字。CI 不打印 Cookie，也不打印密钥内容。

当前没有 Play Console / Microsoft Store 发布 job。main 上的正式商店包仍被缺签名证书和缺商店凭据挡住。
