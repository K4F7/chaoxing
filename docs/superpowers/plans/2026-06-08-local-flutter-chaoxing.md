# Local Flutter Chaoxing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将 `apps/chaoxing_app` 从 Worker URL + Token 同步迁移为纯 Flutter/Dart 本地学习通 Windows 桌面 App，直接完成登录 Cookie 采集、安全保存、收件箱抓取、页面解析、提醒调度、托盘常驻和 Windows 通知。

**Architecture:** Flutter Windows App 是唯一运行时进程；现有 `src/*.ts` Worker 代码只作为行为参考和 fixture 对照，不被 App 调用。Dart 层按账号/Cookie、HTTP、安全域名、收件箱、详情处理、要求页解析、同步模型、提醒调度、托盘通知和 UI 状态分层，每个阶段都保留可运行、可测试的软件。

**Tech Stack:** Flutter/Dart、Flutter Windows desktop、`http`、`html`、`crypto`、`flutter_secure_storage`、`shared_preferences`、`desktop_webview_window`、`window_manager`、`tray_manager`、`local_notifier`、Flutter unit/widget tests、`flutter test`、`flutter build windows`。

---

## Scope And Phasing

阶段 1 交付本地收件箱同步、登录 Cookie、缓存、提醒、托盘和 Windows 通知，完成后 Windows App 不需要 Cloudflare Worker、Bun、Node helper 或 `/app/sync` 服务即可登录、同步和提醒。阶段 2 增加课程空间、作业列表和考试列表补漏数据源，并与阶段 1 结果合并。阶段 3 增加诊断页面和脱敏诊断导出，方便定位登录、网络、解析、通知失败。

每个阶段都必须保持 `apps/chaoxing_app` 可启动、可测试。执行者在开始实现前如果需要隔离工作区，先使用 `superpowers:using-git-worktrees`；执行本计划时使用 `superpowers:subagent-driven-development` 或 `superpowers:executing-plans`，不要把多个任务混在一个大提交里。

## File Structure

新增和调整的 Flutter 文件按责任划分：

- `apps/chaoxing_app/pubspec.yaml`：新增 Windows、本地解析和通知相关依赖。
- `apps/chaoxing_app/lib/models/app_config.dart`：替换 Worker 配置为本地同步、抓取 limit、提醒配置和旧配置提示。
- `apps/chaoxing_app/lib/models/auth_state.dart`：认证状态、错误分类、账号状态缓存。
- `apps/chaoxing_app/lib/models/reminder_config.dart`：作业/考试提醒规则、重复提醒、免打扰、通知暂停。
- `apps/chaoxing_app/lib/models/reminder_history.dart`：已发送提醒记录和去重 key。
- `apps/chaoxing_app/lib/models/inbox_message.dart`：本地通知列表模型。
- `apps/chaoxing_app/lib/models/requirement.dart`：作业/考试要求页解析结果。
- `apps/chaoxing_app/lib/models/sync_item.dart`：保留现有字段，兼容新增 `examId`、`sources`。
- `apps/chaoxing_app/lib/models/app_sync_response.dart`：保留 App 展示响应，新增 meta 和错误分类字段。
- `apps/chaoxing_app/lib/services/app_storage.dart`：Cookie 安全存储、普通配置、缓存、提醒历史和旧 Worker 配置检测。
- `apps/chaoxing_app/lib/services/chaoxing_http_client.dart`：统一 Cookie header、User-Agent、Referer、超时、域名限制、日志脱敏和错误分类。
- `apps/chaoxing_app/lib/services/chaoxing_auth.dart`：认证检查、登录页信号识别、Cookie header 校验。
- `apps/chaoxing_app/lib/services/login_cookie_collector.dart`：WebView 登录 Cookie 采集和手动 Cookie 导入协调。
- `apps/chaoxing_app/lib/services/inbox_client.dart`：首页收件箱 URL 定位、收件箱页面配置、通知分页抓取。
- `apps/chaoxing_app/lib/services/message_processor.dart`：作业/考试通知筛选、详情接口、iframe name 解码、入口链接去重。
- `apps/chaoxing_app/lib/services/requirements_client.dart`：入口页面抓取和 HTML/URL/hidden input 解析。
- `apps/chaoxing_app/lib/services/sync_model_builder.dart`：`Requirement` 到 `SyncItem`、`AppSyncResponse`、失败列表、排序和 display status。
- `apps/chaoxing_app/lib/services/local_sync_runner.dart`：串联 auth/inbox/processor/requirements/model/cache/reminder。
- `apps/chaoxing_app/lib/services/reminder_scheduler.dart`：提前提醒、重复提醒、免打扰、暂停通知和去重计算。
- `apps/chaoxing_app/lib/services/windows_notifier.dart`：Windows 系统通知抽象和 `local_notifier` 实现。
- `apps/chaoxing_app/lib/services/tray_service.dart`：托盘菜单、关闭隐藏、真正退出、托盘状态。
- `apps/chaoxing_app/lib/services/course_space_client.dart`：阶段 2 课程空间列表抓取。
- `apps/chaoxing_app/lib/services/course_work_client.dart`：阶段 2 课程作业列表抓取。
- `apps/chaoxing_app/lib/services/course_exam_client.dart`：阶段 2 考试/测验列表抓取。
- `apps/chaoxing_app/lib/services/local_diagnostics.dart`：阶段 3 失败摘要和脱敏诊断导出。
- `apps/chaoxing_app/lib/state/app_controller.dart`：改为本地账号状态、手动同步、自动同步、托盘动作和提醒配置入口。
- `apps/chaoxing_app/lib/screens/settings_screen.dart`：改为账号、同步和提醒设置。
- `apps/chaoxing_app/lib/screens/login_screen.dart`：登录、WebView 状态、手动 Cookie 导入。
- `apps/chaoxing_app/lib/screens/diagnostics_screen.dart`：阶段 3 诊断页面。
- `apps/chaoxing_app/lib/main.dart`：Windows 初始化、托盘/通知服务注入。
- `apps/chaoxing_app/windows/**`：Flutter Windows 平台文件，执行 `flutter create --platforms=windows .` 生成。
- `apps/chaoxing_app/test/fixtures/chaoxing/**`：录制 HTML/JSON fixture，不包含真实 Cookie、账号或题目隐私。

现有 TypeScript 文件 `src/auth.ts`、`src/inbox.ts`、`src/processor.ts`、`src/requirements.ts`、`src/sync.ts`、`src/app-sync.ts` 只用于迁移对照和 fixture 语义参考，Flutter App 运行时不得 import、spawn 或 HTTP 调用这些模块。

## Phase 1: 本地收件箱同步、提醒和 Windows 常驻

### Task 1: Enable Windows Desktop And Dependencies

**Files:**
- Modify: `apps/chaoxing_app/pubspec.yaml`
- Create: `apps/chaoxing_app/windows/**`
- Test: `apps/chaoxing_app/test/widget_test.dart`

- [ ] **Step 1: Verify Windows desktop support is available**

Run:

```powershell
flutter config --enable-windows-desktop
flutter devices
```

Expected: output includes `Windows (desktop)` or Flutter reports Windows desktop is enabled. If Visual Studio desktop workload is missing, install the Flutter-required Windows desktop toolchain before continuing.

- [ ] **Step 2: Generate Windows platform files**

Run:

```powershell
Set-Location apps/chaoxing_app
flutter create --platforms=windows .
```

Expected: `windows/runner/main.cpp`, `windows/runner/flutter_window.cpp`, and `windows/CMakeLists.txt` exist. Existing Dart files remain unchanged.

- [ ] **Step 3: Add package dependencies**

Modify `apps/chaoxing_app/pubspec.yaml` dependencies to include these packages:

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  http: ^1.6.0
  flutter_secure_storage: ^10.3.1
  shared_preferences: ^2.5.5
  intl: ^0.20.2
  url_launcher: ^6.3.2
  html: ^0.15.6
  crypto: ^3.0.6
  desktop_webview_window: ^0.2.3
  window_manager: ^0.5.1
  tray_manager: ^0.5.1
  local_notifier: ^0.1.6
```

Run:

```powershell
flutter pub get
```

Expected: dependency resolution succeeds and `pubspec.lock` updates.

- [ ] **Step 4: Run baseline Flutter tests**

Run:

```powershell
flutter test
```

Expected: existing widget/model/controller tests pass or only fail because later tasks have not yet migrated Worker config. Record any baseline failure in the task notes before editing.

- [ ] **Step 5: Build Windows shell**

Run:

```powershell
flutter build windows
```

Expected: build finishes and creates `build/windows/x64/runner/Release/chaoxing_app.exe`.

- [ ] **Step 6: Commit**

```bash
git add apps/chaoxing_app/pubspec.yaml apps/chaoxing_app/pubspec.lock apps/chaoxing_app/windows
git commit -m "chore: enable flutter windows desktop"
```

### Task 2: Replace Worker Config With Local Settings Models

**Files:**
- Modify: `apps/chaoxing_app/lib/models/app_config.dart`
- Create: `apps/chaoxing_app/lib/models/reminder_config.dart`
- Create: `apps/chaoxing_app/lib/models/auth_state.dart`
- Test: `apps/chaoxing_app/test/models/app_config_test.dart`
- Test: `apps/chaoxing_app/test/models/reminder_config_test.dart`

- [ ] **Step 1: Write failing config and reminder model tests**

Create `apps/chaoxing_app/test/models/app_config_test.dart`:

```dart
import 'package:chaoxing_app/models/app_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('local config defaults remove worker credentials', () {
    const config = AppConfig.empty;

    expect(config.refreshMinutes, 60);
    expect(config.autoSyncEnabled, true);
    expect(config.syncLimits.inboxLimit, 100);
    expect(config.syncLimits.detailsLimit, 10);
    expect(config.syncLimits.requirementsLimit, 40);
    expect(config.hasLegacyWorkerConfig, false);
  });

  test('config json keeps local sync fields', () {
    const config = AppConfig(
      refreshMinutes: 30,
      autoSyncEnabled: false,
      syncLimits: SyncLimits(inboxLimit: 20, detailsLimit: 5, requirementsLimit: 12),
      hasLegacyWorkerConfig: true,
    );

    final decoded = AppConfig.fromJson(config.toJson());

    expect(decoded.refreshMinutes, 30);
    expect(decoded.autoSyncEnabled, false);
    expect(decoded.syncLimits.inboxLimit, 20);
    expect(decoded.syncLimits.detailsLimit, 5);
    expect(decoded.syncLimits.requirementsLimit, 12);
    expect(decoded.hasLegacyWorkerConfig, true);
  });
}
```

Create `apps/chaoxing_app/test/models/reminder_config_test.dart`:

```dart
import 'package:chaoxing_app/models/reminder_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('default reminder config separates assignment and exam rules', () {
    const config = ReminderConfig.defaults;

    expect(config.assignment.enabled, true);
    expect(config.exam.enabled, true);
    expect(config.assignment.advanceRules.map((rule) => rule.id), contains('advance_1440m'));
    expect(config.exam.advanceRules.map((rule) => rule.id), contains('advance_60m'));
    expect(config.quietHours.enabled, false);
    expect(config.notificationsPaused, false);
  });

  test('cross-midnight quiet hours are detected', () {
    const quiet = QuietHours(enabled: true, startLocalTime: '22:30', endLocalTime: '07:00');

    expect(quiet.contains(DateTime(2026, 6, 8, 23)), true);
    expect(quiet.contains(DateTime(2026, 6, 9, 6, 30)), true);
    expect(quiet.contains(DateTime(2026, 6, 9, 9)), false);
  });
}
```

Run:

```powershell
flutter test test/models/app_config_test.dart test/models/reminder_config_test.dart
```

Expected: FAIL because `autoSyncEnabled`, `SyncLimits`, `ReminderConfig`, `QuietHours`, and related JSON helpers do not exist.

- [ ] **Step 2: Implement local config models**

Replace `apps/chaoxing_app/lib/models/app_config.dart` with:

```dart
class AppConfig {
  const AppConfig({
    required this.refreshMinutes,
    required this.autoSyncEnabled,
    required this.syncLimits,
    required this.hasLegacyWorkerConfig,
  });

  final int refreshMinutes;
  final bool autoSyncEnabled;
  final SyncLimits syncLimits;
  final bool hasLegacyWorkerConfig;

  bool get canAutoSync => autoSyncEnabled && refreshMinutes > 0;

  AppConfig copyWith({
    int? refreshMinutes,
    bool? autoSyncEnabled,
    SyncLimits? syncLimits,
    bool? hasLegacyWorkerConfig,
  }) {
    return AppConfig(
      refreshMinutes: refreshMinutes ?? this.refreshMinutes,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
      syncLimits: syncLimits ?? this.syncLimits,
      hasLegacyWorkerConfig: hasLegacyWorkerConfig ?? this.hasLegacyWorkerConfig,
    );
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    return AppConfig(
      refreshMinutes: _readInt(json['refreshMinutes'], 60, min: 5, max: 720),
      autoSyncEnabled: json['autoSyncEnabled'] is bool ? json['autoSyncEnabled'] as bool : true,
      syncLimits: json['syncLimits'] is Map
          ? SyncLimits.fromJson((json['syncLimits'] as Map).cast<String, dynamic>())
          : SyncLimits.defaults,
      hasLegacyWorkerConfig: json['hasLegacyWorkerConfig'] is bool
          ? json['hasLegacyWorkerConfig'] as bool
          : false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'refreshMinutes': refreshMinutes,
      'autoSyncEnabled': autoSyncEnabled,
      'syncLimits': syncLimits.toJson(),
      'hasLegacyWorkerConfig': hasLegacyWorkerConfig,
    };
  }

  static const empty = AppConfig(
    refreshMinutes: 60,
    autoSyncEnabled: true,
    syncLimits: SyncLimits.defaults,
    hasLegacyWorkerConfig: false,
  );
}

class SyncLimits {
  const SyncLimits({
    required this.inboxLimit,
    required this.detailsLimit,
    required this.requirementsLimit,
  });

  final int inboxLimit;
  final int detailsLimit;
  final int requirementsLimit;

  factory SyncLimits.fromJson(Map<String, dynamic> json) {
    return SyncLimits(
      inboxLimit: _readInt(json['inboxLimit'], 100, min: 1, max: 500),
      detailsLimit: _readInt(json['detailsLimit'], 10, min: 1, max: 100),
      requirementsLimit: _readInt(json['requirementsLimit'], 40, min: 1, max: 100),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'inboxLimit': inboxLimit,
      'detailsLimit': detailsLimit,
      'requirementsLimit': requirementsLimit,
    };
  }

  static const defaults = SyncLimits(inboxLimit: 100, detailsLimit: 10, requirementsLimit: 40);
}

int _readInt(Object? value, int fallback, {required int min, required int max}) {
  final parsed = value is num ? value.round() : int.tryParse(value?.toString() ?? '');
  if (parsed == null) {
    return fallback;
  }
  return parsed.clamp(min, max);
}
```

- [ ] **Step 3: Implement reminder config model**

Create `apps/chaoxing_app/lib/models/reminder_config.dart`:

```dart
class ReminderConfig {
  const ReminderConfig({
    required this.assignment,
    required this.exam,
    required this.quietHours,
    required this.notificationsPaused,
  });

  final KindReminderConfig assignment;
  final KindReminderConfig exam;
  final QuietHours quietHours;
  final bool notificationsPaused;

  factory ReminderConfig.fromJson(Map<String, dynamic> json) {
    return ReminderConfig(
      assignment: json['assignment'] is Map
          ? KindReminderConfig.fromJson((json['assignment'] as Map).cast<String, dynamic>())
          : defaults.assignment,
      exam: json['exam'] is Map
          ? KindReminderConfig.fromJson((json['exam'] as Map).cast<String, dynamic>())
          : defaults.exam,
      quietHours: json['quietHours'] is Map
          ? QuietHours.fromJson((json['quietHours'] as Map).cast<String, dynamic>())
          : defaults.quietHours,
      notificationsPaused: json['notificationsPaused'] is bool
          ? json['notificationsPaused'] as bool
          : false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'assignment': assignment.toJson(),
      'exam': exam.toJson(),
      'quietHours': quietHours.toJson(),
      'notificationsPaused': notificationsPaused,
    };
  }

  ReminderConfig copyWith({
    KindReminderConfig? assignment,
    KindReminderConfig? exam,
    QuietHours? quietHours,
    bool? notificationsPaused,
  }) {
    return ReminderConfig(
      assignment: assignment ?? this.assignment,
      exam: exam ?? this.exam,
      quietHours: quietHours ?? this.quietHours,
      notificationsPaused: notificationsPaused ?? this.notificationsPaused,
    );
  }

  static const defaults = ReminderConfig(
    assignment: KindReminderConfig.defaults,
    exam: KindReminderConfig.defaults,
    quietHours: QuietHours.disabled,
    notificationsPaused: false,
  );
}

class KindReminderConfig {
  const KindReminderConfig({
    required this.enabled,
    required this.advanceRules,
    required this.repeatRule,
  });

  final bool enabled;
  final List<AdvanceRule> advanceRules;
  final RepeatRule repeatRule;

  factory KindReminderConfig.fromJson(Map<String, dynamic> json) {
    final rawRules = json['advanceRules'];
    return KindReminderConfig(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
      advanceRules: rawRules is List
          ? rawRules
              .whereType<Map>()
              .map((rule) => AdvanceRule.fromJson(rule.cast<String, dynamic>()))
              .toList()
          : defaults.advanceRules,
      repeatRule: json['repeatRule'] is Map
          ? RepeatRule.fromJson((json['repeatRule'] as Map).cast<String, dynamic>())
          : defaults.repeatRule,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'advanceRules': advanceRules.map((rule) => rule.toJson()).toList(),
      'repeatRule': repeatRule.toJson(),
    };
  }

