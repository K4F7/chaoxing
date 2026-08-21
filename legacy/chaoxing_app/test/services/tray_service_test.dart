import 'dart:async';

import 'package:chaoxing_app/services/tray_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  test('tray state makes authentication expiry visible', () {
    const state = TrayMenuState(
      notificationsPaused: false,
      syncInProgress: false,
      authSummary: '登录已失效',
      authenticationExpired: true,
    );

    expect(state.labels, contains('重新登录'));
    expect(state.tooltip, startsWith('⚠'));
  });

  test('tray menu state exposes required actions and current status', () {
    expect(
      const TrayMenuState(
        notificationsPaused: false,
        syncInProgress: false,
        authSummary: '已配置',
      ).labels,
      ['打开窗口', '立即同步', '暂停通知', '查看登录状态', '退出'],
    );
    expect(
      const TrayMenuState(
        notificationsPaused: true,
        syncInProgress: true,
        authSummary: '同步中',
      ).labels,
      containsAll(['同步中', '恢复通知']),
    );
  });

  test('tray dispatches menu actions and close hides the window', () async {
    final bridge = FakeTrayPlatformBridge();
    final actions = <String>[];
    final service = TrayService(
      enabled: true,
      bridge: bridge,
      onOpenWindow: () async => actions.add('open'),
      onSyncNow: () async => actions.add('sync'),
      onToggleNotifications: () async => actions.add('pause'),
      onOpenLoginStatus: () async => actions.add('login'),
      onExit: () async => actions.add('exit'),
    );

    await service.initialize(
      const TrayMenuState(
        notificationsPaused: false,
        syncInProgress: false,
        authSummary: '已配置',
      ),
    );
    await service.handleMenuAction('open');
    await service.handleMenuAction('sync');
    await service.handleMenuAction('pause');
    await service.handleMenuAction('login');
    await service.handleWindowClose();

    expect(actions, ['open', 'sync', 'pause', 'login']);
    expect(bridge.initialized, true);
    expect(bridge.state?.authSummary, '已配置');
    expect(bridge.hideCalls, 1);

    await service.handleMenuAction('exit');
    await service.handleWindowClose();
    expect(actions.last, 'exit');
    expect(bridge.hideCalls, 1);

    await service.dispose();
    expect(bridge.disposed, true);
  });

  test(
    'tray serializes updates and coalesces pending state to the latest',
    () async {
      final bridge = DeferredTrayPlatformBridge();
      final service = buildService(bridge);
      final first = service.update(trayState('first'));
      await bridge.firstUpdateStarted.future;

      final second = service.update(trayState('second'));
      final third = service.update(trayState('latest'));
      bridge.releaseFirstUpdate.complete();
      await Future.wait([first, second, third]);

      expect(bridge.summaries, ['first', 'latest']);
      expect(bridge.maxConcurrentUpdates, 1);
    },
  );

  test('tray exit is idempotent while shutdown is in progress', () async {
    final bridge = FakeTrayPlatformBridge();
    final releaseExit = Completer<void>();
    var exitCalls = 0;
    final service = TrayService(
      enabled: true,
      bridge: bridge,
      onOpenWindow: () async {},
      onSyncNow: () async {},
      onToggleNotifications: () async {},
      onOpenLoginStatus: () async {},
      onExit: () async {
        exitCalls += 1;
        await releaseExit.future;
      },
    );

    final first = service.handleMenuAction('exit');
    final second = service.handleMenuAction('exit');
    releaseExit.complete();
    await Future.wait([first, second]);

    expect(exitCalls, 1);
  });

  test('tray plugin callbacks report asynchronous action failures', () async {
    final errors = <Object>[];
    final service = TrayService(
      enabled: true,
      bridge: FakeTrayPlatformBridge(),
      onOpenWindow: () async => throw StateError('open failed'),
      onSyncNow: () async {},
      onToggleNotifications: () async {},
      onOpenLoginStatus: () async {},
      onExit: () async {},
      onError: (error, _) => errors.add(error),
    );

    service.onTrayIconMouseDown();
    await Future<void>.delayed(Duration.zero);

    expect(errors, hasLength(1));
    expect(errors.single, isA<StateError>());
  });
}

TrayService buildService(TrayPlatformBridge bridge) => TrayService(
  enabled: true,
  bridge: bridge,
  onOpenWindow: () async {},
  onSyncNow: () async {},
  onToggleNotifications: () async {},
  onOpenLoginStatus: () async {},
  onExit: () async {},
);

TrayMenuState trayState(String summary) => TrayMenuState(
  notificationsPaused: false,
  syncInProgress: false,
  authSummary: summary,
);

class FakeTrayPlatformBridge implements TrayPlatformBridge {
  bool initialized = false;
  bool disposed = false;
  int hideCalls = 0;
  TrayMenuState? state;

  @override
  Future<void> initialize({
    required TrayListener trayListener,
    required WindowListener windowListener,
  }) async {
    initialized = true;
  }

  @override
  Future<void> update(TrayMenuState state) async {
    this.state = state;
  }

  @override
  Future<void> hideWindow() async {
    hideCalls += 1;
  }

  @override
  Future<void> dispose({
    required TrayListener trayListener,
    required WindowListener windowListener,
  }) async {
    disposed = true;
  }
}

class DeferredTrayPlatformBridge extends FakeTrayPlatformBridge {
  final firstUpdateStarted = Completer<void>();
  final releaseFirstUpdate = Completer<void>();
  final summaries = <String>[];
  int concurrentUpdates = 0;
  int maxConcurrentUpdates = 0;

  @override
  Future<void> update(TrayMenuState state) async {
    summaries.add(state.authSummary);
    concurrentUpdates += 1;
    if (concurrentUpdates > maxConcurrentUpdates) {
      maxConcurrentUpdates = concurrentUpdates;
    }
    if (!firstUpdateStarted.isCompleted) {
      firstUpdateStarted.complete();
      await releaseFirstUpdate.future;
    }
    concurrentUpdates -= 1;
  }
}
