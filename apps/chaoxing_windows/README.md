# 学习通待办（Windows 生产路径）

TypeScript 本机宿主 + 小型 C# WinForms 外壳。复用 [`packages/chaoxing-domain`](../../packages/chaoxing-domain)：同步、URL 信任分级、认证失效、提醒规则的「此刻该触发的」一侧。

Expo 57 没有桌面 Windows 运行时；见 [ADR-0003](../../docs/adr/0003-windows-native-host.md)。

## 产品行为

- 应用内 WebView2 登录（顶层导航只允许学习通可信主机）
- 托盘常驻：关闭主窗口隐藏到托盘；菜单「退出」才结束进程
- 开机自启默认关闭，写入 `HKCU\...\Run`，命令带 `--hidden`
- 同步后消费「此刻该触发的」提醒（不是 Android 预排）
- Cookie 只进 DPAPI / 测试用内存罐，不进设置 JSON，界面不回填
- 安装器：当前用户目录、开始菜单、升级/卸载 `taskkill`、卸载清自启、检测 WebView2

## 验证（无需 Windows 桌面）

```sh
npm test
npm run typecheck
```

C# 外壳与 Inno Setup 需要 Windows SDK / ISCC，本环境不构建。
