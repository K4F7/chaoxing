# Windows 用 TypeScript 本机宿主，而不是 react-native-windows 或 Electron

生产 Windows 应用落在 `apps/chaoxing_windows`：TypeScript 复用 [`packages/chaoxing-domain`](../../packages/chaoxing-domain)，再用小型 C# WinForms 外壳提供托盘、WebView2、DPAPI 和系统通知。

**为什么不是 react-native-windows。** Expo 57 不提供桌面 Windows 运行时。把现有 Expo Android 应用改成 RN-windows 需要另开一套 Visual Studio / Windows SDK 工程，而 Linux CI 与本环境都编不了、也跑不了那套产物。领域约束（本机直连、可见失败、Windows 消费「此刻该触发的」提醒）已经在 TypeScript 里，再包一层 RN 桌面运行时不会减少静默失效风险。

**为什么不是 Electron。** ticket 明确把 Electron 当作 RN-windows 不可行时的逃生口。本机宿主更小：没有 Chromium 整包，安装器仍是 per-user Inno Setup，Cookie 走 DPAPI 而不是 Chromium 存储。

**不变的约束。** 不经过自建服务端；Windows 与 Android 各自抓取、存储、提醒；Cookie 不进明文设置；安装器升级/卸载必须结束进程并清掉开机自启。
