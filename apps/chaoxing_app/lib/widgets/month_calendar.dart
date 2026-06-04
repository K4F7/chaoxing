import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/sync_item.dart';

class MonthCalendar extends StatefulWidget {
  const MonthCalendar({
    required this.items,
    required this.onItemTap,
    super.key,
  });

  final List<SyncItem> items;
  final ValueChanged<SyncItem> onItemTap;

  @override
  State<MonthCalendar> createState() => _MonthCalendarState();
}

class _MonthCalendarState extends State<MonthCalendar> {
  late DateTime _visibleMonth;

  @override
  void initState() {
    super.initState();
    final firstDue = _firstDueItem(widget.items);
    _visibleMonth = DateTime(
      firstDue?.dueAt?.year ?? DateTime.now().year,
      firstDue?.dueAt?.month ?? DateTime.now().month,
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = _calendarDays(_visibleMonth);
    final itemsByDay = <String, List<SyncItem>>{};
    for (final item in widget.items) {
      if (item.dueAt == null) {
        continue;
      }
      itemsByDay.putIfAbsent(_dayKey(item.dueAt!), () => []).add(item);
    }

    return Column(
      children: [
        Row(
          children: [
            IconButton(
              tooltip: '上个月',
              onPressed: () => setState(() {
                _visibleMonth = DateTime(
                  _visibleMonth.year,
                  _visibleMonth.month - 1,
                );
              }),
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Center(
                child: Text(
                  DateFormat('yyyy年M月').format(_visibleMonth),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '下个月',
              onPressed: () => setState(() {
                _visibleMonth = DateTime(
                  _visibleMonth.year,
                  _visibleMonth.month + 1,
                );
              }),
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _WeekHeader(),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: days.length,
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            childAspectRatio: 0.82,
          ),
          itemBuilder: (context, index) {
            final day = days[index];
            final dayItems = itemsByDay[_dayKey(day)] ?? const <SyncItem>[];
            return _DayCell(
              day: day,
              visibleMonth: _visibleMonth,
              items: dayItems,
              onItemTap: widget.onItemTap,
            );
          },
        ),
      ],
    );
  }
}

class _WeekHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    const labels = ['一', '二', '三', '四', '五', '六', '日'];
    return Row(
      children: labels
          .map(
            (label) => Expanded(
              child: Center(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.visibleMonth,
    required this.items,
    required this.onItemTap,
  });

  final DateTime day;
  final DateTime visibleMonth;
  final List<SyncItem> items;
  final ValueChanged<SyncItem> onItemTap;

  @override
  Widget build(BuildContext context) {
    final inMonth = day.month == visibleMonth.month;
    final today = _dayKey(day) == _dayKey(DateTime.now());

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: today
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.10)
            : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: today
              ? Theme.of(context).colorScheme.primary
              : const Color(0xFFE1E5EA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${day.day}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: inMonth ? null : const Color(0xFF94A3B8),
              fontWeight: today ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: items.take(3).length,
              separatorBuilder: (_, _) => const SizedBox(height: 3),
              itemBuilder: (context, index) {
                final item = items[index];
                return InkWell(
                  onTap: () => onItemTap(item),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: item.isExam
                          ? const Color(0xFFFEF3C7)
                          : const Color(0xFFDDF4FF),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

List<DateTime> _calendarDays(DateTime month) {
  final first = DateTime(month.year, month.month);
  final start = first.subtract(Duration(days: first.weekday - 1));
  return List.generate(42, (index) => start.add(Duration(days: index)));
}

String _dayKey(DateTime date) {
  return '${date.year}-${date.month}-${date.day}';
}

SyncItem? _firstDueItem(List<SyncItem> items) {
  for (final item in items) {
    if (item.dueAt != null) {
      return item;
    }
  }
  return null;
}
