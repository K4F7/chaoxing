import 'sync_item.dart';
import '../utils/redaction.dart';

class SyncStats {
  const SyncStats({
    this.durationMs = 0,
    this.authenticationMs = 0,
    this.inboxMs = 0,
    this.noticeDetailsMs = 0,
    this.assignmentDetailsMs = 0,
    this.coursesMs = 0,
    this.inboxMessages = 0,
    this.relevantNotices = 0,
    this.detailSummaries = 0,
    this.inboxTaskLinks = 0,
    this.inboxTaskDetails = 0,
    this.statusFilteredItems = 0,
    this.courses = 0,
    this.courseTaskLinksDiscovered = 0,
    this.courseTaskLinks = 0,
    this.courseTaskStatusFiltered = 0,
    this.itemCandidates = 0,
    this.courseSourcesEnabled = false,
  });

  final int durationMs;
  final int authenticationMs;
  final int inboxMs;
  final int noticeDetailsMs;
  final int assignmentDetailsMs;
  final int coursesMs;
  final int inboxMessages;
  final int relevantNotices;
  final int detailSummaries;
  final int inboxTaskLinks;
  final int inboxTaskDetails;
  final int statusFilteredItems;
  final int courses;
  final int courseTaskLinksDiscovered;
  final int courseTaskLinks;
  final int courseTaskStatusFiltered;
  final int itemCandidates;
  final bool courseSourcesEnabled;

