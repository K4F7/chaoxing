import 'package:chaoxing_app/models/sync_item.dart';
import 'package:chaoxing_app/widgets/month_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('opens on current month even when the first item is overdue', (
    tester,
  ) async {
    final now = DateTime.now();
    final overdue = DateTime(now.year - 1, now.month, 10, 12);

    await tester.pumpWidget(_app(items: [_item('old', '旧任务', overdue)]));

    expect(find.text('${now.year}年${now.month}月'), findsOneWidget);
    expect(find.text('这一天没有截止事项'), findsOneWidget);
  });

  testWidgets('selects a day and lists every item hidden by the cell limit', (
    tester,
  ) async {
    final now = DateTime.now();
    final due = DateTime(now.year, now.month, 15, 20);
    final tapped = <SyncItem>[];
    final items = List.generate(5, (index) => _item('$index', '任务$index', due));

    await tester.pumpWidget(_app(items: items, onItemTap: tapped.add));
    final dayCell = find.byKey(Key('calendar-day-${due.year}-${due.month}-15'));
    await tester.tapAt(tester.getTopLeft(dayCell) + const Offset(8, 8));
    await tester.pump();

    expect(find.text('+2'), findsOneWidget);
    final summary = tester.widget<Text>(
      find.byKey(const Key('calendar-selected-day-summary')),
    );
    expect(summary.data, contains('· 5 项'));
    expect(find.text('任务4'), findsOneWidget);

    await tester.ensureVisible(find.text('任务4'));
    await tester.tap(find.text('任务4'));
    expect(tapped.single.id, '4');
  });

  testWidgets('today button returns from another month', (tester) async {
    final now = DateTime.now();
    await tester.pumpWidget(_app(items: const []));

    await tester.tap(find.byTooltip('下个月'));
    await tester.pump();
    expect(find.text('${now.year}年${now.month}月'), findsNothing);

    await tester.tap(find.text('今天'));
    await tester.pump();
    expect(find.text('${now.year}年${now.month}月'), findsOneWidget);
  });
}

Widget _app({
  required List<SyncItem> items,
  ValueChanged<SyncItem>? onItemTap,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: MonthCalendar(items: items, onItemTap: onItemTap ?? (_) {}),
      ),
    ),
  );
}

SyncItem _item(String id, String title, DateTime dueAt) {
  return SyncItem(
    id: id,
    kind: SyncItemKind.assignment,
    title: title,
    url: 'https://mooc1.chaoxing.com/work/view?id=$id',
    sourceTitle: '课程',
    status: '未提交',
    displayStatus: SyncDisplayStatus.upcoming,
    dueAt: dueAt,
  );
}
