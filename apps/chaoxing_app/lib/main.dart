import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'models/sync_item.dart';
import 'screens/detail_screen.dart';
import 'screens/home_screen.dart';
import 'screens/windows_login_screen.dart';
import 'services/app_storage.dart';
import 'services/reminder_service.dart';
import 'services/tray_service.dart';
import 'state/app_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    await windowManager.setPreventClose(true);
  }

  final navigatorKey = GlobalKey<NavigatorState>();
  late final AppController controller;
  final windowsNotifier = WindowsReminderNotifier(
    onNotificationClick: (itemId) {
      unawaited(_openItemFromDesktop(navigatorKey, controller, itemId));
    },
  );
  ReminderNotifier notifier = const NoopReminderNotifier();
  try {
    await windowsNotifier.initialize();
    notifier = windowsNotifier;
  } catch (error) {
    debugPrint('Windows 通知初始化失败：$error');
  }

  controller = AppController(
    DeviceAppStorage(),
    reminderService: LocalReminderService(notifier: notifier),
  );
  runApp(ChaoxingApp(controller: controller, navigatorKey: navigatorKey));

  if (!Platform.isWindows) {
    return;
  }

  const windowOptions = WindowOptions(
    size: Size(1080, 760),
    minimumSize: Size(760, 560),
    center: true,
    title: '学习通待办',
  );

  late final TrayService trayService;
  trayService = TrayService(
    onOpenWindow: _showMainWindow,
    onSyncNow: controller.refresh,
    onToggleNotifications: controller.toggleRemindersEnabled,
    onOpenLoginStatus: () async {
      await _showMainWindow();
      _openLoginFromDesktop(navigatorKey, controller);
    },
    onError: (error, _) => debugPrint('Windows 托盘操作失败：$error'),
    onExit: () async {
      controller.dispose();
      await trayService.dispose();
      await windowManager.setPreventClose(false);
      await windowManager.close();
    },
  );
  try {
    await trayService.initialize(_trayState(controller));
  } catch (error) {
    debugPrint('Windows 托盘初始化失败：$error');
    try {
      await trayService.dispose();
    } catch (disposeError) {
      debugPrint('Windows 托盘清理失败：$disposeError');
    }
    await windowManager.setPreventClose(false);
    await windowManager.waitUntilReadyToShow(windowOptions, _showMainWindow);
    return;
  }
  controller.addListener(() {
    unawaited(_updateTraySafely(trayService, _trayState(controller)));
  });
  await windowManager.waitUntilReadyToShow(windowOptions, _showMainWindow);
}

class ChaoxingApp extends StatelessWidget {
  const ChaoxingApp({required this.controller, this.navigatorKey, super.key});

  final AppController controller;
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '学习通待办',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF256D85),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF6F7F9),
        cardTheme: const CardThemeData(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
            side: BorderSide(color: Color(0xFFE1E5EA)),
          ),
        ),
      ),
      home: HomeScreen(controller: controller),
    );
  }
}

Future<void> _showMainWindow() async {
  await windowManager.show();
  await windowManager.focus();
}

Future<void> _openItemFromDesktop(
  GlobalKey<NavigatorState> navigatorKey,
  AppController controller,
  String itemId,
) async {
  if (Platform.isWindows) {
    await _showMainWindow();
  }
  SyncItem? selected;
  for (final item in controller.items) {
    if (item.id == itemId) {
      selected = item;
      break;
    }
  }
  final navigator = navigatorKey.currentState;
  if (selected != null && navigator != null) {
    final selectedItem = selected;
    await navigator.push<void>(
      MaterialPageRoute(builder: (_) => DetailScreen(item: selectedItem)),
    );
  }
}

void _openLoginFromDesktop(
  GlobalKey<NavigatorState> navigatorKey,
  AppController controller,
) {
  navigatorKey.currentState?.push<void>(
    MaterialPageRoute(
      builder: (_) =>
          WindowsLoginScreen(onCookieCaptured: controller.importLoginCookie),
    ),
  );
}

TrayMenuState _trayState(AppController controller) {
  final summary = controller.refreshing
      ? controller.syncProgress?.description ?? '同步中'
      : controller.isConfigured
      ? controller.sync == null
            ? '已配置，尚未同步'
            : controller.sync!.lastSyncedAt == null
            ? '已配置，同步时间未知'
            : '已配置，上次同步 ${_formatTrayTime(controller.sync!.lastSyncedAt!)}'
      : '未配置 Cookie';
  final authenticationExpired =
      controller.authenticationState == AuthenticationState.expired;
  return TrayMenuState(
    notificationsPaused: !controller.config.remindersEnabled,
    syncInProgress: controller.refreshing,
    authSummary: authenticationExpired ? '登录已失效' : summary,
    authenticationExpired: authenticationExpired,
  );
}

String _formatTrayTime(DateTime value) {
  String twoDigits(int number) => number.toString().padLeft(2, '0');
  return '${twoDigits(value.hour)}:${twoDigits(value.minute)}';
}

Future<void> _updateTraySafely(
  TrayService trayService,
  TrayMenuState state,
) async {
  try {
    await trayService.update(state);
  } catch (error) {
    debugPrint('Windows 托盘状态更新失败：$error');
  }
}
