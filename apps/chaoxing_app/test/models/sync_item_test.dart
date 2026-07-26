import 'package:chaoxing_app/models/sync_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses app sync item with missing optional fields', () {
    final item = SyncItem.fromJson({
      'id': 'assignment-1',
      'kind': 'assignment',
      'title': '线性代数作业',
      'url': 'https://example.com/work',
      'sourceTitle': '作业通知',
      'status': 'answering',
      'displayStatus': 'today',
      'dueAt': '2026-06-05T15:59:00.000Z',
      'dueInHours': 3,
    });

    expect(item.kind, SyncItemKind.assignment);
    expect(item.displayStatus, SyncDisplayStatus.today);
    expect(item.dueAt, isNotNull);
    expect(item.courseId, isNull);
    expect(item.examId, isNull);
    expect(item.sources, isEmpty);
  });
}