  static const defaults = KindReminderConfig(
    enabled: true,
    advanceRules: [
      AdvanceRule(id: 'advance_10080m', minutesBeforeDue: 10080, enabled: true),
      AdvanceRule(id: 'advance_4320m', minutesBeforeDue: 4320, enabled: true),
      AdvanceRule(id: 'advance_1440m', minutesBeforeDue: 1440, enabled: true),
      AdvanceRule(id: 'advance_360m', minutesBeforeDue: 360, enabled: true),
      AdvanceRule(id: 'advance_60m', minutesBeforeDue: 60, enabled: true),
      AdvanceRule(id: 'advance_15m', minutesBeforeDue: 15, enabled: true),
    ],
    repeatRule: RepeatRule(
      enabled: false,
      intervalMinutes: 60,
      startMinutesBeforeDue: 1440,
      stopAtDue: true,
      maxCountPerItem: 6,
    ),
  );
}

class AdvanceRule {
  const AdvanceRule({required this.id, required this.minutesBeforeDue, required this.enabled});

  final String id;
  final int minutesBeforeDue;
  final bool enabled;

  factory AdvanceRule.fromJson(Map<String, dynamic> json) {
    final minutes = _readInt(json['minutesBeforeDue'], 60, min: 1, max: 525600);
    return AdvanceRule(
      id: json['id'] is String && (json['id'] as String).isNotEmpty
          ? json['id'] as String
          : 'advance_${minutes}m',
      minutesBeforeDue: minutes,
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'minutesBeforeDue': minutesBeforeDue, 'enabled': enabled};
  }
}

class RepeatRule {
  const RepeatRule({
    required this.enabled,
    required this.intervalMinutes,
    required this.startMinutesBeforeDue,
    required this.stopAtDue,
    required this.maxCountPerItem,
  });

  final bool enabled;
  final int intervalMinutes;
  final int startMinutesBeforeDue;
  final bool stopAtDue;
  final int maxCountPerItem;

  factory RepeatRule.fromJson(Map<String, dynamic> json) {
    return RepeatRule(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : false,
      intervalMinutes: _readInt(json['intervalMinutes'], 60, min: 5, max: 1440),
      startMinutesBeforeDue: _readInt(json['startMinutesBeforeDue'], 1440, min: 5, max: 525600),
      stopAtDue: json['stopAtDue'] is bool ? json['stopAtDue'] as bool : true,
      maxCountPerItem: _readInt(json['maxCountPerItem'], 6, min: 1, max: 100),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'enabled': enabled,
      'intervalMinutes': intervalMinutes,
      'startMinutesBeforeDue': startMinutesBeforeDue,
      'stopAtDue': stopAtDue,
      'maxCountPerItem': maxCountPerItem,
    };
  }
}

class QuietHours {
  const QuietHours({
    required this.enabled,
    required this.startLocalTime,
    required this.endLocalTime,
  });

  final bool enabled;
  final String startLocalTime;
  final String endLocalTime;

  bool contains(DateTime localNow) {
    if (!enabled) {
      return false;
    }
    final start = _minutesOfDay(startLocalTime);
    final end = _minutesOfDay(endLocalTime);
    final now = localNow.hour * 60 + localNow.minute;
    if (start == end) {
      return true;
    }
    return start < end ? now >= start && now < end : now >= start || now < end;
  }

  factory QuietHours.fromJson(Map<String, dynamic> json) {
    return QuietHours(
      enabled: json['enabled'] is bool ? json['enabled'] as bool : false,
      startLocalTime: json['startLocalTime'] is String ? json['startLocalTime'] as String : '22:00',
      endLocalTime: json['endLocalTime'] is String ? json['endLocalTime'] as String : '07:00',
    );
  }

  Map<String, dynamic> toJson() {
    return {'enabled': enabled, 'startLocalTime': startLocalTime, 'endLocalTime': endLocalTime};
  }

  static const disabled = QuietHours(enabled: false, startLocalTime: '22:00', endLocalTime: '07:00');
}

int _readInt(Object? value, int fallback, {required int min, required int max}) {
  final parsed = value is num ? value.round() : int.tryParse(value?.toString() ?? '');
  if (parsed == null) {
    return fallback;
  }
  return parsed.clamp(min, max);
}

int _minutesOfDay(String value) {
  final parts = value.split(':');
  if (parts.length != 2) {
    return 0;
  }
  final hour = int.tryParse(parts[0]) ?? 0;
  final minute = int.tryParse(parts[1]) ?? 0;
  return hour.clamp(0, 23) * 60 + minute.clamp(0, 59);
}
```

- [ ] **Step 4: Implement auth state model**

Create `apps/chaoxing_app/lib/models/auth_state.dart`:

```dart
enum AuthStatus { authenticated, expired, missingCookie, networkError, httpStatus, unknown }

class AuthState {
  const AuthState({
    required this.status,
    required this.checkedAt,
    required this.title,
    required this.finalUrl,
    required this.message,
  });

  final AuthStatus status;
  final DateTime? checkedAt;
  final String? title;
  final String? finalUrl;
  final String? message;

  bool get isAuthenticated => status == AuthStatus.authenticated;

  factory AuthState.fromJson(Map<String, dynamic> json) {
    return AuthState(
      status: AuthStatus.values.firstWhere(
        (value) => value.name == json['status'],
        orElse: () => AuthStatus.unknown,
      ),
      checkedAt: DateTime.tryParse(json['checkedAt']?.toString() ?? '')?.toLocal(),
      title: json['title'] is String ? json['title'] as String : null,
      finalUrl: json['finalUrl'] is String ? json['finalUrl'] as String : null,
      message: json['message'] is String ? json['message'] as String : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'status': status.name,
      'checkedAt': checkedAt?.toIso8601String(),
      'title': title,
      'finalUrl': finalUrl,
      'message': message,
    };
  }

  static const missing = AuthState(
    status: AuthStatus.missingCookie,
    checkedAt: null,
    title: null,
    finalUrl: null,
    message: '未登录学习通',
  );
}
```

- [ ] **Step 5: Run model tests**

Run:

```powershell
flutter test test/models/app_config_test.dart test/models/reminder_config_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/chaoxing_app/lib/models/app_config.dart apps/chaoxing_app/lib/models/reminder_config.dart apps/chaoxing_app/lib/models/auth_state.dart apps/chaoxing_app/test/models/app_config_test.dart apps/chaoxing_app/test/models/reminder_config_test.dart
git commit -m "feat: add local sync configuration models"
```

### Task 3: Migrate Storage To Cookie, Config, Cache, Reminder History

**Files:**
- Modify: `apps/chaoxing_app/lib/services/app_storage.dart`
- Create: `apps/chaoxing_app/lib/models/reminder_history.dart`
- Test: `apps/chaoxing_app/test/services/app_storage_test.dart`

- [ ] **Step 1: Write failing storage tests**

Create `apps/chaoxing_app/test/services/app_storage_test.dart`:

```dart
import 'package:chaoxing_app/models/app_config.dart';
import 'package:chaoxing_app/models/reminder_config.dart';
import 'package:chaoxing_app/models/reminder_history.dart';
import 'package:chaoxing_app/services/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('memory storage saves cookie separately from normal config', () async {
    final storage = MemoryAppStorage();

    await storage.saveCookieHeader('UID=1; vc=abc');
    await storage.saveConfig(AppConfig.empty.copyWith(refreshMinutes: 15));

    expect(await storage.loadCookieHeader(), 'UID=1; vc=abc');
    expect((await storage.loadConfig()).refreshMinutes, 15);
  });

  test('memory storage stores reminder config and history', () async {
    final storage = MemoryAppStorage();
    const config = ReminderConfig.defaults;
    final history = ReminderHistory(records: [
      ReminderRecord(
        itemId: 'assignment-1',
        remindRule: 'advance_60m',
        dueAtSnapshot: '2026-06-10T10:00:00.000',
        titleSnapshot: '作业',
        sentAt: DateTime(2026, 6, 10, 9),
      ),
    ]);

    await storage.saveReminderConfig(config.copyWith(notificationsPaused: true));
    await storage.saveReminderHistory(history);

    expect((await storage.loadReminderConfig()).notificationsPaused, true);
    expect((await storage.loadReminderHistory()).records.single.dedupeKey, 'assignment-1|advance_60m|2026-06-10T10:00:00.000');
  });

  test('logout deletes cookie but keeps cached sync and reminder config', () async {
    final storage = MemoryAppStorage();
    await storage.saveCookieHeader('UID=1');
    await storage.saveReminderConfig(ReminderConfig.defaults.copyWith(notificationsPaused: true));

    await storage.clearCookieHeader();

    expect(await storage.loadCookieHeader(), isNull);
    expect((await storage.loadReminderConfig()).notificationsPaused, true);
  });
}
```

Run:

```powershell
flutter test test/services/app_storage_test.dart
```

Expected: FAIL because new storage methods and `ReminderHistory` do not exist.

- [ ] **Step 2: Implement reminder history model**

Create `apps/chaoxing_app/lib/models/reminder_history.dart`:

```dart
class ReminderHistory {
  const ReminderHistory({required this.records});

  final List<ReminderRecord> records;

  bool contains(String itemId, String remindRule, String dueAtSnapshot) {
    final key = '$itemId|$remindRule|$dueAtSnapshot';
    return records.any((record) => record.dedupeKey == key);
  }

  ReminderHistory add(ReminderRecord record, {DateTime? now, int keepDays = 120, int maxRecords = 1000}) {
    final cutoff = (now ?? DateTime.now()).subtract(Duration(days: keepDays));
    final merged = [
      ...records.where((existing) => existing.sentAt.isAfter(cutoff) && existing.dedupeKey != record.dedupeKey),
      record,
    ];
    final trimmed = merged.length <= maxRecords ? merged : merged.sublist(merged.length - maxRecords);
    return ReminderHistory(records: trimmed);
  }

  factory ReminderHistory.fromJson(Map<String, dynamic> json) {
    final raw = json['records'];
    return ReminderHistory(
      records: raw is List
          ? raw
              .whereType<Map>()
              .map((record) => ReminderRecord.fromJson(record.cast<String, dynamic>()))
              .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {'records': records.map((record) => record.toJson()).toList()};
  }

  static const empty = ReminderHistory(records: []);
}

class ReminderRecord {
  const ReminderRecord({
    required this.itemId,
    required this.remindRule,
    required this.dueAtSnapshot,
    required this.titleSnapshot,
    required this.sentAt,
  });

  final String itemId;
  final String remindRule;
  final String dueAtSnapshot;
  final String titleSnapshot;
  final DateTime sentAt;

  String get dedupeKey => '$itemId|$remindRule|$dueAtSnapshot';

  factory ReminderRecord.fromJson(Map<String, dynamic> json) {
    return ReminderRecord(
      itemId: json['itemId']?.toString() ?? '',
      remindRule: json['remindRule']?.toString() ?? '',
      dueAtSnapshot: json['dueAtSnapshot']?.toString() ?? '',
      titleSnapshot: json['titleSnapshot']?.toString() ?? '',
      sentAt: DateTime.tryParse(json['sentAt']?.toString() ?? '')?.toLocal() ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'itemId': itemId,
      'remindRule': remindRule,
      'dueAtSnapshot': dueAtSnapshot,
      'titleSnapshot': titleSnapshot,
      'sentAt': sentAt.toIso8601String(),
    };
  }
}
```

- [ ] **Step 3: Extend AppStorage contract and implementations**

Modify `apps/chaoxing_app/lib/services/app_storage.dart` so the abstract class includes:

```dart
abstract class AppStorage {
  Future<AppConfig> loadConfig();
  Future<void> saveConfig(AppConfig config);
  Future<String?> loadCookieHeader();
  Future<void> saveCookieHeader(String cookieHeader);
  Future<void> clearCookieHeader();
  Future<ReminderConfig> loadReminderConfig();
  Future<void> saveReminderConfig(ReminderConfig config);
  Future<ReminderHistory> loadReminderHistory();
  Future<void> saveReminderHistory(ReminderHistory history);
  Future<AppSyncResponse?> loadCachedSync();
  Future<void> saveCachedSync(AppSyncResponse response);
}
```

Use these storage keys in `DeviceAppStorage`:

```dart
static const _legacyBaseUrlKey = 'worker_base_url';
static const _legacyTokenKey = 'run_token';
static const _cookieKey = 'chaoxing_cookie';
static const _configKey = 'local_app_config';
static const _reminderConfigKey = 'reminder_config';
static const _cachedSyncKey = 'cached_local_sync';
static const _reminderHistoryKey = 'reminder_history';
```

When `loadConfig()` sees non-empty legacy secure values under `_legacyBaseUrlKey` or `_legacyTokenKey`, return `config.copyWith(hasLegacyWorkerConfig: true)` but do not copy those values into the new config. `saveCookieHeader()` writes only to `FlutterSecureStorage`; `saveConfig()`, `saveReminderConfig()`, `saveCachedSync()`, and `saveReminderHistory()` write JSON to `SharedPreferencesWithCache`.

- [ ] **Step 4: Update MemoryAppStorage**

Update `MemoryAppStorage` fields:

```dart
class MemoryAppStorage implements AppStorage {
  AppConfig config;
  String? cookieHeader;
  ReminderConfig reminderConfig;
  ReminderHistory reminderHistory;
  AppSyncResponse? cachedSync;

  MemoryAppStorage({
    this.config = AppConfig.empty,
    this.cookieHeader,
    this.reminderConfig = ReminderConfig.defaults,
    this.reminderHistory = ReminderHistory.empty,
    this.cachedSync,
  });

  @override
  Future<String?> loadCookieHeader() async => cookieHeader;

  @override
  Future<void> saveCookieHeader(String cookieHeader) async {
    this.cookieHeader = cookieHeader.trim();
  }

  @override
  Future<void> clearCookieHeader() async {
    cookieHeader = null;
  }

  // Keep existing load/save config and cached sync methods, and add reminder methods.
}
```

Complete the two reminder methods by assigning and returning `reminderConfig` and `reminderHistory`.

- [ ] **Step 5: Run storage tests**

Run:

```powershell
flutter test test/services/app_storage_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/chaoxing_app/lib/services/app_storage.dart apps/chaoxing_app/lib/models/reminder_history.dart apps/chaoxing_app/test/services/app_storage_test.dart
git commit -m "feat: store local cookie config and reminders"
```

### Task 4: Add Safe Chaoxing HTTP Client And Error Types

**Files:**
- Create: `apps/chaoxing_app/lib/services/chaoxing_http_client.dart`
- Test: `apps/chaoxing_app/test/services/chaoxing_http_client_test.dart`

- [ ] **Step 1: Write failing HTTP client tests**

Create `apps/chaoxing_app/test/services/chaoxing_http_client_test.dart`:

```dart
import 'package:chaoxing_app/services/chaoxing_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('adds cookie and browser-like headers for trusted chaoxing hosts', () async {
    late http.Request captured;
    final client = ChaoxingHttpClient(
      cookieHeader: 'UID=1; vc=abc',
      inner: MockClient((request) async {
        captured = request;
        return http.Response('ok', 200);
      }),
    );

    await client.getText(Uri.parse('https://notice.chaoxing.com/pc/notice/myNotice'), referer: Uri.parse('https://i.chaoxing.com/base'));

    expect(captured.headers['Cookie'], 'UID=1; vc=abc');
    expect(captured.headers['User-Agent'], contains('Mozilla/5.0'));
    expect(captured.headers['Referer'], 'https://i.chaoxing.com/base');
  });

  test('rejects non-chaoxing hosts before sending cookie', () async {
    final client = ChaoxingHttpClient(
      cookieHeader: 'UID=1',
      inner: MockClient((_) async => http.Response('leak', 200)),
    );

    expect(
      () => client.getText(Uri.parse('https://evil.example.com/pixel')),
      throwsA(isA<ChaoxingClientException>().having((error) => error.kind, 'kind', ChaoxingErrorKind.untrustedHost)),
    );
  });

  test('maps non-2xx status to typed exception', () async {
    final client = ChaoxingHttpClient(
      cookieHeader: 'UID=1',
      inner: MockClient((_) async => http.Response('blocked', 429)),
    );

    expect(
      () => client.getText(Uri.parse('https://i.chaoxing.com/base')),
      throwsA(isA<ChaoxingClientException>().having((error) => error.kind, 'kind', ChaoxingErrorKind.rateLimitedOrRiskControl)),
    );
  });
}
```

Run:

```powershell
flutter test test/services/chaoxing_http_client_test.dart
```

Expected: FAIL because client and error types do not exist.

- [ ] **Step 2: Implement client**

Create `apps/chaoxing_app/lib/services/chaoxing_http_client.dart`:

```dart
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

enum ChaoxingErrorKind {
  missingCookie,
  authExpired,
  networkUnavailable,
  httpStatus,
  inboxNotFound,
  parseFailed,
  rateLimitedOrRiskControl,
  notificationFailed,
  untrustedHost,
}

class ChaoxingClientException implements Exception {
  const ChaoxingClientException(this.kind, this.message, {this.statusCode, this.url});

  final ChaoxingErrorKind kind;
  final String message;
  final int? statusCode;
  final Uri? url;

  @override
  String toString() => statusCode == null ? message : '$message ($statusCode)';
}

class ChaoxingHttpClient {
  ChaoxingHttpClient({
    required String cookieHeader,
    http.Client? inner,
    Duration timeout = const Duration(seconds: 20),
  })  : _cookieHeader = cookieHeader.trim(),
        _inner = inner ?? http.Client(),
        _timeout = timeout;

