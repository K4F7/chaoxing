import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter_windows/webview_flutter_windows.dart';

import '../services/chaoxing_cookie_store.dart';
import '../services/chaoxing_url_policy.dart';
import '../services/local_sync_runner.dart' show LocalSyncException;

const chaoxingLoginUrl =
    'https://passport2.chaoxing.com/login?fid=&refer=https%3A%2F%2Fi.chaoxing.com';

typedef LoginCookieSaver = Future<void> Function(String cookieHeader);

abstract class WindowsLoginBackend {
  Future<void> initialize();

  Widget buildView();

  Future<String> captureCookieHeader();

  Future<void> dispose();
}

class WebviewWindowsLoginBackend implements WindowsLoginBackend {
  WebviewWindowsLoginBackend({WebviewController? controller})
    : _controller = controller ?? WebviewController();

  final WebviewController _controller;
  StreamSubscription<String>? _urlSubscription;
  bool _disposed = false;

  @override
  Future<void> initialize() async {
    final runtimeVersion = await WebviewController.getWebViewVersion();
    if (runtimeVersion == null) {
      throw StateError('未检测到 Microsoft Edge WebView2 Runtime');
    }
    await _controller.initialize();
    if (_disposed) {
      return;
    }
    await _controller.setPopupWindowPolicy(WebviewPopupWindowPolicy.deny);
    _urlSubscription = _controller.url.listen((url) {
      final uri = Uri.tryParse(url);
      if (uri == null || uri.scheme == 'about') {
        return;
      }
      if (!isTrustedChaoxingUrl(url)) {
        unawaited(_returnToTrustedLogin());
      }
    });
    await _controller.loadUrl(chaoxingLoginUrl);
  }

  Future<void> _returnToTrustedLogin() async {
    if (_disposed) {
      return;
    }
    await _controller.stop();
    if (!_disposed) {
      await _controller.loadUrl(chaoxingLoginUrl);
    }
  }

  @override
  Widget buildView() => Webview(
    _controller,
    permissionRequested: (_, _, _) => WebviewPermissionDecision.deny,
  );

  @override
  Future<String> captureCookieHeader() async {
    final cookies = await _controller.getCookies();
    final cookieStore = buildChaoxingCookieStore(cookies);
    return hasChaoxingIdentityCookie(cookieStore) ? cookieStore : '';
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    await _urlSubscription?.cancel();
    await _controller.dispose();
  }
}

String buildChaoxingCookieStore(List<WebviewCookie> cookies) {
  final records = <ChaoxingCookieRecord>[];
  for (final cookie in cookies) {
    final domain = cookie.domain.toLowerCase().replaceFirst(RegExp(r'^\.'), '');
    final safeName = RegExp(
      r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$",
    ).hasMatch(cookie.name);
    final safeValue =
        cookie.value.isNotEmpty &&
        !cookie.value.contains(';') &&
        !cookie.value.contains('\r') &&
        !cookie.value.contains('\n');
    if (!isTrustedChaoxingCookieDomain(domain) || !safeName || !safeValue) {
      continue;
    }
    records.add(
      ChaoxingCookieRecord(
        name: cookie.name,
        value: cookie.value,
        domain: domain,
        path: cookie.path.isEmpty ? '/' : cookie.path,
        secure: cookie.isSecure,
        hostOnly: !cookie.domain.startsWith('.'),
      ),
    );
  }
  return encodeChaoxingCookieStore(records);
}

String buildChaoxingCookieHeader(List<WebviewCookie> cookies) {
  final safeCookies =
      cookies.where((cookie) {
        final domain = cookie.domain.toLowerCase().replaceFirst(
          RegExp(r'^\.'),
          '',
        );
        final trustedDomain = isTrustedChaoxingCookieDomain(domain);
        final safeName = RegExp(
          r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$",
        ).hasMatch(cookie.name);
        final safeValue =
            cookie.value.isNotEmpty &&
            !cookie.value.contains(';') &&
            !cookie.value.contains('\r') &&
            !cookie.value.contains('\n');
        return trustedDomain && safeName && safeValue;
      }).toList()..sort((left, right) {
        final leftDomain = left.domain.toLowerCase().replaceFirst(
          RegExp(r'^\.'),
          '',
        );
        final rightDomain = right.domain.toLowerCase().replaceFirst(
          RegExp(r'^\.'),
          '',
        );
        final domainOrder = (leftDomain == 'chaoxing.com' ? 0 : 1).compareTo(
          rightDomain == 'chaoxing.com' ? 0 : 1,
        );
        if (domainOrder != 0) {
          return domainOrder;
        }
        final pathOrder = right.path.length.compareTo(left.path.length);
        return pathOrder != 0 ? pathOrder : left.name.compareTo(right.name);
      });
  final byName = <String, WebviewCookie>{};
  for (final cookie in safeCookies) {
    byName.putIfAbsent(cookie.name, () => cookie);
  }
  return byName.values
      .map((cookie) => '${cookie.name}=${cookie.value}')
      .join('; ');
}

bool hasChaoxingIdentityCookie(String cookieHeader) {
  return hasChaoxingIdentityCookieSource(cookieHeader);
}

class WindowsLoginScreen extends StatefulWidget {
  const WindowsLoginScreen({
    required this.onCookieCaptured,
    this.backend,
    super.key,
  });

  final LoginCookieSaver onCookieCaptured;
  final WindowsLoginBackend? backend;

  @override
  State<WindowsLoginScreen> createState() => _WindowsLoginScreenState();
}

class _WindowsLoginScreenState extends State<WindowsLoginScreen> {
  late final WindowsLoginBackend _backend;
  bool _ready = false;
  bool _capturing = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _backend = widget.backend ?? WebviewWindowsLoginBackend();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    try {
      await _backend.initialize();
      if (mounted) {
        setState(() => _ready = true);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = '登录窗口初始化失败，请确认已安装 Microsoft Edge WebView2 Runtime。',
        );
      }
    }
  }

  Future<void> _finishLogin() async {
    if (_capturing || !_ready) {
      return;
    }
    setState(() {
      _capturing = true;
      _error = null;
    });
    try {
      final cookieHeader = await _backend.captureCookieHeader();
      if (cookieHeader.isEmpty) {
        throw StateError('尚未读取到有效登录态，请完成登录后再试。');
      }
      try {
        await widget.onCookieCaptured(cookieHeader);
      } on LocalSyncException catch (error) {
        throw StateError(error.message);
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _capturing = false;
          _error = error is StateError ? error.message : '尚未读取到有效登录态，请完成登录后再试。';
        });
      }
    }
  }

  @override
  void dispose() {
    unawaited(_backend.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('登录学习通'),
        actions: [
          TextButton.icon(
            onPressed: _ready && !_capturing ? _finishLogin : null,
            icon: _capturing
                ? const SizedBox.square(
                    dimension: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check),
            label: Text(_capturing ? '正在验证' : '完成登录'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          MaterialBanner(
            content: Text(_error ?? '请在下方登录。成功进入学习通后，点击右上角“完成登录”。'),
            leading: Icon(
              _error == null ? Icons.security_outlined : Icons.error_outline,
            ),
            actions: const [SizedBox.shrink()],
          ),
          Expanded(
            child: _error != null && !_ready
                ? const Center(child: Icon(Icons.web_asset_off, size: 56))
                : _ready
                ? _backend.buildView()
                : const Center(child: CircularProgressIndicator()),
          ),
        ],
      ),
    );
  }
}
