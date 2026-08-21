export const trustedChaoxingRequestHosts = new Set([
  "i.chaoxing.com",
  "notice.chaoxing.com",
  "mooc1.chaoxing.com",
  "mooc1-api.chaoxing.com",
  "mooc2-ans.chaoxing.com",
  "passport2.chaoxing.com",
]);

const numberedMoocHost = /^mooc1-\d+\.chaoxing\.com$/;

export function normalizeChaoxingDomain(domain: string): string {
  return domain.trim().toLowerCase().replace(/^\./, "");
}

export function isTrustedChaoxingRequestHost(host: string): boolean {
  const normalized = normalizeChaoxingDomain(host);
  return (
    trustedChaoxingRequestHosts.has(normalized) ||
    numberedMoocHost.test(normalized)
  );
}

export function isTrustedChaoxingCookieDomain(domain: string): boolean {
  const normalized = normalizeChaoxingDomain(domain);
  return normalized === "chaoxing.com" || isTrustedChaoxingRequestHost(normalized);
}

export function isTrustedChaoxingUri(url: URL): boolean {
  return url.protocol === "https:" && isTrustedChaoxingRequestHost(url.hostname);
}

export function isTrustedChaoxingUrl(url: string): boolean {
  try {
    return isTrustedChaoxingUri(new URL(url));
  } catch {
    return false;
  }
}
