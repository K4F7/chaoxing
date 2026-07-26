import 'package:chaoxing_app/models/app_sync_response.dart';
import 'package:chaoxing_app/services/local_diagnostics.dart';
import 'package:chaoxing_app/utils/redaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redacts URL queries, headers, cookie pairs, and explicit secrets', () {
    const cookie = 'UID=real-user; vc=cookie-secret';
    final encodedCookie = Uri.encodeComponent(cookie);
    final value = redactSensitiveText(
      'https://mooc1.chaoxing.com/work?workId=1&token=url-secret&uid=42 '
      'Authorization: Bearer bearer-secret\n'
      'Cookie: UID=real-user; vc=cookie-secret\n'
      'encoded=$encodedCookie',
      secrets: const [cookie],
    );

    expect(value, contains('workId=1'));
    expect(value, isNot(contains('url-secret')));
    expect(value, isNot(contains('bearer-secret')));
    expect(value, isNot(contains('real-user')));
    expect(value, isNot(contains('cookie-secret')));
    expect(value, isNot(contains(encodedCookie)));
  });

  test('redacts malformed URL-like text without recursive parsing', () {
    final value = redactSensitiveUrl('https://?token=url-secret&workId=1');

    expect(value, contains('workId=1'));
    expect(value, isNot(contains('url-secret')));
  });

  test('diagnostics report contains only redacted failure data', () {
    const cookie = 'UID=real-user; vc=cookie-secret';
    final report = buildDiagnosticsReport(
      cookieHeader: cookie,
      sync: AppSyncResponse(
        lastSyncedAt: DateTime(2026, 6, 8, 10),
        authStatus: 'ok',
        items: const [],
        failures: const [
          AppSyncFailure(
            entryUrl:
                'https://mooc1.chaoxing.com/work?workId=1&access_token=url-secret&puid=42',
            sourceTitle: '作业 account=student-42',
            message: 'Authorization: Bearer bearer-secret',
          ),
        ],
        stats: const SyncStats(
          durationMs: 3210,
          authenticationMs: 210,
          coursesMs: 1200,
          inboxMessages: 10,
          relevantNotices: 3,
          itemCandidates: 2,
        ),
      ),
      lastError: 'Cookie: UID=real-user; vc=cookie-secret',
      clock: () => DateTime(2026, 6, 8, 12),
    );

    expect(report, contains('"hasCookie": true'));
    expect(report, contains('"failureCount": 1'));
    expect(report, contains('"inboxMessages": 10'));
    expect(report, contains('"durationMs": 3210'));
    expect(report, contains('"authenticationMs": 210'));
    expect(report, contains('"coursesMs": 1200'));
    expect(report, contains('"itemCandidates": 2'));
    expect(report, contains('workId=1'));
    expect(report, isNot(contains('url-secret')));
    expect(report, isNot(contains('student-42')));
    expect(report, isNot(contains('bearer-secret')));
    expect(report, isNot(contains('real-user')));
    expect(report, isNot(contains('cookie-secret')));
  });
}
