import 'dart:async';
import 'dart:io';

import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

class TrayMenuState {
  const TrayMenuState({
    required this.notificationsPaused,
    required this.syncInProgress,
    required this.authSummary,
    this.authenticationExpired = false,
  });

  final bool notificationsPaused;
  final bool syncInProgress;
  final String authSummary;
  final bool authenticationExpired;

  String get tooltip =>
      '${authenticationExpired ? '⚠ ' : ''}学习通待办 - $authSummary';

  List<String> get labels => [
    '打开窗口',
    syncInProgress ? '同步中' : '立即同步',
    notificationsPaused ? '恢复通知' : '暂停通知',
    authenticationExpired ? '重新登录' : '查看登录状态',
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
          MenuItem(
            key: 'login',
            label: state.authenticationExpired ? '重新登录' : '查看登录状态',
          ),
          MenuItem.separator(),
          MenuItem(key: 'exit', label: '退出'),
        ],
      ),
    );
    await trayManager.setToolTip(state.tooltip);
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
    this.onError,
    TrayPlatformBridge? bridge,
    bool? enabled,
  }) : _bridge = bridge ?? const PluginTrayPlatformBridge(),
       _enabled = enabled ?? Platform.isWindows;

  final Future<void> Function() onOpenWindow;
  final Future<void> Function() onSyncNow;
  final Future<void> Function() onToggleNotifications;
  final Future<void> Function() onOpenLoginStatus;
  final Future<void> Function() onExit;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final TrayPlatformBridge _bridge;
  final bool _enabled;
  bool _allowClose = false;
  bool _exitRequested = false;
  bool _disposed = false;
  TrayMenuState? _queuedState;
  Future<void>? _updateFuture;

  Future<void> initialize(TrayMenuState state) async {
    if (!_enabled) {
      return;
    }
    await _bridge.initialize(trayListener: this, windowListener: this);
    await _bridge.update(state);
  }

  Future<void> update(TrayMenuState state) async {
    if (!_enabled || _disposed) {
      return;
    }
    _queuedState = state;
    return _updateFuture ??= _drainUpdates();
  }

  Future<void> _drainUpdates() async {
    try {
      while (_queuedState != null) {
        final state = _queuedState!;
        _queuedState = null;
        await _bridge.update(state);
      }
    } finally {
      _updateFuture = null;
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
        if (_exitRequested) {
          return;
        }
        _exitRequested = true;
        _allowClose = true;
        try {
          await onExit();
        } catch (_) {
          _exitRequested = false;
          _allowClose = false;
          rethrow;
        }
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
    _runDetached(handleWindowClose);
  }

  @override
  void onTrayIconMouseDown() {
    _runDetached(onOpenWindow);
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    _runDetached(() => handleMenuAction(menuItem.key));
  }

  void _runDetached(Future<void> Function() action) {
    unawaited(
      action().catchError((Object error, StackTrace stackTrace) {
        final handler = onError;
        if (handler != null) {
          handler(error, stackTrace);
          return;
        }
        Zone.current.handleUncaughtError(error, stackTrace);
      }),
    );
  }

  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _queuedState = null;
    try {
      await _updateFuture;
    } catch (_) {
      // The original update caller reports this error. Cleanup must continue.
    }
    if (_enabled) {
      await _bridge.dispose(trayListener: this, windowListener: this);
    }
  }
}
