import 'dart:convert';
import 'dart:io';

import 'chaoxing_url_policy.dart';

const _cookieStoreFormat = 'chaoxing-cookie-store-v1';
const _identityCookieNames = {
  '_uid',
  'UID',
  'vc3',
  'uf',
  'p_auth_token',
  'cx_p_token',
  'xxtenc',
};

class ChaoxingCookieRecord {
  const ChaoxingCookieRecord({
    required this.name,
    required this.value,
    required this.domain,
    this.path = '/',
    this.secure = true,
    this.hostOnly = false,
  });

  final String name;
  final String value;
  final String domain;
  final String path;
  final bool secure;
  final bool hostOnly;

  Map<String, dynamic> toJson() => {
    'name': name,
    'value': value,
    'domain': domain,
    'path': path,
    'secure': secure,
    'hostOnly': hostOnly,
  };

  factory ChaoxingCookieRecord.fromJson(Map<String, dynamic> json) {
    return ChaoxingCookieRecord(
      name: json['name'] is String ? json['name'] as String : '',
      value: json['value'] is String ? json['value'] as String : '',
      domain: json['domain'] is String ? json['domain'] as String : '',
      path: json['path'] is String ? json['path'] as String : '/',
      secure: json['secure'] != false,
      hostOnly: json['hostOnly'] == true,
    );
  }
}

String encodeChaoxingCookieStore(Iterable<ChaoxingCookieRecord> cookies) {
  return jsonEncode({
    'format': _cookieStoreFormat,
    'cookies': cookies.map((cookie) => cookie.toJson()).toList(),
  });
}

List<ChaoxingCookieRecord>? decodeChaoxingCookieStore(String source) {
  final trimmed = source.trim();
  if (!trimmed.startsWith('{')) {
    return null;
  }
  try {
    final decoded = jsonDecode(trimmed);
    if (decoded is! Map || decoded['format'] != _cookieStoreFormat) {
      return null;
    }
    final rawCookies = decoded['cookies'];
    if (rawCookies is! List) {
      return null;
    }
    return rawCookies
        .whereType<Map>()
        .map(
          (cookie) =>
              ChaoxingCookieRecord.fromJson(cookie.cast<String, dynamic>()),
        )
        .where(_isValidCookieRecord)
        .toList();
  } catch (_) {
    return null;
  }
}

bool hasChaoxingIdentityCookieSource(String source) {
  if (!isSafeChaoxingCookieSource(source)) {
    return false;
  }
  final structured = decodeChaoxingCookieStore(source);
  if (structured != null) {
    return structured.any(
      (cookie) => _identityCookieNames.contains(cookie.name),
    );
  }
  return _parseLegacyCookieHeader(
    source,
  ).any((cookie) => _identityCookieNames.contains(cookie.name));
}

bool isSafeChaoxingCookieSource(String source) {
  if (source.contains('\r') || source.contains('\n')) {
    return false;
  }
  final structured = decodeChaoxingCookieStore(source);
  if (structured != null) {
    return structured.isNotEmpty;
  }
  return _parseLegacyCookieHeader(source).isNotEmpty;
}

Iterable<String> chaoxingCookieSecrets(String source) sync* {
  if (source.trim().isNotEmpty) {
    yield source;
  }
  final records = decodeChaoxingCookieStore(source);
  if (records != null) {
    for (final cookie in records) {
      if (cookie.value.isNotEmpty) {
        yield cookie.value;
      }
    }
  }
}

String cookieHeaderForChaoxingUri(String source, Uri uri) {
  if (!isSafeChaoxingCookieSource(source) ||
      uri.scheme != 'https' ||
      uri.host.toLowerCase() == 'passport2.chaoxing.com') {
    return '';
  }
  final records =
      decodeChaoxingCookieStore(source) ?? _parseLegacyCookieHeader(source);
  final applicable =
      records.where((cookie) {
        if (cookie.secure && uri.scheme != 'https') {
          return false;
        }
        return _domainMatches(
              uri.host,
              cookie.domain,
              hostOnly: cookie.hostOnly,
            ) &&
            _pathMatches(uri.path, cookie.path);
      }).toList()..sort((left, right) {
        final pathOrder = right.path.length.compareTo(left.path.length);
        return pathOrder != 0 ? pathOrder : left.name.compareTo(right.name);
      });
  return applicable
      .map((cookie) => '${cookie.name}=${cookie.value}')
      .join('; ');
}