  final String _cookieHeader;
  final http.Client _inner;
  final Duration _timeout;

  Future<String> getText(Uri uri, {Uri? referer, String accept = 'text/html,application/xhtml+xml'}) async {
    final response = await get(uri, referer: referer, accept: accept);
    return utf8.decode(response.bodyBytes);
  }

  Future<Map<String, dynamic>> getJson(Uri uri, {Uri? referer}) async {
    final response = await get(uri, referer: referer, accept: 'application/json, text/javascript, */*; q=0.01');
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw ChaoxingClientException(ChaoxingErrorKind.parseFailed, '学习通返回 JSON 格式不正确', url: uri);
    }
    return decoded;
  }

  Future<Map<String, dynamic>> postFormJson(Uri uri, Map<String, String> form, {Uri? referer}) async {
    _validateRequest(uri);
    try {
      final response = await _inner
          .post(
            uri,
            headers: _headers(referer: referer, accept: 'application/json, text/javascript, */*; q=0.01')
              ..addAll({'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8', 'Origin': '${uri.scheme}://${uri.host}', 'X-Requested-With': 'XMLHttpRequest'}),
            body: form,
          )
          .timeout(_timeout);
      _throwForStatus(response, uri);
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw ChaoxingClientException(ChaoxingErrorKind.parseFailed, '学习通返回 JSON 格式不正确', url: uri);
      }
      return decoded;
    } on TimeoutException {
      throw ChaoxingClientException(ChaoxingErrorKind.networkUnavailable, '网络超时', url: uri);
    } on http.ClientException catch (error) {
      throw ChaoxingClientException(ChaoxingErrorKind.networkUnavailable, error.message, url: uri);
    }
  }

  Future<http.Response> get(Uri uri, {Uri? referer, String accept = 'text/html,application/xhtml+xml'}) async {
    _validateRequest(uri);
    try {
      final response = await _inner.get(uri, headers: _headers(referer: referer, accept: accept)).timeout(_timeout);
      _throwForStatus(response, uri);
      return response;
    } on TimeoutException {
      throw ChaoxingClientException(ChaoxingErrorKind.networkUnavailable, '网络超时', url: uri);
    } on http.ClientException catch (error) {
      throw ChaoxingClientException(ChaoxingErrorKind.networkUnavailable, error.message, url: uri);
    }
  }

  Map<String, String> _headers({Uri? referer, required String accept}) {
    return {
      'Accept': accept,
      'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.7',
      'Cache-Control': 'no-cache',
      'Cookie': _cookieHeader,
      if (referer != null) 'Referer': referer.toString(),
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125 Safari/537.36',
    };
  }

  void _validateRequest(Uri uri) {
    if (_cookieHeader.isEmpty) {
      throw ChaoxingClientException(ChaoxingErrorKind.missingCookie, '未登录学习通', url: uri);
    }
    if (uri.scheme != 'https' && uri.scheme != 'http') {
      throw ChaoxingClientException(ChaoxingErrorKind.untrustedHost, '链接协议不受信任', url: uri);
    }
    final host = uri.host.toLowerCase();
    final trusted = host == 'chaoxing.com' || host.endsWith('.chaoxing.com') || host == 'chaoxing.edu' || host.endsWith('.chaoxing.edu');
    if (!trusted) {
      throw ChaoxingClientException(ChaoxingErrorKind.untrustedHost, '链接域名不属于学习通', url: uri);
    }
  }

  void _throwForStatus(http.Response response, Uri uri) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return;
    }
    final kind = response.statusCode == 429 || response.statusCode == 403
        ? ChaoxingErrorKind.rateLimitedOrRiskControl
        : ChaoxingErrorKind.httpStatus;
    throw ChaoxingClientException(kind, '学习通请求失败', statusCode: response.statusCode, url: uri);
  }
}

String redactSensitiveUrl(Uri uri) {
  final sensitive = {'token', 'enc', 'key', 'uid', 'puid'};
  final query = <String, String>{};
  for (final entry in uri.queryParameters.entries) {
    query[entry.key] = sensitive.contains(entry.key.toLowerCase()) ? '***' : entry.value;
  }
  return uri.replace(queryParameters: query.isEmpty ? null : query).toString();
}
```

- [ ] **Step 3: Run HTTP client tests**

Run:

```powershell
flutter test test/services/chaoxing_http_client_test.dart
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add apps/chaoxing_app/lib/services/chaoxing_http_client.dart apps/chaoxing_app/test/services/chaoxing_http_client_test.dart
git commit -m "feat: add safe chaoxing http client"
```

### Task 5: Implement Auth Check And Cookie Validation

**Files:**
- Create: `apps/chaoxing_app/lib/services/chaoxing_auth.dart`
- Test: `apps/chaoxing_app/test/services/chaoxing_auth_test.dart`

- [ ] **Step 1: Write failing auth tests**

Create `apps/chaoxing_app/test/services/chaoxing_auth_test.dart`:

```dart
import 'package:chaoxing_app/models/auth_state.dart';
import 'package:chaoxing_app/services/chaoxing_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('missing cookie returns missingCookie without network call', () async {
    final auth = ChaoxingAuth(clientFactory: (_) => throw StateError('network not allowed'));

    final result = await auth.checkAuth('');

    expect(result.status, AuthStatus.missingCookie);
  });

  test('login page signals mark cookie expired', () async {
    final auth = ChaoxingAuth(
      clientFactory: (cookie) => MockClient((request) async {
        return http.Response('<title>用户登录</title><button id="loginBtn">登录</button>', 200, request: request);
      }),
    );

    final result = await auth.checkAuth('UID=1');

    expect(result.status, AuthStatus.expired);
    expect(result.message, contains('重新登录'));
  });

  test('space page marks cookie authenticated', () async {
    final auth = ChaoxingAuth(
      clientFactory: (cookie) => MockClient((request) async {
        return http.Response('<title>空间首页</title><a>收件箱</a><span>我的课程</span>', 200, request: request);
      }),
    );

    final result = await auth.checkAuth('UID=1');

    expect(result.status, AuthStatus.authenticated);
    expect(result.title, '空间首页');
  });

  test('manual cookie header rejects newlines', () {
    expect(() => validateManualCookieHeader('UID=1\nAuthorization: bad'), throwsA(isA<FormatException>()));
    expect(validateManualCookieHeader('UID=1; vc=abc'), 'UID=1; vc=abc');
  });
}
```

Run:

```powershell
flutter test test/services/chaoxing_auth_test.dart
```

Expected: FAIL because `ChaoxingAuth` and `validateManualCookieHeader` do not exist.

- [ ] **Step 2: Implement auth service**

Create `apps/chaoxing_app/lib/services/chaoxing_auth.dart`:

```dart
import 'package:http/http.dart' as http;

import '../models/auth_state.dart';
import 'chaoxing_http_client.dart';

const defaultChaoxingHomeUrl = 'https://i.chaoxing.com/base?ws=1&t=1780231212848';

typedef AuthHttpClientFactory = http.Client Function(String cookieHeader);

class ChaoxingAuth {
  ChaoxingAuth({AuthHttpClientFactory? clientFactory, Uri? homeUri})
      : _clientFactory = clientFactory ?? ((_) => http.Client()),
        _homeUri = homeUri ?? Uri.parse(defaultChaoxingHomeUrl);

  final AuthHttpClientFactory _clientFactory;
  final Uri _homeUri;

  Future<AuthState> checkAuth(String? cookieHeader) async {
    final cookie = cookieHeader?.trim() ?? '';
    if (cookie.isEmpty) {
      return AuthState.missing;
    }

    final client = ChaoxingHttpClient(cookieHeader: cookie, inner: _clientFactory(cookie));
    try {
      final html = await client.getText(_homeUri, referer: _homeUri);
      final title = extractPageTitle(html);
      if (detectLoginSignals(_homeUri.toString(), html)) {
        return AuthState(
          status: AuthStatus.expired,
          checkedAt: DateTime.now(),
          title: title,
          finalUrl: _homeUri.toString(),
          message: '登录已过期，请重新登录学习通',
        );
      }
      return AuthState(
        status: AuthStatus.authenticated,
        checkedAt: DateTime.now(),
        title: title,
        finalUrl: _homeUri.toString(),
        message: '学习通登录可用',
      );
    } on ChaoxingClientException catch (error) {
      return AuthState(
        status: error.kind == ChaoxingErrorKind.networkUnavailable ? AuthStatus.networkError : AuthStatus.httpStatus,
        checkedAt: DateTime.now(),
        title: null,
        finalUrl: _homeUri.toString(),
        message: error.message,
      );
    }
  }
}

bool detectLoginSignals(String url, String html) {
  return RegExp(r'passport2\.chaoxing\.com\/login', caseSensitive: false).hasMatch(url) ||
      RegExp(r'passport2\.chaoxing\.com\/login', caseSensitive: false).hasMatch(html) ||
      RegExp(r'<title[^>]*>\s*用户登录\s*<\/title>', caseSensitive: false).hasMatch(html) ||
      RegExp(r'\bid=["'']loginBtn["'']', caseSensitive: false).hasMatch(html);
}

String? extractPageTitle(String html) {
  final match = RegExp(r'<title[^>]*>([\s\S]*?)<\/title>', caseSensitive: false).firstMatch(html);
  final value = match?.group(1);
  if (value == null) {
    return null;
  }
  return _decodeBasicHtmlEntities(value).replaceAll(RegExp(r'\s+'), ' ').trim();
}

String validateManualCookieHeader(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) {
    throw const FormatException('Cookie 不能为空');
  }
  if (trimmed.contains('\n') || trimmed.contains('\r')) {
    throw const FormatException('Cookie 不能包含换行');
  }
  final parts = trimmed.split(';').map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
  if (parts.length < 2 || parts.any((part) => !part.contains('='))) {
    throw const FormatException('Cookie 格式不完整');
  }
  return parts.join('; ');
}

String _decodeBasicHtmlEntities(String value) {
  return value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}
```

- [ ] **Step 3: Run auth tests**

Run:

```powershell
flutter test test/services/chaoxing_auth_test.dart
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add apps/chaoxing_app/lib/services/chaoxing_auth.dart apps/chaoxing_app/test/services/chaoxing_auth_test.dart
git commit -m "feat: add local chaoxing auth checks"
```

### Task 6: Add WebView Login Cookie Collector And Manual Fallback

**Files:**
- Create: `apps/chaoxing_app/lib/services/login_cookie_collector.dart`
- Create: `apps/chaoxing_app/lib/screens/login_screen.dart`
- Test: `apps/chaoxing_app/test/services/login_cookie_collector_test.dart`
- Test: `apps/chaoxing_app/test/screens/login_screen_test.dart`

- [ ] **Step 1: Write failing service tests for manual fallback**

Create `apps/chaoxing_app/test/services/login_cookie_collector_test.dart`:

```dart
import 'package:chaoxing_app/models/auth_state.dart';
import 'package:chaoxing_app/services/login_cookie_collector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('manual import saves cookie after successful auth check', () async {
    String? saved;
    final collector = LoginCookieCollector(
      checkAuth: (cookie) async => AuthState(
        status: AuthStatus.authenticated,
        checkedAt: DateTime(2026, 6, 8, 10),
        title: '空间首页',
        finalUrl: 'https://i.chaoxing.com/base',
        message: 'ok',
      ),
      saveCookie: (cookie) async => saved = cookie,
    );

    final state = await collector.importManualCookie('UID=1; vc=abc');

    expect(state.isAuthenticated, true);
    expect(saved, 'UID=1; vc=abc');
  });

  test('manual import does not save invalid auth cookie', () async {
    String? saved;
    final collector = LoginCookieCollector(
      checkAuth: (_) async => AuthState.missing,
      saveCookie: (cookie) async => saved = cookie,
    );

    final state = await collector.importManualCookie('UID=1; vc=abc');

    expect(state.status, AuthStatus.missingCookie);
    expect(saved, isNull);
  });
}
```

Run:

```powershell
flutter test test/services/login_cookie_collector_test.dart
```

Expected: FAIL because `LoginCookieCollector` does not exist.

- [ ] **Step 2: Implement login collector service**

Create `apps/chaoxing_app/lib/services/login_cookie_collector.dart`:

```dart
import 'dart:async';

import 'package:desktop_webview_window/desktop_webview_window.dart';

import '../models/auth_state.dart';
import 'chaoxing_auth.dart';

typedef AuthChecker = Future<AuthState> Function(String cookieHeader);
typedef CookieSaver = Future<void> Function(String cookieHeader);

class LoginCookieCollector {
  LoginCookieCollector({required AuthChecker checkAuth, required CookieSaver saveCookie})
      : _checkAuth = checkAuth,
        _saveCookie = saveCookie;

  final AuthChecker _checkAuth;
  final CookieSaver _saveCookie;

  Future<AuthState> importManualCookie(String input) async {
    final cookie = validateManualCookieHeader(input);
    final state = await _checkAuth(cookie);
    if (state.isAuthenticated) {
      await _saveCookie(cookie);
    }
    return state;
  }

  Future<AuthState> openWebViewLogin({
    Uri loginUri = const Uri.parse('https://passport2.chaoxing.com/login'),
    Duration pollInterval = const Duration(seconds: 2),
    Duration maxDuration = const Duration(minutes: 10),
  }) async {
    if (!await WebviewWindow.isWebviewAvailable()) {
      return AuthState(
        status: AuthStatus.unknown,
        checkedAt: DateTime.now(),
        title: null,
        finalUrl: loginUri.toString(),
        message: '当前 Windows WebView 不可用，请使用手动 Cookie 导入',
      );
    }
    final webview = await WebviewWindow.create(configuration: const CreateConfiguration(title: '登录学习通'));
    await webview.launch(loginUri.toString());
    final deadline = DateTime.now().add(maxDuration);
    while (DateTime.now().isBefore(deadline) && !webview.isClosed) {
      await Future<void>.delayed(pollInterval);
      final cookie = await _readChaoxingCookieHeader(webview);
      if (cookie == null || cookie.isEmpty) {
        continue;
      }
      final state = await _checkAuth(cookie);
      if (state.isAuthenticated) {
        await _saveCookie(cookie);
        webview.close();
        return state;
      }
    }
    return AuthState(
      status: AuthStatus.unknown,
      checkedAt: DateTime.now(),
      title: null,
      finalUrl: loginUri.toString(),
      message: '未能从 WebView 采集完整 Cookie，请使用手动 Cookie 导入',
    );
  }

  Future<String?> _readChaoxingCookieHeader(Webview webview) async {
    final raw = await webview.evaluateJavaScript('document.cookie');
    final value = raw?.toString().trim();
    if (value == null || value.isEmpty || value == 'null') {
      return null;
    }
    return value.replaceAll(RegExp(r'^"|"$'), '');
  }
}
```

- [ ] **Step 3: Add login screen widget test**

Create `apps/chaoxing_app/test/screens/login_screen_test.dart`:

```dart
import 'package:chaoxing_app/models/auth_state.dart';
import 'package:chaoxing_app/screens/login_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('manual cookie import clears text after successful login', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(
        authState: AuthState.missing,
        onWebViewLogin: () async => AuthState.missing,
        onManualCookieImport: (_) async => AuthState(
          status: AuthStatus.authenticated,
          checkedAt: DateTime(2026, 6, 8),
          title: '空间首页',
          finalUrl: 'https://i.chaoxing.com/base',
          message: '学习通登录可用',
        ),
      ),
    ));

    await tester.tap(find.text('手动导入 Cookie'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'UID=1; vc=abc');
    await tester.tap(find.text('验证并保存'));
    await tester.pumpAndSettle();

    expect(find.text('学习通登录可用'), findsOneWidget);
    expect(find.text('UID=1; vc=abc'), findsNothing);
  });
}
```

Run:

```powershell
flutter test test/screens/login_screen_test.dart
```

Expected: FAIL because `LoginScreen` does not exist.

- [ ] **Step 4: Implement LoginScreen**

Create `apps/chaoxing_app/lib/screens/login_screen.dart` with:

```dart
import 'package:flutter/material.dart';

