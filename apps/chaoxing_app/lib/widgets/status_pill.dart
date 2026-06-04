import 'package:flutter/material.dart';

import '../models/sync_item.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({required this.item, super.key});

  final SyncItem item;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (item.displayStatus) {
      SyncDisplayStatus.overdue => ('已过期', const Color(0xFFC2410C)),
      SyncDisplayStatus.today => ('今日截止', const Color(0xFFB45309)),
      SyncDisplayStatus.upcoming => ('待完成', const Color(0xFF047857)),
      SyncDisplayStatus.unscheduled => ('未排期', const Color(0xFF64748B)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
