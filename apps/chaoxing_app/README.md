# 学习通待办 App

Flutter Windows 桌面客户端。本 App 在本机使用学习通 Cookie 直接同步收件箱里的作业和考试待办，不再把 Worker URL 或 RUN_TOKEN 作为 App 的主配置入口。

## 首次配置

1. 在浏览器中正常登录学习通。
2. 从已登录的学习通请求中复制当前账号的 Cookie header。
3. 打开 App 的“设置”，在“学习通 Cookie”输入框中粘贴 Cookie。
4. 点击“保存并同步”。

Cookie 只用于访问 `chaoxing.com` 及其子域名，保存位置是本机安全存储。设置页不会回填完整 Cookie；已经保存时只显示“已保存 Cookie”，输入框保持为空。只有重新输入新的 Cookie 时才会覆盖旧值。

## Windows 运行

确认已安装 Flutter，并启用 Windows 桌面支持：

```sh
flutter config --enable-windows-desktop
flutter doctor
```

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
