import 'dart:async';

import 'package:chaoxing_app/models/app_config.dart';
import 'package:chaoxing_app/models/app_sync_response.dart';
import 'package:chaoxing_app/models/course_catalog.dart';
import 'package:chaoxing_app/models/sync_item.dart';
import 'package:chaoxing_app/services/app_storage.dart';
import 'package:chaoxing_app/services/local_sync_runner.dart';
import 'package:chaoxing_app/services/reminder_service.dart';
import 'package:chaoxing_app/state/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('loads and updates monitored course selections', () async {
    final storage = MemoryAppStorage(
      courseCatalog: const CourseCatalog(
        courses: [
          CoursePreference(
            course: CourseSpace(
              courseId: '101',
              classId: '201',
              cpi: '301',
              title: '线性代数',
            ),
          ),
        ],
      ),
    );
    final controller = AppController(storage);
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.monitoredCourseCount, 1);

    await controller.setCourseMonitored('101:201', false);

    expect(controller.monitoredCourseCount, 0);
    expect(storage.courseCatalog.courses.single.monitored, isFalse);
  });

  test('manual course refresh forces discovery', () async {
    final now = DateTime(2026, 7, 27, 10);
    final runner = _CourseDiscoveryTrackingRunner(
      AppSyncResponse(
        lastSyncedAt: now,
        authStatus: 'ok',
        items: const [],
        failures: const [],
      ),
    );
    final controller = AppController(
      MemoryAppStorage(
        config: const AppConfig(
          cookie: 'UID=1',
          inboxPageLimit: 1,
          inboxItemLimit: 20,
          refreshMinutes: 60,
          remindersEnabled: true,
        ),
        cachedSync: AppSyncResponse(
          lastSyncedAt: now,
          authStatus: 'ok',
          items: const [],
          failures: const [],
        ),
      ),
      clock: () => now,
      runnerFactory: () => runner,
    );
    addTearDown(controller.dispose);
    await controller.load();

    await controller.refreshCourses();

    expect(runner.forceDiscoveryValues, [true]);
  });

  test('exposes progressive items before the final sync response', () async {
    final runner = _ProgressiveRunner();
    final controller = AppController(
      MemoryAppStorage(
        config: const AppConfig(
          cookie: 'UID=1',
          inboxPageLimit: 1,
          inboxItemLimit: 20,
          refreshMinutes: 60,
          remindersEnabled: true,
        ),
      ),
      runnerFactory: () => runner,
    );
    addTearDown(controller.dispose);

    final loading = controller.load();
    await runner.progressSent.future;

    expect(controller.items.single.id, 'assignment-1');
    expect(controller.items.single.status, 'details_loading');

    runner.finish(responseWithTitle('已解析作业'));
    await loading;
    expect(controller.items.single.title, '已解析作业');
  });

  test(
    'authentication expiry notifies once and blocks later refreshes',
    () async {
      var fetches = 0;
      final notifier = _RecordingControllerNotifier();
      final controller = AppController(
        MemoryAppStorage(
          config: const AppConfig(
            cookie: 'UID=1',
            inboxPageLimit: 1,
            inboxItemLimit: 20,
            refreshMinutes: 60,
            remindersEnabled: true,
          ),
        ),
        fetcher: (_, {previous}) async {
          fetches += 1;
          throw const AuthenticationExpiredException();
        },
        reminderService: LocalReminderService(notifier: notifier),
      );
      addTearDown(controller.dispose);

      await controller.load();
      await controller.refresh();

      expect(controller.authenticationState, AuthenticationState.expired);
      expect(fetches, 1);
      expect(notifier.candidates, hasLength(1));
      expect(notifier.candidates.single.key, 'authentication-expired');
    },
  );

  test('saving a new cookie recovers from authentication expiry', () async {
    var fetches = 0;
    final controller = AppController(
      MemoryAppStorage(
        config: const AppConfig(
          cookie: 'UID=old',
          inboxPageLimit: 1,
          inboxItemLimit: 20,
          refreshMinutes: 60,
          remindersEnabled: true,
        ),
      ),
      fetcher: (_, {previous}) async {
        fetches += 1;
        if (fetches == 1) {
          throw const AuthenticationExpiredException();
        }
        return responseWithTitle('恢复同步');
      },
    );
    addTearDown(controller.dispose);
    await controller.load();
    expect(controller.authenticationState, AuthenticationState.expired);

    await controller.saveConfig(controller.config.copyWith(cookie: 'UID=new'));

    expect(controller.authenticationState, AuthenticationState.valid);
    expect(controller.items.single.title, '恢复同步');
  });

  test('loads cached sync before refreshing configured accounts', () async {
    final cached = responseWithTitle('缓存作业');
    final fresh = responseWithTitle('最新作业');
    final storage = MemoryAppStorage(
      config: const AppConfig(
        cookie: 'UID=1',
        inboxPageLimit: 3,
        inboxItemLimit: 60,
        refreshMinutes: 60,
        remindersEnabled: true,
      ),
      cachedSync: cached,
    );
    final controller = AppController(
      storage,
      fetcher: (_, {previous}) async => fresh,
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.items.single.title, '最新作业');
    expect(storage.cachedSync?.items.single.title, '最新作业');
  });

  test('normalizes untrusted config loaded by the controller', () async {
    AppConfig? fetchedConfig;
    final controller = AppController(
      MemoryAppStorage(
        config: const AppConfig(
          cookie: '  UID=1  ',
          inboxPageLimit: 1000,
          inboxItemLimit: -1,
          refreshMinutes: 1,
          remindersEnabled: true,
          courseLimit: 0,
        ),
      ),
      fetcher: (config, {previous}) async {
        fetchedConfig = config;
        return responseWithTitle('规范化加载结果');
      },
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.config.cookie, 'UID=1');
    expect(controller.config.inboxPageLimit, 20);
    expect(controller.config.inboxItemLimit, 60);
    expect(controller.config.refreshMinutes, 15);
    expect(controller.config.courseLimit, 20);
    expect(fetchedConfig, same(controller.config));
  });

  test('quarantines an unsafe cookie loaded from legacy storage', () async {
    var fetches = 0;
    final storage = MemoryAppStorage(
      config: const AppConfig(
        cookie: 'UID=1\r\nX-Evil: injected',
        inboxPageLimit: 3,
        inboxItemLimit: 60,
        refreshMinutes: 60,
        remindersEnabled: true,
      ),
    );
    final controller = AppController(
      storage,
      fetcher: (_, {previous}) async {
        fetches += 1;
        return responseWithTitle('不应同步');
      },
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.isConfigured, isFalse);
    expect(controller.config.cookie, isEmpty);
    expect(controller.error, '本地 Cookie 格式不安全，已忽略，请重新登录');
    expect(controller.error, isNot(contains('injected')));
    expect(fetches, 0);
    expect(storage.config.cookie, isEmpty);
  });

  test(
    'uses a fresh startup cache without immediately syncing again',
    () async {
      final now = DateTime(2026, 7, 16, 21, 30);
      final itemResponse = responseWithTitle('刚同步的待办');
      final cached = AppSyncResponse(
        lastSyncedAt: now.subtract(const Duration(minutes: 2)),
        authStatus: 'ok',
        items: itemResponse.items,
        failures: const [],
      );
      var fetches = 0;
      final controller = AppController(
        MemoryAppStorage(
          config: const AppConfig(
            cookie: 'UID=1',
            inboxPageLimit: 3,
            inboxItemLimit: 60,
            refreshMinutes: 60,
            remindersEnabled: true,
          ),
          cachedSync: cached,
        ),
        clock: () => now,
        fetcher: (_, {previous}) async {
          fetches += 1;
          return responseWithTitle('不应立即同步');
        },
      );
      addTearDown(controller.dispose);

      await controller.load();

      expect(fetches, 0);
      expect(controller.items.single.title, '刚同步的待办');
      expect(controller.refreshing, isFalse);
    },
  );

  test('restores rate-limit backoff from a fresh startup cache', () async {
    var now = DateTime(2026, 7, 16, 21, 30);
    var fetches = 0;
    final cached = AppSyncResponse(
      lastSyncedAt: now.subtract(const Duration(minutes: 2)),
      authStatus: 'ok',
      items: const [],
      failures: const [
        AppSyncFailure(
          entryUrl: '',
          sourceTitle: '',
          message: '任务列表抓取失败 (429)',
        ),
      ],
    );
    final controller = AppController(
      MemoryAppStorage(
        config: const AppConfig(
          cookie: 'UID=1',
          inboxPageLimit: 3,
          inboxItemLimit: 60,
          refreshMinutes: 60,
          remindersEnabled: true,
        ),
        cachedSync: cached,
      ),
      clock: () => now,
      fetcher: (_, {previous}) async {
        fetches += 1;
        return responseWithTitle('退避结束后的结果');
      },
    );
    addTearDown(controller.dispose);

    await controller.load();
    await controller.refresh();
    await controller.refresh(silent: true);
    expect(fetches, 0);
    expect(controller.error, contains('180 秒后'));

    now = now.add(const Duration(minutes: 3));
    await controller.refresh(silent: true);
    expect(fetches, 1);
  });

  test('keeps cached items when refresh fails', () async {
    final cached = responseWithTitle('缓存作业');
    final controller = AppController(
      MemoryAppStorage(
        config: const AppConfig(
          cookie: 'UID=1',
          inboxPageLimit: 3,
          inboxItemLimit: 60,
          refreshMinutes: 60,
          remindersEnabled: true,
        ),
        cachedSync: cached,
      ),
      fetcher: (_, {previous}) async => throw Exception('network down'),
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.items.single.title, '缓存作业');
    expect(controller.error, contains('network down'));
  });

  test('recovers from local storage load failures', () async {
    final controller = AppController(
      _LoadFailingAppStorage(),
      fetcher: (_, {previous}) async => responseWithTitle('不应同步'),
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(controller.loading, isFalse);
    expect(controller.isConfigured, isFalse);
    expect(controller.error, contains('加载本地数据失败'));
    expect(controller.error, contains('secure storage unavailable'));
  });

  test('coalesces overlapping refresh calls into one fetch', () async {
    final completer = Completer<AppSyncResponse>();
    var calls = 0;
    final controller = AppController(
      MemoryAppStorage(),
      fetcher: (_, {previous}) {
        calls += 1;
        return completer.future;
      },
    );
    addTearDown(controller.dispose);

    final saveFuture = controller.saveConfig(
      const AppConfig(
        cookie: 'UID=1',
        inboxPageLimit: 3,
        inboxItemLimit: 60,
        refreshMinutes: 0,
        remindersEnabled: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    final manualFuture = controller.refresh();
    final autoFuture = controller.refresh(silent: true);

    expect(calls, 1);
    completer.complete(responseWithTitle('最新作业'));
    await Future.wait([saveFuture, manualFuture, autoFuture]);

    expect(calls, 1);
    expect(controller.items.single.title, '最新作业');
  });

  test('normalizes config before applying it to a sync', () async {
    AppConfig? fetchedConfig;
    final controller = AppController(
      MemoryAppStorage(),
      fetcher: (config, {previous}) async {
        fetchedConfig = config;
        return responseWithTitle('规范化配置结果');
      },
    );
    addTearDown(controller.dispose);

    await controller.saveConfig(
      const AppConfig(
        cookie: '  UID=1  ',
        inboxPageLimit: 999,
        inboxItemLimit: -1,
        refreshMinutes: 1,
        remindersEnabled: true,
        courseLimit: 0,
      ),
    );

    expect(controller.config.cookie, 'UID=1');
    expect(controller.config.inboxPageLimit, 20);
    expect(controller.config.inboxItemLimit, 60);
    expect(controller.config.refreshMinutes, 15);
    expect(controller.config.courseLimit, 20);
    expect(fetchedConfig, same(controller.config));
  });

  test('throttles immediate repeated manual refreshes after success', () async {
    var now = DateTime(2026, 7, 16, 21, 30);
    var calls = 0;
    final controller = AppController(
      MemoryAppStorage(),
      clock: () => now,
      fetcher: (_, {previous}) async {
        calls += 1;
        return responseWithTitle('最新作业');
      },
    );
    addTearDown(controller.dispose);

    await controller.saveConfig(
      const AppConfig(
        cookie: 'UID=1',
        inboxPageLimit: 3,
        inboxItemLimit: 60,
        refreshMinutes: 0,
        remindersEnabled: true,
      ),
    );
    expect(calls, 1);

    await controller.refresh();
    expect(calls, 1);
    expect(controller.error, contains('60 秒后'));

    await controller.refresh(silent: true);
    expect(calls, 2);

    now = now.add(const Duration(minutes: 1));
    await controller.refresh();
    expect(calls, 3);
    expect(controller.error, isNull);
  });

  test('backs off manual and silent refreshes after rate limiting', () async {
    var now = DateTime(2026, 7, 16, 21, 30);
    var calls = 0;
    final controller = AppController(
      MemoryAppStorage(),
      clock: () => now,
      fetcher: (_, {previous}) async {
        calls += 1;
        return AppSyncResponse(
          lastSyncedAt: now,
          authStatus: 'ok',
          items: const [],
          failures: calls == 1
              ? const [
                  AppSyncFailure(
                    entryUrl: '',
                    sourceTitle: '',
                    message: '页面抓取失败 (429)',
                  ),
                ]
              : const [],
        );
      },
    );
    addTearDown(controller.dispose);

    await controller.saveConfig(
      const AppConfig(
        cookie: 'UID=1',
        inboxPageLimit: 3,
        inboxItemLimit: 60,
        refreshMinutes: 0,
        remindersEnabled: true,
      ),
    );
    expect(calls, 1);

    await controller.refresh();
    await controller.refresh(silent: true);
    expect(calls, 1);
    expect(controller.error, contains('300 秒后'));

    now = now.add(const Duration(minutes: 5));
    await controller.refresh(silent: true);
    expect(calls, 2);
  });

  test(
    'reruns refresh with new config and discards the stale result',
    () async {
      final fetches =
          <({AppConfig config, Completer<AppSyncResponse> result})>[];
      final storage = MemoryAppStorage();
      final controller = AppController(
        storage,
        fetcher: (config, {previous}) {
          final fetch = (config: config, result: Completer<AppSyncResponse>());
          fetches.add(fetch);
          return fetch.result.future;
        },
      );
      addTearDown(controller.dispose);

      final oldSave = controller.saveConfig(
        const AppConfig(
          cookie: 'UID=old',
          inboxPageLimit: 3,
          inboxItemLimit: 60,
          refreshMinutes: 0,
          remindersEnabled: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(fetches, hasLength(1));

      final newSave = controller.saveConfig(
        controller.config.copyWith(cookie: 'UID=new'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(fetches, hasLength(1));

      fetches.first.result.complete(responseWithTitle('旧配置结果'));
      while (fetches.length < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(fetches.last.config.cookie, 'UID=new');
      expect(controller.items, isEmpty);

      fetches.last.result.complete(responseWithTitle('新配置结果'));
      await Future.wait([oldSave, newSave]);

      expect(controller.items.single.title, '新配置结果');
      expect(storage.cachedSync?.items.single.title, '新配置结果');
    },
  );

  test('cancels the old default client before syncing new config', () async {
    final firstRunner = _CloseTrackingRunner();
    final secondRunner = _ImmediateRunner(responseWithTitle('新配置结果'));
    final runners = <LocalSyncRunner>[firstRunner, secondRunner];
    final controller = AppController(
      MemoryAppStorage(),
      runnerFactory: () => runners.removeAt(0),
    );
    addTearDown(controller.dispose);

    final oldSave = controller.saveConfig(
      const AppConfig(
        cookie: 'UID=old',
        inboxPageLimit: 3,
        inboxItemLimit: 60,
        refreshMinutes: 0,
        remindersEnabled: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(firstRunner.closed, isFalse);

    final newSave = controller.saveConfig(
      controller.config.copyWith(cookie: 'UID=new'),
    );
    await Future<void>.delayed(Duration.zero);

    expect(firstRunner.closed, isTrue);
    await Future.wait([oldSave, newSave]);
    expect(controller.items.single.title, '新配置结果');
    expect(secondRunner.closed, isTrue);
  });

  test('clears the previous account cache when the cookie changes', () async {
    final storage = MemoryAppStorage();
    final controller = AppController(
      storage,
      fetcher: (config, {previous}) async {
        if (config.cookie == 'UID=old') {
          return responseWithTitle('旧账号待办');
        }
        throw Exception('new account sync failed');
      },
    );
    addTearDown(controller.dispose);

    await controller.saveConfig(
      const AppConfig(
        cookie: 'UID=old',
        inboxPageLimit: 3,
        inboxItemLimit: 60,
        refreshMinutes: 0,
        remindersEnabled: true,
      ),
    );
    expect(controller.items.single.title, '旧账号待办');
    expect(storage.cachedSync, isNotNull);

    await controller.saveConfig(controller.config.copyWith(cookie: 'UID=new'));

    expect(controller.config.cookie, 'UID=new');
    expect(controller.items, isEmpty);
    expect(storage.cachedSync, isNull);
    expect(controller.error, contains('new account sync failed'));
  });

  test('serializes concurrent reminder toggles without losing one', () async {
    final storage = MemoryAppStorage(
      config: const AppConfig(
        cookie: '',
        inboxPageLimit: 3,
        inboxItemLimit: 60,
        refreshMinutes: 0,
        remindersEnabled: true,
      ),
    );
    final controller = AppController(storage);
    addTearDown(controller.dispose);
    await controller.load();

    await Future.wait([
      controller.toggleRemindersEnabled(),
      controller.toggleRemindersEnabled(),
    ]);

    expect(controller.config.remindersEnabled, isTrue);
    expect(storage.config.remindersEnabled, isTrue);
  });

  test('redacts cookie from refresh errors', () async {
    final controller = AppController(
      MemoryAppStorage(),
      fetcher: (_, {previous}) async => throw Exception(
        'network failed Cookie: UID=1; vc=secret\n'
        'https://example.com?access_token=url-secret&account=student-42\n'
        'Authorization: Bearer bearer-secret',
      ),
    );
    addTearDown(controller.dispose);

    await controller.saveConfig(
      const AppConfig(
        cookie: 'UID=1; vc=secret',
        inboxPageLimit: 3,
        inboxItemLimit: 60,
        refreshMinutes: 0,
        remindersEnabled: true,
      ),
    );

    expect(controller.error, isNot(contains('UID=1')));
    expect(controller.error, isNot(contains('vc=secret')));
    expect(controller.error, isNot(contains('url-secret')));
    expect(controller.error, isNot(contains('student-42')));
    expect(controller.error, isNot(contains('bearer-secret')));
  });

  test('toggles reminder delivery without triggering a sync', () async {
    var fetches = 0;
    final storage = MemoryAppStorage(
      config: const AppConfig(
        cookie: 'UID=1',
        inboxPageLimit: 3,
        inboxItemLimit: 60,
        refreshMinutes: 0,
        remindersEnabled: true,
      ),
    );
    final controller = AppController(
      storage,
      fetcher: (_, {previous}) async {
        fetches += 1;
        return responseWithTitle('作业');
      },
    );
    addTearDown(controller.dispose);

    await controller.load();
    final fetchesAfterLoad = fetches;
    await controller.toggleRemindersEnabled();

    expect(controller.config.remindersEnabled, false);
    expect(storage.config.remindersEnabled, false);
    expect(fetches, fetchesAfterLoad);
  });

  test('allows an in-flight refresh to finish after desktop exit', () async {
    final completer = Completer<AppSyncResponse>();
    final controller = AppController(
      MemoryAppStorage(),
      fetcher: (_, {previous}) => completer.future,
    );

    final saveFuture = controller.saveConfig(
      const AppConfig(
        cookie: 'UID=1',
        inboxPageLimit: 3,
        inboxItemLimit: 60,
        refreshMinutes: 0,
        remindersEnabled: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    controller.dispose();
    completer.complete(responseWithTitle('退出前同步'));

    await expectLater(saveFuture, completes);
  });

  test('closes an active default sync client on desktop exit', () async {
    final runner = _CloseTrackingRunner();
    final controller = AppController(
      MemoryAppStorage(),
      runnerFactory: () => runner,
    );

    final saveFuture = controller.saveConfig(
      const AppConfig(
        cookie: 'UID=1',
        inboxPageLimit: 3,
        inboxItemLimit: 60,
        refreshMinutes: 0,
        remindersEnabled: true,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    controller.dispose();
    expect(runner.closed, isTrue);
    await saveFuture;
  });

  test(
    'keeps the previous in-memory config when secure storage fails',
    () async {
      final storage = _FailingAppStorage(
        config: const AppConfig(
          cookie: 'UID=old',
          inboxPageLimit: 3,
          inboxItemLimit: 60,
          refreshMinutes: 0,
          remindersEnabled: true,
        ),
      );
      final controller = AppController(
        storage,
        fetcher: (_, {previous}) async => responseWithTitle('作业'),
      );
      addTearDown(controller.dispose);
      await controller.load();

      await expectLater(
        controller.saveConfig(controller.config.copyWith(cookie: 'UID=new')),
        throwsStateError,
      );

      expect(controller.config.cookie, 'UID=old');
    },
  );

  test('imports a login cookie without waiting for the full sync', () async {
    final syncCompleter = Completer<AppSyncResponse>();
    final storage = MemoryAppStorage();
    final controller = AppController(
      storage,
      fetcher: (_, {previous}) => syncCompleter.future,
      authenticator: (_) async => const AuthCheckResult(
        authenticated: true,
        statusCode: 200,
        loginDetected: false,
        finalUrl: 'https://i.chaoxing.com/base',
        title: '个人空间',
      ),
    );
    addTearDown(controller.dispose);
    await controller.load();

    await controller.importLoginCookie('  UID=imported  ');

    expect(storage.config.cookie, 'UID=imported');
    expect(controller.config.cookie, 'UID=imported');
    expect(controller.refreshing, isTrue);
    expect(controller.syncProgress?.phase, SyncPhase.authentication);

    syncCompleter.complete(responseWithTitle('后台同步'));
    await controller.refresh();
    expect(controller.refreshing, isFalse);
    expect(controller.syncProgress, isNull);
  });

  test('rejects a captured cookie before saving when auth fails', () async {
    final storage = MemoryAppStorage();
    final controller = AppController(
      storage,
      fetcher: (_, {previous}) async => responseWithTitle('不应同步'),
      authenticator: (_) async => const AuthCheckResult(
        authenticated: false,
        statusCode: 200,
        loginDetected: true,
        finalUrl: 'https://passport2.chaoxing.com/login',
        title: '用户登录',
      ),
    );
    addTearDown(controller.dispose);
    await controller.load();

    await expectLater(
      controller.importLoginCookie('UID=invalid'),
      throwsA(
        isA<LocalSyncException>().having(
          (error) => error.message,
          'message',
          contains('登录态验证失败'),
        ),
      ),
    );

    expect(storage.config.cookie, isEmpty);
    expect(controller.config.cookie, isEmpty);
  });

  test('hands the cached seen notices to the next sync', () async {
    final cached = AppSyncResponse(
      lastSyncedAt: DateTime(2026, 6, 5, 8),
      authStatus: 'ok',
      items: responseWithTitle('缓存作业').items,
      failures: const [],
      seenNotices: const [
        SeenNotice(
          id: 'notice-1',
          detailParsed: true,
          taskLinks: ['https://mooc1.chaoxing.com/work?workId=1'],
        ),
      ],
    );
    AppSyncResponse? handedPrevious;
    final controller = AppController(
      MemoryAppStorage(
        config: const AppConfig(
          cookie: 'UID=1',
          inboxPageLimit: 3,
          inboxItemLimit: 60,
          refreshMinutes: 60,
          remindersEnabled: true,
        ),
        cachedSync: cached,
      ),
      fetcher: (_, {previous}) async {
        handedPrevious = previous;
        return responseWithTitle('最新作业');
      },
    );
    addTearDown(controller.dispose);

    await controller.load();

    expect(handedPrevious?.seenNotices.single.id, 'notice-1');
    expect(handedPrevious?.seenNotices.single.taskLinks, [
      'https://mooc1.chaoxing.com/work?workId=1',
    ]);
  });

  test('rejects newline cookie injection before auth or storage', () async {
    var authCalls = 0;
    final storage = MemoryAppStorage();
    final controller = AppController(
      storage,
      authenticator: (_) async {
        authCalls += 1;
        return const AuthCheckResult(
          authenticated: true,
          statusCode: 200,
          loginDetected: false,
          finalUrl: '',
          title: null,
        );
      },
    );
    addTearDown(controller.dispose);

    expect(
      () => controller.importLoginCookie('UID=1\r\nX-Evil: injected'),
      throwsA(isA<LocalSyncException>()),
    );
    expect(authCalls, 0);
    expect(storage.config.cookie, isEmpty);
  });
}

class _FailingAppStorage extends MemoryAppStorage {
  _FailingAppStorage({required super.config});

  @override
  Future<void> saveConfig(AppConfig config) {
    throw StateError('secure storage unavailable');
  }
}

class _CloseTrackingRunner extends LocalSyncRunner {
  final Completer<AppSyncResponse> _result = Completer<AppSyncResponse>();
  bool closed = false;

  @override
  Future<AppSyncResponse> run(
    AppConfig config, {
    AppSyncResponse? previous,
    SyncProgressCallback? onProgress,
    CourseCatalog courseCatalog = CourseCatalog.empty,
    bool forceCourseDiscovery = false,
    CourseCatalogChanged? onCourseCatalogChanged,
  }) => _result.future;

  @override
  void close() {
    closed = true;
    if (!_result.isCompleted) {
      _result.completeError(const LocalSyncException('同步已停止'));
    }
  }
}

class _ImmediateRunner extends LocalSyncRunner {
  _ImmediateRunner(this.response);

  final AppSyncResponse response;
  bool closed = false;

  @override
  Future<AppSyncResponse> run(
    AppConfig config, {
    AppSyncResponse? previous,
    SyncProgressCallback? onProgress,
    CourseCatalog courseCatalog = CourseCatalog.empty,
    bool forceCourseDiscovery = false,
    CourseCatalogChanged? onCourseCatalogChanged,
  }) async => response;

  @override
  void close() => closed = true;
}

class _CourseDiscoveryTrackingRunner extends LocalSyncRunner {
  _CourseDiscoveryTrackingRunner(this.response);

  final AppSyncResponse response;
  final List<bool> forceDiscoveryValues = [];

  @override
  Future<AppSyncResponse> run(
    AppConfig config, {
    AppSyncResponse? previous,
    SyncProgressCallback? onProgress,
    CourseCatalog courseCatalog = CourseCatalog.empty,
    bool forceCourseDiscovery = false,
    CourseCatalogChanged? onCourseCatalogChanged,
  }) async {
    forceDiscoveryValues.add(forceCourseDiscovery);
    return response;
  }
}

class _ProgressiveRunner extends LocalSyncRunner {
  final Completer<void> progressSent = Completer<void>();
  final Completer<AppSyncResponse> _result = Completer<AppSyncResponse>();

  @override
  Future<AppSyncResponse> run(
    AppConfig config, {
    AppSyncResponse? previous,
    SyncProgressCallback? onProgress,
    CourseCatalog courseCatalog = CourseCatalog.empty,
    bool forceCourseDiscovery = false,
    CourseCatalogChanged? onCourseCatalogChanged,
  }) {
    onProgress?.call(
      const SyncProgress(
        phase: SyncPhase.assignmentDetails,
        total: 1,
        partialItems: [
          SyncItem(
            id: 'assignment-1',
            kind: SyncItemKind.assignment,
            title: '正在解析的作业',
            url: 'https://mooc1.chaoxing.com/work?workId=1',
            sourceTitle: '通知',
            status: 'details_loading',
            displayStatus: SyncDisplayStatus.unscheduled,
          ),
        ],
      ),
    );
    progressSent.complete();
    return _result.future;
  }

  void finish(AppSyncResponse response) => _result.complete(response);
}

class _RecordingControllerNotifier implements ReminderNotifier {
  final List<ReminderCandidate> candidates = [];

  @override
  Future<bool> show(ReminderCandidate candidate) async {
    candidates.add(candidate);
    return true;
  }
}

class _LoadFailingAppStorage extends MemoryAppStorage {
  @override
  Future<AppConfig> loadConfig() {
    throw StateError('secure storage unavailable');
  }
}

AppSyncResponse responseWithTitle(String title) {
  return AppSyncResponse(
    lastSyncedAt: DateTime(2026, 6, 5, 8),
    authStatus: 'ok',
    failures: const [],
    items: [
      SyncItem(
        id: 'assignment-1',
        kind: SyncItemKind.assignment,
        title: title,
        url: 'https://example.com/work',
        sourceTitle: '作业通知',
        status: 'answering',
        displayStatus: SyncDisplayStatus.upcoming,
        dueAt: DateTime(2026, 6, 6, 10),
      ),
    ],
  );
}
