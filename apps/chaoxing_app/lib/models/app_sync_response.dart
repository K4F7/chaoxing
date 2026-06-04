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

  Map<String, dynamic> toJson() {
    return {
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'authStatus': authStatus,
      'items': items.map((item) => item.toJson()).toList(),
      'failures': failures.map((failure) => failure.toJson()).toList(),
    };
  }
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
