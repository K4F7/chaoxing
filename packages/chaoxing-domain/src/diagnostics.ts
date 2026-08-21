import { type AppSyncResponse } from "./app-sync";
import { chaoxingCookieSecrets } from "./cookie";
import { redactSensitiveText, redactSensitiveUrl } from "./redaction";

export type DiagnosticsReportInput = {
  cookieSource?: string | null;
  sync?: AppSyncResponse | null;
  lastError?: string | null;
  alarmError?: string | null;
  generatedAt?: Date;
};

export function buildDiagnosticsReport(input: DiagnosticsReportInput): string {
  const generatedAt = input.generatedAt ?? new Date();
  const cookie = input.cookieSource?.trim() ?? "";
  const secrets = chaoxingCookieSecrets(cookie);
  const sync = input.sync ?? null;
  const failures = (sync?.failures ?? []).map((failure) => ({
    entryUrl: redactSensitiveUrl(failure.entryUrl),
    sourceTitle: redactSensitiveText(failure.sourceTitle, secrets),
    message: redactSensitiveText(failure.message, secrets),
  }));

  return `${JSON.stringify(
    {
      generatedAt: generatedAt.toISOString(),
      hasCookie: cookie.length > 0,
      authStatus: sync?.authStatus ?? "unknown",
      lastSyncedAt: sync?.lastSyncedAt?.toISOString() ?? null,
      itemCount: sync?.items.length ?? 0,
      stats: sync?.stats ?? null,
      failureCount: sync?.failures.length ?? 0,
      failures,
      lastError:
        input.lastError == null
          ? null
          : redactSensitiveText(input.lastError, secrets),
      alarmError:
        input.alarmError == null
          ? null
          : redactSensitiveText(input.alarmError, secrets),
    },
    null,
    2,
  )}\n`;
}
