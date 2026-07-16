import 'dart:async';
import 'dart:convert';

import 'package:html/dom.dart' as html_dom;
import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

import '../models/app_config.dart';
import '../models/app_sync_response.dart';
import '../models/sync_item.dart';
import '../utils/redaction.dart';
import 'chaoxing_cookie_store.dart';
import 'chaoxing_url_policy.dart';

export 'chaoxing_url_policy.dart';

const defaultChaoxingHomeUrl =
    'https://i.chaoxing.com/base?ws=1&t=1780231212848';
const _noticeOrigin = 'https://notice.chaoxing.com';
const _courseApiOrigin = 'https://mooc1-api.chaoxing.com';
const _courseListUrl = '$_courseApiOrigin/mycourse/backclazzdata';
const _modernCourseListOrigin = 'https://mooc1-1.chaoxing.com';
const _modernCourseListUrl =
    '$_modernCourseListOrigin/mooc-ans/visit/courselistdata';
const _maxCookieRedirects = 5;
const _noticeDetailConcurrency = 6;
const _assignmentDetailConcurrency = 6;
const _courseListConcurrency = 3;
const _courseDetailConcurrency = 6;

class LocalSyncException implements Exception {
  const LocalSyncException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AuthCheckResult {
  const AuthCheckResult({
    required this.authenticated,
    required this.statusCode,
    required this.loginDetected,
    required this.finalUrl,
    required this.title,
  });

  final bool authenticated;
  final int statusCode;
  final bool loginDetected;
  final String finalUrl;
  final String? title;
}

enum SyncPhase {
  authentication,
  inbox,
  noticeDetails,
  assignmentDetails,
  courses,
  finalizing,
}

class SyncProgress {
  const SyncProgress({required this.phase, this.completed = 0, this.total = 0});

  final SyncPhase phase;
  final int completed;
  final int total;

  String get label => switch (phase) {
    SyncPhase.authentication => '验证登录态',
    SyncPhase.inbox => '读取通知',
    SyncPhase.noticeDetails => '解析通知详情',
    SyncPhase.assignmentDetails => '解析作业考试',
    SyncPhase.courses => '扫描课程空间',
    SyncPhase.finalizing => '整理同步结果',
  };

  String get description => total > 0 ? '$label $completed/$total' : label;
}

typedef SyncProgressCallback = void Function(SyncProgress progress);

class InboxFetchResult {
  const InboxFetchResult({
    required this.inboxUrl,
    required this.pagesFetched,
    required this.totalFetched,
    required this.messages,
  });

  final String inboxUrl;
  final int pagesFetched;
  final int totalFetched;
  final List<InboxMessage> messages;
}

class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.uuid,
    required this.title,
    required this.sender,
    required this.sendTime,
    required this.isRead,
    required this.content,
    required this.detailUrl,
    required this.sendTag,
  });

  final String id;
  final String? uuid;
  final String title;
  final String? sender;
  final String? sendTime;
  final bool isRead;
  final String? content;
  final String? detailUrl;
  final Object? sendTag;
}

class DetailSummary {
  const DetailSummary({
    required this.title,
    required this.sendTime,
    required this.content,
    required this.assignmentLinks,
  });

  final String title;
  final String? sendTime;
  final String? content;
  final List<String> assignmentLinks;
}

class AssignmentRequirement {
  const AssignmentRequirement({
    required this.sourceTitle,
    required this.sourceSendTime,
    required this.sourceContent,
    required this.entryUrl,
    required this.finalUrl,
    required this.pageTitle,
    required this.status,
    required this.courseId,
    required this.classId,
    required this.workId,
    required this.answerId,
    required this.workStatus,
    required this.timeWindowStart,
    required this.timeWindowEnd,
    this.source = 'inbox',
  });

  final String sourceTitle;
  final String? sourceSendTime;
  final String? sourceContent;
  final String entryUrl;
  final String finalUrl;
  final String? pageTitle;
  final int status;
  final String? courseId;
  final String? classId;
  final String? workId;
  final String? answerId;
  final String workStatus;
  final String? timeWindowStart;
  final String? timeWindowEnd;
  final String source;
}

class CourseSpace {
  const CourseSpace({
    required this.courseId,
    required this.classId,
    required this.cpi,
    required this.title,
  });

  final String courseId;
  final String classId;
  final String cpi;
  final String title;
}

class CourseTaskLink {
  const CourseTaskLink({
    required this.url,
    required this.title,
    this.status = 'unknown',
  });

  final String url;
  final String title;
  final String status;

  bool get isActionable => isActionableWorkStatus(status);
}

class _CourseSourceStats {
  const _CourseSourceStats({
    this.courses = 0,
    this.taskLinksDiscovered = 0,
    this.taskLinks = 0,
    this.statusFiltered = 0,
  });

  final int courses;
  final int taskLinksDiscovered;
  final int taskLinks;
  final int statusFiltered;
}

class _CourseDiscoveryResult {
  const _CourseDiscoveryResult({required this.courses, required this.cookie});

  final List<CourseSpace> courses;
  final String cookie;
}

class _CookieSession {
  _CookieSession(this.source);

  String source;
}

