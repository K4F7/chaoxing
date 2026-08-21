import 'package:chaoxing_app/models/sync_item.dart';
import 'package:chaoxing_app/screens/detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('only enables explicitly trusted Chaoxing links', (tester) async {
    Future<void> pump(String url) async {
      await tester.pumpWidget(
        MaterialApp(home: DetailScreen(item: _item(url))),
      );
      await tester.pumpAndSettle();
    }

    await pump('https://example.com/phishing');
    var button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.text('学习通链接不可用'), findsOneWidget);

    await pump('https://mooc1.chaoxing.com/work?workId=1');
    button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNotNull);
    expect(find.text('打开学习通链接'), findsOneWidget);
  });
}

SyncItem _item(String url) {
  return SyncItem(
    id: 'assignment-1',
    kind: SyncItemKind.assignment,
    title: '测试作业',
    url: url,
    sourceTitle: '作业通知',
    status: 'answering',
    displayStatus: SyncDisplayStatus.upcoming,
  );
}