import '../models/auth_state.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({
    required this.authState,
    required this.onWebViewLogin,
    required this.onManualCookieImport,
    super.key,
  });

  final AuthState authState;
  final Future<AuthState> Function() onWebViewLogin;
  final Future<AuthState> Function(String cookie) onManualCookieImport;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _cookieController = TextEditingController();
  AuthState? _state;
  bool _busy = false;
  bool _manualOpen = false;

  @override
  void dispose() {
    _cookieController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = _state ?? widget.authState;
    return Scaffold(
      appBar: AppBar(title: const Text('学习通登录')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: Icon(state.isAuthenticated ? Icons.verified_user : Icons.login),
            title: Text(state.isAuthenticated ? '已登录学习通' : '需要登录学习通'),
            subtitle: Text(state.message ?? '请使用 WebView 登录，失败时使用手动 Cookie 导入'),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _runWebViewLogin,
            icon: const Icon(Icons.open_in_browser),
            label: const Text('打开登录窗口'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : () => setState(() => _manualOpen = !_manualOpen),
            icon: const Icon(Icons.cookie),
            label: const Text('手动导入 Cookie'),
          ),
          if (_manualOpen) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _cookieController,
              minLines: 3,
              maxLines: 5,
              decoration: const InputDecoration(
                labelText: 'Cookie header',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _runManualImport,
              icon: const Icon(Icons.save),
              label: const Text('验证并保存'),
            ),
          ],
          if (_busy) const Padding(padding: EdgeInsets.only(top: 16), child: LinearProgressIndicator()),
        ],
      ),
    );
  }

  Future<void> _runWebViewLogin() async {
    setState(() => _busy = true);
    final result = await widget.onWebViewLogin();
    if (mounted) {
      setState(() {
        _state = result;
        _busy = false;
      });
    }
  }

  Future<void> _runManualImport() async {
    setState(() => _busy = true);
    final result = await widget.onManualCookieImport(_cookieController.text);
    if (result.isAuthenticated) {
      _cookieController.clear();
    }
    if (mounted) {
      setState(() {
        _state = result;
        _busy = false;
      });
    }
  }
}
```

- [ ] **Step 5: Run login tests**

Run:

```powershell
flutter test test/services/login_cookie_collector_test.dart test/screens/login_screen_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/chaoxing_app/lib/services/login_cookie_collector.dart apps/chaoxing_app/lib/screens/login_screen.dart apps/chaoxing_app/test/services/login_cookie_collector_test.dart apps/chaoxing_app/test/screens/login_screen_test.dart
git commit -m "feat: add chaoxing login cookie flow"
```

### Task 7: Implement Inbox Client With Fixtures

**Files:**
- Create: `apps/chaoxing_app/lib/models/inbox_message.dart`
- Create: `apps/chaoxing_app/lib/services/inbox_client.dart`
- Create: `apps/chaoxing_app/test/fixtures/chaoxing/home_with_inbox.html`
- Create: `apps/chaoxing_app/test/fixtures/chaoxing/inbox_page.html`
- Test: `apps/chaoxing_app/test/services/inbox_client_test.dart`

- [ ] **Step 1: Add fixture files**

Create `apps/chaoxing_app/test/fixtures/chaoxing/home_with_inbox.html`:

```html
<html><body><a href="https://notice.chaoxing.com/pc/notice/myNotice?s=abc123">收件箱</a></body></html>
```

Create `apps/chaoxing_app/test/fixtures/chaoxing/inbox_page.html`:

```html
<script>
window.type = "2";
window.noticeType = "";
window.nowYear = "2026";
window.folderUUID = "folder-1";
window.fidsCode = "fid-1";
</script>
```

- [ ] **Step 2: Write failing inbox tests**

Create `apps/chaoxing_app/test/services/inbox_client_test.dart`:

```dart
import 'dart:io';

import 'package:chaoxing_app/services/inbox_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('extracts inbox url and config', () {
    final home = File('test/fixtures/chaoxing/home_with_inbox.html').readAsStringSync();
    final inbox = File('test/fixtures/chaoxing/inbox_page.html').readAsStringSync();

    expect(findInboxUrl(home, Uri.parse('https://i.chaoxing.com/base')).toString(), 'https://notice.chaoxing.com/pc/notice/myNotice?s=abc123');
    expect(extractInboxPageConfig(inbox).year, '2026');
    expect(extractInboxPageConfig(inbox).folderUUID, 'folder-1');
  });

  test('fetches paged notices and normalizes messages', () async {
    final home = File('test/fixtures/chaoxing/home_with_inbox.html').readAsStringSync();
    final inbox = File('test/fixtures/chaoxing/inbox_page.html').readAsStringSync();
    var postCount = 0;
    final client = InboxClient(
      cookieHeader: 'UID=1',
      httpClientFactory: (_) => MockClient((request) async {
        if (request.url.host == 'i.chaoxing.com') {
          return http.Response(home, 200, request: request);
        }
        if (request.url.path.contains('/myNotice')) {
          return http.Response(inbox, 200, request: request);
        }
        postCount += 1;
        return http.Response('{"status":true,"notices":{"list":[{"id":1,"uuid":"u1","title":"作业提醒","createrName":"老师","sendTime":"2026-06-08 10:00","isread":1,"content":"<b>完成作业</b>","sendTag":0}],"lastGetId":"","lastPage":true}}', 200, request: request);
      }),
    );

    final result = await client.fetchMessages(limit: 10);

    expect(postCount, 1);
    expect(result.messages.single.id, '1');
    expect(result.messages.single.uuid, 'u1');
    expect(result.messages.single.content, '完成作业');
    expect(result.messages.single.detailUrl, 'https://notice.chaoxing.com/pc/notice/u1/detail?sendTag=0');
  });
}
```

Run:

```powershell
flutter test test/services/inbox_client_test.dart
```

Expected: FAIL because inbox model and client do not exist.

- [ ] **Step 3: Implement InboxMessage model**

Create `apps/chaoxing_app/lib/models/inbox_message.dart`:

```dart
class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.uuid,
    required this.title,
    required this.sender,
    required this.sendTime,
    required this.isRead,
    required this.content,
    required this.detailUrl,
    required this.sendTag,
  });

  final String id;
  final String? uuid;
  final String title;
  final String? sender;
  final String? sendTime;
  final bool isRead;
  final String? content;
  final String? detailUrl;
  final Object? sendTag;
}
```

- [ ] **Step 4: Implement InboxClient**

Create `apps/chaoxing_app/lib/services/inbox_client.dart` with public functions `findInboxUrl`, `extractInboxPageConfig`, `normalizeNotice`, and class `InboxClient`. Use the same behavior as `src/inbox.ts`: locate `https://notice.chaoxing.com/pc/notice/myNotice?s=...`, read `window.type`, `window.noticeType`, `window.nowYear`, `window.folderUUID`, `window.fidsCode`, POST `/pc/notice/getNoticeList`, merge first-page `topNotices`, `urgentNotices`, and `notices.list`, then stop at `lastPage`, missing `lastGetId`, or limit. Use `ChaoxingHttpClient.postFormJson()` and `stripHtml()` with `style/script/tag` removal and basic entity decoding.

The Dart class signatures must be:

```dart
class InboxClient {
  InboxClient({required String cookieHeader, http.Client Function(String cookieHeader)? httpClientFactory});
  Future<InboxFetchResult> fetchMessages({int limit = 100, Uri? homeUri});
}

class InboxFetchResult {
  const InboxFetchResult({
    required this.inboxUrl,
    required this.apiUrl,
    required this.year,
    required this.lastGetId,
    required this.lastPage,
    required this.pagesFetched,
    required this.totalFetched,
    required this.messages,
  });

  final Uri inboxUrl;
  final Uri apiUrl;
  final String year;
  final String? lastGetId;
  final bool lastPage;
  final int pagesFetched;
  final int totalFetched;
  final List<InboxMessage> messages;
}

class InboxPageConfig {
  const InboxPageConfig({
    required this.type,
    required this.noticeType,
    required this.year,
    required this.folderUUID,
    required this.fidsCode,
    required this.queryFolderNoticePrevYear,
  });

  final String type;
  final String noticeType;
  final String year;
  final String folderUUID;
  final String fidsCode;
  final String queryFolderNoticePrevYear;
}
```

- [ ] **Step 5: Run inbox tests**

Run:

```powershell
flutter test test/services/inbox_client_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/chaoxing_app/lib/models/inbox_message.dart apps/chaoxing_app/lib/services/inbox_client.dart apps/chaoxing_app/test/fixtures/chaoxing/home_with_inbox.html apps/chaoxing_app/test/fixtures/chaoxing/inbox_page.html apps/chaoxing_app/test/services/inbox_client_test.dart
git commit -m "feat: fetch chaoxing inbox messages locally"
```

### Task 8: Implement Message Processor And Detail Link Extraction

**Files:**
- Create: `apps/chaoxing_app/lib/services/message_processor.dart`
- Test: `apps/chaoxing_app/test/services/message_processor_test.dart`

- [ ] **Step 1: Write failing processor tests**

Create `apps/chaoxing_app/test/services/message_processor_test.dart`:

```dart
import 'dart:convert';

import 'package:chaoxing_app/models/inbox_message.dart';
import 'package:chaoxing_app/services/message_processor.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('detects assignment and exam related messages', () {
    expect(isAssignmentOrExamRelated(message('作业截止提醒')), true);
    expect(isAssignmentOrExamRelated(message('期末考试通知')), true);
    expect(isAssignmentOrExamRelated(message('校园活动')), false);
  });

  test('decodes iframe names and extracts unique work links', () async {
    final payload = Uri.encodeComponent(jsonEncode({'url': 'https://mooc1.chaoxing.com/work?workOrExam=work&workId=1'}));
    final processor = MessageProcessor(
      cookieHeader: 'UID=1',
      httpClientFactory: (_) => MockClient((request) async {
        return http.Response('{"status":true,"msg":{"title":"作业","rtf_content":"<iframe name=\\"$payload\\"></iframe>"}}', 200, request: request);
      }),
    );

    final summary = await processor.fetchDetailSummary(message('作业提醒', uuid: 'u1'));

    expect(summary.assignmentLinks, ['https://mooc1.chaoxing.com/work?workOrExam=work&workId=1']);
  });

  test('processMessages isolates detail failures', () async {
    final processor = MessageProcessor(
      cookieHeader: 'UID=1',
      httpClientFactory: (_) => MockClient((request) async => http.Response('missing', 404, request: request)),
    );

    final result = await processor.processMessages([message('作业提醒', uuid: 'u1')], detailsLimit: 1);

    expect(result.failedDetails.single.sourceTitle, '作业提醒');
    expect(result.uniqueLinks, isEmpty);
  });
}

InboxMessage message(String title, {String uuid = 'u1'}) {
  return InboxMessage(
    id: uuid,
    uuid: uuid,
    title: title,
    sender: '老师',
    sendTime: '2026-06-08 10:00',
    isRead: false,
    content: title,
    detailUrl: 'https://notice.chaoxing.com/pc/notice/$uuid/detail',
    sendTag: 0,
  );
}
```

Run:

```powershell
flutter test test/services/message_processor_test.dart
```

Expected: FAIL because `MessageProcessor` does not exist.

- [ ] **Step 2: Implement processor**

Create `apps/chaoxing_app/lib/services/message_processor.dart` with:

```dart
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/inbox_message.dart';
import 'chaoxing_http_client.dart';

bool isAssignmentOrExamRelated(InboxMessage message) {
  return RegExp(r'作业|考试|测验|测试|截止|结束提醒|答题|试卷|练习').hasMatch('${message.title}\n${message.content ?? ''}');
}

class MessageProcessor {
  MessageProcessor({required String cookieHeader, http.Client Function(String cookieHeader)? httpClientFactory})
      : _cookieHeader = cookieHeader,
        _httpClientFactory = httpClientFactory;

  final String _cookieHeader;
  final http.Client Function(String cookieHeader)? _httpClientFactory;

  Future<ProcessorResult> processMessages(List<InboxMessage> messages, {int detailsLimit = 10}) async {
    final relevant = messages.where(isAssignmentOrExamRelated).take(detailsLimit).toList();
    final summaries = <DetailSummary>[];
    final failed = <DetailFailure>[];
    for (final message in relevant) {
      try {
        summaries.add(await fetchDetailSummary(message));
      } catch (error) {
        failed.add(DetailFailure(sourceTitle: message.title, message: error.toString()));
      }
    }
    final unique = <String, DetailSummary>{};
    for (final summary in summaries) {
      for (final link in summary.assignmentLinks) {
        if (_isWorkOrExamLink(link)) {
          unique.putIfAbsent(link, () => summary);
        }
      }
    }
    return ProcessorResult(
      relevantCount: relevant.length,
      inspectedDetails: summaries.length,
      uniqueLinks: unique,
      failedDetails: failed,
    );
  }

  Future<DetailSummary> fetchDetailSummary(InboxMessage message) async {
    final id = message.uuid ?? message.id;
    final sendTag = message.sendTag ?? 0;
    final uri = Uri.parse('https://notice.chaoxing.com/pc/notice/$id/getNoticeDetail?sendTag=$sendTag');
    final client = ChaoxingHttpClient(cookieHeader: _cookieHeader, inner: _httpClientFactory?.call(_cookieHeader));
    final data = await client.getJson(uri, referer: Uri.tryParse(message.detailUrl ?? 'https://notice.chaoxing.com/pc/notice/myNotice'));
    final detail = data['msg'] is Map ? (data['msg'] as Map).cast<String, dynamic>() : <String, dynamic>{};
    final rtf = detail['rtf_content']?.toString() ?? '';
    final decoded = decodeIframeNames(rtf);
    final links = [
      ...extractUrls(rtf),
      ...extractUrls(jsonEncode(decoded)),
    ].where((link) {
      return RegExp(r'(exam|work|homework|task|mooc1|course|clazz|classId|courseId|examOrWork)', caseSensitive: false).hasMatch(link);
    }).toList();
    return DetailSummary(
      title: message.title,
      sendTime: message.sendTime,
      detailStatus: 200,
      apiStatus: data['status'] == true,
      detailTitle: detail['title']?.toString(),
      sourceType: detail['sourceType'],
      content: stripHtml(detail['content']?.toString() ?? rtf),
      assignmentLinks: links.toSet().toList(),
      decodedAttachments: decoded,
    );
  }
}

class ProcessorResult {
  const ProcessorResult({required this.relevantCount, required this.inspectedDetails, required this.uniqueLinks, required this.failedDetails});
  final int relevantCount;
  final int inspectedDetails;
  final Map<String, DetailSummary> uniqueLinks;
  final List<DetailFailure> failedDetails;
}

class DetailSummary {
  const DetailSummary({
    required this.title,
    required this.sendTime,
    required this.detailStatus,
    required this.apiStatus,
    required this.detailTitle,
    required this.sourceType,
    required this.content,
    required this.assignmentLinks,
    required this.decodedAttachments,
  });

  final String title;
  final String? sendTime;
  final int detailStatus;
  final bool apiStatus;
  final String? detailTitle;
  final Object? sourceType;
  final String? content;
  final List<String> assignmentLinks;
  final List<Object?> decodedAttachments;
}

class DetailFailure {
  const DetailFailure({required this.sourceTitle, required this.message});
  final String sourceTitle;
  final String message;
}

List<Object?> decodeIframeNames(String html) {
  final names = RegExp(r'<iframe\b[^>]*\bname=["'']([^"'']+)["''][^>]*>', caseSensitive: false)
      .allMatches(html)
      .map((match) => match.group(1)!)
      .toList();
  final decoded = <Object?>[];
  for (final name in names) {
    final attempts = <String Function()>[
      () => Uri.decodeComponent(name),
      () => utf8.decode(base64Url.decode(base64Url.normalize(Uri.decodeComponent(name)))),
    ];
    for (final attempt in attempts) {
      try {
        decoded.add(jsonDecode(attempt()));
        break;
      } catch (_) {}
    }
  }
  return decoded;
}

List<String> extractUrls(String text) {
  return RegExp(r'https?:\\?/\\?/[^"'' <>)\\]+')
      .allMatches(text)
      .map((match) => match.group(0)!.replaceAll(r'\/', '/'))
      .toList();
}

String? stripHtml(String value) {
  final stripped = value
      .replaceAll(RegExp(r'<style[\s\S]*?<\/style>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<script[\s\S]*?<\/script>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return stripped.isEmpty ? null : stripped;
}

bool _isWorkOrExamLink(String link) {
  return RegExp(r'workOrExam=(?:work|exam)', caseSensitive: false).hasMatch(link) ||
      RegExp(r'/(?:work|exam)\b', caseSensitive: false).hasMatch(link);
}
```

- [ ] **Step 3: Run processor tests**

Run:

```powershell
flutter test test/services/message_processor_test.dart
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add apps/chaoxing_app/lib/services/message_processor.dart apps/chaoxing_app/test/services/message_processor_test.dart
git commit -m "feat: process chaoxing notice details locally"
```

### Task 9: Implement Requirement Parser And Fetcher

**Files:**
- Create: `apps/chaoxing_app/lib/models/requirement.dart`
- Create: `apps/chaoxing_app/lib/services/requirements_client.dart`
- Create: `apps/chaoxing_app/test/fixtures/chaoxing/requirement_assignment.html`
- Test: `apps/chaoxing_app/test/services/requirements_client_test.dart`

- [ ] **Step 1: Add requirement fixture**

Create `apps/chaoxing_app/test/fixtures/chaoxing/requirement_assignment.html`:

```html
<html>
<head><title>作业详情</title></head>
<body>
<input type="hidden" name="courseId" value="c1">
<input type="hidden" name="classId" value="cl1">
<input type="hidden" name="workId" value="w1">
<input type="hidden" name="answerId" value="a1">
<div>开放时间：2026-06-01 08:00 至 2026-06-10 22:00</div>
<div>作答状态：未作答</div>
<div class="question">第一题 简答题</div>
</body>
</html>
```

- [ ] **Step 2: Write failing requirement tests**

Create `apps/chaoxing_app/test/services/requirements_client_test.dart`:

