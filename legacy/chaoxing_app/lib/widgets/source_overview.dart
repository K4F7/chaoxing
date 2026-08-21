import 'package:flutter/material.dart';

import '../models/sync_item.dart';
import 'sync_item_card.dart';

class SourceOverview extends StatelessWidget {
  const SourceOverview({
    required this.items,
    required this.onItemTap,
    super.key,
  });

  final List<SyncItem> items;
  final ValueChanged<SyncItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(Icons.account_tree_outlined, size: 40),
              SizedBox(height: 12),
              Text('暂无来源数据'),
              SizedBox(height: 8),
              Text('同步到作业或考试后，可在这里按课程或通知来源查看。'),
            ],
          ),
        ),
      );
    }

    final groups = _groupItems(items);
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '${groups.length} 个来源 · ${items.length} 项待办',
            key: const Key('source-overview-summary'),
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        const SizedBox(height: 8),
        ...groups.map(
          (group) => Card(
            key: Key('source-group-${group.title}'),
            clipBehavior: Clip.antiAlias,
            child: ExpansionTile(
              initiallyExpanded: groups.length == 1,
              leading: const Icon(Icons.school_outlined),
              title: Text(
                group.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${group.assignmentCount} 个作业 · ${group.examCount} 个考试',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: group.items
                  .map(
                    (item) =>
                        SyncItemCard(item: item, onTap: () => onItemTap(item)),
                  )
                  .toList(),
            ),
          ),
        ),
      ],
    );
  }
}

List<_SourceGroup> _groupItems(List<SyncItem> items) {
  final grouped = <String, List<SyncItem>>{};
  for (final item in items) {
    final title = item.sourceTitle.trim().isEmpty
        ? '未识别来源'
        : item.sourceTitle.trim();
    grouped.putIfAbsent(title, () => []).add(item);
  }

  final groups = grouped.entries.map((entry) {
    final groupItems = [...entry.value]..sort(_compareItems);
    return _SourceGroup(title: entry.key, items: groupItems);
  }).toList();
  groups.sort((left, right) {
    final dueComparison = _compareNullableDates(left.nextDue, right.nextDue);
    return dueComparison != 0
        ? dueComparison
        : left.title.compareTo(right.title);
  });
  return groups;
}

int _compareItems(SyncItem left, SyncItem right) {
  final dueComparison = _compareNullableDates(left.dueAt, right.dueAt);
  return dueComparison != 0 ? dueComparison : left.title.compareTo(right.title);
}

int _compareNullableDates(DateTime? left, DateTime? right) {
  if (left == null) return right == null ? 0 : 1;
  if (right == null) return -1;
  return left.compareTo(right);
}

class _SourceGroup {
  const _SourceGroup({required this.title, required this.items});

  final String title;
  final List<SyncItem> items;

  int get assignmentCount => items.where((item) => !item.isExam).length;
  int get examCount => items.where((item) => item.isExam).length;
  DateTime? get nextDue => items.firstOrNull?.dueAt;
}
