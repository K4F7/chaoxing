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

/// 已见通知：在过去某一轮同步的通知列表里出现过的通知。
///
/// 通知一旦发出内容就不再变化，所以详情解析成功的通知会把正文与任务入口链接
/// 一并记下（[detailParsed] 为真），后续同步直接复用，不再请求它的详情页。
/// 只是在列表里露过面、或详情抓取失败的通知，[detailParsed] 保持为假，下一轮
/// 照常重试——否则一次失败会被永久记成「已解析」，那条通知的待办就再也进不来。
class SeenNotice {
  const SeenNotice({
    required this.id,
    this.detailParsed = false,
    this.title = '',
    this.sendTime,
    this.content,
    this.taskLinks = const [],
  });

  final String id;
  final bool detailParsed;

  /// 通知标题与发出时间。两者都参与待办的构建——发出时间还用来补全「06-20 23:59」
  /// 这类不带年份的截止时间，所以记录里必须留着，否则补回来的待办会和原样抓取
  /// 的不一致。
  final String title;
  final String? sendTime;
  final String? content;
  final List<String> taskLinks;

  factory SeenNotice.fromJson(Map<String, dynamic> json) {
    final rawLinks = json['taskLinks'];
    return SeenNotice(
      id: json.readString('id'),
      detailParsed: json['detailParsed'] == true,
      title: json.readString('title'),
      sendTime: json.readNullableString('sendTime'),
      content: json.readNullableString('content'),
      taskLinks: rawLinks is List
          ? rawLinks
                .whereType<String>()
                .where((link) => link.isNotEmpty)
                .toList()
          : const [],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'detailParsed': detailParsed,
    'title': title,
    if (sendTime != null) 'sendTime': sendTime,
    if (content != null) 'content': content,
    'taskLinks': taskLinks,
  };
}

class AppSyncResponse {
  const AppSyncResponse({
    required this.lastSyncedAt,
    required this.authStatus,
    required this.items,
    required this.failures,
    this.stats = const SyncStats(),
    this.seenNotices = const [],
  });

  final DateTime? lastSyncedAt;
  final String authStatus;
  final List<SyncItem> items;
  final List<AppSyncFailure> failures;
  final SyncStats stats;

  /// 已见通知，最近出现的排在前面。首轮运行或缓存被清空时为空，那一轮所有通知
  /// 都会照常抓取详情。
  final List<SeenNotice> seenNotices;

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
      seenNotices: _readSeenNotices(json['seenNotices']),
    );
  }

  factory AppSyncResponse.build({
    required DateTime now,
    required DateTime lastSyncedAt,
    required List<SyncItem> items,
    required List<AppSyncFailure> failures,
    String authStatus = 'ok',
    SyncStats stats = const SyncStats(),
    List<SeenNotice> seenNotices = const [],
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
      seenNotices: _boundSeenNotices(seenNotices),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lastSyncedAt': lastSyncedAt?.toIso8601String(),
      'authStatus': authStatus,
      'items': items.map((item) => item.toJson()).toList(),
      'failures': failures.map((failure) => failure.toJson()).toList(),
      'stats': stats.toJson(),
      'seenNotices': seenNotices.map((notice) => notice.toJson()).toList(),
    };
  }
}

/// 已见通知的条数上限，与收件箱单轮抓取条数的上限一致：一轮同步见到的通知永远
/// 记得下，更早的按最近优先淘汰。淘汰只会让那条通知下次重新抓一遍详情，不会让
/// 它的待办消失。
const maxSeenNotices = 500;

List<SeenNotice> _boundSeenNotices(List<SeenNotice> notices) {
  final bounded = <String, SeenNotice>{};
  for (final notice in notices) {
    if (notice.id.isEmpty || bounded.length >= maxSeenNotices) {
      continue;
    }
    bounded.putIfAbsent(notice.id, () => notice);
  }
  return bounded.values.toList();
}

List<SeenNotice> _readSeenNotices(Object? raw) {
  if (raw is! List) {
    return const [];
  }
  return _boundSeenNotices(
    raw
        .whereType<Map>()
        .map(
          (notice) => SeenNotice.fromJson(notice.cast<String, dynamic>()),
        )
        .toList(),
  );
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