```dart
import 'dart:io';

import 'package:chaoxing_app/services/message_processor.dart';
import 'package:chaoxing_app/services/requirements_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parses ids time window status and question summary', () {
    final html = File('test/fixtures/chaoxing/requirement_assignment.html').readAsStringSync();

    final requirement = parseRequirement(
      html: html,
      entryUrl: 'https://mooc1.chaoxing.com/work?courseId=c1&classId=cl1',
      finalUrl: 'https://mooc1.chaoxing.com/work?courseId=c1&classId=cl1&workId=w1',
      status: 200,
      summary: const DetailSummary(
        title: '作业提醒',
        sendTime: '2026-06-08 10:00',
        detailStatus: 200,
        apiStatus: true,
        detailTitle: null,
        sourceType: null,
        content: '请完成作业',
        assignmentLinks: [],
        decodedAttachments: [],
      ),
    );

    expect(requirement.courseId, 'c1');
    expect(requirement.classId, 'cl1');
    expect(requirement.workId, 'w1');
    expect(requirement.answerId, 'a1');
    expect(requirement.timeWindow.start, '2026-06-01 08:00');
    expect(requirement.timeWindow.end, '2026-06-10 22:00');
    expect(requirement.workStatus, '未作答');
    expect(requirement.questionSummary, contains('第一题'));
  });

  test('fetchRequirement preserves source summary', () async {
    final html = File('test/fixtures/chaoxing/requirement_assignment.html').readAsStringSync();
    final client = RequirementsClient(
      cookieHeader: 'UID=1',
      httpClientFactory: (_) => MockClient((request) async => http.Response(html, 200, request: request)),
    );

    final requirement = await client.fetchRequirement(
      entryUrl: 'https://mooc1.chaoxing.com/work?courseId=c1&classId=cl1',
      summary: const DetailSummary(
        title: '作业提醒',
        sendTime: '2026-06-08 10:00',
        detailStatus: 200,
        apiStatus: true,
        detailTitle: null,
        sourceType: null,
        content: '请完成作业',
        assignmentLinks: [],
        decodedAttachments: [],
      ),
    );

    expect(requirement.sourceTitle, '作业提醒');
    expect(requirement.finalUrl, contains('work'));
  });
}
```

Run:

```powershell
flutter test test/services/requirements_client_test.dart
```

Expected: FAIL because requirement model and client do not exist.

- [ ] **Step 3: Implement requirement model**

Create `apps/chaoxing_app/lib/models/requirement.dart`:

```dart
class Requirement {
  const Requirement({
    required this.entryUrl,
    required this.finalUrl,
    required this.status,
    required this.sourceTitle,
    required this.sourceSendTime,
    required this.sourceContent,
    required this.pageTitle,
    required this.courseId,
    required this.classId,
    required this.workId,
    required this.answerId,
    required this.examId,
    required this.workStatus,
    required this.timeWindow,
    required this.questionSummary,
  });

  final String entryUrl;
  final String finalUrl;
  final int status;
  final String sourceTitle;
  final String? sourceSendTime;
  final String? sourceContent;
  final String? pageTitle;
  final String? courseId;
  final String? classId;
  final String? workId;
  final String? answerId;
  final String? examId;
  final String workStatus;
  final RequirementTimeWindow timeWindow;
  final String? questionSummary;
}

class RequirementTimeWindow {
  const RequirementTimeWindow({required this.start, required this.end});

  final String? start;
  final String? end;
}
```

- [ ] **Step 4: Implement parser and fetcher**

Create `apps/chaoxing_app/lib/services/requirements_client.dart`. Use `package:html/parser.dart` as `html_parser` and `package:html/dom.dart`. The public API must be:

```dart
class RequirementsClient {
  RequirementsClient({required String cookieHeader, http.Client Function(String cookieHeader)? httpClientFactory});
  Future<Requirement> fetchRequirement({required String entryUrl, required DetailSummary summary});
}

Requirement parseRequirement({
  required String html,
  required String entryUrl,
  required String finalUrl,
  required int status,
  required DetailSummary summary,
});
```

Parsing rules:

- `pageTitle`: `<title>` text with collapsed whitespace.
- IDs: first read hidden inputs named `courseId`, `classId`, `workId`, `answerId`, `examId`; if missing, read query params from `finalUrl`; if still missing, read query params from `entryUrl`.
- Time window: match `开放时间|作答时间|考试时间|时间` followed by `yyyy-MM-dd HH:mm 至 yyyy-MM-dd HH:mm`; also accept `/` as date separator and normalize to `-`.
- `workStatus`: match `作答状态[:：]\s*...` or page text containing `未作答`、`已完成`、`已提交`、`已过期`; fallback to `unknown`.
- `questionSummary`: join up to five `.question`, `.TiMu`, `.ans-formula-moudle`, or text blocks containing `第...题`; collapse whitespace and limit to 300 characters.
- Fetcher uses `ChaoxingHttpClient.get()` and passes `Referer: https://notice.chaoxing.com/pc/notice/myNotice`.

- [ ] **Step 5: Run requirement tests**

Run:

```powershell
flutter test test/services/requirements_client_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/chaoxing_app/lib/models/requirement.dart apps/chaoxing_app/lib/services/requirements_client.dart apps/chaoxing_app/test/fixtures/chaoxing/requirement_assignment.html apps/chaoxing_app/test/services/requirements_client_test.dart
git commit -m "feat: parse chaoxing requirement pages"
```

### Task 10: Build Local Sync Items And AppSyncResponse

**Files:**
- Modify: `apps/chaoxing_app/lib/models/sync_item.dart`
- Modify: `apps/chaoxing_app/lib/models/app_sync_response.dart`
- Create: `apps/chaoxing_app/lib/services/sync_model_builder.dart`
- Test: `apps/chaoxing_app/test/services/sync_model_builder_test.dart`
- Test: `apps/chaoxing_app/test/models/sync_item_test.dart`

- [ ] **Step 1: Write failing sync model tests**

Create or extend `apps/chaoxing_app/test/services/sync_model_builder_test.dart`:

```dart
import 'package:chaoxing_app/models/requirement.dart';
import 'package:chaoxing_app/models/sync_item.dart';
import 'package:chaoxing_app/services/sync_model_builder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('builds stable assignment item from work id', () {
    final item = buildSyncItem(requirement(), generatedAt: DateTime(2026, 6, 8, 10))!;

    expect(item.id, 'assignment-w1');
    expect(item.kind, SyncItemKind.assignment);
    expect(item.dueAt, DateTime(2026, 6, 10, 22));
    expect(item.displayStatus, SyncDisplayStatus.upcoming);
    expect(item.dueInHours, 62);
  });

  test('infers exam kind and stable id from exam url', () {
    final item = buildSyncItem(requirement(
      entryUrl: 'https://mooc1.chaoxing.com/exam?examId=e1',
      finalUrl: 'https://mooc1.chaoxing.com/exam?examId=e1',
      sourceTitle: '期末考试',
      workId: null,
      examId: 'e1',
    ), generatedAt: DateTime(2026, 6, 8, 10))!;

    expect(item.id, 'exam-e1');
    expect(item.kind, SyncItemKind.exam);
  });

  test('sorts overdue today upcoming and carries failures', () {
    final response = buildAppSyncResponse(
      requirements: [requirement()],
      failures: const [AppSyncFailure(entryUrl: 'https://mooc1.chaoxing.com/bad', sourceTitle: '坏链接', message: 'parse_failed')],
      authStatus: 'authenticated',
      generatedAt: DateTime(2026, 6, 8, 10),
    );

    expect(response.items.single.title, '作业提醒');
    expect(response.failures.single.message, 'parse_failed');
    expect(response.authStatus, 'authenticated');
  });
}

Requirement requirement({
  String entryUrl = 'https://mooc1.chaoxing.com/work?workId=w1',
  String finalUrl = 'https://mooc1.chaoxing.com/work?workId=w1',
  String sourceTitle = '作业提醒',
  String? workId = 'w1',
  String? examId,
}) {
  return Requirement(
    entryUrl: entryUrl,
    finalUrl: finalUrl,
    status: 200,
    sourceTitle: sourceTitle,
    sourceSendTime: '2026-06-08 10:00',
    sourceContent: '请完成作业',
    pageTitle: '作业详情',
    courseId: 'c1',
    classId: 'cl1',
    workId: workId,
    answerId: 'a1',
    examId: examId,
    workStatus: '未作答',
    timeWindow: const RequirementTimeWindow(start: '2026-06-01 08:00', end: '2026-06-10 22:00'),
    questionSummary: '第一题',
  );
}
```

Run:

```powershell
flutter test test/services/sync_model_builder_test.dart
```

Expected: FAIL because builder does not exist and `SyncItem` lacks `examId` or `sources`.

- [ ] **Step 2: Extend SyncItem compatibly**

Modify `apps/chaoxing_app/lib/models/sync_item.dart`:

- Add optional fields `examId` and `sources` to constructor and class.
- Include `examId` and `sources` in `fromJson()` and `toJson()`.
- Preserve existing enum names and existing fields so current UI and tests still compile.
- Keep `isDueSoon` behavior, but compute against a single `DateTime.now()` local variable to avoid inconsistent boundary checks.

The added constructor fields must be:

```dart
this.examId,
this.sources = const [],
```

The JSON additions must be:

```dart
examId: json.readNullableString('examId'),
sources: json['sources'] is List ? (json['sources'] as List).whereType<String>().toList() : const [],
```

and:

```dart
'examId': examId,
'sources': sources,
```

- [ ] **Step 3: Extend AppSyncResponse meta fields**

Modify `apps/chaoxing_app/lib/models/app_sync_response.dart`:

- Keep existing `lastSyncedAt`, `authStatus`, `items`, `failures`.
- Add optional `lastSuccessfulSyncAt`, `errorSummary`, `meta`.
- Include all fields in JSON.

Use:

```dart
final DateTime? lastSuccessfulSyncAt;
final String? errorSummary;
final Map<String, dynamic> meta;
```

- [ ] **Step 4: Implement sync model builder**

Create `apps/chaoxing_app/lib/services/sync_model_builder.dart` with functions:

```dart
SyncItem? buildSyncItem(Requirement requirement, {DateTime? generatedAt});
AppSyncResponse buildAppSyncResponse({
  required List<Requirement> requirements,
  required List<AppSyncFailure> failures,
  required String authStatus,
  DateTime? generatedAt,
  Map<String, dynamic> meta = const {},
});
DateTime? parseChaoxingDateTime(String? value, String? sourceSendTime, DateTime fallbackDate);
SyncDisplayStatus displayStatusFor(DateTime? dueAt, DateTime now);
```

Implementation details:

- Return `null` when no `dueAt` can be parsed.
- Parse `yyyy-MM-dd HH:mm[:ss]`, `yyyy/MM/dd HH:mm[:ss]`, `MM-dd HH:mm[:ss]`, and `DateTime.tryParse`.
- For `MM-dd` without year, infer from `sourceSendTime`; if source month is December and due month is January, use next year.
- Use UTC+8 semantics by constructing local `DateTime(year, month, day, hour, minute, second)` for app display.
- `kind` is `exam` if URL/title/pageTitle contains `workOrExam=exam`、`/exam`、`考试`、`测验`、`测试`、`试卷`; otherwise `assignment`.
- Stable ID priority: `workId`, `examId`, `examId` query param, final URL hash, entry URL hash; prefix with `assignment-` or `exam-`.
- `displayStatus`: before now is `overdue`; same local calendar day is `today`; future with dueAt is `upcoming`; missing dueAt is `unscheduled`.
- Sort items by `dueAt` ascending, unscheduled last, then title.

- [ ] **Step 5: Run sync model tests and existing model tests**

Run:

```powershell
flutter test test/services/sync_model_builder_test.dart test/models/sync_item_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/chaoxing_app/lib/models/sync_item.dart apps/chaoxing_app/lib/models/app_sync_response.dart apps/chaoxing_app/lib/services/sync_model_builder.dart apps/chaoxing_app/test/services/sync_model_builder_test.dart apps/chaoxing_app/test/models/sync_item_test.dart
git commit -m "feat: build local app sync response"
```

### Task 11: Add Local Sync Runner And Integration Fixture Test

**Files:**
- Create: `apps/chaoxing_app/lib/services/local_sync_runner.dart`
- Test: `apps/chaoxing_app/test/services/local_sync_runner_test.dart`

- [ ] **Step 1: Write failing sync runner test**

Create `apps/chaoxing_app/test/services/local_sync_runner_test.dart`:

```dart
import 'dart:io';

import 'package:chaoxing_app/models/app_config.dart';
import 'package:chaoxing_app/models/auth_state.dart';
import 'package:chaoxing_app/services/local_sync_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('runs inbox detail requirement pipeline and returns local response', () async {
    final home = File('test/fixtures/chaoxing/home_with_inbox.html').readAsStringSync();
    final inbox = File('test/fixtures/chaoxing/inbox_page.html').readAsStringSync();
    final requirement = File('test/fixtures/chaoxing/requirement_assignment.html').readAsStringSync();
    final runner = LocalSyncRunner(
      loadCookie: () async => 'UID=1; vc=abc',
      checkAuth: (_) async => AuthState(
        status: AuthStatus.authenticated,
        checkedAt: DateTime(2026, 6, 8, 10),
        title: '空间首页',
        finalUrl: 'https://i.chaoxing.com/base',
        message: 'ok',
      ),
      httpClientFactory: (_) => MockClient((request) async {
        if (request.url.host == 'i.chaoxing.com') {
          return http.Response(home, 200, request: request);
        }
        if (request.url.path.contains('/myNotice')) {
          return http.Response(inbox, 200, request: request);
        }
        if (request.url.path.contains('/getNoticeList')) {
          return http.Response('{"status":true,"notices":{"list":[{"id":1,"uuid":"u1","title":"作业提醒","sendTime":"2026-06-08 10:00","content":"作业","sendTag":0}],"lastGetId":"","lastPage":true}}', 200, request: request);
        }
        if (request.url.path.contains('/getNoticeDetail')) {
          return http.Response('{"status":true,"msg":{"title":"作业","rtf_content":"https://mooc1.chaoxing.com/work?workOrExam=work&workId=w1"}}', 200, request: request);
        }
        if (request.url.host == 'mooc1.chaoxing.com') {
          return http.Response(requirement, 200, request: request);
        }
        return http.Response('not found', 404, request: request);
      }),
    );

    final response = await runner.sync(
      config: const AppConfig(
        refreshMinutes: 60,
        autoSyncEnabled: true,
        syncLimits: SyncLimits(inboxLimit: 20, detailsLimit: 5, requirementsLimit: 10),
        hasLegacyWorkerConfig: false,
      ),
      now: DateTime(2026, 6, 8, 10),
    );

    expect(response.authStatus, 'authenticated');
    expect(response.items.single.id, 'assignment-w1');
    expect(response.failures, isEmpty);
    expect(response.meta['inboxFetched'], 1);
  });
}
```

Run:

```powershell
flutter test test/services/local_sync_runner_test.dart
```

Expected: FAIL because `LocalSyncRunner` does not exist.

- [ ] **Step 2: Implement LocalSyncRunner**

Create `apps/chaoxing_app/lib/services/local_sync_runner.dart`:

```dart
import 'package:http/http.dart' as http;

import '../models/app_config.dart';
import '../models/app_sync_response.dart';
import '../models/auth_state.dart';
import 'inbox_client.dart';
import 'message_processor.dart';
import 'requirements_client.dart';
import 'sync_model_builder.dart';

typedef CookieLoader = Future<String?> Function();
typedef AuthCheck = Future<AuthState> Function(String cookieHeader);

class LocalSyncRunner {
  LocalSyncRunner({
    required CookieLoader loadCookie,
    required AuthCheck checkAuth,
    http.Client Function(String cookieHeader)? httpClientFactory,
  })  : _loadCookie = loadCookie,
        _checkAuth = checkAuth,
        _httpClientFactory = httpClientFactory;

  final CookieLoader _loadCookie;
  final AuthCheck _checkAuth;
  final http.Client Function(String cookieHeader)? _httpClientFactory;

  Future<AppSyncResponse> sync({required AppConfig config, DateTime? now}) async {
    final generatedAt = now ?? DateTime.now();
    final cookie = (await _loadCookie())?.trim() ?? '';
    if (cookie.isEmpty) {
      return AppSyncResponse(
        lastSyncedAt: generatedAt,
        authStatus: 'missingCookie',
        items: const [],
        failures: const [],
        errorSummary: '未登录学习通',
        meta: const {},
      );
    }
    final auth = await _checkAuth(cookie);
    if (!auth.isAuthenticated) {
      return AppSyncResponse(
        lastSyncedAt: generatedAt,
        authStatus: auth.status.name,
        items: const [],
        failures: const [],
        errorSummary: auth.message,
        meta: const {},
      );
    }

    final inbox = await InboxClient(cookieHeader: cookie, httpClientFactory: _httpClientFactory).fetchMessages(limit: config.syncLimits.inboxLimit);
    final processed = await MessageProcessor(cookieHeader: cookie, httpClientFactory: _httpClientFactory).processMessages(
      inbox.messages,
      detailsLimit: config.syncLimits.detailsLimit,
    );
    final requirementsClient = RequirementsClient(cookieHeader: cookie, httpClientFactory: _httpClientFactory);
    final requirements = <Requirement>[];
    final failures = <AppSyncFailure>[];
    for (final entry in processed.uniqueLinks.entries.take(config.syncLimits.requirementsLimit)) {
      try {
        requirements.add(await requirementsClient.fetchRequirement(entryUrl: entry.key, summary: entry.value));
      } catch (error) {
        failures.add(AppSyncFailure(entryUrl: entry.key, sourceTitle: entry.value.title, message: error.toString()));
      }
    }
    for (final failed in processed.failedDetails) {
      failures.add(AppSyncFailure(entryUrl: '', sourceTitle: failed.sourceTitle, message: failed.message));
    }
    return buildAppSyncResponse(
      requirements: requirements,
      failures: failures,
      authStatus: auth.status.name,
      generatedAt: generatedAt,
      meta: {
        'inboxFetched': inbox.totalFetched,
        'inboxRelevant': processed.relevantCount,
        'inspectedDetails': processed.inspectedDetails,
        'uniqueLinks': processed.uniqueLinks.length,
        'failedDetails': processed.failedDetails.length,
      },
    );
  }
}
```

Add import for `Requirement` from `../models/requirement.dart`.

- [ ] **Step 3: Run sync runner test**

Run:

```powershell
flutter test test/services/local_sync_runner_test.dart
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add apps/chaoxing_app/lib/services/local_sync_runner.dart apps/chaoxing_app/test/services/local_sync_runner_test.dart
git commit -m "feat: run local chaoxing sync pipeline"
```

