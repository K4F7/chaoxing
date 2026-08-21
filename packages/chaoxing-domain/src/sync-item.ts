export const SyncItemKind = {
  assignment: "assignment",
  exam: "exam",
} as const;

export type SyncItemKind = (typeof SyncItemKind)[keyof typeof SyncItemKind];

export type SyncItem = {
  id: string;
  kind: SyncItemKind;
  title: string;
  url: string;
  sourceTitle: string;
  dueAt: Date | null;
};

export function parseSyncItemKind(value: unknown): SyncItemKind {
  return value === SyncItemKind.exam
    ? SyncItemKind.exam
    : SyncItemKind.assignment;
}

export function parseDueAt(value: unknown): Date | null {
  if (typeof value !== "string" || value.length === 0) {
    return null;
  }
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? null : parsed;
}
