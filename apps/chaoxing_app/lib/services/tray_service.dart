import 'dart:async';
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

abstract class TrayPlatformBridge {
  Future<void> initialize({
    required TrayListener trayListener,
    required WindowListener windowListener,
  });

  Future<void> update(TrayMenuState state);

  Future<void> hideWindow();

  Future<void> dispose({
    required TrayListener trayListener,
    required WindowListener windowListener,
  });
}

class PluginTrayPlatformBridge implements TrayPlatformBridge {
  const PluginTrayPlatformBridge();

  @override
  Future<void> initialize({
    required TrayListener trayListener,
    required WindowListener windowListener,
  }) async {
    trayManager.addListener(trayListener);
    windowManager.addListener(windowListener);
    await trayManager.setIcon('windows/runner/resources/app_icon.ico');
  }

  @override
  Future<void> update(TrayMenuState state) async {
    await trayManager.setContextMenu(
      Menu(
        items: [
          MenuItem(key: 'open', label: '打开窗口'),
          MenuItem(
            key: 'sync',
            label: state.syncInProgress ? '同步中' : '立即同步',
            disabled: state.syncInProgress,
          ),
          MenuItem(
            key: 'pause',
            label: state.notificationsPaused ? '恢复通知' : '暂停通知',
          ),
          MenuItem(key: 'login', label: '查看登录状态'),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: '退出'),
        ],
      ),
    );
    await trayManager.setToolTip('学习通待办 - ${state.authSummary}');
  }

  @override
  Future<void> hideWindow() => windowManager.hide();

  @override
  Future<void> dispose({
    required TrayListener trayListener,
    required WindowListener windowListener,
  }) async {
    trayManager.removeListener(trayListener);
    windowManager.removeListener(windowListener);
    await trayManager.destroy();
  }
}

class TrayService with TrayListener, WindowListener {
  TrayService({
    required this.onOpenWindow,
    required this.onSyncNow,
    required this.onToggleNotifications,
    required this.onOpenLoginStatus,
    required this.onExit,
    TrayPlatformBridge? bridge,
    bool? enabled,
  }) : _bridge = bridge ?? const PluginTrayPlatformBridge(),
       _enabled = enabled ?? Platform.isWindows;

  final Future<void> Function() onOpenWindow;
  final Future<void> Function() onSyncNow;
  final Future<void> Function() onToggleNotifications;
  final Future<void> Function() onOpenLoginStatus;
  final Future<void> Function() onExit;
  final TrayPlatformBridge _bridge;
  final bool _enabled;
  bool _allowClose = false;

  Future<void> initialize(TrayMenuState state) async {
    if (!_enabled) {
      return;
    }
    await _bridge.initialize(trayListener: this, windowListener: this);
    await _bridge.update(state);
  }

  Future<void> update(TrayMenuState state) async {
    if (_enabled) {
      await _bridge.update(state);
    }
  }

  Future<void> handleMenuAction(String? key) async {
    switch (key) {
      case 'open':
        await onOpenWindow();
        return;
      case 'sync':
        await onSyncNow();
        return;
      case 'pause':
        await onToggleNotifications();
        return;
      case 'login':
        await onOpenLoginStatus();
        return;
      case 'exit':
        _allowClose = true;
        await onExit();
        return;
    }
  }

  Future<void> handleWindowClose() async {
    if (_enabled && !_allowClose) {
      await _bridge.hideWindow();
    }
  }

  @override
  void onWindowClose() {
    unawaited(handleWindowClose());
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(onOpenWindow());
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    unawaited(handleMenuAction(menuItem.key));
  }

  Future<void> dispose() async {
    if (_enabled) {
      await _bridge.dispose(trayListener: this, windowListener: this);
    }
  }
}
