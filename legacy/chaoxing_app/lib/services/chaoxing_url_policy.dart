const trustedChaoxingRequestHosts = {
  'i.chaoxing.com',
  'notice.chaoxing.com',
  'mooc1.chaoxing.com',
  'mooc1-api.chaoxing.com',
  'mooc2-ans.chaoxing.com',
  'passport2.chaoxing.com',
};

String normalizeChaoxingDomain(String domain) =>
    domain.trim().toLowerCase().replaceFirst(RegExp(r'^\.'), '');

bool isTrustedChaoxingRequestHost(String host) {
  final normalized = normalizeChaoxingDomain(host);
  return trustedChaoxingRequestHosts.contains(normalized) ||
      RegExp(r'^mooc1-\d+\.chaoxing\.com$').hasMatch(normalized);
}

bool isTrustedChaoxingCookieDomain(String domain) {
  final normalized = normalizeChaoxingDomain(domain);
  return normalized == 'chaoxing.com' ||
      isTrustedChaoxingRequestHost(normalized);
}

bool isTrustedChaoxingUri(Uri uri) {
  return uri.scheme.toLowerCase() == 'https' &&
      isTrustedChaoxingRequestHost(uri.host);
}

bool isTrustedChaoxingUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && isTrustedChaoxingUri(uri);
}
