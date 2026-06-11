import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_config.dart';
import '../models/app_sync_response.dart';
import '../models/sync_item.dart';

const defaultChaoxingHomeUrl =
    'https://i.chaoxing.com/base?ws=1&t=1780231212848';
const _noticeOrigin = 'https://notice.chaoxing.com';
const _maxCookieRedirects = 5;

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
}

class LocalSyncRunner {
  LocalSyncRunner({
    http.Client? client,
    DateTime Function()? clock,
    this._homeUrl = defaultChaoxingHomeUrl,
  }) : _client = client ?? http.Client(),
       _clock = clock ?? DateTime.now;

  final http.Client _client;
  final DateTime Function() _clock;
  final String _homeUrl;

  Future<AppSyncResponse> run(AppConfig config) async {
    final cookie = config.cookie.trim();
    if (cookie.isEmpty) {
      throw const LocalSyncException('请先在设置中填入学习通 Cookie');
    }

    final auth = await checkAuth(cookie);
    if (!auth.authenticated) {
      throw const LocalSyncException('Cookie 已失效或跳转到登录页，请重新登录后更新 Cookie');
    }

    final inbox = await fetchInboxMessages(
      cookie: cookie,
      itemLimit: config.inboxItemLimit,
      pageLimit: config.inboxPageLimit,
    );
    final relevant = inbox.messages.where(isAssignmentOrExamRelated).toList();
    final summaries = <DetailSummary>[];
    for (final message in relevant.take(config.inboxItemLimit)) {
      summaries.add(await fetchDetailSummary(message: message, cookie: cookie));
    }

    final unique = collectUniqueWorkLinks(summaries);
    final items = <SyncItem>[];
    final failures = <AppSyncFailure>[];
    for (final entry in unique.entries) {
      try {
        final requirement = await fetchAssignmentRequirement(
          entryUrl: entry.key,
          summary: entry.value,
          cookie: cookie,
        );
        final item = buildSyncItem(requirement, _clock());
        if (item != null) {
          items.add(item);
        }
      } catch (error) {
        failures.add(
          AppSyncFailure(
            entryUrl: entry.key,
            sourceTitle: entry.value.title,
            message: error is LocalSyncException
                ? _redactSecret(error.message, cookie)
                : '作业详情解析失败',
          ),
        );
      }
    }

    final now = _clock();
    return AppSyncResponse.build(
      now: now,
      lastSyncedAt: now,
      items: items,
      failures: failures,
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
      finalUrl: finalUrl,
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

      if (data['status'] != true) {
        throw LocalSyncException(_readString(data, 'msg', '通知列表抓取失败'));
      }

      final notices = data['notices'] is Map ? data['notices'] as Map : {};
      final rawMessages = <Object?>[
        if (lastGetId.isEmpty) ..._readList(data['topNotices']),
        if (lastGetId.isEmpty) ..._readList(data['urgentNotices']),
        ..._readList(notices['list']),
      ];

      for (final notice in rawMessages) {
        if (messages.length >= normalizedItemLimit) {
          break;
        }
        if (notice is Map) {
          messages.add(_normalizeNotice(notice));
        }
      }

      lastGetId = _stringOrEmpty(notices['lastGetId']);
      lastPage =
          notices['lastPage'] == true ||
          notices['lastPage'] == 1 ||
          rawMessages.isEmpty ||
          lastGetId.isEmpty;
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
    if (decoded['status'] != true) {
      throw const LocalSyncException('通知详情接口返回失败');
    }
    final detail = decoded['msg'] is Map ? decoded['msg'] as Map : {};
    final content = _stripHtml(
      _stringOrEmpty(detail['content']).isNotEmpty
          ? _stringOrEmpty(detail['content'])
          : _stringOrEmpty(detail['rtf_content']),
    );
    final rtf = _stringOrEmpty(detail['rtf_content']);
    final decodedAttachments = _decodeIframeNames(rtf);
    final links = extractNoticeLinks('$rtf\n${jsonEncode(decodedAttachments)}');

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
    );
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
  }) {
    return _sendWithCookie('GET', uri, headers: headers);
  }

  Future<http.Response> _postFormWithCookie(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, String> body,
  }) {
    return _sendWithCookie('POST', uri, headers: headers, bodyFields: body);
  }

  Future<http.Response> _sendWithCookie(
    String method,
    Uri uri, {
    required Map<String, String> headers,
    Map<String, String>? bodyFields,
  }) async {
    var current = uri;
    var currentMethod = method;
    var redirects = 0;

    while (true) {
      _ensureTrustedCookieTarget(current);
      final request = http.Request(currentMethod, current)
        ..followRedirects = false
        ..headers.addAll(headers);
      if (bodyFields != null && currentMethod == 'POST') {
        request.bodyFields = bodyFields;
      }

      final streamed = await _client.send(request);
      final response = await http.Response.fromStream(streamed);
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

bool isTrustedChaoxingUrl(String url) {
  final uri = Uri.tryParse(url);
  return uri != null && _isTrustedChaoxingUri(uri);
}

bool _isTrustedChaoxingUri(Uri uri) {
  if (uri.scheme.toLowerCase() != 'https') {
    return false;
  }
  final host = uri.host.toLowerCase();
  return host == 'chaoxing.com' || host.endsWith('.chaoxing.com');
}

void _ensureTrustedCookieTarget(Uri uri) {
  if (!_isTrustedChaoxingUri(uri)) {
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

bool isAssignmentOrExamRelated(InboxMessage message) {
  return RegExp(
    r'作业|考试|测验|测试|截止|结束提醒|答题|试卷|练习',
  ).hasMatch('${message.title}\n${message.content ?? ''}');
}

List<String> extractNoticeLinks(String text) {
  final seen = <String>{};
  final links = <String>[];
  for (final match in RegExp(
    r'''https?:\\?\/\\?\/[^"'\s<>)\[\]\\]+''',
  ).allMatches(text)) {
    final link = match.group(0)!.replaceAll(r'\/', '/');
    if (RegExp(
          r'(exam|work|homework|task|mooc1|course|clazz|classId|courseId|examOrWork)',
          caseSensitive: false,
        ).hasMatch(link) &&
        seen.add(link)) {
      links.add(link);
    }
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

AssignmentRequirement parseAssignmentRequirement({
  required String html,
  required String entryUrl,
  required String finalUrl,
  required int status,
  required String sourceTitle,
  required String? sourceSendTime,
  required String? sourceContent,
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
        _readUrlParam(finalUrl, 'workId') ?? _readHiddenValue(html, 'workId'),
    answerId:
        _readUrlParam(finalUrl, 'answerId') ??
        _readHiddenValue(html, 'answerId'),
    workStatus: _inferWorkStatus(pageTitle, finalUrl),
    timeWindowStart: timeWindow.$1,
    timeWindowEnd: timeWindow.$2,
  );
}

SyncItem? buildSyncItem(
  AssignmentRequirement requirement,
  DateTime generatedAt,
) {
  final dueAt = parseChaoxingDateTime(
    requirement.timeWindowEnd,
    requirement.sourceSendTime,
    generatedAt,
  );
  if (dueAt == null) {
    return null;
  }
  final startAt = parseChaoxingDateTime(
    requirement.timeWindowStart,
    requirement.sourceSendTime,
    generatedAt,
  );
  final kind = _inferKind(requirement);
  final stableId =
      requirement.workId ??
      _readUrlParam(requirement.finalUrl, 'examId') ??
      _readUrlParam(requirement.entryUrl, 'examId') ??
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
    answerId: requirement.answerId,
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
      RegExp(r'\/(?:work|exam)\b', caseSensitive: false).hasMatch(link);
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

String _inferWorkStatus(String? pageTitle, String finalUrl) {
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

List<Object?> _readList(Object? value) {
  return value is List ? value : const [];
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

String _redactSecret(String message, String secret) {
  final trimmed = secret.trim();
  return trimmed.isEmpty ? message : message.replaceAll(trimmed, '[已隐藏]');
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
