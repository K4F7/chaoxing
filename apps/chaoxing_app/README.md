# 学习通待办 App

Flutter 自用客户端，连接项目里的 Cloudflare Worker `/app/sync` 接口，展示学习通作业和考试待办。

## 运行

```sh
flutter run -d macos
```

Android 运行需要本机安装 Android SDK：

```sh
flutter run -d android
```

构建 Android debug APK：

```sh
flutter build apk --debug
```

创建并启动 Android 36 模拟器：

```sh
avdmanager create avd \
  -n chaoxing_android_36 \
  -k "system-images;android-36;google_apis;arm64-v8a" \
  -d pixel_7
flutter emulators --launch chaoxing_android_36
```

## 首次配置

打开 App 后填写：

- Worker URL，例如 `https://your-worker.workers.dev`
- `RUN_TOKEN`
- 刷新间隔

App 不保存学习通 Cookie；Cookie 仍只放在 Worker 环境变量或本地 `.dev.vars` 中。

## 验证

```sh
flutter analyze
flutter test
```