### Task 12: Implement Reminder Scheduler And Notification Dedupe

**Files:**
- Create: `apps/chaoxing_app/lib/services/reminder_scheduler.dart`
- Test: `apps/chaoxing_app/test/services/reminder_scheduler_test.dart`

- [ ] **Step 1: Write failing scheduler tests**

Create `apps/chaoxing_app/test/services/reminder_scheduler_test.dart`:

```dart
import 'package:chaoxing_app/models/reminder_config.dart';
import 'package:chaoxing_app/models/reminder_history.dart';
import 'package:chaoxing_app/models/sync_item.dart';
import 'package:chaoxing_app/services/reminder_scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('creates assignment and exam advance notifications independently', () {
    final now = DateTime(2026, 6, 8, 9);
    final candidates = ReminderScheduler().computeDueNotifications(
      items: [
        item('assignment-1', SyncItemKind.assignment, DateTime(2026, 6, 8, 10)),
        item('exam-1', SyncItemKind.exam, DateTime(2026, 6, 8, 10)),
      ],
      config: ReminderConfig.defaults,
      history: ReminderHistory.empty,
      now: now,
    );

    expect(candidates.map((candidate) => candidate.remindRule), contains('advance_60m'));
    expect(candidates.map((candidate) => candidate.item.kind).toSet(), {SyncItemKind.assignment, SyncItemKind.exam});
  });

  test('quiet hours suppress candidates without writing history', () {
    final config = ReminderConfig.defaults.copyWith(
      quietHours: const QuietHours(enabled: true, startLocalTime: '22:00', endLocalTime: '07:00'),
    );

    final candidates = ReminderScheduler().computeDueNotifications(
      items: [item('assignment-1', SyncItemKind.assignment, DateTime(2026, 6, 9, 0))],
      config: config,
      history: ReminderHistory.empty,
      now: DateTime(2026, 6, 8, 23),
    );

    expect(candidates, isEmpty);
  });

  test('dedupes by item rule and dueAt snapshot', () {
    final due = DateTime(2026, 6, 8, 10);
    final history = ReminderHistory(records: [
      ReminderRecord(
        itemId: 'assignment-1',
        remindRule: 'advance_60m',
        dueAtSnapshot: due.toIso8601String(),
        titleSnapshot: '标题',
        sentAt: DateTime(2026, 6, 8, 9),
      ),
    ]);

    final candidates = ReminderScheduler().computeDueNotifications(
      items: [item('assignment-1', SyncItemKind.assignment, due)],
      config: ReminderConfig.defaults,
      history: history,
      now: DateTime(2026, 6, 8, 9),
    );

    expect(candidates, isEmpty);
  });

  test('repeat reminder uses sequence in rule key', () {
    final config = ReminderConfig.defaults.copyWith(
      assignment: const KindReminderConfig(
        enabled: true,
        advanceRules: [],
        repeatRule: RepeatRule(enabled: true, intervalMinutes: 30, startMinutesBeforeDue: 120, stopAtDue: true, maxCountPerItem: 3),
      ),
    );

    final candidates = ReminderScheduler().computeDueNotifications(
      items: [item('assignment-1', SyncItemKind.assignment, DateTime(2026, 6, 8, 10))],
      config: config,
      history: ReminderHistory.empty,
      now: DateTime(2026, 6, 8, 9),
    );

    expect(candidates.single.remindRule, 'repeat:30:2026-06-08T10:00:00.000:2');
  });
}

SyncItem item(String id, SyncItemKind kind, DateTime dueAt) {
  return SyncItem(
    id: id,
    kind: kind,
    title: '标题',
    url: 'https://mooc1.chaoxing.com/work',
    sourceTitle: '通知',
    status: '未作答',
    displayStatus: SyncDisplayStatus.upcoming,
    dueAt: dueAt,
  );
}
```

Run:

```powershell
flutter test test/services/reminder_scheduler_test.dart
```

Expected: FAIL because `ReminderScheduler` does not exist.

- [ ] **Step 2: Implement scheduler**

Create `apps/chaoxing_app/lib/services/reminder_scheduler.dart`:

```dart
import '../models/reminder_config.dart';
import '../models/reminder_history.dart';
import '../models/sync_item.dart';

class ReminderScheduler {
  List<ReminderCandidate> computeDueNotifications({
    required List<SyncItem> items,
    required ReminderConfig config,
    required ReminderHistory history,
    required DateTime now,
  }) {
    if (config.notificationsPaused || config.quietHours.contains(now)) {
      return const [];
    }
    final result = <ReminderCandidate>[];
    for (final item in items) {
      final dueAt = item.dueAt;
      if (dueAt == null || !dueAt.isAfter(now)) {
        continue;
      }
      final kindConfig = item.kind == SyncItemKind.exam ? config.exam : config.assignment;
      if (!kindConfig.enabled) {
        continue;
      }
      final dueSnapshot = dueAt.toIso8601String();
      final minutesUntilDue = dueAt.difference(now).inMinutes;
      for (final rule in kindConfig.advanceRules.where((rule) => rule.enabled)) {
        if (minutesUntilDue == rule.minutesBeforeDue && !history.contains(item.id, rule.id, dueSnapshot)) {
          result.add(ReminderCandidate(item: item, remindRule: rule.id, dueAtSnapshot: dueSnapshot, title: _title(item), body: _body(item, minutesUntilDue)));
        }
      }
      final repeat = kindConfig.repeatRule;
      if (repeat.enabled && minutesUntilDue <= repeat.startMinutesBeforeDue) {
        if (!repeat.stopAtDue || minutesUntilDue > 0) {
          final elapsed = repeat.startMinutesBeforeDue - minutesUntilDue;
          if (elapsed >= 0 && elapsed % repeat.intervalMinutes == 0) {
            final sequence = elapsed ~/ repeat.intervalMinutes + 1;
            if (sequence <= repeat.maxCountPerItem) {
              final key = 'repeat:${repeat.intervalMinutes}:$dueSnapshot:$sequence';
              if (!history.contains(item.id, key, dueSnapshot)) {
                result.add(ReminderCandidate(item: item, remindRule: key, dueAtSnapshot: dueSnapshot, title: _title(item), body: _body(item, minutesUntilDue)));
              }
            }
          }
        }
      }
    }
    return result;
  }
}

class ReminderCandidate {
  const ReminderCandidate({
    required this.item,
    required this.remindRule,
    required this.dueAtSnapshot,
    required this.title,
    required this.body,
  });

  final SyncItem item;
  final String remindRule;
  final String dueAtSnapshot;
  final String title;
  final String body;

  ReminderRecord toRecord(DateTime sentAt) {
    return ReminderRecord(
      itemId: item.id,
      remindRule: remindRule,
      dueAtSnapshot: dueAtSnapshot,
      titleSnapshot: item.title,
      sentAt: sentAt,
    );
  }
}

String _title(SyncItem item) {
  return item.kind == SyncItemKind.exam ? '考试截止提醒' : '作业截止提醒';
}

String _body(SyncItem item, int minutesUntilDue) {
  final hours = minutesUntilDue ~/ 60;
  final minutes = minutesUntilDue % 60;
  final left = hours > 0 ? '$hours 小时 $minutes 分钟' : '$minutes 分钟';
  return '${item.sourceTitle}\n${item.title}\n剩余 $left';
}
```

- [ ] **Step 3: Run scheduler tests**

Run:

```powershell
flutter test test/services/reminder_scheduler_test.dart
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add apps/chaoxing_app/lib/services/reminder_scheduler.dart apps/chaoxing_app/test/services/reminder_scheduler_test.dart
git commit -m "feat: schedule local assignment exam reminders"
```

### Task 13: Add Windows Notification Service

**Files:**
- Create: `apps/chaoxing_app/lib/services/windows_notifier.dart`
- Test: `apps/chaoxing_app/test/services/windows_notifier_test.dart`

- [ ] **Step 1: Write failing notifier tests**

Create `apps/chaoxing_app/test/services/windows_notifier_test.dart`:

```dart
import 'package:chaoxing_app/models/sync_item.dart';
import 'package:chaoxing_app/services/reminder_scheduler.dart';
import 'package:chaoxing_app/services/windows_notifier.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fake notifier records sent candidates', () async {
    final notifier = FakeWindowsNotifier();
    final candidate = ReminderCandidate(
      item: SyncItem(
        id: 'assignment-1',
        kind: SyncItemKind.assignment,
        title: '作业',
        url: 'https://mooc1.chaoxing.com/work',
        sourceTitle: '课程',
        status: '未作答',
        displayStatus: SyncDisplayStatus.upcoming,
        dueAt: DateTime(2026, 6, 8, 10),
      ),
      remindRule: 'advance_60m',
      dueAtSnapshot: '2026-06-08T10:00:00.000',
      title: '作业截止提醒',
      body: '课程\n作业\n剩余 1 小时',
    );

    await notifier.showReminder(candidate);

    expect(notifier.sent.single.title, '作业截止提醒');
    expect(notifier.sent.single.item.id, 'assignment-1');
  });
}
```

Run:

```powershell
flutter test test/services/windows_notifier_test.dart
```

Expected: FAIL because notifier classes do not exist.

- [ ] **Step 2: Implement notifier abstraction**

Create `apps/chaoxing_app/lib/services/windows_notifier.dart`:

```dart
import 'dart:io';

import 'package:local_notifier/local_notifier.dart';

import 'reminder_scheduler.dart';

abstract class WindowsNotifier {
  Future<void> initialize();
  Future<void> showReminder(ReminderCandidate candidate);
}

class LocalWindowsNotifier implements WindowsNotifier {
  LocalWindowsNotifier({this.onNotificationClick});

  final void Function(String itemId)? onNotificationClick;

  @override
  Future<void> initialize() async {
    if (!Platform.isWindows) {
      return;
    }
    await localNotifier.setup(appName: '学习通待办');
  }

  @override
  Future<void> showReminder(ReminderCandidate candidate) async {
    if (!Platform.isWindows) {
      return;
    }
    final notification = LocalNotification(
      title: candidate.title,
      body: candidate.body,
      actions: const [],
    );
    notification.onShow = () {};
    notification.onClick = () {
      onNotificationClick?.call(candidate.item.id);
    };
    notification.show();
  }
}

class FakeWindowsNotifier implements WindowsNotifier {
  final List<ReminderCandidate> sent = [];

  @override
  Future<void> initialize() async {}

  @override
  Future<void> showReminder(ReminderCandidate candidate) async {
    sent.add(candidate);
  }
}
```

- [ ] **Step 3: Run notifier tests**

Run:

```powershell
flutter test test/services/windows_notifier_test.dart
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add apps/chaoxing_app/lib/services/windows_notifier.dart apps/chaoxing_app/test/services/windows_notifier_test.dart
git commit -m "feat: add windows notification service"
```

### Task 14: Migrate AppController To Local Sync, Cache, Auto Timer, Reminder Dispatch

**Files:**
- Modify: `apps/chaoxing_app/lib/state/app_controller.dart`
- Test: `apps/chaoxing_app/test/state/app_controller_test.dart`

- [ ] **Step 1: Replace controller tests with local behavior**

Update `apps/chaoxing_app/test/state/app_controller_test.dart` so it verifies:

```dart
import 'package:chaoxing_app/models/app_config.dart';
import 'package:chaoxing_app/models/app_sync_response.dart';
import 'package:chaoxing_app/models/auth_state.dart';
import 'package:chaoxing_app/models/reminder_config.dart';
import 'package:chaoxing_app/models/sync_item.dart';
import 'package:chaoxing_app/services/app_storage.dart';
import 'package:chaoxing_app/services/reminder_scheduler.dart';
import 'package:chaoxing_app/services/windows_notifier.dart';
import 'package:chaoxing_app/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads cached sync before local refresh', () async {
    final cached = responseWithTitle('缓存作业');
    final fresh = responseWithTitle('最新作业');
    final storage = MemoryAppStorage(config: AppConfig.empty, cookieHeader: 'UID=1', cachedSync: cached);
    final controller = AppController(
      storage,
      syncRunner: (_, __) async => fresh,
      notifier: FakeWindowsNotifier(),
    );

    await controller.load();

    expect(controller.items.single.title, '最新作业');
    expect(storage.cachedSync?.items.single.title, '最新作业');
  });

  test('keeps cached items when local refresh fails', () async {
    final cached = responseWithTitle('缓存作业');
    final controller = AppController(
      MemoryAppStorage(config: AppConfig.empty, cookieHeader: 'UID=1', cachedSync: cached),
      syncRunner: (_, __) async => throw Exception('network down'),
      notifier: FakeWindowsNotifier(),
    );

    await controller.load();

    expect(controller.items.single.title, '缓存作业');
    expect(controller.error, contains('network down'));
  });

  test('login import updates auth state and cookie', () async {
    final storage = MemoryAppStorage();
    final controller = AppController(
      storage,
      syncRunner: (_, __) async => responseWithTitle('作业'),
      authChecker: (_) async => AuthState(
        status: AuthStatus.authenticated,
        checkedAt: DateTime(2026, 6, 8),
        title: '空间首页',
        finalUrl: 'https://i.chaoxing.com/base',
        message: 'ok',
      ),
      notifier: FakeWindowsNotifier(),
    );

    final state = await controller.importManualCookie('UID=1; vc=abc');

    expect(state.isAuthenticated, true);
    expect(await storage.loadCookieHeader(), 'UID=1; vc=abc');
  });

  test('dispatches due reminders and saves history after refresh', () async {
    final notifier = FakeWindowsNotifier();
    final storage = MemoryAppStorage(
      config: AppConfig.empty,
      cookieHeader: 'UID=1',
      reminderConfig: ReminderConfig.defaults,
    );
    final controller = AppController(
      storage,
      syncRunner: (_, __) async => responseWithDue(DateTime(2026, 6, 8, 10)),
      notifier: notifier,
      nowProvider: () => DateTime(2026, 6, 8, 9),
    );

    await controller.load();

    expect(notifier.sent, isNotEmpty);
    expect((await storage.loadReminderHistory()).records, isNotEmpty);
  });
}

AppSyncResponse responseWithTitle(String title) {
  return AppSyncResponse(
    lastSyncedAt: DateTime(2026, 6, 8, 8),
    authStatus: 'authenticated',
    failures: const [],
    items: [
      SyncItem(
        id: 'assignment-1',
        kind: SyncItemKind.assignment,
        title: title,
        url: 'https://mooc1.chaoxing.com/work',
        sourceTitle: '作业通知',
        status: '未作答',
        displayStatus: SyncDisplayStatus.upcoming,
        dueAt: DateTime(2026, 6, 9, 10),
      ),
    ],
  );
}

AppSyncResponse responseWithDue(DateTime dueAt) {
  return AppSyncResponse(
    lastSyncedAt: DateTime(2026, 6, 8, 9),
    authStatus: 'authenticated',
    failures: const [],
    items: [
      SyncItem(
        id: 'assignment-1',
        kind: SyncItemKind.assignment,
        title: '作业',
        url: 'https://mooc1.chaoxing.com/work',
        sourceTitle: '作业通知',
        status: '未作答',
        displayStatus: SyncDisplayStatus.upcoming,
        dueAt: dueAt,
      ),
    ],
  );
}
```

Run:

```powershell
flutter test test/state/app_controller_test.dart
```

Expected: FAIL because controller still expects Worker config and `ChaoxingApi`.

- [ ] **Step 2: Refactor controller constructor and dependencies**

Modify `apps/chaoxing_app/lib/state/app_controller.dart`:

```dart
typedef LocalSyncFetcher = Future<AppSyncResponse> Function(AppConfig config, DateTime now);
typedef AuthChecker = Future<AuthState> Function(String cookieHeader);
typedef NowProvider = DateTime Function();
```

Constructor:

```dart
AppController(
  this._storage, {
  LocalSyncFetcher? syncRunner,
  AuthChecker? authChecker,
  WindowsNotifier? notifier,
  NowProvider? nowProvider,
})  : _syncRunner = syncRunner ?? _buildDefaultSyncRunner(_storage),
      _authChecker = authChecker ?? ChaoxingAuth().checkAuth,
      _notifier = notifier ?? LocalWindowsNotifier(),
      _nowProvider = nowProvider ?? DateTime.now;
```

State fields:

```dart
AppConfig _config = AppConfig.empty;
ReminderConfig _reminderConfig = ReminderConfig.defaults;
AuthState _authState = AuthState.missing;
Timer? _timer;
bool _syncInProgress = false;
```

Keep getters for `items`, `overdueItems`, `todayItems`, `upcomingItems`, `dueSoonItems`. Replace `isConfigured` with:

```dart
bool get isLoggedIn => _authState.isAuthenticated || (_sync?.authStatus == 'authenticated');
bool get canRefresh => !_refreshing && !_syncInProgress;
ReminderConfig get reminderConfig => _reminderConfig;
AuthState get authState => _authState;
```

- [ ] **Step 3: Implement load, refresh, auth, timer, reminder dispatch**

Controller methods must:

- `load()`: load config, reminder config, cached sync, cookie; run auth check if cookie exists; call `refresh(silent: _sync != null)` when logged in; start timer only when `config.canAutoSync`.
- `refresh({bool silent = false})`: skip if `_syncInProgress`; call `_syncRunner(_config, _nowProvider())`; save cache; update `_authState` if response auth is not authenticated; call `_dispatchReminders(response.items)`.
- `saveConfig(AppConfig config)`: persist local config and restart timer.
- `saveReminderConfig(ReminderConfig config)`: persist reminder config.
- `importManualCookie(String input)`: use `LoginCookieCollector` with `_authChecker` and storage save; update `_authState`; refresh on success.
- `logout()`: clear cookie; set `_authState = AuthState.missing`; keep cached sync and reminder history.
- `toggleNotificationsPaused()`: flip `reminderConfig.notificationsPaused` and persist.
- `_dispatchReminders(List<SyncItem> items)`: load history, compute candidates, call `_notifier.showReminder`, add successful records, save history. If notifier throws, set `_error` to a notification failure summary but keep cached sync.

