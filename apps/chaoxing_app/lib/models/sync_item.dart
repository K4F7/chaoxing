enum SyncItemKind { assignment, exam }

enum SyncDisplayStatus { overdue, today, upcoming, unscheduled }

class SyncItem {
  const SyncItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.url,
    required this.sourceTitle,
    required this.status,
    required this.displayStatus,
    this.sourceSendTime,
    this.startAt,
    this.dueAt,
    this.dueInHours,
    this.courseId,
    this.classId,
    this.workId,
    this.answerId,
  });

  final String id;
  final SyncItemKind kind;
  final String title;
  final String url;
  final String sourceTitle;
  final String? sourceSendTime;
  final DateTime? startAt;
  final DateTime? dueAt;
  final String status;
  final SyncDisplayStatus displayStatus;
  final int? dueInHours;
  final String? courseId;
  final String? classId;
  final String? workId;
  final String? answerId;

  bool get isExam => kind == SyncItemKind.exam;

  bool get isOverdue => displayStatus == SyncDisplayStatus.overdue;

  bool get isDueSoon =>
      dueAt != null &&
      dueAt!.isAfter(DateTime.now()) &&
      dueAt!.difference(DateTime.now()).inHours <= 72;

  factory SyncItem.fromJson(Map<String, dynamic> json) {
    return SyncItem(
      id: json.readString('id'),
      kind: parseKind(json['kind']),
      title: json.readString('title'),
      url: json.readString('url'),
      sourceTitle: json.readString('sourceTitle'),
      sourceSendTime: json.readNullableString('sourceSendTime'),
      startAt: parseDate(json['startAt']),
      dueAt: parseDate(json['dueAt']),
      status: json.readString('status'),
      displayStatus: parseDisplayStatus(json['displayStatus']),
      dueInHours: json['dueInHours'] is num
          ? (json['dueInHours'] as num).round()
          : null,
      courseId: json.readNullableString('courseId'),
      classId: json.readNullableString('classId'),
      workId: json.readNullableString('workId'),
      answerId: json.readNullableString('answerId'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kind': kind.name,
      'title': title,
      'url': url,
      'sourceTitle': sourceTitle,
      'sourceSendTime': sourceSendTime,
      'startAt': startAt?.toIso8601String(),
      'dueAt': dueAt?.toIso8601String(),
      'status': status,
      'displayStatus': displayStatus.name,
      'dueInHours': dueInHours,
      'courseId': courseId,
      'classId': classId,
      'workId': workId,
      'answerId': answerId,
    };
  }

  static SyncItemKind parseKind(Object? value) {
    return value == 'exam' ? SyncItemKind.exam : SyncItemKind.assignment;
  }

  static SyncDisplayStatus parseDisplayStatus(Object? value) {
    return SyncDisplayStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => SyncDisplayStatus.unscheduled,
    );
  }

  static DateTime? parseDate(Object? value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toLocal();
  }
}

extension JsonRead on Map<String, dynamic> {
  String readString(String key) {
    final value = this[key];
    return value is String ? value : '';
  }

  String? readNullableString(String key) {
    final value = this[key];
    return value is String && value.isNotEmpty ? value : null;
  }
}
