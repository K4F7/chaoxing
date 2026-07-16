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
    this.examId,
    this.answerId,
    this.sources = const [],
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
  final String? examId;
  final String? answerId;
  final List<String> sources;

  bool get isExam => kind == SyncItemKind.exam;

  bool get isOverdue => displayStatus == SyncDisplayStatus.overdue;

  bool get isDueSoon =>
      dueAt != null &&
      dueAt!.isAfter(DateTime.now()) &&
      dueAt!.difference(DateTime.now()).inHours <= 72;

  SyncItem copyWith({
    String? id,
    SyncItemKind? kind,
    String? title,
    String? url,
    String? sourceTitle,
    String? sourceSendTime,
    DateTime? startAt,
    DateTime? dueAt,
    String? status,
    SyncDisplayStatus? displayStatus,
    int? dueInHours,
    String? courseId,
    String? classId,
    String? workId,
    String? examId,
    String? answerId,
    List<String>? sources,
  }) {
    return SyncItem(
      id: id ?? this.id,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      url: url ?? this.url,
      sourceTitle: sourceTitle ?? this.sourceTitle,
      sourceSendTime: sourceSendTime ?? this.sourceSendTime,
      startAt: startAt ?? this.startAt,
      dueAt: dueAt ?? this.dueAt,
      status: status ?? this.status,
      displayStatus: displayStatus ?? this.displayStatus,
      dueInHours: dueInHours ?? this.dueInHours,
      courseId: courseId ?? this.courseId,
      classId: classId ?? this.classId,
      workId: workId ?? this.workId,
      examId: examId ?? this.examId,
      answerId: answerId ?? this.answerId,
      sources: sources ?? this.sources,
    );
  }

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
      examId: json.readNullableString('examId'),
      answerId: json.readNullableString('answerId'),
      sources: json['sources'] is List
          ? (json['sources'] as List)
                .whereType<String>()
                .where((source) => source.isNotEmpty)
                .toList()
          : const [],
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
      'examId': examId,
      'answerId': answerId,
      'sources': sources,
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
