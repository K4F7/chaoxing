import 'package:chaoxing_app/screens/windows_login_screen.dart';
import 'package:chaoxing_app/services/chaoxing_cookie_store.dart';
import 'package:chaoxing_app/services/local_sync_runner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

void main() {
  test(
    'builds a safe chaoxing cookie header without exposing invalid values',
    () {
      final header = buildChaoxingCookieHeader(const [
        WebviewCookie(name: 'UID', value: '42', domain: '.chaoxing.com'),
        WebviewCookie(
          name: 'UID',
          value: 'host-specific',
          domain: 'i.chaoxing.com',
          path: '/base',
        ),
        WebviewCookie(
          name: 'vc3',
          value: 'secret=value',
          domain: '.chaoxing.com',
        ),
        WebviewCookie(name: 'route', value: 'abc', domain: 'i.chaoxing.com'),
        WebviewCookie(name: 'foreign', value: 'nope', domain: 'example.com'),
        WebviewCookie(
          name: 'bad',
          value: 'line\nbreak',
          domain: '.chaoxing.com',
        ),
      ]);

      expect(header, contains('UID=42'));
      expect(header, isNot(contains('UID=host-specific')));
      expect(header, contains('vc3=secret=value'));
      expect(header, contains('route=abc'));
      expect(header, isNot(contains('foreign')));
      expect(header, isNot(contains('line')));
    },
  );

  test('recognizes only supported chaoxing identity cookies', () {
    expect(hasChaoxingIdentityCookie('route=abc; vc3=secret'), isTrue);
    expect(hasChaoxingIdentityCookie('route=abc; theme=dark'), isFalse);
  });

  test('preserves cookie scope when exporting the WebView cookie store', () {
    final store = buildChaoxingCookieStore(const [
      WebviewCookie(name: 'UID', value: '42', domain: '.chaoxing.com'),
      WebviewCookie(name: 'i_route', value: 'i-only', domain: 'i.chaoxing.com'),
      WebviewCookie(
        name: 'notice_route',
        value: 'notice-only',
        domain: 'notice.chaoxing.com',
      ),
    ]);

    final homeHeader = cookieHeaderForChaoxingUri(
      store,
      Uri.parse('https://i.chaoxing.com/base'),
    );
    final noticeHeader = cookieHeaderForChaoxingUri(
      store,
      Uri.parse('https://notice.chaoxing.com/pc/notice/myNotice'),
    );

    expect(homeHeader, contains('UID=42'));
    expect(homeHeader, contains('i_route=i-only'));
    expect(homeHeader, isNot(contains('notice_route')));
    expect(noticeHeader, contains('UID=42'));
    expect(noticeHeader, contains('notice_route=notice-only'));
    expect(noticeHeader, isNot(contains('i_route')));
    expect(
      cookieHeaderForChaoxingUri(
        store,
        Uri.parse('https://passport2.chaoxing.com/login'),
      ),
      isEmpty,
    );
    expect(hasChaoxingIdentityCookie(store), isTrue);
  });

  testWidgets('shows auth validation failures without closing login', (
    tester,
  ) async {
    final backend = _FakeLoginBackend(cookieHeader: 'UID=invalid');

    await tester.pumpWidget(
      MaterialApp(
        home: WindowsLoginScreen(
          backend: backend,
          onCookieCaptured: (_) async =>
              throw const LocalSyncException('登录态验证失败，请在登录成功后重试。'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成登录'));
    await tester.pumpAndSettle();

    expect(find.text('登录态验证失败，请在登录成功后重试。'), findsOneWidget);
    expect(find.text('模拟登录页'), findsOneWidget);
  });

  testWidgets('captures browser cookies and returns to the caller', (
    tester,
  ) async {
    final backend = _FakeLoginBackend(cookieHeader: 'UID=42; vc3=secret');
    String? captured;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () {
                Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) => WindowsLoginScreen(
                      backend: backend,
                      onCookieCaptured: (cookie) async => captured = cookie,
                    ),
                  ),
                );
              },
              child: const Text('打开登录'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开登录'));
    await tester.pumpAndSettle();
    expect(find.text('模拟登录页'), findsOneWidget);

    await tester.tap(find.text('完成登录'));
    await tester.pumpAndSettle();

    expect(captured, 'UID=42; vc3=secret');
    expect(find.text('打开登录'), findsOneWidget);
    expect(backend.disposed, isTrue);
  });

  testWidgets('keeps the login page open when no cookie is available', (
    tester,
  ) async {
    final backend = _FakeLoginBackend(cookieHeader: '');

    await tester.pumpWidget(
      MaterialApp(
        home: WindowsLoginScreen(
          backend: backend,
          onCookieCaptured: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成登录'));
    await tester.pumpAndSettle();

    expect(find.text('尚未读取到有效登录态，请完成登录后再试。'), findsOneWidget);
  });
}

class _FakeLoginBackend implements WindowsLoginBackend {
  _FakeLoginBackend({required this.cookieHeader});

  final String cookieHeader;
  bool disposed = false;

  @override
  Widget buildView() => const Center(child: Text('模拟登录页'));

  @override
  Future<String> captureCookieHeader() async => cookieHeader;

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  @override
  Future<void> initialize() async {}
}
