import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_config.dart';
import '../models/app_sync_response.dart';
import '../models/course_catalog.dart';
import '../models/sync_item.dart';
import '../services/app_storage.dart';
import '../services/chaoxing_cookie_store.dart';
import '../services/local_sync_runner.dart';
import '../services/reminder_service.dart';
import '../utils/redaction.dart';

typedef SyncFetcher =
    Future<AppSyncResponse> Function(
      AppConfig config, {
      AppSyncResponse? previous,
    });
typedef CookieAuthenticator = Future<AuthCheckResult> Function(String cookie);
const _startupCacheFreshness = Duration(minutes: 5);
const _manualRefreshCooldown = Duration(minutes: 1);
const _rateLimitBackoff = Duration(minutes: 5);

class AppController extends ChangeNotifier {
  AppController(
    this._storage, {
    SyncFetcher? fetcher,
    CookieAuthenticator? authenticator,
    LocalReminderService? reminderService,
    DateTime Function()? clock,
    LocalSyncRunner Function()? runnerFactory,
  }) : _reminderService = reminderService ?? const LocalReminderService(),
       _clock = clock ?? DateTime.now,
       _runnerFactory = runnerFactory ?? LocalSyncRunner.new,
       super() {
    _fetcher =
        fetcher ??
        (config, {previous}) => _withLocalRunner(
          (runner) => runner.run(
            config,
            previous: previous,
            onProgress: _handleSyncProgress,
            courseCatalog: _courseCatalog,
            forceCourseDiscovery: _forceCourseDiscovery,
            onCourseCatalogChanged: _saveDiscoveredCourseCatalog,
          ),
        );
    _authenticator =
        authenticator ??
        (cookie) => _withLocalRunner((runner) => runner.checkAuth(cookie));
  }

  final AppStorage _storage;
  late final SyncFetcher _fetcher;
  late final CookieAuthenticator _authenticator;
  final LocalReminderService _reminderService;
  final DateTime Function() _clock;
  final LocalSyncRunner Function() _runnerFactory;
  Timer? _refreshTimer;
  Future<void>? _refreshInFlight;
  Future<void> _configMutationTail = Future<void>.value();
  int _configRevision = 0;
  int _loadGeneration = 0;
  int? _activeRefreshRevision;
  DateTime? _lastAcceptedRefreshAt;
  DateTime? _rateLimitBackoffUntil;
  bool _refreshQueued = false;
  bool _queuedRefreshIsSilent = true;
  bool _forceCourseDiscovery = false;
  bool _disposed = false;
  final Set<LocalSyncRunner> _activeLocalRunners = {};

  AppConfig _config = AppConfig.empty;
  AppSyncResponse? _sync;
  CourseCatalog _courseCatalog = CourseCatalog.empty;
  bool _loading = true;
  bool _refreshing = false;
  SyncProgress? _syncProgress;
  String? _error;

  AppConfig get config => _config;

  AppSyncResponse? get sync => _sync;

  CourseCatalog get courseCatalog => _courseCatalog;

  int get monitoredCourseCount => _courseCatalog.monitoredCourses.length;

  bool get loading => _loading;

  bool get refreshing => _refreshing;

  SyncProgress? get syncProgress => _syncProgress;

  String? get error => _error;

  bool get isConfigured => _config.isConfigured;

  List<SyncItem> get items => _sync?.items ?? const [];

  List<SyncItem> get overdueItems => items
      .where((item) => item.displayStatus == SyncDisplayStatus.overdue)
      .toList();

  List<SyncItem> get todayItems => items
      .where((item) => item.displayStatus == SyncDisplayStatus.today)
      .toList();

  List<SyncItem> get upcomingItems => items
      .where((item) => item.displayStatus == SyncDisplayStatus.upcoming)
      .toList();

  List<SyncItem> get unscheduledItems => items
      .where((item) => item.displayStatus == SyncDisplayStatus.unscheduled)
      .toList();

  List<SyncItem> get dueSoonItems =>
      items.where((item) => item.isDueSoon).toList();