class LocalSyncRunner {
  LocalSyncRunner({
    http.Client? client,
    DateTime Function()? clock,
    this.requestTimeout = const Duration(seconds: 20),
    this._homeUrl = defaultChaoxingHomeUrl,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  final http.Client _client;
  final DateTime Function() _clock;
  final Duration requestTimeout;
  final String _homeUrl;

  void close() => _client.close();

  Future<AppSyncResponse> run(
    AppConfig config, {
    SyncProgressCallback? onProgress,
  }) async {
    final syncStopwatch = Stopwatch()..start();
    var authenticationMs = 0;
    var inboxMs = 0;
    var noticeDetailsMs = 0;
    var assignmentDetailsMs = 0;
    var coursesMs = 0;
    var phaseStartedAt = 0;
    final cookie = config.cookie.trim();
    if (cookie.isEmpty) {
      throw const LocalSyncException('请先在设置中填入学习通 Cookie');
    }

    onProgress?.call(
      const SyncProgress(phase: SyncPhase.authentication, total: 1),
    );
    final auth = await checkAuth(cookie);
    if (!auth.authenticated) {
      throw const LocalSyncException('Cookie 已失效或跳转到登录页，请重新登录后更新 Cookie');
    }
    onProgress?.call(
      const SyncProgress(
        phase: SyncPhase.authentication,
        completed: 1,
        total: 1,
      ),
    );
    authenticationMs = syncStopwatch.elapsedMilliseconds;
    phaseStartedAt = authenticationMs;

    onProgress?.call(const SyncProgress(phase: SyncPhase.inbox, total: 1));
    final inbox = await fetchInboxMessages(
      cookie: cookie,
      itemLimit: config.inboxItemLimit,
      pageLimit: config.inboxPageLimit,
    );
    onProgress?.call(
      const SyncProgress(phase: SyncPhase.inbox, completed: 1, total: 1),
    );
    inboxMs = syncStopwatch.elapsedMilliseconds - phaseStartedAt;
    phaseStartedAt = syncStopwatch.elapsedMilliseconds;
    final relevant = inbox.messages.where(isAssignmentOrExamRelated).toList();
    final summaries = <DetailSummary>[];
    final failures = <AppSyncFailure>[];
    final noticesToParse = relevant.take(config.inboxItemLimit).toList();
    onProgress?.call(
      SyncProgress(
        phase: SyncPhase.noticeDetails,
        total: noticesToParse.length,
      ),
    );
    var completedNoticeDetails = 0;
    await _forEachConcurrent(noticesToParse, _noticeDetailConcurrency, (
      message,
      _,
    ) async {
      try {
        summaries.add(
          await fetchDetailSummary(message: message, cookie: cookie),
        );
      } catch (error) {
        failures.add(
          AppSyncFailure(
            entryUrl: redactSensitiveUrl(
              message.detailUrl ?? 'notice:${message.id}',
            ),
            sourceTitle: redactSensitiveText(message.title),
            message: error is LocalSyncException
                ? redactSensitiveText(
                    error.message,
                    secrets: chaoxingCookieSecrets(cookie),
                  )
                : '通知详情解析失败',
          ),
        );
      }
      completedNoticeDetails += 1;
      onProgress?.call(
        SyncProgress(
          phase: SyncPhase.noticeDetails,
          completed: completedNoticeDetails,
          total: noticesToParse.length,
        ),
      );
    });
    noticeDetailsMs = syncStopwatch.elapsedMilliseconds - phaseStartedAt;
    phaseStartedAt = syncStopwatch.elapsedMilliseconds;

    final unique = collectUniqueWorkLinks(summaries);
    final items = <SyncItem>[];
    final uniqueEntries = unique.entries.toList();
    var statusFilteredItems = 0;
    onProgress?.call(
      SyncProgress(
        phase: SyncPhase.assignmentDetails,
        total: uniqueEntries.length,
      ),
    );
    var completedAssignmentDetails = 0;
    await _forEachConcurrent(uniqueEntries, _assignmentDetailConcurrency, (
      entry,
      _,
    ) async {
      try {
        final requirement = await fetchAssignmentRequirement(
          entryUrl: entry.key,
          summary: entry.value,
          cookie: cookie,
        );
        if (isActionableWorkStatus(requirement.workStatus)) {
          items.add(buildSyncItem(requirement, _clock()));
        } else {
          statusFilteredItems += 1;
        }
      } catch (error) {
        failures.add(
          AppSyncFailure(
            entryUrl: redactSensitiveUrl(entry.key),
            sourceTitle: redactSensitiveText(entry.value.title),
            message: error is LocalSyncException
                ? redactSensitiveText(
                    error.message,
                    secrets: chaoxingCookieSecrets(cookie),
                  )
                : '作业详情解析失败',
          ),
        );
      }
      completedAssignmentDetails += 1;
      onProgress?.call(
        SyncProgress(
          phase: SyncPhase.assignmentDetails,
          completed: completedAssignmentDetails,
          total: uniqueEntries.length,
        ),
      );
    });
    assignmentDetailsMs = syncStopwatch.elapsedMilliseconds - phaseStartedAt;
    phaseStartedAt = syncStopwatch.elapsedMilliseconds;

    var courseStats = const _CourseSourceStats();
    if (config.courseSourcesEnabled) {
      courseStats = await _appendCourseSourceItems(
        cookie: cookie,
        courseLimit: config.courseLimit,
        itemLimit: config.inboxItemLimit,
        items: items,
        failures: failures,
        onProgress: onProgress,
      );
    }
    coursesMs = syncStopwatch.elapsedMilliseconds - phaseStartedAt;

    onProgress?.call(const SyncProgress(phase: SyncPhase.finalizing));
    final now = _clock();
    return AppSyncResponse.build(
      now: now,
      lastSyncedAt: now,
      items: items,
      failures: failures,
      stats: SyncStats(
        durationMs: syncStopwatch.elapsedMilliseconds,
        authenticationMs: authenticationMs,
        inboxMs: inboxMs,
        noticeDetailsMs: noticeDetailsMs,
        assignmentDetailsMs: assignmentDetailsMs,
        coursesMs: coursesMs,
        inboxMessages: inbox.messages.length,
        relevantNotices: relevant.length,
        detailSummaries: summaries.length,
        inboxTaskLinks: unique.length,
        inboxTaskDetails: uniqueEntries.length,
        statusFilteredItems: statusFilteredItems,
        courses: courseStats.courses,
        courseTaskLinksDiscovered: courseStats.taskLinksDiscovered,
        courseTaskLinks: courseStats.taskLinks,
        courseTaskStatusFiltered: courseStats.statusFiltered,
        itemCandidates: items.map((item) => item.id).toSet().length,
        courseSourcesEnabled: config.courseSourcesEnabled,
      ),
    );
  }

  Future<AuthCheckResult> checkAuth(String cookie) async {
    final response = await _getWithCookie(
      Uri.parse(_homeUrl),
      headers: _htmlHeaders(cookie, _homeUrl),
    );
    final html = _decodeBody(response);
    final finalUrl = response.request?.url.toString() ?? _homeUrl;
    final loginDetected = detectLoginSignals(finalUrl, html);
    return AuthCheckResult(
      authenticated:
          response.statusCode >= 200 &&
          response.statusCode < 300 &&
          !loginDetected,
      statusCode: response.statusCode,
      loginDetected: loginDetected,
      finalUrl: redactSensitiveUrl(finalUrl),
      title: extractPageTitle(html),
    );
  }

  Future<InboxFetchResult> fetchInboxMessages({
    required String cookie,
    required int itemLimit,
    required int pageLimit,
  }) async {
    final normalizedItemLimit = _normalizeLimit(itemLimit, 20, 500);
    final normalizedPageLimit = _normalizeLimit(pageLimit, 1, 20);
    final homeHtml = await _fetchPageText(_homeUrl, _homeUrl, cookie);
    final inboxUrl = findInboxUrl(homeHtml, _homeUrl);
    if (inboxUrl == null) {
      throw const LocalSyncException('未能在学习通首页找到收件箱入口');
    }

    final inboxHtml = await _fetchPageText(inboxUrl, _homeUrl, cookie);
    final pageConfig = _extractInboxPageConfig(inboxHtml);
    final messages = <InboxMessage>[];
    var lastGetId = '';
    var lastPage = false;
    var pagesFetched = 0;

    while (messages.length < normalizedItemLimit &&
        !lastPage &&
        pagesFetched < normalizedPageLimit) {
      final data = await _postNoticeList(
        apiUrl: '$_noticeOrigin/pc/notice/getNoticeList',
        referer: inboxUrl,
        cookie: cookie,
        config: pageConfig,
        lastValue: lastGetId,
      );
      pagesFetched += 1;

      if (!_hasSuccessfulApiStatus(data)) {
        throw LocalSyncException(_readString(data, 'msg', '通知列表抓取失败'));
      }

      final page = _extractNoticePage(data);
      final rawMessages = <Object?>[
        if (lastGetId.isEmpty) ...page.topNotices,
        if (lastGetId.isEmpty) ...page.urgentNotices,
        ...page.items,
      ];

      for (final notice in rawMessages) {
        if (messages.length >= normalizedItemLimit) {
          break;
        }
        if (notice is Map) {
          messages.add(_normalizeNotice(notice));
        }
      }

      lastGetId = page.lastGetId;
      lastPage = page.lastPage || rawMessages.isEmpty || lastGetId.isEmpty;
    }

    return InboxFetchResult(
      inboxUrl: inboxUrl,
      pagesFetched: pagesFetched,
      totalFetched: messages.length,
      messages: messages,
    );
  }

  Future<DetailSummary> fetchDetailSummary({
    required InboxMessage message,
    required String cookie,
  }) async {
    final id = message.uuid ?? message.id;
    final sendTag = message.sendTag ?? 0;
    final url = '$_noticeOrigin/pc/notice/$id/getNoticeDetail?sendTag=$sendTag';
    final response = await _getWithCookie(
      Uri.parse(url),
      headers: {
        ..._jsonHeaders(
          cookie,
          message.detailUrl ?? '$_noticeOrigin/pc/notice/myNotice',
        ),
        'X-Requested-With': 'XMLHttpRequest',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LocalSyncException('通知详情抓取失败 (${response.statusCode})');
    }

    final decoded = jsonDecode(_decodeBody(response));
    if (decoded is! Map) {
      throw const LocalSyncException('通知详情返回格式不正确');
    }
    if (!_hasSuccessfulApiStatus(decoded)) {
      throw const LocalSyncException('通知详情接口返回失败');
    }
    final detail = _extractNoticeDetail(decoded);
    final rawContent = _stringOrEmpty(_mapValue(detail, 'content'));
    final rawRtf = _stringOrEmpty(
      _mapValue(detail, 'rtf_content') ?? _mapValue(detail, 'rtfContent'),
    );
    final content = _stripHtml(rawContent.isNotEmpty ? rawContent : rawRtf);
    final rtf = rawRtf;
    final decodedAttachments = _decodeIframeNames(rtf);
    final links = extractNoticeLinks(
      '$rtf\n${_collectStringValues(decodedAttachments).join('\n')}\n'
      '${_collectStringValues(decoded).join('\n')}',
    );

    return DetailSummary(
      title: message.title,
      sendTime: message.sendTime,
      content: content.isEmpty ? null : content,
      assignmentLinks: links,
    );
  }

  Future<AssignmentRequirement> fetchAssignmentRequirement({
    required String entryUrl,
    required DetailSummary summary,
    required String cookie,
    String source = 'inbox',
  }) async {
    final entryUri = Uri.parse(entryUrl);
    _ensureTrustedCookieTarget(entryUri);
    final response = await _getWithCookie(
      Uri.parse(entryUrl),
      headers: _htmlHeaders(cookie, '$_noticeOrigin/pc/notice/myNotice'),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LocalSyncException('作业页面抓取失败 (${response.statusCode})');
    }

    final finalUrl = response.request?.url.toString() ?? entryUrl;
    _ensureTrustedCookieTarget(Uri.parse(finalUrl));
    return parseAssignmentRequirement(
      html: _decodeBody(response),
      entryUrl: entryUrl,
      finalUrl: finalUrl,
      status: response.statusCode,
      sourceTitle: summary.title,
      sourceSendTime: summary.sendTime,
      sourceContent: summary.content,
      source: source,
    );
  }

  Future<_CourseSourceStats> _appendCourseSourceItems({
    required String cookie,
    required int courseLimit,
    required int itemLimit,
    required List<SyncItem> items,
    required List<AppSyncFailure> failures,
    SyncProgressCallback? onProgress,
  }) async {
    onProgress?.call(const SyncProgress(phase: SyncPhase.courses));
    List<CourseSpace> courses;
    var courseCookie = cookie;
    try {
      final discovery = await _fetchCourseDiscovery(cookie);
      courses = discovery.courses;
      courseCookie = discovery.cookie;
    } catch (error) {
      failures.add(
        AppSyncFailure(
          entryUrl: _modernCourseListUrl,
          sourceTitle: '课程空间',
          message: error is LocalSyncException
              ? redactSensitiveText(
                  error.message,
                  secrets: chaoxingCookieSecrets(cookie),
                )
              : '课程列表解析失败',
        ),
      );
      return const _CourseSourceStats();
    }

    final normalizedCourseLimit = _normalizeLimit(courseLimit, 20, 100);
    final normalizedItemLimit = _normalizeLimit(itemLimit, 60, 500);
    final scannedCourses = courses.take(normalizedCourseLimit).length;
    final coursesToScan = courses.take(normalizedCourseLimit).toList();
    onProgress?.call(
      SyncProgress(phase: SyncPhase.courses, total: scannedCourses),
    );
    final sourcePagesByCourse =
        List<List<({String source, List<CourseTaskLink> links})>?>.filled(
          scannedCourses,
          null,
        );
    var completedCourseLists = 0;
    await _forEachConcurrent(coursesToScan, _courseListConcurrency, (
      course,
      courseIndex,
    ) async {
      sourcePagesByCourse[courseIndex] = await Future.wait(
        const ['course_work', 'course_exam'].map((source) async {
          final listUrl = buildCourseTaskListUrl(course, source);
          try {
            final response = await _getWithCookie(
              Uri.parse(listUrl),
              headers: _htmlHeaders(courseCookie, _modernCourseListUrl),
            );
            if (response.statusCode < 200 || response.statusCode >= 300) {
              throw LocalSyncException('任务列表抓取失败 (${response.statusCode})');
            }
            return (
              source: source,
              links: parseCourseTaskLinks(
                _decodeBody(response),
                listUrl,
                fallbackTitle: course.title,
              ),
            );
          } catch (error) {
            failures.add(
              AppSyncFailure(
                entryUrl: listUrl,
                sourceTitle: course.title,
                message: error is LocalSyncException
                    ? redactSensitiveText(
                        error.message,
                        secrets: chaoxingCookieSecrets(cookie),
                      )
                    : '任务列表解析失败',
              ),
            );
            return (source: source, links: const <CourseTaskLink>[]);
          }
        }),
      );
      completedCourseLists += 1;
      onProgress?.call(
        SyncProgress(
          phase: SyncPhase.courses,
          completed: completedCourseLists,
          total: scannedCourses,
        ),
      );
    });

    var processedTasks = 0;
    var discoveredTaskLinks = 0;
    var statusFilteredTasks = 0;
    final visitedUrls = <String>{};
    final pendingDetails = <({String source, CourseTaskLink link})>[];
    var limitReached = false;
    for (
      var courseIndex = 0;
      courseIndex < sourcePagesByCourse.length;
      courseIndex += 1
    ) {
      final sourcePages = sourcePagesByCourse[courseIndex] ?? const [];
      for (final page in sourcePages) {
        for (final link in page.links) {
          if (processedTasks >= normalizedItemLimit) {
            limitReached = true;
            break;
          }
          if (!visitedUrls.add(link.url)) {
            continue;
          }
          discoveredTaskLinks += 1;
          if (!link.isActionable) {
            statusFilteredTasks += 1;
            continue;
          }
          processedTasks += 1;
          pendingDetails.add((source: page.source, link: link));
        }
        if (limitReached) {
          break;
        }
      }
      if (limitReached) {
        break;
      }
    }

    final totalCourseUnits = scannedCourses + pendingDetails.length;
    onProgress?.call(
      SyncProgress(
        phase: SyncPhase.courses,
        completed: scannedCourses,
        total: totalCourseUnits,
      ),
    );
    var completedCourseDetails = 0;
    await _forEachConcurrent(pendingDetails, _courseDetailConcurrency, (
      pending,
      _,
    ) async {
      final link = pending.link;
      try {
        final requirement = await fetchAssignmentRequirement(
          entryUrl: link.url,
          summary: DetailSummary(
            title: link.title,
            sendTime: null,
            content: null,
            assignmentLinks: const [],
          ),
          cookie: courseCookie,
          source: pending.source,
        );
        if (isActionableWorkStatus(requirement.workStatus)) {
          items.add(buildSyncItem(requirement, _clock()));
        } else {
          statusFilteredTasks += 1;
        }
      } catch (error) {
        failures.add(
          AppSyncFailure(
            entryUrl: link.url,
            sourceTitle: link.title,
            message: error is LocalSyncException
                ? redactSensitiveText(
                    error.message,
                    secrets: chaoxingCookieSecrets(cookie),
                  )
                : '任务详情解析失败',
          ),
        );
      }
      completedCourseDetails += 1;
      onProgress?.call(
        SyncProgress(
          phase: SyncPhase.courses,
          completed: scannedCourses + completedCourseDetails,
          total: totalCourseUnits,
        ),
      );
    });
    if (pendingDetails.isEmpty) {
      onProgress?.call(
        SyncProgress(
          phase: SyncPhase.courses,
          completed: totalCourseUnits,
          total: totalCourseUnits,
        ),
      );
    }
    return _CourseSourceStats(
      courses: scannedCourses,
      taskLinksDiscovered: discoveredTaskLinks,
      taskLinks: processedTasks,
      statusFiltered: statusFilteredTasks,
    );
  }

  Future<List<CourseSpace>> fetchCourseSpaces(String cookie) async {
    return (await _fetchCourseDiscovery(cookie)).courses;
  }

  Future<_CourseDiscoveryResult> _fetchCourseDiscovery(String cookie) async {
    Object? modernError;
    final session = _CookieSession(cookie);
    try {
      final homeResponse = await _getWithCookie(
        Uri.parse(_homeUrl),
        headers: _htmlHeaders(session.source, _homeUrl),
        session: session,
      );
      final interactionUrl = findCourseInteractionUrl(
        _decodeBody(homeResponse),
      );
      if (interactionUrl != null) {
        await _getWithCookie(
          Uri.parse(interactionUrl),
          headers: _htmlHeaders(session.source, _homeUrl),
          session: session,
        );
      }
      final response = await _postFormWithCookie(
        Uri.parse(_modernCourseListUrl),
        headers: {
          ..._htmlHeaders(
            session.source,
            interactionUrl ?? '$_modernCourseListOrigin/visit/interaction',
          ),
          'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
          'Origin': _modernCourseListOrigin,
          'X-Requested-With': 'XMLHttpRequest',
        },
        body: const {
          'courseType': '1',
          'courseFolderId': '0',
          'baseEducation': '0',
          'superstarClass': '',
          'courseFolderSize': '0',
        },
        session: session,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LocalSyncException('新版课程列表抓取失败 (${response.statusCode})');
      }
      return _CourseDiscoveryResult(
        courses: parseCourseSpaces(_decodeBody(response)),
        cookie: session.source,
      );
    } catch (error) {
      modernError = error;
    }

    try {
      final response = await _getWithCookie(
        Uri.parse(_courseListUrl),
        headers: _jsonHeaders(session.source, _homeUrl),
        session: session,
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw LocalSyncException('旧版课程列表抓取失败 (${response.statusCode})');
      }
      return _CourseDiscoveryResult(
        courses: parseCourseSpaces(_decodeBody(response)),
        cookie: session.source,
      );
    } catch (legacyError) {
      final modernMessage = modernError is LocalSyncException
          ? modernError.message
          : '新版课程列表不可用';
      final legacyMessage = legacyError is LocalSyncException
          ? legacyError.message
          : '旧版课程列表不可用';
      throw LocalSyncException('$modernMessage；$legacyMessage');
    }
  }

  Future<String> _fetchPageText(
    String url,
    String referer,
    String cookie,
  ) async {
    final response = await _getWithCookie(
      Uri.parse(url),
      headers: _htmlHeaders(cookie, referer),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LocalSyncException('页面抓取失败 (${response.statusCode})');
    }
    return _decodeBody(response);
  }

  Future<Map<String, dynamic>> _postNoticeList({
    required String apiUrl,
    required String referer,
    required String cookie,
    required _InboxPageConfig config,
    required String lastValue,
  }) async {
    final response = await _postFormWithCookie(
      Uri.parse(apiUrl),
      headers: {
        ..._jsonHeaders(cookie, referer),
        'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
        'Origin': _noticeOrigin,
        'X-Requested-With': 'XMLHttpRequest',
      },
      body: {
        'type': config.type,
        'notice_type': config.noticeType,
        'lastValue': lastValue,
        'sort': '',
        'folderUUID': config.folderUuid,
        'kw': '',
        'startTime': '',
        'endTime': '',
        'gKw': '',
        'gName': '',
        'year': config.year,
        'tag': '',
        'fidsCode': config.fidsCode,
        'queryFolderNoticePrevYear': '0',
        'filterSenderPuids': '',
        'filterTags': '',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw LocalSyncException('通知列表抓取失败 (${response.statusCode})');
    }

    final decoded = jsonDecode(_decodeBody(response));
    if (decoded is! Map<String, dynamic>) {
      throw const LocalSyncException('通知列表返回格式不正确');
    }
    return decoded;
  }

  Future<http.Response> _getWithCookie(
    Uri uri, {
    required Map<String, String> headers,
    _CookieSession? session,
  }) {
    return _sendWithCookie('GET', uri, headers: headers, session: session);
  }

  Future<http.Response> _postFormWithCookie(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, String> body,
    _CookieSession? session,
  }) {
    return _sendWithCookie(
      'POST',
      uri,
      headers: headers,
      bodyFields: body,
      session: session,
    );
  }

  Future<http.Response> _sendWithCookie(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    Map<String, String>? bodyFields,
    _CookieSession? session,
  }) async {
    var current = uri;
    var currentMethod = method;
    var redirects = 0;
    var cookieSource = session?.source ?? headers['Cookie'] ?? '';
    final requestStopwatch = Stopwatch()..start();

    Duration remainingTimeout() {
      final remaining = requestTimeout - requestStopwatch.elapsed;
      if (remaining <= Duration.zero) {
        throw TimeoutException('request deadline exceeded');
      }
      return remaining;
    }

    while (true) {
      _ensureTrustedCookieTarget(current);
      final request = http.Request(currentMethod, current)
        ..followRedirects = false
        ..headers.addAll(headers);
      final scopedCookie = cookieHeaderForChaoxingUri(cookieSource, current);
      if (scopedCookie.isEmpty) {
        request.headers.remove('Cookie');
      } else {
        request.headers['Cookie'] = scopedCookie;
      }
      if (bodyFields != null && currentMethod == 'POST') {
        request.bodyFields = bodyFields;
      }

      late final http.StreamedResponse streamed;
      late final http.Response response;
      try {
        streamed = await _client.send(request).timeout(remainingTimeout());
        response = await http.Response.fromStream(
          streamed,
        ).timeout(remainingTimeout());
      } on TimeoutException {
        throw LocalSyncException(
          '请求 ${current.host} 超时（${requestTimeout.inSeconds} 秒），请检查网络后重试',
        );
      }
      cookieSource = mergeChaoxingResponseCookies(
        cookieSource,
        current,
        response.headers['set-cookie'],
      );
      if (session != null) {
        session.source = cookieSource;
      }
      if (!_isRedirect(response.statusCode)) {
        return response;
      }

      final location = response.headers['location'];
      if (location == null || location.trim().isEmpty) {
        return response;
      }
      if (redirects >= _maxCookieRedirects) {
        throw const LocalSyncException('学习通页面重定向次数过多');
      }

      final next = current.resolve(location);
      _ensureTrustedCookieTarget(next);
      current = next;
      redirects += 1;
      if (response.statusCode == 303 ||
          ((response.statusCode == 301 || response.statusCode == 302) &&
              currentMethod == 'POST')) {
        currentMethod = 'GET';
        bodyFields = null;
      }
    }
  }
}

void _ensureTrustedCookieTarget(Uri uri) {
  if (!isTrustedChaoxingUri(uri)) {
    throw const LocalSyncException('已跳过非学习通域名请求');
  }
}

bool _isRedirect(int statusCode) {
  return statusCode == 301 ||
      statusCode == 302 ||
      statusCode == 303 ||
      statusCode == 307 ||
      statusCode == 308;
}

bool detectLoginSignals(String url, String html) {
  return RegExp(
        r'passport2\.chaoxing\.com\/login',
        caseSensitive: false,
      ).hasMatch(url) ||
      RegExp(
        r'passport2\.chaoxing\.com\/login',
        caseSensitive: false,
      ).hasMatch(html) ||
      RegExp(
        r'<title[^>]*>\s*用户登录\s*<\/title>',
        caseSensitive: false,
      ).hasMatch(html) ||
      RegExp(r'''\bid=["']loginBtn["']''', caseSensitive: false).hasMatch(html);
}

String? extractPageTitle(String html) {
  final match = RegExp(
    r'<title[^>]*>([\s\S]*?)<\/title>',
    caseSensitive: false,
  ).firstMatch(html);
  if (match == null) {
    return null;
  }
  final title = _decodeBasicHtmlEntities(
    match.group(1)!,
  ).replaceAll(RegExp(r'\s+'), ' ').trim();
  return title.isEmpty ? null : title;
}

String? findInboxUrl(String html, String baseUrl) {
  final exact = RegExp(
    r'''https:\/\/notice\.chaoxing\.com\/pc\/notice\/myNotice\?s=[^"'\s<)]+''',
  ).firstMatch(html)?.group(0);
  if (exact != null) {
    return exact;
  }

  final relative = RegExp(
    r'''\/pc\/notice\/myNotice\?s=[^"'\s<)]+''',
  ).firstMatch(html)?.group(0);
  if (relative == null) {
    return null;
  }
  return Uri.parse(_noticeOrigin).resolve(relative).toString();
}

String? findCourseInteractionUrl(String html) {
  final matches = RegExp(
    r'''\bdataurl=["']([^"']*\/visit\/interaction[^"']*)["']''',
    caseSensitive: false,
  ).allMatches(html);
  for (final match in matches) {
    final raw = _decodeBasicHtmlEntities(match.group(1)!);
    final url = Uri.parse(_modernCourseListOrigin).resolve(raw).toString();
    if (isTrustedChaoxingUrl(url)) {
      return url;
    }
  }
  return null;
}

bool isAssignmentOrExamRelated(InboxMessage message) {
  return RegExp(
    r'作业|考试|测验|测试|截止|结束提醒|答题|试卷|练习',
  ).hasMatch('${message.title}\n${message.content ?? ''}');
}

List<String> extractNoticeLinks(String text) {
  final seen = <String>{};
  final links = <String>[];
  final decoded = _decodeBasicHtmlEntities(
    text,
  ).replaceAll(r'\/', '/').replaceAll(r'\u0026', '&');

  void addCandidate(String raw) {
    var candidate = raw.trim();
    if (candidate.startsWith('//')) {
      candidate = 'https:$candidate';
    }
    final parsed = Uri.tryParse(candidate);
    if (parsed == null) {
      return;
    }
    final resolved = Uri.parse(_noticeOrigin).resolveUri(parsed);
    if (!isTrustedChaoxingUri(resolved)) {
      return;
    }
    final link = resolved.toString();
    if (_isWorkOrExamLink(link) && seen.add(link)) {
      links.add(link);
    }
  }

  for (final match in RegExp(
    r'''(?:https?:)?//[^"'\s<>)\[\]\\]+''',
    caseSensitive: false,
  ).allMatches(decoded)) {
    addCandidate(match.group(0)!);
  }

  final fragment = html_parser.parseFragment(decoded);
  for (final element in fragment.querySelectorAll(
    '[href], [src], [data], [dataurl], [data-url]',
  )) {
    for (final name in const ['href', 'src', 'data', 'dataurl', 'data-url']) {
      final value = element.attributes[name];
      if (value != null) {
        addCandidate(value);
      }
    }
  }

  for (final match in RegExp(
    r'''["']((?:/|\.\.?/)[^"']*(?:work|exam)[^"']*)["']''',
    caseSensitive: false,
  ).allMatches(decoded)) {
    addCandidate(match.group(1)!);
  }
  return links;
}

Map<String, DetailSummary> collectUniqueWorkLinks(
  List<DetailSummary> summaries,
) {
  final unique = <String, DetailSummary>{};
  for (final summary in summaries) {
    for (final link in summary.assignmentLinks) {
      if (_isWorkOrExamLink(link) && !unique.containsKey(link)) {
        unique[link] = summary;
      }
    }
  }
  return unique;
}

List<CourseSpace> parseCourseSpaces(String body) {
  final htmlCourses = _parseCourseSpacesFromHtml(body);
  if (htmlCourses.isNotEmpty) {
    return htmlCourses;
  }

  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    throw const LocalSyncException('课程列表返回格式不正确');
  }

  final courses = <String, CourseSpace>{};
  void visit(Object? value, {String inheritedCpi = ''}) {
    if (value is List) {
      for (final child in value) {
        visit(child, inheritedCpi: inheritedCpi);
      }
      return;
    }
    if (value is! Map) {
      return;
    }

    final cpi = _firstMapText(value, const ['cpi', 'personId']) ?? inheritedCpi;
    final title =
        _firstMapText(value, const ['courseName', 'name', 'title']) ?? '';
    final rawUrl = _firstMapText(value, const [
      'courseSquareUrl',
      'courseUrl',
      'url',
    ]);
    final normalizedUrl = rawUrl == null
        ? null
        : _decodeBasicHtmlEntities(rawUrl).replaceAll(r'\/', '/');
    final courseId =
        (normalizedUrl == null
            ? null
            : _readUrlParamAny(normalizedUrl, const [
                'courseId',
                'courseid',
              ])) ??
        _firstMapText(value, const ['courseId', 'courseid']);
    final classId =
        (normalizedUrl == null
            ? null
            : _readUrlParamAny(normalizedUrl, const [
                'classId',
                'clazzId',
                'clazzid',
              ])) ??
        _firstMapText(value, const ['classId', 'clazzId', 'clazzid', 'key']);
    if (courseId != null && classId != null) {
      final key = '$courseId:$classId';
      courses[key] = CourseSpace(
        courseId: courseId,
        classId: classId,
        cpi: cpi,
        title: title.isEmpty ? '课程 $courseId' : title,
      );
    }

    for (final child in value.values) {
      visit(child, inheritedCpi: cpi);
    }
  }

  visit(decoded);
  if (courses.isEmpty) {
    throw const LocalSyncException('课程列表中未找到可同步课程');
  }
  return courses.values.toList();
}

List<CourseSpace> _parseCourseSpacesFromHtml(String body) {
  if (!body.contains('courseList') && !body.contains('courseid')) {
    return const [];
  }
  final document = html_parser.parse(body);
  final courses = <String, CourseSpace>{};
  for (final item in document.querySelectorAll('#courseList > li.course')) {
    final courseId = item.attributes['courseid']?.trim() ?? '';
    final classId = item.attributes['clazzid']?.trim() ?? '';
    final cpi = item.attributes['personid']?.trim() ?? '';
    if (courseId.isEmpty || classId.isEmpty || cpi.isEmpty) {
      continue;
    }
    final title = item.querySelector('.course-name')?.text.trim() ?? '';
    courses['$courseId:$classId'] = CourseSpace(
      courseId: courseId,
      classId: classId,
      cpi: cpi,
      title: title.isEmpty ? '课程 $courseId' : title,
    );
  }
  return courses.values.toList();
}

String buildCourseTaskListUrl(CourseSpace course, String source) {
  final path = source == 'course_exam'
      ? '/mooc-ans/exam/phone/task-list'
      : '/work/task-list';
  return Uri.parse('$_courseApiOrigin$path')
      .replace(
        queryParameters: {
          'courseId': course.courseId,
          'classId': course.classId,
          'cpi': course.cpi,
        },
      )
      .toString();
}

List<CourseTaskLink> parseCourseTaskLinks(
  String html,
  String baseUrl, {
  required String fallbackTitle,
}) {
  final linksByUrl = <String, CourseTaskLink>{};
  final document = html_parser.parse(html);
  for (final element in document.querySelectorAll('[href], [data]')) {
    final rawUrl = element.attributes['href'] ?? element.attributes['data'];
    if (rawUrl == null) {
      continue;
    }
    final url = _normalizeCourseTaskUrl(rawUrl, baseUrl);
    if (url == null) {
      continue;
    }
    String? selectedTitle;
    for (final selector in const [
      'p',
      'dl dt',
      '.course-name',
      '.task-title',
      '.title',
    ]) {
      final candidate = element.querySelector(selector)?.text.trim();
      if (candidate != null && candidate.isNotEmpty) {
        selectedTitle = candidate;
        break;
      }
    }
    final text = element.text.trim();
    final status = _inferListedTaskStatus(element, text);
    final candidate = CourseTaskLink(
      url: url,
      title: _normalizeWhitespace(
        selectedTitle ?? (text.isEmpty ? fallbackTitle : text),
      ),
      status: status,
    );
    final previous = linksByUrl[url];
    if (previous == null ||
        (previous.status == 'unknown' && status != 'unknown')) {
      linksByUrl[url] = candidate;
    }
  }

  // Keep a tolerant fallback for malformed task-list markup.
  final elementPattern = RegExp(
    r'''<(?:a|div|li)\b[^>]*\b(?:href|data)=["']([^"']+)["'][^>]*>([\s\S]*?)<\/(?:a|div|li)>''',
    caseSensitive: false,
  );
  for (final match in elementPattern.allMatches(html)) {
    final url = _normalizeCourseTaskUrl(match.group(1)!, baseUrl);
    if (url == null) {
      continue;
    }
    final title = _stripHtml(match.group(2)!);
    linksByUrl.putIfAbsent(
      url,
      () => CourseTaskLink(
        url: url,
        title: title.isEmpty ? fallbackTitle : title,
      ),
    );
  }

  final attributePattern = RegExp(
    r'''(?:href|data)=["']([^"']+)["']''',
    caseSensitive: false,
  );
  for (final match in attributePattern.allMatches(html)) {
    final url = _normalizeCourseTaskUrl(match.group(1)!, baseUrl);
    if (url != null) {
      linksByUrl.putIfAbsent(
        url,
        () => CourseTaskLink(url: url, title: fallbackTitle),
      );
    }
  }
  return linksByUrl.values.toList();
}

String _inferListedTaskStatus(html_dom.Element element, String text) {
  final normalized = _normalizeWhitespace(text);
  final imageMarksExpired = element
      .querySelectorAll('img')
      .any(
        (image) =>
            (image.attributes['src'] ?? '').toLowerCase().contains('ks_02'),
      );
  if (imageMarksExpired || RegExp(r'已过期|已结束|不可作答').hasMatch(normalized)) {
    return 'expired';
  }
  if (RegExp(r'待批阅|已提交').hasMatch(normalized)) {
    return 'submitted';
  }
  if (RegExp(r'已完成|已批阅').hasMatch(normalized)) {
    return 'completed';
  }
  return 'unknown';
}

String _normalizeWhitespace(String value) {
  return value.replaceAll(RegExp(r'\s+'), ' ').trim();
}

String? _normalizeCourseTaskUrl(String rawUrl, String baseUrl) {
  final decoded = _decodeBasicHtmlEntities(
    rawUrl,
  ).replaceAll(r'\/', '/').trim();
  final parsed = Uri.tryParse(decoded);
  if (parsed == null) {
    return null;
  }
  final resolved = Uri.parse(baseUrl).resolveUri(parsed);
  if (!isTrustedChaoxingUri(resolved)) {
    return null;
  }
  final text = resolved.toString();
  if (RegExp(r'\/task-list\b', caseSensitive: false).hasMatch(text)) {
    return null;
  }
  final hasTaskId =
      _readUrlParamAny(text, const ['taskrefId', 'workId', 'examId']) != null;
  final hasTaskPath = RegExp(
    r'\/(?:work|exam|exam-ans|mooc-ans)\b',
    caseSensitive: false,
  ).hasMatch(text);
  return hasTaskId && hasTaskPath ? text : null;
}

String? _firstMapText(Map map, List<String> keys) {
  for (final key in keys) {
    for (final entry in map.entries) {
      if (entry.key.toString().toLowerCase() == key.toLowerCase()) {
        final text = _nullableString(entry.value);
        if (text != null) {
          return text;
        }
      }
    }
  }
  return null;
}

String? _readUrlParamAny(String url, List<String> keys) {
  final uri = Uri.tryParse(url);
  if (uri == null) {
    return null;
  }
  for (final key in keys) {
    for (final entry in uri.queryParameters.entries) {
      if (entry.key.toLowerCase() == key.toLowerCase() &&
          entry.value.isNotEmpty) {
        return entry.value;
      }
    }
  }
  return null;
}

AssignmentRequirement parseAssignmentRequirement({
  required String html,
  required String entryUrl,
  required String finalUrl,
  required int status,
  required String sourceTitle,
  required String? sourceSendTime,
  required String? sourceContent,
  String source = 'inbox',
}) {
  final pageTitle = extractPageTitle(html);
  final timeWindow = _extractTimeWindow(html, sourceContent);
  return AssignmentRequirement(
    sourceTitle: sourceTitle,
    sourceSendTime: sourceSendTime,
    sourceContent: sourceContent,
    entryUrl: entryUrl,
    finalUrl: finalUrl,
    pageTitle: pageTitle,
    status: status,
    courseId: _readUrlParam(finalUrl, 'courseId'),
    classId: _readUrlParam(finalUrl, 'classId'),
    workId:
        _readUrlParam(finalUrl, 'workId') ??
        _readHiddenValue(html, 'workId') ??
        (source == 'course_work'
            ? _readUrlParam(finalUrl, 'taskrefId') ??
                  _readUrlParam(entryUrl, 'taskrefId')
            : null),
    answerId:
        _readUrlParam(finalUrl, 'answerId') ??
        _readHiddenValue(html, 'answerId'),
    workStatus: _inferWorkStatus(pageTitle, finalUrl, html),
    timeWindowStart: timeWindow.$1,
    timeWindowEnd: timeWindow.$2,
    source: source,
  );
}

SyncItem buildSyncItem(
  AssignmentRequirement requirement,
  DateTime generatedAt,
) {
  final dueAt = parseChaoxingDateTime(
    requirement.timeWindowEnd,
    requirement.sourceSendTime,
    generatedAt,
  );
  final startAt = parseChaoxingDateTime(
    requirement.timeWindowStart,
    requirement.sourceSendTime,
    generatedAt,
  );
  final kind = _inferKind(requirement);
  final examId =
      _readUrlParam(requirement.finalUrl, 'examId') ??
      _readUrlParam(requirement.finalUrl, 'taskrefId') ??
      _readUrlParam(requirement.entryUrl, 'examId') ??
      _readUrlParam(requirement.entryUrl, 'taskrefId');
  final stableId =
      requirement.workId ??
      examId ??
      _hashString(
        requirement.finalUrl.isNotEmpty
            ? requirement.finalUrl
            : requirement.entryUrl,
      );

  return SyncItem(
    id: '${kind.name}-$stableId',
    kind: kind,
    title: requirement.sourceTitle.isNotEmpty
        ? requirement.sourceTitle
        : requirement.pageTitle ?? (kind == SyncItemKind.exam ? '考试' : '作业'),
    url: requirement.finalUrl.isNotEmpty
        ? requirement.finalUrl
        : requirement.entryUrl,
    sourceTitle: requirement.sourceTitle,
    sourceSendTime: requirement.sourceSendTime,
    startAt: startAt,
    dueAt: dueAt,
    status: requirement.workStatus,
    displayStatus: SyncDisplayStatus.unscheduled,
    courseId: requirement.courseId,
    classId: requirement.classId,
    workId: requirement.workId,
    examId: kind == SyncItemKind.exam ? examId : null,
    answerId: requirement.answerId,
    sources: [requirement.source],
  );
}

DateTime? parseChaoxingDateTime(
  String? value,
  String? sourceSendTime,
  DateTime fallbackDate,
) {
  if (value == null || value.trim().isEmpty) {
    return null;
  }

  final normalized = value.trim().replaceAll('/', '-');
  final withYear = RegExp(
    r'^(\d{4})-(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?$',
  ).firstMatch(normalized);
  if (withYear != null) {
    return _dateFromParts(
      withYear.group(1)!,
      withYear.group(2)!,
      withYear.group(3)!,
      withYear.group(4)!,
      withYear.group(5)!,
      withYear.group(6) ?? '0',
    );
  }

  final withoutYear = RegExp(
    r'^(\d{1,2})-(\d{1,2})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?$',
  ).firstMatch(normalized);
  if (withoutYear != null) {
    final year = _inferYear(
      int.parse(withoutYear.group(1)!),
      sourceSendTime,
      fallbackDate,
    );
    return _dateFromParts(
      year.toString(),
      withoutYear.group(1)!,
      withoutYear.group(2)!,
      withoutYear.group(3)!,
      withoutYear.group(4)!,
      withoutYear.group(5) ?? '0',
    );
  }

  return DateTime.tryParse(normalized)?.toLocal();
}

Map<String, String> _htmlHeaders(String cookie, String referer) {
  return {
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.7',
    'Cache-Control': 'no-cache',
    'Cookie': cookie,
    'Pragma': 'no-cache',
    'Referer': referer,
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125 Safari/537.36',
  };
}

Map<String, String> _jsonHeaders(String cookie, String referer) {
  return {
    'Accept': 'application/json, text/javascript, */*; q=0.01',
    'Accept-Language': 'zh-CN,zh;q=0.9,en;q=0.7',
    'Cookie': cookie,
    'Referer': referer,
    'User-Agent': 'Mozilla/5.0',
  };
}

String _decodeBody(http.Response response) {
  return utf8.decode(response.bodyBytes);
}

class _NoticePage {
  const _NoticePage({
    required this.items,
    required this.topNotices,
    required this.urgentNotices,
    required this.lastGetId,
    required this.lastPage,
  });

