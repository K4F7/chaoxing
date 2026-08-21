import { SyncItemKind, type SyncItem } from "../src/index";

export function assignmentItem(input: {
  dueAt: Date | null;
  id?: string;
}): SyncItem {
  return {
    id: input.id ?? "assignment-1",
    kind: SyncItemKind.assignment,
    title: "作业",
    url: "https://mooc1.chaoxing.com/work",
    sourceTitle: "作业通知",
    dueAt: input.dueAt,
  };
}