  Future<void> load() async {
    final generation = ++_loadGeneration;
    final revisionAtStart = _configRevision;
    _loading = true;
    _notifyListeners();
    var applied = false;
    try {
      final loadedConfig = await _storage.loadConfig();
      final loadedSync = await _storage.loadCachedSync();
      final loadedCourseCatalog = await _storage.loadCourseCatalog();
      await _serializeStorageMutation(() async {
        if (_disposed ||
            generation != _loadGeneration ||
            revisionAtStart != _configRevision) {
          return;
        }
        final normalizedConfig = loadedConfig.normalized();
        final unsafeCookie =
            normalizedConfig.cookie.isNotEmpty &&
            !isSafeChaoxingCookieSource(normalizedConfig.cookie);
        if (unsafeCookie) {
          try {
            await _storage.clearCookie();
          } catch (_) {
            // In-memory quarantine stays authoritative while a platform
            // credential store is temporarily unavailable.
          }
        }
        _config = unsafeCookie
            ? normalizedConfig.copyWith(cookie: '')
            : normalizedConfig;
        _sync = loadedSync;
        _courseCatalog = loadedCourseCatalog;
        _restoreRefreshGuardsFromCache(loadedSync);
        _error = unsafeCookie ? '本地 Cookie 格式不安全，已忽略，请重新登录' : null;
        _configRevision += 1;
        applied = true;
      });
    } catch (error) {
      if (!_disposed &&
          generation == _loadGeneration &&
          revisionAtStart == _configRevision) {
        _error = '加载本地数据失败：${_safeErrorMessage(error, _config.cookie)}';
      }
    } finally {
      if (!_disposed && generation == _loadGeneration) {
        _loading = false;
        _notifyListeners();
      }
    }

    if (applied && _config.isConfigured) {
      _scheduleAutoRefresh();
      if (_hasFreshCachedSync()) {
        return;
      }
      await refresh(silent: _sync != null);
    }
  }

  Future<void> saveConfig(AppConfig config) async {
    await _saveConfig(config, waitForRefresh: true);
  }

  Future<void> importLoginCookie(String cookie) async {
    final normalizedCookie = cookie.trim();
    _validateCookieSource(normalizedCookie);
    _syncProgress = const SyncProgress(
      phase: SyncPhase.authentication,
      total: 1,
    );
    _notifyListeners();
    try {
      final auth = await _authenticator(normalizedCookie);
      if (!auth.authenticated) {
        throw const LocalSyncException('登录态验证失败，请在登录成功后重试。');
      }
    } catch (_) {
      _syncProgress = null;
      _notifyListeners();
      rethrow;
    }
    try {
      await _saveConfig(
        _config.copyWith(cookie: normalizedCookie),
        waitForRefresh: false,
      );
    } catch (_) {
      _syncProgress = null;
      _notifyListeners();
      rethrow;
    }
  }

  Future<void> _saveConfig(
    AppConfig config, {
    required bool waitForRefresh,
  }) async {
    config = config.normalized();
    if (config.cookie.isNotEmpty) {
      _validateCookieSource(config.cookie);
    }
    await _serializeStorageMutation(() async {
      final accountChanged = _config.cookie.trim() != config.cookie.trim();
      await _storage.saveConfig(config);
      if (accountChanged) {
        await _storage.clearCachedSync();
      }
      if (_disposed) {
        return;
      }
      if (accountChanged) {
        _sync = null;
      }
      _closeActiveLocalRunners();
      _lastAcceptedRefreshAt = null;
      _rateLimitBackoffUntil = null;
      _applyConfig(config);
    });
    if (config.isConfigured) {
      final refreshFuture = refresh();
      if (waitForRefresh) {
        await refreshFuture;
      } else {
        unawaited(refreshFuture);
      }
    }
  }

  Future<void> toggleRemindersEnabled() async {
    await _serializeStorageMutation(() async {
      final updated = _config.copyWith(
        remindersEnabled: !_config.remindersEnabled,
      );
      await _storage.saveConfig(updated);
      if (_disposed) {
        return;
      }
      _applyConfig(updated, scheduleRefresh: false);
    });
  }

