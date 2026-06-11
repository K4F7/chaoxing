import 'sync_item.dart';

class AppSyncResponse {
  const AppSyncResponse({
    required this.lastSyncedAt,
    required this.authStatus,
    required this.items,
    required this.failures,
  });

  final DateTime? lastSyncedAt;
  final String authStatus;
  final List<SyncItem> items;
  final List<AppSyncFailure> failures;

  factory AppSyncResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final rawFailures = json['failures'];
    return AppSyncResponse(
      lastSyncedAt: SyncItem.parseDate(json['lastSyncedAt']),
      authStatus: json.readString('authStatus'),
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map((item) => SyncItem.fromJson(item.cast<String, dynamic>()))
                .toList()
          : const [],
      failures: rawFailures is List
          ? rawFailures
                .whereType<Map>()
                .map(
                  (failure) =>
                      AppSyncFailure.fromJson(failure.cast<String, dynamic>()),
                )
                .toList()
          : const [],
    );
  }

  factory AppSyncResponse.build({
    required DateTime now,
    required DateTime lastSyncedAt,
    required List<SyncItem> items,
    required List<AppSyncFailure> failures,
    String authStatus = 'ok',
  }) {
    final enriched = items.map((item) => _buildAppSyncItem(item, now)).toList()
      ..sort(_compareAppSyncItems);
    return AppSyncResponse(
      lastSyncedAt: lastSyncedAt,
      authStatus: authStatus,
      items: enriched,
      failures: failures,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'authStatus': authStatus,
      'items': items.map((item) => item.toJson()).toList(),
      'failures': failures.map((failure) => failure.toJson()).toList(),
    };
  }
}

SyncItem _buildAppSyncItem(SyncItem item, DateTime now) {
  final dueAt = item.dueAt;
  final dueInHours = dueAt == null
      ? null
      : ((dueAt.millisecondsSinceEpoch - now.millisecondsSinceEpoch) /
                Duration.millisecondsPerHour)
            .round();

  return item.copyWith(
    displayStatus: dueAt == null
        ? SyncDisplayStatus.unscheduled
        : _classifyDueDate(dueAt, now),
    dueInHours: dueInHours,
  );
}

int _compareAppSyncItems(SyncItem left, SyncItem right) {
  if (left.dueAt == null && right.dueAt == null) {
    return left.title.compareTo(right.title);
  }
  if (left.dueAt == null) {
    return 1;
  }
  if (right.dueAt == null) {
    return -1;
  }
  return left.dueAt!.compareTo(right.dueAt!);
}

SyncDisplayStatus _classifyDueDate(DateTime dueAt, DateTime now) {
  if (dueAt.isBefore(now)) {
    return SyncDisplayStatus.overdue;
  }

  return _localDateKey(dueAt) == _localDateKey(now)
      ? SyncDisplayStatus.today
      : SyncDisplayStatus.upcoming;
}

String _localDateKey(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

class AppSyncFailure {
  const AppSyncFailure({
    required this.entryUrl,
    required this.sourceTitle,
    required this.message,
  });

  final String entryUrl;
  final String sourceTitle;
  final String message;

  factory AppSyncFailure.fromJson(Map<String, dynamic> json) {
    return AppSyncFailure(
      entryUrl: json.readString('entryUrl'),
      sourceTitle: json.readString('sourceTitle'),
      message: json.readString('message'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'entryUrl': entryUrl,
      'sourceTitle': sourceTitle,
      'message': message,
    };
  }
}
