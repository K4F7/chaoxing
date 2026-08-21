# 学习通作业考试待办

从学习通收件箱和课程空间识别作业与考试，解析截止时间，在本机汇总成待办列表并在截止前提醒。

工具在本机直接访问学习通，不经过任何自建服务端，凭据只保存在本机安全存储中。Windows 与 Android 各自独立完成抓取、存储与提醒，装一端即可使用，不需要配对。术语见 [CONTEXT.md](./CONTEXT.md)。

## 项目结构

- `apps/chaoxing_app/`：Flutter App，支持 Windows 和 Android。这是当前唯一的生产形态。
- `packages/chaoxing-domain/`：可移植的 TypeScript 领域切片（提醒规则、URL 信任分级）。供 React Native 使用。
- `packages/chaoxing-android-alarms/`：ADR-0001 的 RN Android 预排闹钟（两档映射 + Expo native module）。见 [docs/rn-android-alarms.md](docs/rn-android-alarms.md)。
- `apps/chaoxing_rn/`：Expo / React Native 脚手架。领域切片已接线；Android 闹钟可从 fixture 待办事项登记。不做登录或抓取。见 [ADR-0002](docs/adr/0002-react-native-incremental-migration.md)。
- `docs/`：产品文档与架构决策记录。
- `src/`、`scripts/`、`tests/`：早期 Cloudflare Worker 实现的遗留代码，已不参与 App 运行路径，仅作为解析行为的对照保留。

## 使用

见 [`apps/chaoxing_app/README.md`](./apps/chaoxing_app/README.md)：首次登录、Windows 运行与构建、Android 构建、安全边界与已知限制。

## 验证

```sh
cd apps/chaoxing_app
flutter analyze
flutter test
flutter build windows
```

遗留 Worker 代码的测试仍可单独运行，与 App 无依赖关系：

```sh
bun install
bun run typecheck
bun test
```

React Native 增量与领域切片：

```sh
cd packages/chaoxing-domain
npm test
npm run typecheck

cd ../chaoxing-android-alarms
npm test
npm run typecheck

cd ../../apps/chaoxing_rn
npm test
npm run typecheck
```
