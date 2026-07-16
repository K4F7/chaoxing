const _redacted = '[已隐藏]';

const _sensitiveQueryKeys = {
  'access_token',
  'account',
  'accountid',
  'auth',
  'authorization',
  'cookie',
  'enc',
  'id_token',
  'key',
  'puid',
  'refresh_token',
  'session',
  'sessionid',
  'sid',
  'token',
  'uid',
  'user_id',
  'userid',
};

const _sensitiveCookieNames = {
  '_uid',
  'fid',
  'jsessionid',
  'route',
  'uid',
  'vc',
};

String redactSensitiveUrl(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null || (uri.host.isEmpty && uri.query.isEmpty)) {
    return _redactStructuredText(value);
  }

  final redactedQuery = <String, List<String>>{};
  for (final entry in uri.queryParametersAll.entries) {
    redactedQuery[entry.key] = _isSensitiveKey(entry.key)
        ? const [_redacted]
        : entry.value;
  }
  final sanitized = uri.replace(
    userInfo: uri.userInfo.isEmpty ? null : _redacted,
    queryParameters: redactedQuery.isEmpty ? null : redactedQuery,
    fragment: uri.fragment.isEmpty ? null : _redacted,
  );
  return sanitized.toString();
}

String redactSensitiveText(
  String value, {
  Iterable<String> secrets = const [],
}) {
  var result = value;
  for (final secret in secrets) {
    final trimmed = secret.trim();
    if (trimmed.isEmpty) {
      continue;
    }
    result = result.replaceAll(trimmed, _redacted);
    final encoded = Uri.encodeComponent(trimmed);
    if (encoded != trimmed) {
      result = result.replaceAll(encoded, _redacted);
    }
  }

  result = result.replaceAllMapped(
    RegExp(r'''https?:\/\/[^\s"'<>]+''', caseSensitive: false),
    (match) => redactSensitiveUrl(match.group(0)!),
  );
  return _redactStructuredText(result);
}

String _redactStructuredText(String value) {
  var result = value;
  result = result.replaceAllMapped(
    RegExp(
      r'\b(?:Cookie|Set-Cookie|Authorization)\s*[:=]\s*[^\r\n]+',
      caseSensitive: false,
    ),
    (match) => '${match.group(0)!.split(RegExp(r'[:=]')).first}: $_redacted',
  );
  result = result.replaceAll(
    RegExp(r'\bBearer\s+[^\s,;]+', caseSensitive: false),
    'Bearer $_redacted',
  );
  result = result.replaceAllMapped(
    RegExp(
      r'\b([a-zA-Z_][a-zA-Z0-9_-]*)\s*([:=])\s*([^\s&,;]+)',
      caseSensitive: false,
    ),
    (match) {
      final key = match.group(1)!;
      if (!_isSensitiveKey(key) &&
          !_sensitiveCookieNames.contains(key.toLowerCase())) {
        return match.group(0)!;
      }
      return '$key${match.group(2)}$_redacted';
    },
  );
  return result;
}

bool _isSensitiveKey(String key) {
  final normalized = key.toLowerCase().replaceAll('-', '_');
  return _sensitiveQueryKeys.contains(normalized) ||
      normalized.endsWith('_token') ||
      normalized.endsWith('_secret');
}