  final List<Object?> items;
  final List<Object?> topNotices;
  final List<Object?> urgentNotices;
  final String lastGetId;
  final bool lastPage;
}

_NoticePage _extractNoticePage(Map data) {
  final containers = <Map>[data];
  var cursor = 0;
  while (cursor < containers.length && containers.length < 12) {
    final current = containers[cursor++];
    for (final key in const ['notices', 'data', 'result', 'page', 'payload']) {
      final child = _mapValue(current, key);
      if (child is Map && !containers.contains(child)) {
        containers.add(child);
      }
    }
  }

  List<Object?> readFirstList(List<String> keys) {
    for (final container in containers) {
      for (final key in keys) {
        final value = _mapValue(container, key);
        if (value is List) {
          return value;
        }
      }
    }
    return const [];
  }

  final directData = _mapValue(data, 'data');
  final items = directData is List
      ? directData
      : readFirstList(const ['list', 'rows', 'records', 'items', 'notices']);

  String firstText(List<String> keys) {
    for (final container in containers) {
      for (final key in keys) {
        final value = _nullableString(_mapValue(container, key));
        if (value != null) {
          return value;
        }
      }
    }
    return '';
  }

  bool firstTruthy(List<String> keys) {
    for (final container in containers) {
      for (final key in keys) {
        final value = _mapValue(container, key);
        if (value != null && _isTruthy(value)) {
          return true;
        }
      }
    }
    return false;
  }

  return _NoticePage(
    items: items,
    topNotices: readFirstList(const ['topNotices', 'topList']),
    urgentNotices: readFirstList(const ['urgentNotices', 'urgentList']),
    lastGetId: firstText(const [
      'lastGetId',
      'lastId',
      'nextId',
      'nextValue',
      'cursor',
      'nextCursor',
    ]),
    lastPage: firstTruthy(const ['lastPage', 'isLastPage', 'finished']),
  );
}

Map _extractNoticeDetail(Map decoded) {
  final containers = <Map>[decoded];
  var cursor = 0;
  while (cursor < containers.length && containers.length < 12) {
    final current = containers[cursor++];
    if (_mapValue(current, 'content') != null ||
        _mapValue(current, 'rtf_content') != null ||
        _mapValue(current, 'rtfContent') != null) {
      return current;
    }
    for (final key in const ['msg', 'data', 'detail', 'notice', 'result']) {
      final child = _mapValue(current, key);
      if (child is Map && !containers.contains(child)) {
        containers.add(child);
      }
    }
  }
  return containers.length > 1 ? containers[1] : decoded;
}

Iterable<String> _collectStringValues(Object? value, [int depth = 0]) sync* {
  if (depth > 8) {
    return;
  }
  if (value is String) {
    yield value;
    return;
  }
  if (value is Map) {
    for (final child in value.values) {
      yield* _collectStringValues(child, depth + 1);
    }
    return;
  }
  if (value is List) {
    for (final child in value) {
      yield* _collectStringValues(child, depth + 1);
    }
  }
}

Object? _mapValue(Map map, String key) {
  for (final entry in map.entries) {
    if (entry.key.toString().toLowerCase() == key.toLowerCase()) {
      return entry.value;
    }
  }
  return null;
}

bool _isTruthy(Object? value) {
  if (value == true || value == 1) {
    return true;
  }
  final text = _stringOrEmpty(value).trim().toLowerCase();
  return text == 'true' || text == '1' || text == 'ok' || text == 'success';
}

bool _hasSuccessfulApiStatus(Map response) {
  if (response.containsKey('status')) {
    return _isTruthy(response['status']);
  }
  if (response.containsKey('success')) {
    return _isTruthy(response['success']);
  }
  return false;
}

_InboxPageConfig _extractInboxPageConfig(String html) {
  return _InboxPageConfig(
    type: _extractWindowString(html, 'type') ?? '2',
    noticeType: _extractWindowString(html, 'noticeType') ?? '',
    year:
        _extractWindowString(html, 'nowYear') ?? DateTime.now().year.toString(),
    folderUuid: _extractWindowString(html, 'folderUUID') ?? '',
    fidsCode: _extractWindowString(html, 'fidsCode') ?? '',
  );
}

String? _extractWindowString(String html, String key) {
  return RegExp(
    '''window\\.$key\\s*=\\s*['"]([^'"]*)['"]''',
    caseSensitive: false,
  ).firstMatch(html)?.group(1);
}

InboxMessage _normalizeNotice(Map notice) {
  final id = _stringOrEmpty(notice['idCode']).isNotEmpty
      ? _stringOrEmpty(notice['idCode'])
      : _stringOrEmpty(notice['id']).isNotEmpty
      ? _stringOrEmpty(notice['id'])
      : _stringOrEmpty(notice['uuid']);
  final uuid = _nullableString(notice['uuid']);
  final sendTag = notice['sendTag'];
  final content = _stripHtml(
    _stringOrEmpty(notice['content']).isNotEmpty
        ? _stringOrEmpty(notice['content'])
        : _stringOrEmpty(notice['rtf_content']),
  );

  return InboxMessage(
    id: id,
    uuid: uuid,
    title: _stringOrEmpty(notice['title']).isNotEmpty
        ? _stringOrEmpty(notice['title'])
        : _readString(notice, 'noticeTitle', '(无标题)'),
    sender:
        _nullableString(notice['createrName']) ??
        _nullableString(notice['senderName']),
    sendTime:
        _nullableString(notice['sendTime']) ??
        _nullableString(notice['createTime']) ??
        _normalizeTimestamp(notice['insertTime']),
    isRead: notice['isread'] == true || notice['isread'] == 1,
    content: content.isEmpty ? null : content,
    detailUrl: id.isEmpty && uuid == null
        ? null
        : _buildDetailUrl(uuid ?? id, sendTag),
    sendTag: sendTag,
  );
}

String _buildDetailUrl(String id, Object? sendTag) {
  final url = Uri.parse('$_noticeOrigin/pc/notice/$id/detail');
  if (sendTag == null) {
    return url.toString();
  }
  return url
      .replace(queryParameters: {'sendTag': sendTag.toString()})
      .toString();
}

List<Object?> _decodeIframeNames(String html) {
  final names = RegExp(
    r'''<iframe\b[^>]*\bname=["']([^"']+)["'][^>]*>''',
    caseSensitive: false,
  ).allMatches(html).map((match) => match.group(1)!);
  final decoded = <Object?>[];

  for (final name in names) {
    final candidates = [
      () => jsonDecode(Uri.decodeComponent(name)),
      () => jsonDecode(utf8.decode(base64Decode(Uri.decodeComponent(name)))),
    ];
    for (final decode in candidates) {
      try {
        decoded.add(decode());
        break;
      } catch (_) {
        // Try the next encoding.
      }
    }
  }
  return decoded;
}

bool _isWorkOrExamLink(String link) {
  return RegExp(
        r'workOrExam=(?:work|exam)',
        caseSensitive: false,
      ).hasMatch(link) ||
      RegExp(
        r'\/(?:work|exam|exam-ans|mooc-ans)\b',
        caseSensitive: false,
      ).hasMatch(link) ||
      _readUrlParamAny(link, const [
            'taskrefId',
            'workId',
            'examId',
            'taskId',
            'jobid',
          ]) !=
          null;
}

(String?, String?) _extractTimeWindow(String html, String? sourceContent) {
  final htmlWindow = RegExp(
    r'作答时间[:：]\s*<em>([^<]+)<\/em>\s*至\s*<em>([^<]+)<\/em>',
  ).firstMatch(html);
  if (htmlWindow != null) {
    return (
      _normalizeChaoxingDateText(htmlWindow.group(1)!),
      _normalizeChaoxingDateText(htmlWindow.group(2)!),
    );
  }

  final text = [_stripHtml(html), _stripHtml(sourceContent ?? '')]
      .where((value) => value.isNotEmpty)
      .join('\n')
      .replaceAll(RegExp(r'\s+'), ' ');
  const dateTime =
      r'((?:\d{4}\s*[-/年]\s*)?\d{1,2}\s*[-/月]\s*\d{1,2}\s*(?:日)?\s+\d{1,2}:\d{2}(?::\d{2})?)';

  final contentWindow = RegExp(
    '开始时间\\s*[:：]?\\s*$dateTime[\\s\\S]*?结束时间\\s*[:：]?\\s*$dateTime',
  ).firstMatch(text);
  if (contentWindow != null) {
    return (
      _normalizeChaoxingDateText(contentWindow.group(1)!),
      _normalizeChaoxingDateText(contentWindow.group(2)!),
    );
  }

  final answerWindow = RegExp(
    '作答时间\\s*[:：]?\\s*$dateTime\\s*(?:至|-|到)\\s*$dateTime',
  ).firstMatch(text);
  if (answerWindow != null) {
    return (
      _normalizeChaoxingDateText(answerWindow.group(1)!),
      _normalizeChaoxingDateText(answerWindow.group(2)!),
    );
  }

  final singleDue = RegExp(
    '(?:提交截止时间|截止时间|结束时间|截止|结束)\\s*[:：]?\\s*$dateTime',
  ).firstMatch(text);
  if (singleDue != null) {
    return (null, _normalizeChaoxingDateText(singleDue.group(1)!));
  }
  return (null, null);
}

bool isActionableWorkStatus(String status) {
  return !const {
    'completed',
    'submitted',
    'expired',
    'view',
    'preview',
  }.contains(status.toLowerCase());
}

String _inferWorkStatus(String? pageTitle, String finalUrl, String html) {
  final pageText = _stripHtml(html);
  if (RegExp(r'已过期|已结束|不可作答').hasMatch(pageText)) {
    return 'expired';
  }
  if (RegExp(r'待批阅|已提交').hasMatch(pageText)) {
    return 'submitted';
  }
  if (RegExp(r'已完成|已批阅|查看答案').hasMatch(pageText)) {
    return 'completed';
  }
  if (finalUrl.contains('dowork') || pageTitle == '作业作答') {
    return 'answering';
  }
  if (finalUrl.contains('/work/view') || pageTitle == '作业详情') {
    return 'view';
  }
  if (finalUrl.contains('/work/preview') || pageTitle == '查看详情') {
    return 'preview';
  }
  if (pageTitle == '提示') {
    return 'prompt';
  }
  return 'unknown';
}

SyncItemKind _inferKind(AssignmentRequirement requirement) {
  final text =
      '${requirement.entryUrl}\n${requirement.finalUrl}\n${requirement.sourceTitle}\n${requirement.pageTitle ?? ''}';
  return RegExp(
        r'workOrExam=exam|\/exam\b|考试|测验|测试|试卷',
        caseSensitive: false,
      ).hasMatch(text)
      ? SyncItemKind.exam
      : SyncItemKind.assignment;
}

DateTime _dateFromParts(
  String year,
  String month,
  String day,
  String hour,
  String minute,
  String second,
) {
  String pad(String value) => value.padLeft(2, '0');
  return DateTime.parse(
    '$year-${pad(month)}-${pad(day)}T${pad(hour)}:${pad(minute)}:${pad(second)}+08:00',
  ).toLocal();
}

int _inferYear(int month, String? sourceSendTime, DateTime fallbackDate) {
  final source = sourceSendTime == null
      ? null
      : parseChaoxingDateTime(sourceSendTime, null, fallbackDate);
  final base = (source ?? fallbackDate).toLocal();
  final year = base.year;
  final sourceMonth = base.month;
  return sourceMonth == 12 && month == 1 ? year + 1 : year;
}

String? _readUrlParam(String url, String key) {
  return Uri.tryParse(url)?.queryParameters[key];
}

String? _readHiddenValue(String html, String id) {
  return RegExp(
    '''<input[^>]+id=["']${RegExp.escape(id)}["'][^>]+value=["']([^"']*)["']''',
    caseSensitive: false,
  ).firstMatch(html)?.group(1);
}

String _hashString(String value) {
  var hash = 5381;
  for (final code in value.codeUnits) {
    hash = ((hash * 33) ^ code) & 0xFFFFFFFF;
  }
  return hash.toRadixString(36);
}

String? _normalizeTimestamp(Object? value) {
  if (value == null) {
    return null;
  }
  final parsed = DateTime.tryParse(value.toString());
  return parsed?.toIso8601String() ?? value.toString();
}

int _normalizeLimit(int value, int fallback, int maximum) {
  if (value < 1) {
    return fallback;
  }
  return value > maximum ? maximum : value;
}

Future<void> _forEachConcurrent<T>(
  List<T> values,
  int concurrency,
  Future<void> Function(T value, int index) action,
) async {
  if (values.isEmpty) {
    return;
  }
  var nextIndex = 0;

  Future<void> worker() async {
    while (nextIndex < values.length) {
      final index = nextIndex;
      nextIndex += 1;
      await action(values[index], index);
    }
  }

  final workerCount = concurrency.clamp(1, values.length);
  await Future.wait(List.generate(workerCount, (_) => worker()));
}

String _readString(Map map, String key, String fallback) {
  final value = map[key];
  return value is String && value.isNotEmpty ? value : fallback;
}

String _stringOrEmpty(Object? value) => value == null ? '' : value.toString();

String? _nullableString(Object? value) {
  final text = _stringOrEmpty(value);
  return text.isEmpty ? null : text;
}

String _stripHtml(String value) {
  return _decodeBasicHtmlEntities(
    value
        .replaceAll(
          RegExp(r'<style[\s\S]*?<\/style>', caseSensitive: false),
          ' ',
        )
        .replaceAll(
          RegExp(r'<script[\s\S]*?<\/script>', caseSensitive: false),
          ' ',
        )
        .replaceAll(RegExp(r'<[^>]+>'), ' '),
  ).replaceAll(RegExp(r'\s+'), ' ').trim();
}

String _decodeBasicHtmlEntities(String value) {
  return value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&#160;', ' ')
      .replaceAll('&ensp;', ' ')
      .replaceAll('&emsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'");
}

String _normalizeChaoxingDateText(String value) {
  return _decodeBasicHtmlEntities(value)
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .replaceAllMapped(
        RegExp(r'^(\d{4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})\s*日?'),
        (match) => '${match.group(1)}-${match.group(2)}-${match.group(3)}',
      )
      .replaceAllMapped(
        RegExp(r'^(\d{1,2})\s*月\s*(\d{1,2})\s*日?'),
        (match) => '${match.group(1)}-${match.group(2)}',
      )
      .replaceAll('/', '-');
}

class _InboxPageConfig {
  const _InboxPageConfig({
    required this.type,
    required this.noticeType,
    required this.year,
    required this.folderUuid,
    required this.fidsCode,
  });

  final String type;
  final String noticeType;
  final String year;
  final String folderUuid;
  final String fidsCode;
}