String mergeChaoxingResponseCookies(
  String source,
  Uri requestUri,
  String? setCookieHeader,
) {
  if (setCookieHeader == null || setCookieHeader.trim().isEmpty) {
    return source;
  }
  if (requestUri.host.toLowerCase() == 'passport2.chaoxing.com') {
    return source;
  }
  final records = <ChaoxingCookieRecord>[
    ...(decodeChaoxingCookieStore(source) ?? _parseLegacyCookieHeader(source)),
  ];
  for (final rawCookie in _splitSetCookieHeader(setCookieHeader)) {
    final parts = rawCookie.split(';');
    if (parts.isEmpty) {
      continue;
    }
    final separator = parts.first.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    final name = parts.first.substring(0, separator).trim();
    final value = parts.first.substring(separator + 1).trim();
    var domain = requestUri.host.toLowerCase();
    var path = _defaultCookiePath(requestUri.path);
    var secure = false;
    var hostOnly = true;
    var delete = value.isEmpty;
    DateTime? expires;
    for (final attribute in parts.skip(1)) {
      final attributeSeparator = attribute.indexOf('=');
      final attributeName =
          (attributeSeparator < 0
                  ? attribute
                  : attribute.substring(0, attributeSeparator))
              .trim()
              .toLowerCase();
      final attributeValue = attributeSeparator < 0
          ? ''
          : attribute.substring(attributeSeparator + 1).trim();
      if (attributeName == 'domain' && attributeValue.isNotEmpty) {
        domain = _normalizeDomain(attributeValue);
        hostOnly = false;
      } else if (attributeName == 'path' && attributeValue.startsWith('/')) {
        path = attributeValue;
      } else if (attributeName == 'secure') {
        secure = true;
      } else if (attributeName == 'max-age' && attributeValue == '0') {
        delete = true;
      } else if (attributeName == 'max-age') {
        final seconds = int.tryParse(attributeValue);
        if (seconds != null && seconds <= 0) {
          delete = true;
        }
      } else if (attributeName == 'expires') {
        try {
          expires = HttpDate.parse(attributeValue);
        } catch (_) {
          expires = null;
        }
      }
    }
    if (expires != null && !expires.isAfter(DateTime.now().toUtc())) {
      delete = true;
    }
    if (!_isSafeCookieName(name) ||
        !_domainMatches(requestUri.host, domain, hostOnly: hostOnly) ||
        !isTrustedChaoxingCookieDomain(domain)) {
      continue;
    }
    records.removeWhere(
      (cookie) =>
          cookie.name == name &&
          _normalizeDomain(cookie.domain) == domain &&
          cookie.path == path &&
          cookie.hostOnly == hostOnly,
    );
    if (!delete && _isSafeCookieValue(value)) {
      records.add(
        ChaoxingCookieRecord(
          name: name,
          value: value,
          domain: domain,
          path: path,
          secure: secure,
          hostOnly: hostOnly,
        ),
      );
    }
  }
  return encodeChaoxingCookieStore(records.where(_isValidCookieRecord));
}

List<ChaoxingCookieRecord> _parseLegacyCookieHeader(String header) {
  final records = <ChaoxingCookieRecord>[];
  for (final part in header.split(';')) {
    final separator = part.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    final name = part.substring(0, separator).trim();
    final value = part.substring(separator + 1).trim();
    if (_isSafeCookieName(name) && _isSafeCookieValue(value)) {
      records.add(
        ChaoxingCookieRecord(name: name, value: value, domain: 'chaoxing.com'),
      );
    }
  }
  return records;
}

List<String> _splitSetCookieHeader(String header) {
  final starts = RegExp(
    r'''(?:^|,\s*)([!#$%&'*+\-.^_`|~0-9A-Za-z]+)=''',
  ).allMatches(header).toList();
  if (starts.isEmpty) {
    return const [];
  }
  final cookies = <String>[];
  for (var index = 0; index < starts.length; index += 1) {
    final start =
        starts[index].start + (header[starts[index].start] == ',' ? 1 : 0);
    final end = index + 1 < starts.length
        ? starts[index + 1].start
        : header.length;
    cookies.add(
      header.substring(start, end).trim().replaceFirst(RegExp(r',$'), ''),
    );
  }
  return cookies;
}

bool _isValidCookieRecord(ChaoxingCookieRecord cookie) {
  return _isSafeCookieName(cookie.name) &&
      _isSafeCookieValue(cookie.value) &&
      isTrustedChaoxingCookieDomain(cookie.domain) &&
      cookie.path.startsWith('/');
}

bool _isSafeCookieName(String name) =>
    RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$").hasMatch(name);

bool _isSafeCookieValue(String value) =>
    value.isNotEmpty &&
    !value.contains(';') &&
    !value.contains('\r') &&
    !value.contains('\n');

String _normalizeDomain(String domain) => normalizeChaoxingDomain(domain);

bool _domainMatches(String host, String domain, {required bool hostOnly}) {
  final normalizedHost = host.toLowerCase();
  final normalizedDomain = _normalizeDomain(domain);
  return normalizedHost == normalizedDomain ||
      (!hostOnly && normalizedHost.endsWith('.$normalizedDomain'));
}

String _defaultCookiePath(String requestPath) {
  if (!requestPath.startsWith('/') || requestPath == '/') {
    return '/';
  }
  final lastSlash = requestPath.lastIndexOf('/');
  return lastSlash <= 0 ? '/' : requestPath.substring(0, lastSlash);
}

bool _pathMatches(String requestPath, String cookiePath) {
  final normalizedPath = cookiePath.isEmpty ? '/' : cookiePath;
  if (requestPath == normalizedPath) {
    return true;
  }
  if (!requestPath.startsWith(normalizedPath)) {
    return false;
  }
  return normalizedPath.endsWith('/') ||
      requestPath.substring(normalizedPath.length).startsWith('/');
}