- [ ] **Step 4: Run controller tests**

Run:

```powershell
flutter test test/state/app_controller_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/chaoxing_app/lib/state/app_controller.dart apps/chaoxing_app/test/state/app_controller_test.dart
git commit -m "feat: drive app state from local sync"
```

### Task 15: Update UI For Local Login, Settings, Reminder Configuration

**Files:**
- Modify: `apps/chaoxing_app/lib/screens/home_screen.dart`
- Modify: `apps/chaoxing_app/lib/screens/settings_screen.dart`
- Modify: `apps/chaoxing_app/lib/main.dart`
- Test: `apps/chaoxing_app/test/widget_test.dart`
- Test: `apps/chaoxing_app/test/screens/settings_screen_test.dart`

- [ ] **Step 1: Write failing UI tests**

Create `apps/chaoxing_app/test/screens/settings_screen_test.dart`:

```dart
import 'package:chaoxing_app/models/app_config.dart';
import 'package:chaoxing_app/models/reminder_config.dart';
import 'package:chaoxing_app/screens/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings screen shows local sync and reminder controls', (tester) async {
    AppConfig? savedConfig;
    ReminderConfig? savedReminder;
    await tester.pumpWidget(MaterialApp(
      home: SettingsScreen(
        initialConfig: AppConfig.empty.copyWith(hasLegacyWorkerConfig: true),
        initialReminderConfig: ReminderConfig.defaults,
        onSaveConfig: (config) async => savedConfig = config,
        onSaveReminderConfig: (config) async => savedReminder = config,
      ),
    ));

    expect(find.text('本地同步设置'), findsOneWidget);
    expect(find.text('旧 Worker 配置已不再使用'), findsOneWidget);
    expect(find.text('作业提醒'), findsOneWidget);
    expect(find.text('考试提醒'), findsOneWidget);

    await tester.tap(find.text('保存设置'));
    await tester.pumpAndSettle();

    expect(savedConfig, isNotNull);
    expect(savedReminder, isNotNull);
  });
}
```

Update `apps/chaoxing_app/test/widget_test.dart` to expect login-first copy:

```dart
expect(find.text('登录学习通'), findsWidgets);
expect(find.text('本地同步作业和考试'), findsOneWidget);
```

Run:

```powershell
flutter test test/widget_test.dart test/screens/settings_screen_test.dart
```

Expected: FAIL because UI still says Worker URL and RUN_TOKEN.

- [ ] **Step 2: Update HomeScreen**

Modify `apps/chaoxing_app/lib/screens/home_screen.dart`:

- Replace `controller.isConfigured` checks with `controller.isLoggedIn`.
- Refresh button is enabled when `controller.canRefresh && controller.isLoggedIn`.
- Settings button still opens `SettingsScreen`.
- Add login button in app bar or empty state that opens `LoginScreen` with `controller.authState`, `controller.openWebViewLogin`, and `controller.importManualCookie`.
- Empty state title: `登录学习通`; body: `本地同步作业和考试，Cookie 只保存在本机。`
- Summary header shows `authState.message` and `sync?.lastSyncedAt`.
- If `config.hasLegacyWorkerConfig` is true, show a small banner: `旧 Worker 配置已不再使用，请使用学习通登录。`

- [ ] **Step 3: Update SettingsScreen**

Replace Worker URL/token fields with:

- Refresh interval slider, min 5, max 180.
- Auto sync switch.
- Inbox/detail/requirement limit numeric inputs.
- Assignment reminder enabled switch.
- Exam reminder enabled switch.
- Advance rule chips or switches for `10080`, `4320`, `1440`, `360`, `60`, `15` minutes.
- Repeat reminder enabled switch, interval minutes input, start minutes before due input, max count input.
- Quiet hours enabled switch, start/end `HH:mm` fields.
- Notifications paused switch.

Use constructor:

```dart
const SettingsScreen({
  required this.initialConfig,
  required this.initialReminderConfig,
  required this.onSaveConfig,
  required this.onSaveReminderConfig,
  super.key,
});
```

On save, call both callbacks and pop.

- [ ] **Step 4: Update main wiring**

Modify `apps/chaoxing_app/lib/main.dart`:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
  }
  final storage = DeviceAppStorage();
  final notifier = LocalWindowsNotifier();
  await notifier.initialize();
  runApp(ChaoxingApp(controller: AppController(storage, notifier: notifier)));
}
```

Import `dart:io`, `window_manager`, and `windows_notifier.dart`.

- [ ] **Step 5: Run UI tests**

Run:

```powershell
flutter test test/widget_test.dart test/screens/settings_screen_test.dart test/screens/login_screen_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/chaoxing_app/lib/screens/home_screen.dart apps/chaoxing_app/lib/screens/settings_screen.dart apps/chaoxing_app/lib/main.dart apps/chaoxing_app/test/widget_test.dart apps/chaoxing_app/test/screens/settings_screen_test.dart
git commit -m "feat: replace worker settings with local login ui"
```

### Task 16: Add Windows Tray Resident Behavior

**Files:**
- Create: `apps/chaoxing_app/lib/services/tray_service.dart`
- Modify: `apps/chaoxing_app/lib/main.dart`
- Test: `apps/chaoxing_app/test/services/tray_service_test.dart`

- [ ] **Step 1: Write failing tray state tests**

Create `apps/chaoxing_app/test/services/tray_service_test.dart`:

```dart
import 'package:chaoxing_app/services/tray_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('tray menu labels include required actions', () {
    final labels = TrayMenuState(
      notificationsPaused: false,
      syncInProgress: false,
      authSummary: '已登录，上次同步 09:00',
    ).labels;

    expect(labels, containsAll(['打开窗口', '立即同步', '暂停通知', '查看登录状态', '退出']));
  });

  test('paused state flips pause label', () {
    final labels = TrayMenuState(
      notificationsPaused: true,
      syncInProgress: true,
      authSummary: '同步中',
    ).labels;

    expect(labels, contains('恢复通知'));
    expect(labels, contains('同步中'));
  });
}
```

Run:

```powershell
flutter test test/services/tray_service_test.dart
```

Expected: FAIL because tray service does not exist.

- [ ] **Step 2: Implement tray service**

Create `apps/chaoxing_app/lib/services/tray_service.dart`:

```dart
import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class TrayMenuState {
  const TrayMenuState({
    required this.notificationsPaused,
    required this.syncInProgress,
    required this.authSummary,
  });

  final bool notificationsPaused;
  final bool syncInProgress;
  final String authSummary;

  List<String> get labels => [
        '打开窗口',
        syncInProgress ? '同步中' : '立即同步',
        notificationsPaused ? '恢复通知' : '暂停通知',
        '查看登录状态',
        '退出',
      ];
}

class TrayService with TrayListener, WindowListener {
  TrayService({
    required Future<void> Function() onOpenWindow,
    required Future<void> Function() onSyncNow,
    required Future<void> Function() onToggleNotifications,
    required Future<void> Function() onOpenLoginStatus,
    required Future<void> Function() onExit,
  })  : _onOpenWindow = onOpenWindow,
        _onSyncNow = onSyncNow,
        _onToggleNotifications = onToggleNotifications,
        _onOpenLoginStatus = onOpenLoginStatus,
        _onExit = onExit;

  final Future<void> Function() _onOpenWindow;
  final Future<void> Function() _onSyncNow;
  final Future<void> Function() _onToggleNotifications;
  final Future<void> Function() _onOpenLoginStatus;
  final Future<void> Function() _onExit;
  bool _allowClose = false;

  Future<void> initialize(TrayMenuState state) async {
    if (!Platform.isWindows) {
      return;
    }
    windowManager.addListener(this);
    trayManager.addListener(this);
    await trayManager.setToolTip('学习通待办 - ${state.authSummary}');
    await updateMenu(state);
  }

  Future<void> updateMenu(TrayMenuState state) async {
    if (!Platform.isWindows) {
      return;
    }
    await trayManager.setContextMenu(Menu(items: [
      MenuItem(key: 'open', label: '打开窗口'),
      MenuItem(key: 'sync', label: state.syncInProgress ? '同步中' : '立即同步', disabled: state.syncInProgress),
      MenuItem(key: 'pause', label: state.notificationsPaused ? '恢复通知' : '暂停通知'),
      MenuItem(key: 'login', label: '查看登录状态'),
      MenuItem.separator(),
      MenuItem(key: 'exit', label: '退出'),
    ]));
    await trayManager.setToolTip('学习通待办 - ${state.authSummary}');
  }

  @override
  Future<void> onWindowClose() async {
    if (_allowClose) {
      return;
    }
    await windowManager.hide();
  }

  @override
  Future<void> onTrayIconMouseDown() async {
    await _onOpenWindow();
  }

  @override
  Future<void> onTrayMenuItemClick(MenuItem menuItem) async {
    switch (menuItem.key) {
      case 'open':
        await _onOpenWindow();
        break;
      case 'sync':
        await _onSyncNow();
        break;
      case 'pause':
        await _onToggleNotifications();
        break;
      case 'login':
        await _onOpenLoginStatus();
        break;
      case 'exit':
        _allowClose = true;
        await _onExit();
        break;
    }
  }

  Future<void> dispose() async {
    if (!Platform.isWindows) {
      return;
    }
    trayManager.removeListener(this);
    windowManager.removeListener(this);
    await trayManager.destroy();
  }
}
```

- [ ] **Step 3: Wire tray in main and controller**

Modify `main.dart` after controller creation:

- Initialize `TrayService` only on Windows.
- `打开窗口`: `windowManager.show()` and `windowManager.focus()`.
- `立即同步`: call `controller.refresh()`.
- `暂停通知/恢复通知`: call `controller.toggleNotificationsPaused()`.
- `查看登录状态`: add `final ValueNotifier<String?> pendingRoute = ValueNotifier<String?>(null);` to `AppController`; tray action sets `controller.pendingRoute.value = 'login'`; `HomeScreen.initState()` listens to `pendingRoute`, opens `LoginScreen` when the value is `login`, then resets it to `null`.
- `退出`: call `controller.dispose()`, `tray.dispose()`, and `windowManager.close()`.

Set `WindowOptions` with a reasonable title and prevent default close from exiting by using `windowManager.setPreventClose(true)`.

- [ ] **Step 4: Run tray tests and Windows build**

Run:

```powershell
flutter test test/services/tray_service_test.dart
flutter build windows
```

Expected: tests PASS and Windows build PASS.

- [ ] **Step 5: Manual Windows validation**

Run:

```powershell
flutter run -d windows
```

Expected:

- Closing the window hides it and leaves the process running.
- Tray menu shows `打开窗口`、`立即同步`、`暂停通知` or `恢复通知`、`查看登录状态`、`退出`.
- `打开窗口` restores and focuses the window.
- `退出` ends the process.

- [ ] **Step 6: Commit**

```bash
git add apps/chaoxing_app/lib/services/tray_service.dart apps/chaoxing_app/lib/main.dart apps/chaoxing_app/test/services/tray_service_test.dart
git commit -m "feat: keep windows app resident in tray"
```

### Task 17: Remove Runtime Worker API Dependency

**Files:**
- Delete: `apps/chaoxing_app/lib/services/chaoxing_api.dart`
- Delete or rewrite: `apps/chaoxing_app/test/services/chaoxing_api_test.dart`
- Modify: `apps/chaoxing_app/lib/state/app_controller.dart`
- Modify: `apps/chaoxing_app/lib/screens/settings_screen.dart`
- Test: all Flutter tests

- [ ] **Step 1: Search for Worker runtime references**

Run:

```powershell
rg "Worker URL|RUN_TOKEN|worker_base_url|run_token|ChaoxingApi|/app/sync|Bearer" apps/chaoxing_app/lib apps/chaoxing_app/test
```

Expected before edits: references remain only in old service/test files or migrated legacy-warning code.

- [ ] **Step 2: Remove obsolete Worker API**

Delete `apps/chaoxing_app/lib/services/chaoxing_api.dart`. Delete `apps/chaoxing_app/test/services/chaoxing_api_test.dart` unless it has been repurposed for `LocalSyncRunner`; prefer deleting it because Task 11 covers local sync.

- [ ] **Step 3: Keep legacy key detection only in storage**

After deletion, run:

```powershell
rg "Worker URL|RUN_TOKEN|ChaoxingApi|/app/sync|Bearer" apps/chaoxing_app/lib apps/chaoxing_app/test
```

Expected: no matches for `ChaoxingApi`, `/app/sync`, `Bearer`, `RUN_TOKEN`; only a user-facing legacy warning may contain the word `Worker`.

- [ ] **Step 4: Run all Flutter tests**

Run:

```powershell
flutter test
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A apps/chaoxing_app/lib/services/chaoxing_api.dart apps/chaoxing_app/test/services/chaoxing_api_test.dart apps/chaoxing_app/lib/state/app_controller.dart apps/chaoxing_app/lib/screens/settings_screen.dart
git commit -m "refactor: remove worker sync runtime dependency"
```

## Phase 2: 课程空间、作业列表和考试列表补漏

### Task 18: Add Course Space Client

**Files:**
- Create: `apps/chaoxing_app/lib/models/course_space.dart`
- Create: `apps/chaoxing_app/lib/services/course_space_client.dart`
- Create: `apps/chaoxing_app/test/fixtures/chaoxing/course_space.html`
- Test: `apps/chaoxing_app/test/services/course_space_client_test.dart`

- [ ] **Step 1: Add fixture and failing tests**

Create `apps/chaoxing_app/test/fixtures/chaoxing/course_space.html`:

```html
<html><body>
<a href="https://mooc1.chaoxing.com/mycourse/studentstudy?courseId=c1&clazzid=cl1">高等数学</a>
<a href="https://mooc1.chaoxing.com/mycourse/studentstudy?courseId=c2&clazzid=cl2">大学英语</a>
</body></html>
```

Create `apps/chaoxing_app/test/services/course_space_client_test.dart`:

```dart
import 'dart:io';

import 'package:chaoxing_app/services/course_space_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('parses course and class ids from course space page', () {
    final html = File('test/fixtures/chaoxing/course_space.html').readAsStringSync();
    final courses = parseCourseSpace(html);

    expect(courses.map((course) => course.courseId), ['c1', 'c2']);
    expect(courses.first.classId, 'cl1');
    expect(courses.first.title, '高等数学');
  });

  test('fetches course space through safe client', () async {
    final html = File('test/fixtures/chaoxing/course_space.html').readAsStringSync();
    final client = CourseSpaceClient(
      cookieHeader: 'UID=1',
      httpClientFactory: (_) => MockClient((request) async => http.Response(html, 200, request: request)),
    );

    final courses = await client.fetchCourses();

    expect(courses.length, 2);
  });
}
```

Run:

```powershell
flutter test test/services/course_space_client_test.dart
```

Expected: FAIL because course space files do not exist.

- [ ] **Step 2: Implement course model and client**

Create `apps/chaoxing_app/lib/models/course_space.dart`:

```dart
class CourseSpace {
  const CourseSpace({required this.courseId, required this.classId, required this.title, required this.url});

  final String courseId;
  final String classId;
  final String title;
  final String url;
}
```

Create `apps/chaoxing_app/lib/services/course_space_client.dart`:

```dart
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/course_space.dart';
import 'chaoxing_http_client.dart';

class CourseSpaceClient {
  CourseSpaceClient({required String cookieHeader, http.Client Function(String cookieHeader)? httpClientFactory})
      : _cookieHeader = cookieHeader,
        _httpClientFactory = httpClientFactory;

  final String _cookieHeader;
  final http.Client Function(String cookieHeader)? _httpClientFactory;

  Future<List<CourseSpace>> fetchCourses() async {
    final client = ChaoxingHttpClient(cookieHeader: _cookieHeader, inner: _httpClientFactory?.call(_cookieHeader));
    final html = await client.getText(Uri.parse('https://mooc1.chaoxing.com/visit/courses'));
    return parseCourseSpace(html);
  }
}

List<CourseSpace> parseCourseSpace(String html) {
  final document = html_parser.parse(html);
  final courses = <CourseSpace>[];
  for (final anchor in document.querySelectorAll('a[href*="courseId="]')) {
    final href = anchor.attributes['href'];
    if (href == null) {
      continue;
    }
    final uri = Uri.tryParse(href);
    if (uri == null) {
      continue;
    }
    final courseId = uri.queryParameters['courseId'];
    final classId = uri.queryParameters['clazzid'] ?? uri.queryParameters['classId'];
    if (courseId == null || classId == null) {
      continue;
    }
    courses.add(CourseSpace(courseId: courseId, classId: classId, title: anchor.text.trim(), url: href));
  }
  return courses;
}
```

- [ ] **Step 3: Run course space tests**

Run:

```powershell
flutter test test/services/course_space_client_test.dart
```

Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add apps/chaoxing_app/lib/models/course_space.dart apps/chaoxing_app/lib/services/course_space_client.dart apps/chaoxing_app/test/fixtures/chaoxing/course_space.html apps/chaoxing_app/test/services/course_space_client_test.dart
git commit -m "feat: fetch chaoxing course spaces locally"
```

### Task 19: Add Course Work And Exam List Clients

