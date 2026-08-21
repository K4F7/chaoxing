import 'dart:convert';

import '../models/app_sync_response.dart';
import '../utils/redaction.dart';
import 'chaoxing_cookie_store.dart';

String buildDiagnosticsReport({
  required String? cookieHeader,
  required AppSyncResponse? sync,
  required String? lastError,
  DateTime Function()? clock,
}) {
  final generatedAt = (clock ?? DateTime.now)();
  final secrets = cookieHeader == null
      ? const <String>[]
      : chaoxingCookieSecrets(cookieHeader).toList();
  final failures = sync?.failures.map((failure) {
    return {
      'entryUrl': redactSensitiveUrl(failure.entryUrl),
      'sourceTitle': redactSensitiveText(failure.sourceTitle, secrets: secrets),
      'message': redactSensitiveText(failure.message, secrets: secrets),
    };
  }).toList();

  return const JsonEncoder.withIndent('  ').convert({
    'generatedAt': generatedAt.toIso8601String(),
    'hasCookie': cookieHeader?.trim().isNotEmpty ?? false,
    'authStatus': sync?.authStatus ?? 'unknown',
    'lastSyncedAt': sync?.lastSyncedAt?.toIso8601String(),
    'itemCount': sync?.items.length ?? 0,
    'stats': sync?.stats.toJson() ?? const SyncStats().toJson(),
    'failureCount': sync?.failures.length ?? 0,
    'failures': failures ?? const [],
    'lastError': lastError == null
        ? null
        : redactSensitiveText(lastError, secrets: secrets),
  });
}
