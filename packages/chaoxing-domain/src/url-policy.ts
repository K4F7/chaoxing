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

export function isTrustedChaoxingUrl(url: string): boolean {
  try {
    const parsed = new URL(url);
    return (
      parsed.protocol === "https:" && isTrustedChaoxingRequestHost(parsed.hostname)
    );
  } catch {
    return false;
  }
}