**Files:**
- Create: `apps/chaoxing_app/lib/services/course_work_client.dart`
- Create: `apps/chaoxing_app/lib/services/course_exam_client.dart`
- Test: `apps/chaoxing_app/test/services/course_work_client_test.dart`
- Test: `apps/chaoxing_app/test/services/course_exam_client_test.dart`

- [ ] **Step 1: Write failing list parser tests**

Create `apps/chaoxing_app/test/services/course_work_client_test.dart`:

```dart
import 'package:chaoxing_app/models/course_space.dart';
import 'package:chaoxing_app/services/course_work_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses open work entries and skips completed entries', () {
    const html = '''
    <div class="work-row">
      <a href="https://mooc1.chaoxing.com/work?courseId=c1&classId=cl1&workId=w1">第一章作业</a>
      <span>截止 2026-06-10 22:00</span>
      <span>未作答</span>
    </div>
    <div class="work-row">
      <a href="https://mooc1.chaoxing.com/work?courseId=c1&classId=cl1&workId=w2">已完成作业</a>
      <span>已提交</span>
    </div>
    ''';
    const course = CourseSpace(courseId: 'c1', classId: 'cl1', title: '高等数学', url: 'https://mooc1.chaoxing.com/course');

    final requirements = parseCourseWorkList(html: html, course: course);

    expect(requirements.length, 1);
    expect(requirements.single.courseId, 'c1');
    expect(requirements.single.classId, 'cl1');
    expect(requirements.single.workId, 'w1');
    expect(requirements.single.sourceTitle, '高等数学');
    expect(requirements.single.pageTitle, '第一章作业');
    expect(requirements.single.timeWindow.end, '2026-06-10 22:00');
    expect(requirements.single.entryUrl, contains('workId=w1'));
  });
}
```

Create `apps/chaoxing_app/test/services/course_exam_client_test.dart`:

```dart
import 'package:chaoxing_app/models/course_space.dart';
import 'package:chaoxing_app/services/course_exam_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses open exam entries and skips ended entries', () {
    const html = '''
    <div class="exam-row">
      <a href="https://mooc1.chaoxing.com/exam?courseId=c1&classId=cl1&examId=e1">期末测验</a>
      <span>截止 2026-06-12 20:00</span>
      <span>待完成</span>
    </div>
    <div class="exam-row">
      <a href="https://mooc1.chaoxing.com/exam?courseId=c1&classId=cl1&examId=e2">已结束考试</a>
      <span>已结束</span>
    </div>
    ''';
    const course = CourseSpace(courseId: 'c1', classId: 'cl1', title: '高等数学', url: 'https://mooc1.chaoxing.com/course');

    final requirements = parseCourseExamList(html: html, course: course);

    expect(requirements.length, 1);
    expect(requirements.single.courseId, 'c1');
    expect(requirements.single.classId, 'cl1');
    expect(requirements.single.examId, 'e1');
    expect(requirements.single.sourceTitle, '高等数学');
    expect(requirements.single.pageTitle, '期末测验');
    expect(requirements.single.workStatus, '未作答');
    expect(requirements.single.timeWindow.end, '2026-06-12 20:00');
    expect(requirements.single.entryUrl, contains('examId=e1'));
  });
}
```

Use command:

```powershell
flutter test test/services/course_work_client_test.dart test/services/course_exam_client_test.dart
```

Expected: FAIL because clients do not exist.

- [ ] **Step 2: Implement course work client**

Create `apps/chaoxing_app/lib/services/course_work_client.dart` with:

```dart
class CourseWorkClient {
  CourseWorkClient({required String cookieHeader, http.Client Function(String cookieHeader)? httpClientFactory});
  Future<List<Requirement>> fetchOpenWorks(CourseSpace course);
}

List<Requirement> parseCourseWorkList({required String html, required CourseSpace course});
```

Parser rules:

- Select anchors whose `href` contains `workId=` or `workOrExam=work`.
- Skip entries whose surrounding text contains `已完成`、`已提交` when no future due time is present.
- Build `Requirement` with `sourceTitle` as course title, `sourceContent` as row text, IDs from URL, `timeWindow.end` from first matched date-time after `截止`.
- Set `sources` later through `SyncModelBuilder` as `course_work`.

- [ ] **Step 3: Implement course exam client**

Create `apps/chaoxing_app/lib/services/course_exam_client.dart` with:

```dart
class CourseExamClient {
  CourseExamClient({required String cookieHeader, http.Client Function(String cookieHeader)? httpClientFactory});
  Future<List<Requirement>> fetchOpenExams(CourseSpace course);
}

List<Requirement> parseCourseExamList({required String html, required CourseSpace course});
```

Parser rules:

- Select anchors whose `href` contains `examId=`, `workOrExam=exam`, or `/exam`.
- Skip rows containing `已结束` or `不可作答` unless a future due time is present.
- Build `Requirement` with `examId`, course/class IDs, source title, entry URL, and `timeWindow.end`.
- Set `workStatus` to `未作答` when text contains `未作答` or `待完成`; otherwise `unknown`.

- [ ] **Step 4: Run list client tests**

Run:

```powershell
flutter test test/services/course_work_client_test.dart test/services/course_exam_client_test.dart
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/chaoxing_app/lib/services/course_work_client.dart apps/chaoxing_app/lib/services/course_exam_client.dart apps/chaoxing_app/test/services/course_work_client_test.dart apps/chaoxing_app/test/services/course_exam_client_test.dart
git commit -m "feat: fetch course work and exam lists"
```

### Task 20: Merge Multi-Source Results Without Duplicate Display Or Notifications

**Files:**
- Modify: `apps/chaoxing_app/lib/services/local_sync_runner.dart`
- Modify: `apps/chaoxing_app/lib/services/sync_model_builder.dart`
- Modify: `apps/chaoxing_app/lib/models/app_config.dart`
- Test: `apps/chaoxing_app/test/services/local_sync_runner_test.dart`
- Test: `apps/chaoxing_app/test/services/sync_model_builder_test.dart`

- [ ] **Step 1: Write failing merge tests**

Add to `sync_model_builder_test.dart`:

```dart
test('merges duplicate requirements by business id and records sources', () {
  final response = buildAppSyncResponse(
    sourceRequirements: [
      SourceRequirement(source: 'inbox', requirement: requirement(sourceTitle: '通知来源')),
      SourceRequirement(source: 'course_work', requirement: requirement(sourceTitle: '课程列表来源')),
    ],
    failures: const [],
    authStatus: 'authenticated',
    generatedAt: DateTime(2026, 6, 8, 10),
  );

  expect(response.items.length, 1);
  expect(response.items.single.sources, ['course_work', 'inbox']);
});
```

Add to `local_sync_runner_test.dart`:

```dart
test('course source merges duplicate inbox work by item id', () async {
  final inboxRequirement = requirement(sourceTitle: '通知来源');
  final courseRequirement = requirement(sourceTitle: '课程来源');
  final runner = LocalSyncRunner(
    loadCookie: () async => 'UID=1',
    checkAuth: (_) async => AuthState(
      status: AuthStatus.authenticated,
      checkedAt: DateTime(2026, 6, 8, 10),
      title: '空间首页',
      finalUrl: 'https://i.chaoxing.com/base',
      message: 'ok',
    ),
    inboxRequirementFetcher: (_) async => [inboxRequirement],
    courseRequirementFetcher: (_) async => [courseRequirement],
  );

  final response = await runner.sync(
    config: AppConfig.empty.copyWith(
      dataSources: const DataSourceConfig(inboxEnabled: true, courseSpaceEnabled: true),
    ),
    now: DateTime(2026, 6, 8, 10),
  );

  expect(response.items.length, 1);
  expect(response.items.single.id, 'assignment-w1');
  expect(response.items.single.sources, ['course_work', 'inbox']);
});
```

Run:

```powershell
flutter test test/services/sync_model_builder_test.dart test/services/local_sync_runner_test.dart
```

Expected: FAIL because data source config and merge support do not exist.

- [ ] **Step 2: Add data source config**

Modify `AppConfig` to include:

```dart
final DataSourceConfig dataSources;

class DataSourceConfig {
  const DataSourceConfig({required this.inboxEnabled, required this.courseSpaceEnabled});
  final bool inboxEnabled;
  final bool courseSpaceEnabled;
  static const defaults = DataSourceConfig(inboxEnabled: true, courseSpaceEnabled: false);
}
```

Include JSON serialization. Default keeps course space disabled until user enables it in settings.

- [ ] **Step 3: Merge by stable item id**

Modify `buildAppSyncResponse()`:

- Change the primary input from `requirements` to `sourceRequirements: List<SourceRequirement>`.
- Define `class SourceRequirement { const SourceRequirement({required this.source, required this.requirement}); final String source; final Requirement requirement; }`.
- Keep a compatibility overload or helper `sourceRequirementsFrom(String source, List<Requirement> requirements)` for Task 10 tests that still pass only inbox requirements.
- Build each item with its source name.
- Use `Map<String, SyncItem>` keyed by `item.id`.
- On duplicate, keep the item with non-null `dueAt`, longer title, and more complete `courseId/classId/workId/answerId/examId`; merge `sources` as a sorted unique list.
- Return sorted merged items.

- [ ] **Step 4: Extend LocalSyncRunner for course source**

When `config.dataSources.courseSpaceEnabled` is true:

- Fetch courses with `CourseSpaceClient`.
- For each course, fetch works with `CourseWorkClient` and exams with `CourseExamClient`.
- Add their requirements to the same model builder call as `SourceRequirement(source: 'course_work', requirement: workRequirement)` and `SourceRequirement(source: 'course_exam', requirement: examRequirement)`. Inbox requirements use `SourceRequirement(source: 'inbox', requirement: inboxRequirement)`.
- Catch per-course failures and append `AppSyncFailure` with source title as course title.

- [ ] **Step 5: Run merge tests**

Run:

```powershell
flutter test test/services/sync_model_builder_test.dart test/services/local_sync_runner_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/chaoxing_app/lib/models/app_config.dart apps/chaoxing_app/lib/services/local_sync_runner.dart apps/chaoxing_app/lib/services/sync_model_builder.dart apps/chaoxing_app/test/services/local_sync_runner_test.dart apps/chaoxing_app/test/services/sync_model_builder_test.dart
git commit -m "feat: merge multi-source chaoxing sync results"
```

## Phase 3: 诊断和体验增强

### Task 21: Add Diagnostics Page And Redacted Export

**Files:**
- Create: `apps/chaoxing_app/lib/services/local_diagnostics.dart`
- Create: `apps/chaoxing_app/lib/screens/diagnostics_screen.dart`
- Modify: `apps/chaoxing_app/lib/screens/home_screen.dart`
- Test: `apps/chaoxing_app/test/services/local_diagnostics_test.dart`
- Test: `apps/chaoxing_app/test/screens/diagnostics_screen_test.dart`

- [ ] **Step 1: Write failing diagnostics tests**

Create `apps/chaoxing_app/test/services/local_diagnostics_test.dart`:

```dart
import 'package:chaoxing_app/models/app_sync_response.dart';
import 'package:chaoxing_app/services/local_diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('diagnostics redact cookies and sensitive query params', () {
    final report = buildDiagnosticsReport(
      cookieHeader: 'UID=1; vc=secret',
      sync: AppSyncResponse(
        lastSyncedAt: DateTime(2026, 6, 8),
        authStatus: 'authenticated',
        items: const [],
        failures: const [
          AppSyncFailure(entryUrl: 'https://mooc1.chaoxing.com/work?token=secret&workId=w1', sourceTitle: '作业', message: 'parse_failed'),
        ],
      ),
      lastError: 'UID=1 network error',
    );

    expect(report, isNot(contains('secret')));
    expect(report, contains('token=***'));
    expect(report, contains('parse_failed'));
  });
}
```

Create `apps/chaoxing_app/test/screens/diagnostics_screen_test.dart` and assert it displays last sync time, auth status, failures, and a `导出诊断` button.

Run:

```powershell
flutter test test/services/local_diagnostics_test.dart test/screens/diagnostics_screen_test.dart
```

Expected: FAIL because diagnostics files do not exist.

- [ ] **Step 2: Implement diagnostics service**

Create `apps/chaoxing_app/lib/services/local_diagnostics.dart`:

```dart
import 'dart:convert';

import '../models/app_sync_response.dart';
import 'chaoxing_http_client.dart';

String buildDiagnosticsReport({
  required String? cookieHeader,
  required AppSyncResponse? sync,
  required String? lastError,
}) {
  final failures = sync?.failures.map((failure) {
    final uri = Uri.tryParse(failure.entryUrl);
    return {
      'entryUrl': uri == null ? failure.entryUrl : redactSensitiveUrl(uri),
      'sourceTitle': failure.sourceTitle,
      'message': _redactText(failure.message),
    };
  }).toList();
  return const JsonEncoder.withIndent('  ').convert({
    'generatedAt': DateTime.now().toIso8601String(),
    'hasCookie': cookieHeader != null && cookieHeader.trim().isNotEmpty,
    'authStatus': sync?.authStatus,
    'lastSyncedAt': sync?.lastSyncedAt?.toIso8601String(),
    'itemCount': sync?.items.length ?? 0,
    'failureCount': sync?.failures.length ?? 0,
    'failures': failures ?? const [],
    'lastError': _redactText(lastError),
  });
}

String? _redactText(String? value) {
  if (value == null) {
    return null;
  }
  return value
      .replaceAll(RegExp(r'UID=[^;\s]+'), 'UID=***')
      .replaceAll(RegExp(r'vc=[^;\s]+'), 'vc=***')
      .replaceAll(RegExp(r'token=[^&\s]+'), 'token=***');
}
```

- [ ] **Step 3: Implement DiagnosticsScreen**

Create `apps/chaoxing_app/lib/screens/diagnostics_screen.dart` with constructor:

```dart
const DiagnosticsScreen({
  required this.sync,
  required this.authMessage,
  required this.error,
  required this.onExport,
  super.key,
});
```

Display:

- `认证状态`
- `最近同步`
- `最近错误`
- failures list with source title and message
- `导出诊断` button calling `onExport`

Do not display Cookie or full private response bodies.

- [ ] **Step 4: Link diagnostics from HomeScreen**

Add an app bar icon button with tooltip `诊断` that opens `DiagnosticsScreen`. The controller export callback calls `buildDiagnosticsReport()` with current cached sync and cookie presence, then writes to clipboard using `Clipboard.setData()` and shows SnackBar `诊断信息已复制`.

- [ ] **Step 5: Run diagnostics tests**

Run:

```powershell
flutter test test/services/local_diagnostics_test.dart test/screens/diagnostics_screen_test.dart
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add apps/chaoxing_app/lib/services/local_diagnostics.dart apps/chaoxing_app/lib/screens/diagnostics_screen.dart apps/chaoxing_app/lib/screens/home_screen.dart apps/chaoxing_app/test/services/local_diagnostics_test.dart apps/chaoxing_app/test/screens/diagnostics_screen_test.dart
git commit -m "feat: add local sync diagnostics"
```

## Final Verification

- [ ] **Step 1: Run Flutter analyzer**

```powershell
Set-Location apps/chaoxing_app
flutter analyze
```

Expected: no analyzer errors.

- [ ] **Step 2: Run Flutter tests**

```powershell
flutter test
```

Expected: all unit and widget tests pass.

- [ ] **Step 3: Build Windows app**

```powershell
flutter build windows
```

Expected: Windows release build succeeds.

- [ ] **Step 4: Confirm Worker runtime removal**

```powershell
rg "ChaoxingApi|RUN_TOKEN|/app/sync|Bearer" lib test
```

Expected: no matches. `worker_base_url` and `run_token` may remain only as legacy keys in `app_storage.dart`.

- [ ] **Step 5: Manual Windows acceptance**

Run:

```powershell
flutter run -d windows
```

Expected:

- WebView login opens a real learning page; if cookie extraction fails, manual Cookie import validates and saves.
- Manual sync fetches fixture-free live learning data when valid Cookie is present.
- Closing the window hides to tray and timer continues while process runs.
- Tray menu actions work: open window, sync now, pause/resume notifications, view login status, exit.
- Exiting from tray stops process; no sync or notification happens after exit.
- Windows notification appears for a test item due at a configured rule time and click opens the App.
- Cookie never appears in UI, logs, diagnostics, notification body, or SharedPreferences JSON.

## Self-Review Checklist

- Spec coverage: tasks cover Flutter Windows enablement, Dart auth/Cookie/session, WebView/manual login fallback, Dart HTTP inbox fetching, processor and requirements parsing, local `SyncItem`/`AppSyncResponse`, storage migration, Windows tray, Windows notifications, assignment/exam reminder configuration, multiple advance rules, repeat rules, quiet hours, dedupe, errors, diagnostics, and tests.
- Phase coverage: Phase 1 produces a standalone local Windows App; Phase 2 adds course-space, work-list, and exam-list补漏; Phase 3 adds diagnostics without changing the no-background-after-exit rule.
- Runtime dependency check: Flutter App does not call Cloudflare Worker, Bun, Node helper, local helper script, or `/app/sync`.
- Placeholder scan: no placeholder markers, no deferred implementation markers, no unspecified validation steps.
- Type consistency: `AppConfig`, `SyncLimits`, `ReminderConfig`, `ReminderHistory`, `AuthState`, `InboxMessage`, `Requirement`, `SyncItem`, `AppSyncResponse`, `LocalSyncRunner`, `ReminderScheduler`, and service method names are defined before later tasks reference them.
- Security check: Cookie only goes through `flutter_secure_storage`, `ChaoxingHttpClient` limits Cookie-bearing requests to learning hosts, diagnostics redact Cookie and sensitive query params, and manual Cookie input is cleared after successful save.