  Future<void> setCourseMonitored(String courseKey, bool monitored) async {
    await _serializeStorageMutation(() async {
      final updated = _courseCatalog.setMonitored(courseKey, monitored);
      await _storage.saveCourseCatalog(updated);
      if (_disposed) {
        return;
      }
      _courseCatalog = updated;
      _notifyListeners();
    });
  }

  Future<void> refreshCourses() async {
    _forceCourseDiscovery = true;
    _lastAcceptedRefreshAt = null;
    try {
      await refresh();
    } finally {
      _forceCourseDiscovery = false;
    }
  }

  Future<bool> sendTestNotification(bool showDetails) {
    return _reminderService.sendTestNotification(showDetails: showDetails);
  }

  Future<void> refresh({bool silent = false}) async {
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      if (_activeRefreshRevision != _configRevision) {
        _refreshQueued = true;
        _queuedRefreshIsSilent = _queuedRefreshIsSilent && silent;
      }
      return inFlight;
    }

    final rateLimitRemaining = _rateLimitBackoffRemaining();
    if (rateLimitRemaining != null) {
      if (!silent) {
        _error = '检测到请求限流，请 ${rateLimitRemaining.inSeconds} 秒后再刷新';
        _notifyListeners();
      }
      return;
    }
    if (!silent) {
      final remaining = _manualRefreshCooldownRemaining();
      if (remaining != null) {
        _error = '刚刚完成同步，请 ${remaining.inSeconds} 秒后再刷新';
        _notifyListeners();
        return;
      }
    }

