import type { ProcessingResult } from "./processor";
import type { SyncItem } from "./sync";

export type AppSyncItem = SyncItem & {
  displayStatus: "overdue" | "today" | "upcoming" | "unscheduled";
  dueInHours: number | null;
};

export type AppSyncResponse = {
  lastSyncedAt: string;
  authStatus: "ok";
  items: AppSyncItem[];
  failures: ProcessingResult["failedRequirements"];
  meta: {
    inbox: ProcessingResult["inbox"];
    fetchedRequirements: number;
    totalUniqueActivityLinks: number;
    totalUniqueWorkLinks: number;
  };
};

export function buildAppSyncResponse(
  result: ProcessingResult,
  items: SyncItem[],
  options: { now?: Date } = {},
): AppSyncResponse {
  const now = options.now || new Date();
  return {
    lastSyncedAt: result.processedAt,
    authStatus: "ok",
    items: items
      .map((item) => buildAppSyncItem(item, now))
      .sort(compareAppSyncItems),
    failures: result.failedRequirements,
    meta: {
      inbox: result.inbox,
      fetchedRequirements: result.fetchedRequirements,
      totalUniqueActivityLinks: result.totalUniqueActivityLinks,
      totalUniqueWorkLinks: result.totalUniqueWorkLinks,
    },
  };
}

function buildAppSyncItem(item: SyncItem, now: Date): AppSyncItem {
  const dueAt = item.dueAt ? new Date(item.dueAt) : null;
  const dueInHours =
    dueAt && Number.isFinite(dueAt.getTime())
      ? Math.round((dueAt.getTime() - now.getTime()) / (60 * 60 * 1000))
      : null;

  return {
    ...item,
    displayStatus: dueAt ? classifyDueDate(dueAt, now) : "unscheduled",
    dueInHours,
  };
}

function compareAppSyncItems(left: AppSyncItem, right: AppSyncItem): number {
  if (!left.dueAt && !right.dueAt) {
    return left.title.localeCompare(right.title, "zh-Hans-CN");
  }
  if (!left.dueAt) {
    return 1;
  }
  if (!right.dueAt) {
    return -1;
  }
  return new Date(left.dueAt).getTime() - new Date(right.dueAt).getTime();
}

function classifyDueDate(
  dueAt: Date,
  now: Date,
): AppSyncItem["displayStatus"] {
  if (dueAt.getTime() < now.getTime()) {
    return "overdue";
  }

  const localDue = toLocalDateKey(dueAt);
  const localNow = toLocalDateKey(now);
  return localDue === localNow ? "today" : "upcoming";
}

function toLocalDateKey(date: Date): string {
  return [
    date.getFullYear(),
    String(date.getMonth() + 1).padStart(2, "0"),
    String(date.getDate()).padStart(2, "0"),
  ].join("-");
}
