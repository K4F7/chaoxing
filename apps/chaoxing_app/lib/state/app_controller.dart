import 'package:flutter/foundation.dart';

import '../models/app_config.dart';
import '../models/app_sync_response.dart';
import '../models/sync_item.dart';
import '../services/app_storage.dart';
import '../services/chaoxing_api.dart';

typedef SyncFetcher = Future<AppSyncResponse> Function(AppConfig config);

class AppController extends ChangeNotifier {
  AppController(this._storage, {SyncFetcher? fetcher})
    : _fetcher = fetcher ?? ChaoxingApi().fetchAppSync;

  final AppStorage _storage;
  final SyncFetcher _fetcher;

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
      await refresh(silent: _sync != null);
    }
  }

  Future<void> saveConfig(AppConfig config) async {
    _config = config;
    _error = null;
    await _storage.saveConfig(config);
    notifyListeners();
    if (config.isConfigured) {
      await refresh();
    }
  }

  Future<void> refresh({bool silent = false}) async {
    if (!_config.isConfigured) {
      _error = '请先填写 Worker URL 和 Token';
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
    } catch (error) {
      _error = error.toString();
    } finally {
      _refreshing = false;
      notifyListeners();
    }
  }
}
