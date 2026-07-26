import 'package:chaoxing_app/models/sync_item.dart';
import 'package:chaoxing_app/widgets/source_overview.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('groups items by source and counts assignments and exams', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app([
        _item('a', '作业一', '高等数学', DateTime(2026, 8, 2)),
        _item('b', '期末考试', '高等数学', DateTime(2026, 8, 3), exam: true),
        _item('c', '阅读', '大学英语', DateTime(2026, 8, 1)),
      ]),
    );

    expect(find.text('2 个来源 · 3 项待办'), findsOneWidget);
    expect(find.text('高等数学'), findsOneWidget);
    expect(find.text('1 个作业 · 1 个考试'), findsOneWidget);
    expect(find.text('大学英语'), findsOneWidget);
  });

  testWidgets('puts empty source titles in an explicit fallback group', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app([_item('a', '无来源任务', '  ', DateTime(2026, 8, 2))]),
    );

    expect(find.text('未识别来源'), findsOneWidget);
    expect(find.text('无来源任务'), findsOneWidget);
  });

  testWidgets('opens an item from an expanded source group', (tester) async {
    final tapped = <SyncItem>[];
    final item = _item('a', '可打开任务', '课程', DateTime(2026, 8, 2));
    await tester.pumpWidget(_app([item], onItemTap: tapped.add));

    await tester.tap(find.text('可打开任务'));
    expect(tapped.single.id, 'a');
  });

  testWidgets('shows a useful empty state', (tester) async {
    await tester.pumpWidget(_app(const []));
    expect(find.text('暂无来源数据'), findsOneWidget);
  });
}

Widget _app(List<SyncItem> items, {ValueChanged<SyncItem>? onItemTap}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: SourceOverview(items: items, onItemTap: onItemTap ?? (_) {}),
      ),
    ),
  );
}

SyncItem _item(
  String id,
  String title,
  String sourceTitle,
  DateTime dueAt, {
  bool exam = false,
}) {
  return SyncItem(
    id: id,
    kind: exam ? SyncItemKind.exam : SyncItemKind.assignment,
    title: title,
    url: 'https://mooc1.chaoxing.com/work/view?id=$id',
    sourceTitle: sourceTitle,
    status: '未提交',
    displayStatus: SyncDisplayStatus.upcoming,
    dueAt: dueAt,
  );
}