    final future = _drainRefreshes(silent: silent);
    _refreshInFlight = future;
    try {
      await future;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<void> _drainRefreshes({required bool silent}) async {
    if (!_config.isConfigured) {
      _error = '请先填写学习通 Cookie';
      _notifyListeners();
      return;
    }

    _refreshing = true;
    try {
      var nextIsSilent = silent;
      do {
        _refreshQueued = false;
        _queuedRefreshIsSilent = true;
        final revision = _configRevision;
        final config = _config;
        _activeRefreshRevision = revision;
        _syncProgress = const SyncProgress(
          phase: SyncPhase.authentication,
          total: 1,
        );
        if (!nextIsSilent) {
          _error = null;
        }
        _notifyListeners();

        try {
          final response = await _fetcher(config, previous: _sync);
          final accepted = await _commitRefreshResponse(response, revision);
          if (accepted && revision == _configRevision) {
            await _processReminders(response, config);
          }
        } catch (error) {
          if (!_disposed && revision == _configRevision) {
            _error = _safeErrorMessage(error, config.cookie);
          }
        }

        if (!_disposed && revision != _configRevision) {
          _refreshQueued = true;
        }
        nextIsSilent = _queuedRefreshIsSilent;
      } while (_refreshQueued && !_disposed && _config.isConfigured);
    } finally {
      _activeRefreshRevision = null;
      _refreshing = false;
      _syncProgress = null;
      _notifyListeners();
    }
  }

  Future<void> _processReminders(
    AppSyncResponse response,
    AppConfig config,
  ) async {
    if (!config.remindersEnabled) {
      return;
    }
    final history = await _storage.loadReminderHistory();
    final nextHistory = await _reminderService.process(
      items: response.items,
      history: history,
      now: _clock(),
      showDetails: config.showNotificationDetails,
    );
    if (!mapEquals(history.sent, nextHistory.sent)) {
      await _storage.saveReminderHistory(nextHistory);
    }
  }

  void _scheduleAutoRefresh() {
    _refreshTimer?.cancel();
    if (!_config.isConfigured || _config.refreshMinutes <= 0) {
      return;
    }
    _refreshTimer = Timer.periodic(Duration(minutes: _config.refreshMinutes), (
      _,
    ) {
      unawaited(refresh(silent: true));
    });
  }

  bool _hasFreshCachedSync() {
    final lastSyncedAt = _sync?.lastSyncedAt;
    if (lastSyncedAt == null) {
      return false;
    }
    final age = _clock().difference(lastSyncedAt);
    return !age.isNegative && age <= _startupCacheFreshness;
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _refreshTimer?.cancel();
    _closeActiveLocalRunners();
    super.dispose();
  }

  void _notifyListeners() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  void _handleSyncProgress(SyncProgress progress) {
    if (_disposed || !_refreshing) {
      return;
    }
    _syncProgress = progress;
    _notifyListeners();
  }

  Future<void> _saveDiscoveredCourseCatalog(CourseCatalog catalog) async {
    await _storage.saveCourseCatalog(catalog);
    if (_disposed) {
      return;
    }
    _courseCatalog = catalog;
    _notifyListeners();
  }

  void _applyConfig(AppConfig config, {bool scheduleRefresh = true}) {
    _config = config;
    _configRevision += 1;
    _error = null;
    if (scheduleRefresh) {
      _scheduleAutoRefresh();
    }
    _notifyListeners();
  }

  Future<bool> _commitRefreshResponse(AppSyncResponse response, int revision) {
    return _serializeStorageMutation(() async {
      if (_disposed || revision != _configRevision) {
        return false;
      }
      _sync = response;
      _error = null;
      await _storage.saveCachedSync(response);
      _lastAcceptedRefreshAt = _clock();
      _rateLimitBackoffUntil = response.rateLimited
          ? _clock().add(_rateLimitBackoff)
          : null;
      return !_disposed && revision == _configRevision;
    });
  }

  Future<T> _serializeStorageMutation<T>(Future<T> Function() action) {
    final result = Completer<T>();
    _configMutationTail = _configMutationTail.catchError((_) {}).then((
      _,
    ) async {
      try {
        result.complete(await action());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  Future<T> _withLocalRunner<T>(
    Future<T> Function(LocalSyncRunner runner) action,
  ) async {
    final runner = _runnerFactory();
    _activeLocalRunners.add(runner);
    try {
      return await action(runner);
    } finally {
      if (_activeLocalRunners.remove(runner)) {
        runner.close();
      }
    }
  }

  void _closeActiveLocalRunners() {
    for (final runner in _activeLocalRunners.toList()) {
      runner.close();
    }
    _activeLocalRunners.clear();
  }

  String _safeErrorMessage(Object error, String cookie) {
    final message = error is LocalSyncException
        ? error.message
        : error.toString();
    return redactSensitiveText(message, secrets: chaoxingCookieSecrets(cookie));
  }

  void _validateCookieSource(String cookie) {
    if (!isSafeChaoxingCookieSource(cookie)) {
      throw const LocalSyncException('Cookie 格式不安全或无有效字段，请重新登录或检查手动输入');
    }
  }

  Duration? _manualRefreshCooldownRemaining() {
    final lastRefresh = _lastAcceptedRefreshAt;
    if (lastRefresh == null) {
      return null;
    }
    final elapsed = _clock().difference(lastRefresh);
    if (elapsed.isNegative || elapsed >= _manualRefreshCooldown) {
      return null;
    }
    final remainingMs =
        _manualRefreshCooldown.inMilliseconds - elapsed.inMilliseconds;
    return Duration(seconds: (remainingMs / 1000).ceil());
  }

  Duration? _rateLimitBackoffRemaining() {
    final until = _rateLimitBackoffUntil;
    if (until == null) {
      return null;
    }
    final remaining = until.difference(_clock());
    if (remaining <= Duration.zero) {
      _rateLimitBackoffUntil = null;
      return null;
    }
    return Duration(seconds: (remaining.inMilliseconds / 1000).ceil());
  }

  void _restoreRefreshGuardsFromCache(AppSyncResponse? cached) {
    _lastAcceptedRefreshAt = null;
    _rateLimitBackoffUntil = null;
    final syncedAt = cached?.lastSyncedAt;
    if (syncedAt == null) {
      return;
    }
    final age = _clock().difference(syncedAt);
    if (age.isNegative) {
      return;
    }
    if (age < _manualRefreshCooldown) {
      _lastAcceptedRefreshAt = syncedAt;
    }
    if (cached!.rateLimited && age < _rateLimitBackoff) {
      _rateLimitBackoffUntil = syncedAt.add(_rateLimitBackoff);
    }
  }
}
