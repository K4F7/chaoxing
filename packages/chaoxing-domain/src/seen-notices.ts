import { messageFromSeenNotice } from "./assignment";
import type { SeenNotice } from "./app-sync";
import {
  inboxMessageIdentity,
  isAssignmentOrExamRelated,
  type DetailSummary,
  type InboxMessage,
} from "./inbox";

export function preferParsedNotice(
  fresh: SeenNotice | undefined,
  seen: SeenNotice | undefined,
  identity: string,
): SeenNotice {
  if (fresh?.detailParsed) {
    return fresh;
  }
  if (seen?.detailParsed) {
    return seen;
  }
  return fresh ?? seen ?? emptySeenNotice(identity);
}

export function emptySeenNotice(id: string): SeenNotice {
  return {
    id,
    detailParsed: false,
    title: "",
    sendTime: null,
    content: null,
    taskLinks: [],
  };
}

export function summaryFromSeenNotice(
  notice: SeenNotice,
  overrides: { title?: string; sendTime?: string | null } = {},
): DetailSummary {
  return {
    title: overrides.title ?? notice.title,
    sendTime: overrides.sendTime ?? notice.sendTime,
    content: notice.content,
    assignmentLinks: notice.taskLinks,
  };
}

export function carriedSeenNotices(input: {
  seen: readonly SeenNotice[];
  listed: ReadonlySet<string>;
  limit: number;
  includeParsed: boolean;
}): SeenNotice[] {
  const carried: SeenNotice[] = [];
  for (const notice of input.seen) {
    if (carried.length >= input.limit) {
      break;
    }
    if (
      input.listed.has(notice.id) ||
      (!input.includeParsed && notice.detailParsed) ||
      !isAssignmentOrExamRelated(messageFromSeenNotice(notice))
    ) {
      continue;
    }
    carried.push(notice);
  }
  return carried;
}

export function mergeSeenNotices(input: {
  previous: readonly SeenNotice[];
  listed: readonly InboxMessage[];
  parsed: ReadonlyMap<string, SeenNotice>;
}): SeenNotice[] {
  const previousById = new Map(input.previous.map((notice) => [notice.id, notice]));
  const merged: SeenNotice[] = [];
  const listedIds = new Set<string>();
  for (const message of input.listed) {
    const identity = inboxMessageIdentity(message);
    if (identity.length === 0) {
      continue;
    }
    listedIds.add(identity);
    const previousNotice = previousById.get(identity);
    const listedNotice: SeenNotice = {
      id: identity,
      detailParsed: false,
      sendTag: message.sendTag,
      title: message.title,
      sendTime: message.sendTime,
      content: null,
      taskLinks: [],
    };
    merged.push(
      preferParsedNotice(
        input.parsed.get(identity),
        previousNotice?.detailParsed === true ? previousNotice : listedNotice,
        identity,
      ),
    );
  }
  merged.push(
    ...[...input.parsed.values()].filter((notice) => !listedIds.has(notice.id)),
  );
  merged.push(...input.previous);
  return merged;
}