  factory SyncStats.fromJson(Map<String, dynamic> json) {
    int count(String key) => json[key] is num ? (json[key] as num).round() : 0;
    return SyncStats(
      durationMs: count('durationMs'),
      authenticationMs: count('authenticationMs'),
      inboxMs: count('inboxMs'),
      noticeDetailsMs: count('noticeDetailsMs'),
      assignmentDetailsMs: count('assignmentDetailsMs'),
      coursesMs: count('coursesMs'),
      inboxMessages: count('inboxMessages'),
      relevantNotices: count('relevantNotices'),
      detailSummaries: count('detailSummaries'),
      inboxTaskLinks: count('inboxTaskLinks'),
      inboxTaskDetails: count('inboxTaskDetails'),
      statusFilteredItems: count('statusFilteredItems'),
      courses: count('courses'),
      courseTaskLinksDiscovered: count('courseTaskLinksDiscovered'),
      courseTaskLinks: count('courseTaskLinks'),
      courseTaskStatusFiltered: count('courseTaskStatusFiltered'),
      itemCandidates: count('itemCandidates'),
      courseSourcesEnabled: json['courseSourcesEnabled'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'durationMs': durationMs,
    'authenticationMs': authenticationMs,
    'inboxMs': inboxMs,
    'noticeDetailsMs': noticeDetailsMs,
    'assignmentDetailsMs': assignmentDetailsMs,
    'coursesMs': coursesMs,
    'inboxMessages': inboxMessages,
    'relevantNotices': relevantNotices,
    'detailSummaries': detailSummaries,
    'inboxTaskLinks': inboxTaskLinks,
    'inboxTaskDetails': inboxTaskDetails,
    'statusFilteredItems': statusFilteredItems,
    'courses': courses,
    'courseTaskLinksDiscovered': courseTaskLinksDiscovered,
    'courseTaskLinks': courseTaskLinks,
    'courseTaskStatusFiltered': courseTaskStatusFiltered,
    'itemCandidates': itemCandidates,
    'courseSourcesEnabled': courseSourcesEnabled,
  };
}

class AppSyncResponse {
  const AppSyncResponse({
    required this.lastSyncedAt,
    required this.authStatus,
    required this.items,
    required this.failures,
    this.stats = const SyncStats(),
  });

  final DateTime? lastSyncedAt;
  final String authStatus;
  final List<SyncItem> items;
  final List<AppSyncFailure> failures;
  final SyncStats stats;

  bool get rateLimited => failures.any((failure) {
    final message = failure.message.toLowerCase();
    return message.contains('429') ||
        message.contains('too many requests') ||
        message.contains('请求过于频繁') ||
        message.contains('请求频繁') ||
        message.contains('限流');
  });

  factory AppSyncResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'];
    final rawFailures = json['failures'];
    return AppSyncResponse(
      lastSyncedAt: SyncItem.parseDate(json['lastSyncedAt']),
      authStatus: json.readString('authStatus'),
      items: rawItems is List
          ? rawItems
                .whereType<Map>()
                .map((item) => SyncItem.fromJson(item.cast<String, dynamic>()))
                .toList()
          : const [],
      failures: rawFailures is List
          ? rawFailures
                .whereType<Map>()
                .map(
                  (failure) =>
                      AppSyncFailure.fromJson(failure.cast<String, dynamic>()),
                )
                .toList()
          : const [],
      stats: json['stats'] is Map
          ? SyncStats.fromJson((json['stats'] as Map).cast<String, dynamic>())
          : const SyncStats(),
    );
  }

  factory AppSyncResponse.build({
    required DateTime now,
    required DateTime lastSyncedAt,
    required List<SyncItem> items,
    required List<AppSyncFailure> failures,
    String authStatus = 'ok',
    SyncStats stats = const SyncStats(),
  }) {
    final enriched =
        _mergeItems(items).map((item) => _buildAppSyncItem(item, now)).toList()
          ..sort(_compareAppSyncItems);
    final sanitizedFailures = failures.map((failure) {
      return AppSyncFailure(
        entryUrl: redactSensitiveUrl(failure.entryUrl),
        sourceTitle: redactSensitiveText(failure.sourceTitle),
        message: redactSensitiveText(failure.message),
      );
    }).toList()..sort(_compareFailures);
    return AppSyncResponse(
      lastSyncedAt: lastSyncedAt,
      authStatus: authStatus,
      items: enriched,
      stats: stats,
      failures: sanitizedFailures,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'authStatus': authStatus,
      'items': items.map((item) => item.toJson()).toList(),
      'failures': failures.map((failure) => failure.toJson()).toList(),
      'stats': stats.toJson(),
    };
  }
}

List<SyncItem> _mergeItems(List<SyncItem> items) {
  final candidates = [...items]..sort(_compareMergeCandidates);
  final merged = <String, SyncItem>{};
  for (final item in candidates) {
    final current = merged[item.id];
    if (current == null) {
      merged[item.id] = item;
      continue;
    }
    final sources = {...current.sources, ...item.sources}.toList()..sort();
    merged[item.id] = current.copyWith(
      title: _preferText(current.title, item.title),
      url: _preferText(current.url, item.url),
      sourceTitle: _preferText(current.sourceTitle, item.sourceTitle),
      sourceSendTime: current.sourceSendTime ?? item.sourceSendTime,
      startAt: current.startAt ?? item.startAt,
      dueAt: current.dueAt ?? item.dueAt,
      status: _preferText(current.status, item.status),
      courseId: current.courseId ?? item.courseId,
      classId: current.classId ?? item.classId,
      workId: current.workId ?? item.workId,
      examId: current.examId ?? item.examId,
      answerId: current.answerId ?? item.answerId,
      sources: sources,
    );
  }
  return merged.values.toList();
}

String _preferText(String current, String candidate) {
  final currentTrimmed = current.trim();
  final candidateTrimmed = candidate.trim();
  if (currentTrimmed.isEmpty) {
    return candidate;
  }
  if (candidateTrimmed.isEmpty) {
    return current;
  }
  final lengthComparison = candidateTrimmed.length.compareTo(
    currentTrimmed.length,
  );
  if (lengthComparison != 0) {
    return lengthComparison > 0 ? candidate : current;
  }
  return candidate.compareTo(current) < 0 ? candidate : current;
}

int _compareMergeCandidates(SyncItem left, SyncItem right) {
  final sourceComparison = _mergeSourceRank(
    left,
  ).compareTo(_mergeSourceRank(right));
  if (sourceComparison != 0) {
    return sourceComparison;
  }
  return _mergeFingerprint(left).compareTo(_mergeFingerprint(right));
}

int _mergeSourceRank(SyncItem item) {
  if (item.sources.any(
    (source) => source == 'course_work' || source == 'course_exam',
  )) {
    return 0;
  }
  return item.sources.contains('inbox') ? 1 : 2;
}

String _mergeFingerprint(SyncItem item) {
  final sources = [...item.sources]..sort();
  return [
    item.id,
    item.kind.name,
    item.title,
    item.url,
    item.sourceTitle,
    item.sourceSendTime ?? '',
    item.startAt?.toIso8601String() ?? '',
    item.dueAt?.toIso8601String() ?? '',
    item.status,
    item.courseId ?? '',
    item.classId ?? '',
    item.workId ?? '',
    item.examId ?? '',
    item.answerId ?? '',
    sources.join('\u0000'),
  ].join('\u0001');
}

SyncItem _buildAppSyncItem(SyncItem item, DateTime now) {
  final dueAt = item.dueAt;
  final dueInHours = dueAt == null
      ? null
      : ((dueAt.millisecondsSinceEpoch - now.millisecondsSinceEpoch) /
                Duration.millisecondsPerHour)
            .round();

  return item.copyWith(
    displayStatus: dueAt == null
        ? SyncDisplayStatus.unscheduled
        : _classifyDueDate(dueAt, now),
    dueInHours: dueInHours,
  );
}

int _compareAppSyncItems(SyncItem left, SyncItem right) {
  if (left.dueAt == null && right.dueAt == null) {
    return _compareTitleThenId(left, right);
  }
  if (left.dueAt == null) {
    return 1;
  }
  if (right.dueAt == null) {
    return -1;
  }
  final dueComparison = left.dueAt!.compareTo(right.dueAt!);
  return dueComparison != 0 ? dueComparison : _compareTitleThenId(left, right);
}

int _compareTitleThenId(SyncItem left, SyncItem right) {
  final titleComparison = left.title.compareTo(right.title);
  return titleComparison != 0 ? titleComparison : left.id.compareTo(right.id);
}

int _compareFailures(AppSyncFailure left, AppSyncFailure right) {
  final urlComparison = left.entryUrl.compareTo(right.entryUrl);
  if (urlComparison != 0) {
    return urlComparison;
  }
  final sourceComparison = left.sourceTitle.compareTo(right.sourceTitle);
  return sourceComparison != 0
      ? sourceComparison
      : left.message.compareTo(right.message);
}

SyncDisplayStatus _classifyDueDate(DateTime dueAt, DateTime now) {
  if (dueAt.isBefore(now)) {
    return SyncDisplayStatus.overdue;
  }

  return _localDateKey(dueAt) == _localDateKey(now)
      ? SyncDisplayStatus.today
      : SyncDisplayStatus.upcoming;
}

String _localDateKey(DateTime value) {
  final local = value.toLocal();
  return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
}

class AppSyncFailure {
  const AppSyncFailure({
    required this.entryUrl,
    required this.sourceTitle,
    required this.message,
  });

  final String entryUrl;
  final String sourceTitle;
  final String message;

  factory AppSyncFailure.fromJson(Map<String, dynamic> json) {
    return AppSyncFailure(
      entryUrl: redactSensitiveUrl(json.readString('entryUrl')),
      sourceTitle: redactSensitiveText(json.readString('sourceTitle')),
      message: redactSensitiveText(json.readString('message')),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'entryUrl': redactSensitiveUrl(entryUrl),
      'sourceTitle': redactSensitiveText(sourceTitle),
      'message': redactSensitiveText(message),
    };
  }
}
