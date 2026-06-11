import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_config.dart';
import '../models/app_sync_response.dart';
import '../models/sync_item.dart';
import '../services/app_storage.dart';
import '../services/local_sync_runner.dart';
import '../services/reminder_service.dart';

typedef SyncFetcher = Future<AppSyncResponse> Function(AppConfig config);

class AppController extends ChangeNotifier {
  AppController(
    this._storage, {
    SyncFetcher? fetcher,
    this._reminderService = const LocalReminderService(),
  }) : _fetcher = fetcher ?? LocalSyncRunner().run,
       super();

  final AppStorage _storage;
  final SyncFetcher _fetcher;
  final LocalReminderService _reminderService;
  Timer? _refreshTimer;
  Future<void>? _refreshInFlight;

  AppConfig _config = AppConfig.empty;
  AppSyncResponse? _sync;
  bool _loading = true;
  bool _refreshing = false;
  String? _error;

  AppConfig get config => _config;

  AppSyncResponse? get sync => _sync;

  bool get loading => _loading;

  bool get refreshing => _refreshing;

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

  List<SyncItem> get dueSoonItems =>
      items.where((item) => item.isDueSoon).toList();

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    _config = await _storage.loadConfig();
    _sync = await _storage.loadCachedSync();
    _loading = false;
    notifyListeners();

    if (_config.isConfigured) {
      _scheduleAutoRefresh();
      await refresh(silent: _sync != null);
    }
  }

  Future<void> saveConfig(AppConfig config) async {
    _config = config;
    _error = null;
    await _storage.saveConfig(config);
    _scheduleAutoRefresh();
    notifyListeners();
    if (config.isConfigured) {
      await refresh();
    }
  }

  Future<void> refresh({bool silent = false}) async {
    final inFlight = _refreshInFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final future = _refresh(silent: silent);
    _refreshInFlight = future;
    try {
      await future;
    } finally {
      _refreshInFlight = null;
    }
  }

  Future<void> _refresh({required bool silent}) async {
    if (!_config.isConfigured) {
      _error = '请先填写学习通 Cookie';
      notifyListeners();
      return;
    }

    _refreshing = true;
    if (!silent) {
      _error = null;
    }
    notifyListeners();

    try {
      final response = await _fetcher(_config);
      _sync = response;
      _error = null;
      await _storage.saveCachedSync(response);
      await _processReminders(response);
    } catch (error) {
      _error = _safeErrorMessage(error);
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }

  Future<void> _processReminders(AppSyncResponse response) async {
    if (!_config.remindersEnabled) {
      return;
    }
    final history = await _storage.loadReminderHistory();
    final nextHistory = await _reminderService.process(
      items: response.items,
      history: history,
      now: DateTime.now(),
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

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  String _safeErrorMessage(Object error) {
    var message = error is LocalSyncException
        ? error.message
        : error.toString();
    final cookie = _config.cookie.trim();
    if (cookie.isNotEmpty) {
      message = message.replaceAll(cookie, '[已隐藏]');
    }
    return message.replaceAllMapped(
      RegExp(r'(Cookie\s*[:=]\s*)[^\r\n,;]+', caseSensitive: false),
      (match) => '${match.group(1)}[已隐藏]',
    );
  }
}
