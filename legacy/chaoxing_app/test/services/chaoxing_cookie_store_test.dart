import 'package:chaoxing_app/services/chaoxing_cookie_store.dart';
import 'package:chaoxing_app/utils/redaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('rejects an entire cookie source containing newline injection', () {
    const injected = 'UID=1; route=ok\r\nX-Evil: injected';

    expect(isSafeChaoxingCookieSource(injected), isFalse);
    expect(hasChaoxingIdentityCookieSource(injected), isFalse);
    expect(
      cookieHeaderForChaoxingUri(
        injected,
        Uri.parse('https://i.chaoxing.com/base'),
      ),
      isEmpty,
    );
  });

  test('keeps host-only cookies on their exact response host', () {
    final store = mergeChaoxingResponseCookies(
      '',
      Uri.parse('https://i.chaoxing.com/base'),
      'host_route=i-only; Path=/,global_route=global; Domain=.chaoxing.com; Path=/',
    );

    final home = cookieHeaderForChaoxingUri(
      store,
      Uri.parse('https://i.chaoxing.com/base'),
    );
    final notice = cookieHeaderForChaoxingUri(
      store,
      Uri.parse('https://notice.chaoxing.com/pc/notice/myNotice'),
    );

    expect(home, contains('host_route=i-only'));
    expect(home, contains('global_route=global'));
    expect(notice, isNot(contains('host_route')));
    expect(notice, contains('global_route=global'));
  });

  test('uses the response request directory as the default cookie path', () {
    final store = mergeChaoxingResponseCookies(
      '',
      Uri.parse('https://mooc1.chaoxing.com/account/login'),
      'scoped=ready; HttpOnly',
    );

    expect(
      cookieHeaderForChaoxingUri(
        store,
        Uri.parse('https://mooc1.chaoxing.com/account/home'),
      ),
      contains('scoped=ready'),
    );
    expect(
      cookieHeaderForChaoxingUri(
        store,
        Uri.parse('https://mooc1.chaoxing.com/work'),
      ),
      isNot(contains('scoped')),
    );
    expect(
      cookieHeaderForChaoxingUri(
        store,
        Uri.parse('https://mooc1.chaoxing.com/accounting'),
      ),
      isNot(contains('scoped')),
    );
  });

  test('deletes expired response cookies and exposes values for redaction', () {
    final initial = encodeChaoxingCookieStore(const [
      ChaoxingCookieRecord(
        name: 'route',
        value: 'old-secret',
        domain: 'i.chaoxing.com',
        hostOnly: true,
      ),
    ]);
    final updated = mergeChaoxingResponseCookies(
      initial,
      Uri.parse('https://i.chaoxing.com/base'),
      'route=expired-secret; Expires=Thu, 01 Jan 1970 00:00:00 GMT; Path=/',
    );

    expect(
      cookieHeaderForChaoxingUri(
        updated,
        Uri.parse('https://i.chaoxing.com/base'),
      ),
      isNot(contains('route=')),
    );
    expect(chaoxingCookieSecrets(initial), contains('old-secret'));
    expect(
      redactSensitiveText(
        'request failed for old-secret',
        secrets: chaoxingCookieSecrets(initial),
      ),
      isNot(contains('old-secret')),
    );

    final maxAgeDeleted = mergeChaoxingResponseCookies(
      initial,
      Uri.parse('https://i.chaoxing.com/base'),
      'route=next-secret; Max-Age=-1; Path=/',
    );
    expect(
      cookieHeaderForChaoxingUri(
        maxAgeDeleted,
        Uri.parse('https://i.chaoxing.com/base'),
      ),
      isNot(contains('route=')),
    );
  });

  test('keeps legacy headers compatible and ignores login-host cookies', () {
    const legacy = 'UID=1; vc3=secret';
    expect(
      cookieHeaderForChaoxingUri(
        legacy,
        Uri.parse('https://notice.chaoxing.com/pc/notice/myNotice'),
      ),
      contains('UID=1'),
    );
    expect(
      cookieHeaderForChaoxingUri(
        legacy,
        Uri.parse('https://PASSPORT2.CHAOXING.COM/login'),
      ),
      isEmpty,
    );
    expect(
      mergeChaoxingResponseCookies(
        legacy,
        Uri.parse('https://passport2.chaoxing.com/login'),
        'login_route=should-not-store; Path=/',
      ),
      legacy,
    );
  });
}
