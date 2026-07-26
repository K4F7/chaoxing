import 'dart:async';
import 'dart:convert';

import 'package:chaoxing_app/models/app_config.dart';
import 'package:chaoxing_app/models/app_sync_response.dart';
import 'package:chaoxing_app/models/sync_item.dart';
import 'package:chaoxing_app/services/local_sync_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('detects rendered chaoxing login pages during auth check', () async {
    final runner = LocalSyncRunner(
      client: MockClient(
        (_) async => http.Response(
          '<title>用户登录</title><button id="loginBtn">登录</button>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        ),
      ),
    );

    final result = await runner.checkAuth('UID=1');

    expect(result.authenticated, isFalse);
    expect(result.loginDetected, isTrue);
    expect(result.title, '用户登录');
  });

  test(
    'filters assignment notices and extracts work links from detail html',
    () async {
      final attachment = Uri.encodeComponent(
        base64Encode(
          utf8.encode(
            jsonEncode({
              'url': 'https://mooc1.chaoxing.com/work?workOrExam=work&workId=1',
            }),
          ),
        ),
      );
      final runner = LocalSyncRunner(
        client: MockClient((request) async {
          expect(request.headers['Cookie'], 'UID=1');
          return http.Response(
            jsonEncode({
              'status': true,
              'msg': {
                'title': '作业通知',
                'rtf_content': '<iframe name="$attachment"></iframe>',
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final summary = await runner.fetchDetailSummary(
        cookie: 'UID=1',
        message: const InboxMessage(
          id: 'notice-1',
          uuid: null,
          title: '作业通知',
          sender: null,
          sendTime: '2026-06-01 08:00:00',
          isRead: false,
          content: null,
          detailUrl: null,
          sendTag: 0,
        ),
      );

      expect(
        isAssignmentOrExamRelated(
          const InboxMessage(
            id: '2',
            uuid: null,
            title: '普通消息',
            sender: null,
            sendTime: null,
            isRead: false,
            content: '请完成作业',
            detailUrl: null,
            sendTag: 0,
          ),
        ),
        isTrue,
      );
      expect(summary.assignmentLinks, [
        'https://mooc1.chaoxing.com/work?workOrExam=work&workId=1',
      ]);
    },
  );

  test(
    'accepts nested rows and string success in notice list responses',
    () async {
      final runner = LocalSyncRunner(
        client: MockClient((request) async {
          final url = request.url.toString();
          if (url.startsWith('https://i.chaoxing.com/base')) {
            return http.Response(
              'https://notice.chaoxing.com/pc/notice/myNotice?s=nested',
              200,
            );
          }
          if (url.startsWith(
            'https://notice.chaoxing.com/pc/notice/myNotice',
          )) {
            return http.Response("window.nowYear='2026';", 200);
          }
          return http.Response(
            jsonEncode({
              'status': 'true',
              'data': {
                'rows': [
                  {'id': 'nested-1', 'noticeTitle': '作业通知', 'content': '请完成作业'},
                ],
                'finished': 1,
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );

      final result = await runner.fetchInboxMessages(
        cookie: 'UID=1',
        itemLimit: 20,
        pageLimit: 2,
      );

      expect(result.pagesFetched, 1);
      expect(result.messages.single.id, 'nested-1');
      expect(result.messages.single.title, '作业通知');
    },
  );

  test(
    'extracts links from nested detail and protocol-relative URLs',
    () async {
      final runner = LocalSyncRunner(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'success': '1',
              'data': {
                'detail': {
                  'rtfContent':
                      '<a href="//mooc1.chaoxing.com/work?workId=88">查看作业</a>',
                },
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );

      final summary = await runner.fetchDetailSummary(
        cookie: 'UID=1',
        message: const InboxMessage(
          id: 'nested-detail',
          uuid: null,
          title: '作业通知',
          sender: null,
          sendTime: null,
          isRead: false,
          content: null,
          detailUrl: null,
          sendTag: 0,
        ),
      );

      expect(summary.assignmentLinks, [
        'https://mooc1.chaoxing.com/work?workId=88',
      ]);
    },
  );

  test('rejects untrusted assignment entry without sending cookie', () async {
    var requested = false;
    final runner = LocalSyncRunner(
      client: MockClient((request) async {
        requested = true;
        return http.Response('should not request', 500);
      }),
    );

    await expectLater(
      runner.fetchAssignmentRequirement(
        entryUrl: 'https://evil.example/work?workId=1',
        cookie: 'UID=secret; vc=token',
        summary: const DetailSummary(
          title: '作业通知',
          sendTime: null,
          content: null,
          assignmentLinks: [],
        ),
      ),
      throwsA(
        isA<LocalSyncException>().having(
          (error) => error.message,
          'message',
          isNot(contains('UID=secret')),
        ),
      ),
    );
    expect(requested, isFalse);
  });

  test(
    'rejects untrusted assignment redirect before resending cookie',
    () async {
      final calls = <http.BaseRequest>[];
      final runner = LocalSyncRunner(
        client: MockClient((request) async {
          calls.add(request);
          if (request.url.host == 'mooc1.chaoxing.com') {
            expect(request.headers['Cookie'], 'UID=secret; vc=token');
            return http.Response(
              '',
              302,
              headers: {'location': 'https://evil.example/steal'},
              request: request,
            );
          }
          fail('unexpected request to ${request.url}');
        }),
      );

      await expectLater(
        runner.fetchAssignmentRequirement(
          entryUrl: 'https://mooc1.chaoxing.com/work?workId=1',
          cookie: 'UID=secret; vc=token',
          summary: const DetailSummary(
            title: '作业通知',
            sendTime: null,
            content: null,
            assignmentLinks: [],
          ),
        ),
        throwsA(isA<LocalSyncException>()),
      );

      expect(calls.map((request) => request.url.host), ['mooc1.chaoxing.com']);
    },
  );

  test('keeps trusted redirect cookies within their response host', () async {
    final calls = <http.BaseRequest>[];
    final runner = LocalSyncRunner(
      client: MockClient((request) async {
        calls.add(request);
        if (request.url.path == '/work') {
          return http.Response(
            '',
            302,
            headers: {
              'location': '/work/final?workId=1',
              'set-cookie': 'hop=ready; Path=/; HttpOnly',
            },
            request: request,
          );
        }
        expect(request.headers['Cookie'], contains('UID=1'));
        expect(request.headers['Cookie'], contains('hop=ready'));
        return http.Response(
          '<title>作业作答</title><p>截止时间：2026-07-20 23:59</p>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
          request: request,
        );
      }),
    );

    final requirement = await runner.fetchAssignmentRequirement(
      entryUrl: 'https://mooc1.chaoxing.com/work?workId=1',
      cookie: 'UID=1',
      summary: const DetailSummary(
        title: '作业通知',
        sendTime: null,
        content: null,
        assignmentLinks: [],
      ),
    );

    expect(requirement.finalUrl, contains('/work/final'));
    expect(calls, hasLength(2));
  });

  test('does not resend account cookies to the login host', () async {
    final runner = LocalSyncRunner(
      client: MockClient((request) async {
        if (request.url.host == 'i.chaoxing.com') {
          expect(request.headers['Cookie'], contains('UID=1'));
          return http.Response(
            '',
            302,
            headers: {'location': 'https://passport2.chaoxing.com/login'},
            request: request,
          );
        }
        expect(request.url.host, 'passport2.chaoxing.com');
        expect(request.headers['Cookie'], isNull);
        return http.Response(
          '<title>用户登录</title><button id="loginBtn">登录</button>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
          request: request,
        );
      }),
    );

    final auth = await runner.checkAuth('UID=1');

    expect(auth.authenticated, isFalse);
    expect(auth.loginDetected, isTrue);
  });

  test('fails detail summary when API status is not true', () async {
    final runner = LocalSyncRunner(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'status': false, 'msg': 'UID=secret'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

    await expectLater(
      runner.fetchDetailSummary(
        cookie: 'UID=secret',
        message: const InboxMessage(
          id: 'notice-1',
          uuid: null,
          title: '作业通知',
          sender: null,
          sendTime: null,
          isRead: false,
          content: null,
          detailUrl: null,
          sendTag: 0,
        ),
      ),
      throwsA(
        isA<LocalSyncException>().having(
          (error) => error.message,
          'message',
          allOf(contains('通知详情接口返回失败'), isNot(contains('UID=secret'))),
        ),
      ),
    );
  });

  test('fails detail summary when API success status is missing', () async {
    final runner = LocalSyncRunner(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'msg': {'rtf_content': 'https://mooc1.chaoxing.com/work?workId=1'},
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        ),
      ),
    );

    await expectLater(
      runner.fetchDetailSummary(
        cookie: 'UID=1',
        message: const InboxMessage(
          id: 'notice-1',
          uuid: null,
          title: '作业通知',
          sender: null,
          sendTime: null,
          isRead: false,
          content: null,
          detailUrl: null,
          sendTag: 0,
        ),
      ),
      throwsA(isA<LocalSyncException>()),
    );
  });

  test('fails notice list when API success status is missing', () async {
    final runner = LocalSyncRunner(
      client: MockClient((request) async {
        final url = request.url.toString();
        if (url.startsWith('https://i.chaoxing.com/base')) {
          return http.Response(
            'https://notice.chaoxing.com/pc/notice/myNotice?s=missing',
            200,
          );
        }
        if (url.startsWith('https://notice.chaoxing.com/pc/notice/myNotice')) {
          return http.Response("window.nowYear='2026';", 200);
        }
        return http.Response(
          jsonEncode({
            'notices': {
              'list': [
                {'id': 'notice-1', 'title': '作业通知'},
              ],
              'lastPage': true,
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    await expectLater(
      runner.fetchInboxMessages(cookie: 'UID=1', itemLimit: 20, pageLimit: 1),
      throwsA(isA<LocalSyncException>()),
    );
  });

  test('runs local sync and builds sorted app response', () async {
    final calls = <String>[];
    final runner = LocalSyncRunner(
      clock: () => DateTime.parse('2026-06-05T09:00:00+08:00'),
      client: MockClient((request) async {
        await Future<void>.delayed(const Duration(milliseconds: 2));
        final url = request.url.toString();
        calls.add('${request.method} $url');

        if (url.startsWith('https://i.chaoxing.com/base')) {
          return http.Response(
            '个人空间 https://notice.chaoxing.com/pc/notice/myNotice?s=abc123',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }

        if (url.startsWith('https://notice.chaoxing.com/pc/notice/myNotice')) {
          return http.Response(
            "window.nowYear='2026';",
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }

        if (request.method == 'POST' &&
            url == 'https://notice.chaoxing.com/pc/notice/getNoticeList') {
          return http.Response(
            jsonEncode({
              'status': true,
              'notices': {
                'list': [
                  {
                    'id': 'notice-later',
                    'title': '考试通知',
                    'sendTime': '2026-06-01 08:00:00',
                    'content': '考试安排',
                    'sendTag': 0,
                  },
                  {
                    'id': 'notice-soon',
                    'title': '作业通知',
                    'sendTime': '2026-06-01 08:00:00',
                    'content': '作业安排',
                    'sendTag': 0,
                  },
                ],
                'lastPage': true,
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        if (url.contains('notice-later/getNoticeDetail')) {
          return http.Response(
            jsonEncode({
              'status': true,
              'msg': {
                'rtf_content':
                    'https://mooc1.chaoxing.com/exam?workOrExam=exam&examId=2',
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        if (url.contains('notice-soon/getNoticeDetail')) {
          return http.Response(
            jsonEncode({
              'status': true,
              'msg': {
                'rtf_content':
                    'https://mooc1.chaoxing.com/work?workOrExam=work&workId=1',
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        if (url.startsWith('https://mooc1.chaoxing.com/exam')) {
          return http.Response(
            '<title>考试</title><div>作答时间:<em>06-06 09:00</em>至<em>06-06 10:00</em></div>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }

        if (url.startsWith('https://mooc1.chaoxing.com/work')) {
          return http.Response(
            '<title>作业作答</title><input id="workId" value="1" />'
            '<div>作答时间:<em>06-05 10:00</em>至<em>06-05 23:59</em></div>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }

        return http.Response('not found', 404);
      }),
    );

    final progress = <SyncProgress>[];
    final response = await runner.run(
      const AppConfig(
        cookie: 'UID=1',
        inboxPageLimit: 2,
        inboxItemLimit: 20,
        refreshMinutes: 60,
        remindersEnabled: true,
      ),
      onProgress: progress.add,
    );

    expect(response.authStatus, 'ok');
    expect(response.stats.durationMs, greaterThan(0));
    expect(response.stats.authenticationMs, greaterThan(0));
    expect(response.stats.inboxMs, greaterThan(0));
    expect(response.stats.noticeDetailsMs, greaterThan(0));
    expect(response.stats.assignmentDetailsMs, greaterThan(0));
    expect(
      response.stats.authenticationMs +
          response.stats.inboxMs +
          response.stats.noticeDetailsMs +
          response.stats.assignmentDetailsMs +
          response.stats.coursesMs,
      lessThanOrEqualTo(response.stats.durationMs),
    );
    expect(response.items.map((item) => item.id), ['assignment-1', 'exam-2']);
    expect(response.items.first.displayStatus, SyncDisplayStatus.today);
    expect(response.items.first.dueInHours, 15);
    expect(response.items.last.displayStatus, SyncDisplayStatus.upcoming);
    final progressive = progress.firstWhere(
      (entry) => entry.partialItems.isNotEmpty,
    );
    expect(progressive.partialItems.map((item) => item.id), [
      'assignment-1',
      'exam-2',
    ]);
    expect(
      progressive.partialItems.map((item) => item.status),
      everyElement('details_loading'),
    );
    expect(
      progress.map((entry) => entry.phase),
      containsAllInOrder([
        SyncPhase.authentication,
        SyncPhase.inbox,
        SyncPhase.noticeDetails,
        SyncPhase.assignmentDetails,
        SyncPhase.courses,
        SyncPhase.finalizing,
      ]),
    );
    expect(
      calls,
      contains('POST https://notice.chaoxing.com/pc/notice/getNoticeList'),
    );
  });

  test('requests the chaoxing home page once per sync', () async {
    final calls = <String>[];
    final runner = LocalSyncRunner(
      clock: () => DateTime.parse('2026-06-05T09:00:00+08:00'),
      client: MockClient((request) async {
        final url = request.url.toString();
        calls.add('${request.method} $url');

        if (url.startsWith('https://i.chaoxing.com/base')) {
          return http.Response(
            '个人空间 https://notice.chaoxing.com/pc/notice/myNotice?s=shared '
            '<div dataurl="https://mooc1-1.chaoxing.com/visit/interaction"></div>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }

        if (url.startsWith('https://notice.chaoxing.com/pc/notice/myNotice')) {
          return http.Response("window.nowYear='2026';", 200);
        }

        if (request.method == 'POST' &&
            url == 'https://notice.chaoxing.com/pc/notice/getNoticeList') {
          return http.Response(
            jsonEncode({
              'status': true,
              'notices': {
                'list': [
                  {
                    'id': 'notice-shared',
                    'title': '作业通知',
                    'sendTime': '2026-06-01 08:00:00',
                    'sendTag': 0,
                  },
                ],
                'lastPage': true,
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        if (url.contains('/getNoticeDetail')) {
          return http.Response(
            jsonEncode({
              'status': true,
              'msg': {
                'rtf_content':
                    'https://mooc1.chaoxing.com/work?workOrExam=work&workId=1',
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }

        if (url.startsWith('https://mooc1.chaoxing.com/work?')) {
          return http.Response(
            '<title>作业作答</title><input id="workId" value="1" />'
            '<p>截止时间：2026-06-20 23:59</p>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }

        if (request.url.path == '/visit/interaction') {
          return http.Response('course shell', 200);
        }

        if (request.url.path == '/mooc-ans/visit/courselistdata') {
          return http.Response(
            '<ul id="courseList"><li class="course" courseid="1" clazzid="2" '
            'personid="3"><span class="course-name">测试课程</span></li></ul>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }

        if (request.url.path == '/work/task-list' ||
            request.url.path == '/mooc-ans/exam/phone/task-list') {
          return http.Response('<ul></ul>', 200);
        }

        return http.Response('not found', 404);
      }),
    );

    final response = await runner.run(
      const AppConfig(
        cookie: 'UID=1',
        inboxPageLimit: 1,
        inboxItemLimit: 20,
        refreshMinutes: 60,
        remindersEnabled: true,
      ),
    );

    expect(
      calls.where((call) => call.contains('i.chaoxing.com/base')),
      hasLength(1),
    );
    expect(response.authStatus, 'ok');
    expect(response.stats.inboxMessages, 1);
    expect(response.stats.courses, 1);
    expect(response.items.map((item) => item.id), ['assignment-1']);
    expect(response.failures, isEmpty);
  });

  group('notice detail reuse', () {
    /// Serves an inbox whose listing is driven by [listedNotices], so a second
    /// sync can present a mix of already-parsed and brand new notices.
    MockClient noticeClient({
      required List<String> Function() listedNotices,
      required List<String> calls,
      String noticeContent = '作业安排',
      Set<String> Function()? failingDetails,
    }) {
      return MockClient((request) async {
        final url = request.url.toString();
        calls.add('${request.method} $url');

        if (url.startsWith('https://i.chaoxing.com/base')) {
          return http.Response(
            '个人空间 https://notice.chaoxing.com/pc/notice/myNotice?s=reuse',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
        if (url.startsWith('https://notice.chaoxing.com/pc/notice/myNotice')) {
          return http.Response("window.nowYear='2026';", 200);
        }
        if (request.method == 'POST' &&
            url == 'https://notice.chaoxing.com/pc/notice/getNoticeList') {
          return http.Response(
            jsonEncode({
              'status': true,
              'notices': {
                'list': [
                  for (final id in listedNotices())
                    {
                      'id': id,
                      'title': '作业通知 $id',
                      'sendTime': '2026-06-01 08:00:00',
                      'sendTag': 0,
                    },
                ],
                'lastPage': true,
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        final detail = RegExp(
          r'/pc/notice/([^/]+)/getNoticeDetail',
        ).firstMatch(url);
        if (detail != null) {
          final id = detail.group(1)!;
          if (failingDetails?.call().contains(id) ?? false) {
            return http.Response('detail unavailable', 500);
          }
          return http.Response(
            jsonEncode({
              'status': true,
              'msg': {
                'content': noticeContent,
                'rtf_content':
                    'https://mooc1.chaoxing.com/work?workOrExam=work&workId=$id',
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (url.startsWith('https://mooc1.chaoxing.com/work?')) {
          final id = request.url.queryParameters['workId']!;
          return http.Response(
            '<title>作业作答</title><input id="workId" value="$id" />',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
        return http.Response('not found', 404);
      });
    }

    const config = AppConfig(
      cookie: 'UID=1',
      inboxPageLimit: 1,
      inboxItemLimit: 20,
      refreshMinutes: 60,
      remindersEnabled: true,
      courseSourcesEnabled: false,
    );

    test(
      'skips detail requests for notices parsed by an earlier sync',
      () async {
        final calls = <String>[];
        var listed = ['notice-1'];
        final runner = LocalSyncRunner(
          clock: () => DateTime.parse('2026-06-05T09:00:00+08:00'),
          client: noticeClient(listedNotices: () => listed, calls: calls),
        );

        final first = await runner.run(config);
        expect(
          calls.where((call) => call.contains('notice-1/getNoticeDetail')),
          hasLength(1),
        );

        listed = ['notice-2', 'notice-1'];
        calls.clear();
        final second = await runner.run(config, previous: first);

        expect(
          calls.where((call) => call.contains('notice-1/getNoticeDetail')),
          isEmpty,
        );
        expect(
          calls.where((call) => call.contains('notice-2/getNoticeDetail')),
          hasLength(1),
        );
        expect(second.stats.detailSummaries, 2);
        expect(second.failures, isEmpty);
        expect(second.items.map((item) => item.id), [
          'assignment-notice-1',
          'assignment-notice-2',
        ]);
        expect(
          calls.where((call) => call.contains('mooc1.chaoxing.com/work')),
          hasLength(2),
        );
      },
    );

    test('reuse keeps a deadline that only the notice body carries', () async {
      final calls = <String>[];
      final runner = LocalSyncRunner(
        clock: () => DateTime.parse('2026-06-05T09:00:00+08:00'),
        client: noticeClient(
          listedNotices: () => ['notice-1'],
          calls: calls,
          noticeContent: '开始时间：06-18 08:00\n结束时间：06-20 23:59',
        ),
      );

      final first = await runner.run(config);
      final second = await runner.run(config, previous: first);

      expect(first.items.single.dueAt, isNotNull);
      expect(second.items.single.dueAt, first.items.single.dueAt);
      expect(second.items.single.startAt, first.items.single.startAt);
    });

    test('retries a notice whose detail fetch failed', () async {
      final calls = <String>[];
      var failing = {'notice-1'};
      final runner = LocalSyncRunner(
        clock: () => DateTime.parse('2026-06-05T09:00:00+08:00'),
        client: noticeClient(
          listedNotices: () => ['notice-1'],
          calls: calls,
          failingDetails: () => failing,
        ),
      );

      final first = await runner.run(config);
      expect(first.failures, hasLength(1));
      expect(first.items, isEmpty);

      failing = {};
      calls.clear();
      final second = await runner.run(config, previous: first);

      expect(
        calls.where((call) => call.contains('notice-1/getNoticeDetail')),
        hasLength(1),
      );
      expect(second.failures, isEmpty);
      expect(second.items.map((item) => item.id), ['assignment-notice-1']);
    });
  });

  group('inbox paging', () {
    /// Serves one notice list page per entry of [pages], newest page first, and
    /// never reports a last page — so only the page limit or an early stop ends
    /// the walk. Every notice carries its deadline in its own task page.
    MockClient pagingClient({
      required List<String> calls,
      required List<List<String>> Function() pages,
      Set<String> Function()? failingDetails,
      String Function(String id)? titleFor,
    }) {
      return MockClient((request) async {
        final url = request.url.toString();
        calls.add('${request.method} $url');

        if (url.startsWith('https://i.chaoxing.com/base')) {
          return http.Response(
            '个人空间 https://notice.chaoxing.com/pc/notice/myNotice?s=paging',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
        if (url.startsWith('https://notice.chaoxing.com/pc/notice/myNotice')) {
          return http.Response("window.nowYear='2026';", 200);
        }
        if (request.method == 'POST' &&
            url == 'https://notice.chaoxing.com/pc/notice/getNoticeList') {
          final lastValue = request.bodyFields['lastValue'] ?? '';
          final index = lastValue.isEmpty
              ? 0
              : int.parse(lastValue.substring(1));
          final page = pages();
          return http.Response(
            jsonEncode({
              'status': true,
              'notices': {
                'list': [
                  if (index < page.length)
                    for (final id in page[index])
                      {
                        'id': id,
                        'title': titleFor?.call(id) ?? '作业通知 $id',
                        'sendTime': '2026-06-01 08:00:00',
                        'sendTag': 7,
                      },
                ],
                'lastGetId': 'p${index + 1}',
                'lastPage': false,
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        final detail = RegExp(
          r'/pc/notice/([^/]+)/getNoticeDetail',
        ).firstMatch(url);
        if (detail != null) {
          if (failingDetails?.call().contains(detail.group(1)) == true) {
            return http.Response('failed', 500);
          }
          return http.Response(
            jsonEncode({
              'status': true,
              'msg': {
                'content': '作业安排',
                'rtf_content':
                    'https://mooc1.chaoxing.com/work?workOrExam=work'
                    '&workId=${detail.group(1)}',
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (url.startsWith('https://mooc1.chaoxing.com/work?')) {
          final id = request.url.queryParameters['workId']!;
          return http.Response(
            '<title>作业作答</title><input id="workId" value="$id" />'
            '<p>截止时间：2026-06-20 23:59</p>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
        return http.Response('not found', 404);
      });
    }

    const config = AppConfig(
      cookie: 'UID=1',
      inboxPageLimit: 3,
      inboxItemLimit: 20,
      refreshMinutes: 60,
      remindersEnabled: true,
      courseSourcesEnabled: false,
    );

    Iterable<String> noticeListCalls(List<String> calls) =>
        calls.where((call) => call.endsWith('/getNoticeList'));

    test('walks up to the page limit when nothing was seen yet', () async {
      final calls = <String>[];
      final runner = LocalSyncRunner(
        clock: () => DateTime.parse('2026-06-05T09:00:00+08:00'),
        client: pagingClient(
          calls: calls,
          pages: () => [
            ['n1'],
            ['n2'],
            ['n3'],
          ],
        ),
      );

      final response = await runner.run(config);

      expect(noticeListCalls(calls), hasLength(3));
      expect(response.items.map((item) => item.id), [
        'assignment-n1',
        'assignment-n2',
        'assignment-n3',
      ]);
    });

    test('stops paging on the page that repeats a seen notice', () async {
      final calls = <String>[];
      var pages = [
        ['n1'],
        ['n2'],
        ['n3'],
      ];
      final runner = LocalSyncRunner(
        clock: () => DateTime.parse('2026-06-05T09:00:00+08:00'),
        client: pagingClient(calls: calls, pages: () => pages),
      );

      final first = await runner.run(config);

      pages = [
        ['n4', 'n1'],
        ['n2'],
        ['n3'],
      ];
      calls.clear();
      final second = await runner.run(config, previous: first);

      expect(noticeListCalls(calls), hasLength(1));
      expect(second.items.map((item) => item.id), contains('assignment-n4'));
    });

    test('stops after the later page that repeats a seen notice', () async {
      final calls = <String>[];
      var pages = [
        ['n1'],
        ['n2'],
        ['n3'],
      ];
      final runner = LocalSyncRunner(
        clock: () => DateTime.parse('2026-06-05T09:00:00+08:00'),
        client: pagingClient(calls: calls, pages: () => pages),
      );

      final first = await runner.run(config);

      pages = [
        ['n5'],
        ['n4', 'n1'],
        ['n2'],
      ];
      calls.clear();
      final second = await runner.run(config, previous: first);

      expect(noticeListCalls(calls), hasLength(2));
      expect(
        second.items.map((item) => item.id),
        containsAll(['assignment-n4', 'assignment-n5']),
      );
    });

    test('an early stop leaves the todo set unchanged', () async {
      final calls = <String>[];
      var pages = [
        ['n1'],
        ['n2'],
        ['n3'],
      ];
      final runner = LocalSyncRunner(
        clock: () => DateTime.parse('2026-06-05T09:00:00+08:00'),
        client: pagingClient(calls: calls, pages: () => pages),
      );

      final first = await runner.run(config);

      pages = [
        ['n4', 'n1'],
        ['n2'],
        ['n3'],
      ];
      final second = await runner.run(config, previous: first);

      expect(second.items.map((item) => item.id), [
        'assignment-n1',
        'assignment-n2',
        'assignment-n3',
        'assignment-n4',
      ]);
      expect(second.failures, isEmpty);
      for (final id in ['n1', 'n2', 'n3', 'n4']) {
        expect(
          second.items
              .firstWhere((item) => item.id == 'assignment-$id')
              .dueAt
              ?.toUtc(),
          DateTime.parse('2026-06-20T15:59:00Z'),
        );
      }

      final carried = second.items.firstWhere(
        (item) => item.id == 'assignment-n2',
      );
      final listed = first.items.firstWhere(
        (item) => item.id == 'assignment-n2',
      );
      expect(carried.sourceTitle, listed.sourceTitle);
      expect(carried.sourceSendTime, listed.sourceSendTime);
      expect(carried.sourceSendTime, isNotNull);
    });

    test('an early stop retries an unparsed seen notice', () async {
      final calls = <String>[];
      var pages = [
        ['n1'],
        ['n2'],
        ['n3'],
      ];
      var failingDetails = {'n2'};
      final runner = LocalSyncRunner(
        clock: () => DateTime.parse('2026-06-05T09:00:00+08:00'),
        client: pagingClient(
          calls: calls,
          pages: () => pages,
          failingDetails: () => failingDetails,
        ),
      );

      final first = await runner.run(config);
      expect(first.failures, hasLength(1));
      expect(
        first.items.map((item) => item.id),
        isNot(contains('assignment-n2')),
      );

      pages = [
        ['n4', 'n1'],
        ['n2'],
        ['n3'],
      ];
      failingDetails = {};
      calls.clear();
      final second = await runner.run(config, previous: first);

      expect(noticeListCalls(calls), hasLength(1));
      expect(
        calls.where((call) => call.contains('n2/getNoticeDetail?sendTag=7')),
        hasLength(1),
      );
      expect(second.failures, isEmpty);
      expect(second.items.map((item) => item.id), contains('assignment-n2'));
    });

    test('a page limit still retries an unparsed seen notice', () async {
      final calls = <String>[];
      var pages = [
        ['n1'],
        ['n2'],
      ];
      var failingDetails = {'n2'};
      final runner = LocalSyncRunner(
        clock: () => DateTime.parse('2026-06-05T09:00:00+08:00'),
        client: pagingClient(
          calls: calls,
          pages: () => pages,
          failingDetails: () => failingDetails,
        ),
      );
      const pageLimitedConfig = AppConfig(
        cookie: 'UID=1',
        inboxPageLimit: 2,
        inboxItemLimit: 20,
        refreshMinutes: 60,
        remindersEnabled: true,
        courseSourcesEnabled: false,
      );

      final first = await runner.run(pageLimitedConfig);
      expect(first.failures, hasLength(1));

      pages = [
        ['n3'],
        ['n4'],
      ];
      failingDetails = {};
      calls.clear();
      final second = await runner.run(pageLimitedConfig, previous: first);

      expect(noticeListCalls(calls), hasLength(2));
      expect(
        calls.where((call) => call.contains('n2/getNoticeDetail?sendTag=7')),
        hasLength(1),
      );
      expect(second.failures, isEmpty);
      expect(second.items.map((item) => item.id), contains('assignment-n2'));
    });

    test('a failed retry keeps the latest seen notice metadata', () async {
      final calls = <String>[];
      final runner = LocalSyncRunner(
        clock: () => DateTime.parse('2026-06-05T09:00:00+08:00'),
        client: pagingClient(
          calls: calls,
          pages: () => [
            ['n2'],
          ],
          failingDetails: () => {'n2'},
        ),
      );
      final previous = AppSyncResponse(
        lastSyncedAt: DateTime.parse('2026-06-04T09:00:00+08:00'),
        authStatus: 'ok',
        items: const [],
        failures: const [],
        seenNotices: const [SeenNotice(id: 'n2', sendTag: 1, title: '旧标题')],
      );

      final response = await runner.run(config, previous: previous);

      expect(response.failures, hasLength(1));
      expect(response.seenNotices.single.sendTag, 7);
      expect(response.seenNotices.single.title, '作业通知 n2');
    });

    test('an unrelated seen notice does not consume a carry slot', () async {
      final calls = <String>[];
      var pages = [
        ['noise', 'old2', 'trigger'],
      ];
      final runner = LocalSyncRunner(
        clock: () => DateTime.parse('2026-06-05T09:00:00+08:00'),
        client: pagingClient(
          calls: calls,
          pages: () => pages,
          titleFor: (id) => id == 'noise' ? '系统公告' : '作业通知 $id',
        ),
      );
      const limitedConfig = AppConfig(
        cookie: 'UID=1',
        inboxPageLimit: 1,
        inboxItemLimit: 3,
        refreshMinutes: 60,
        remindersEnabled: true,
        courseSourcesEnabled: false,
      );
      final first = await runner.run(limitedConfig);

      pages = [
        ['new', 'trigger'],
      ];
      calls.clear();
      final second = await runner.run(limitedConfig, previous: first);

      expect(
        calls.where((call) => call.contains('noise/getNoticeDetail')),
        isEmpty,
      );
      expect(second.items.map((item) => item.id), contains('assignment-old2'));
    });
  });

  test('blames the auth phase when the shared home page fails', () async {
    final calls = <String>[];
    final runner = LocalSyncRunner(
      client: MockClient((request) async {
        calls.add('${request.method} ${request.url}');
        return http.Response('temporarily unavailable', 503);
      }),
    );

    await expectLater(
      runner.run(
        const AppConfig(
          cookie: 'UID=1',
          inboxPageLimit: 1,
          inboxItemLimit: 20,
          refreshMinutes: 60,
          remindersEnabled: true,
        ),
      ),
      throwsA(
        isA<LocalSyncException>().having(
          (error) => error.message,
          'message',
          contains('登录已失效'),
        ),
      ),
    );
    expect(calls, ['GET https://i.chaoxing.com/base?ws=1&t=1780231212848']);
  });

  test(
    'limits notice detail concurrency and isolates individual failures',
    () async {
      final releaseDetails = Completer<void>();
      final sixDetailsStarted = Completer<void>();
      var activeDetails = 0;
      var maxActiveDetails = 0;
      final runner = LocalSyncRunner(
        client: MockClient((request) async {
          final url = request.url.toString();
          if (url.startsWith('https://i.chaoxing.com/base')) {
            return http.Response(
              'https://notice.chaoxing.com/pc/notice/myNotice?s=parallel',
              200,
            );
          }
          if (url.startsWith(
            'https://notice.chaoxing.com/pc/notice/myNotice',
          )) {
            return http.Response("window.nowYear='2026';", 200);
          }
          if (request.method == 'POST' &&
              url == 'https://notice.chaoxing.com/pc/notice/getNoticeList') {
            return http.Response(
              jsonEncode({
                'status': true,
                'notices': {
                  'list': List.generate(
                    8,
                    (index) => {
                      'id': 'notice-$index',
                      'title': '作业通知 $index',
                      'sendTag': 0,
                    },
                  ),
                  'lastPage': true,
                },
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          if (url.contains('/getNoticeDetail')) {
            activeDetails += 1;
            maxActiveDetails = maxActiveDetails < activeDetails
                ? activeDetails
                : maxActiveDetails;
            if (activeDetails == 6 && !sixDetailsStarted.isCompleted) {
              sixDetailsStarted.complete();
            }
            await releaseDetails.future;
            activeDetails -= 1;
            if (url.contains('notice-3/')) {
              return http.Response('failed', 500);
            }
            return http.Response(
              jsonEncode({
                'status': true,
                'msg': {'content': '没有链接'},
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return http.Response('not found', 404);
        }),
      );

      final sync = runner.run(
        const AppConfig(
          cookie: 'UID=1',
          inboxPageLimit: 1,
          inboxItemLimit: 20,
          refreshMinutes: 60,
          remindersEnabled: true,
          courseSourcesEnabled: false,
        ),
      );
      await sixDetailsStarted.future.timeout(const Duration(seconds: 2));
      expect(maxActiveDetails, 6);
      releaseDetails.complete();

      final response = await sync;
      expect(response.stats.relevantNotices, 8);
      expect(response.stats.detailSummaries, 7);
      expect(response.failures, hasLength(1));
      expect(activeDetails, 0);
    },
  );

  test('caps inbox assignment detail concurrency at six', () async {
    final releaseAssignments = Completer<void>();
    final sixAssignmentsStarted = Completer<void>();
    var activeAssignments = 0;
    var maxActiveAssignments = 0;
    final runner = LocalSyncRunner(
      client: MockClient((request) async {
        final url = request.url.toString();
        if (url.startsWith('https://i.chaoxing.com/base')) {
          return http.Response(
            'https://notice.chaoxing.com/pc/notice/myNotice?s=assignments',
            200,
          );
        }
        if (url.startsWith('https://notice.chaoxing.com/pc/notice/myNotice')) {
          return http.Response("window.nowYear='2026';", 200);
        }
        if (request.method == 'POST' &&
            url == 'https://notice.chaoxing.com/pc/notice/getNoticeList') {
          return http.Response(
            jsonEncode({
              'status': true,
              'notices': {
                'list': List.generate(
                  10,
                  (index) => {
                    'id': 'notice-$index',
                    'title': '作业通知 $index',
                    'sendTag': 0,
                  },
                ),
                'lastPage': true,
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (url.contains('/getNoticeDetail')) {
          final id = RegExp(r'notice-(\d+)').firstMatch(url)!.group(1)!;
          return http.Response(
            jsonEncode({
              'status': true,
              'msg': {
                'rtf_content': 'https://mooc1.chaoxing.com/work?workId=$id',
              },
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.host == 'mooc1.chaoxing.com' &&
            request.url.path == '/work') {
          activeAssignments += 1;
          maxActiveAssignments = maxActiveAssignments < activeAssignments
              ? activeAssignments
              : maxActiveAssignments;
          if (activeAssignments == 6 && !sixAssignmentsStarted.isCompleted) {
            sixAssignmentsStarted.complete();
          }
          await releaseAssignments.future;
          activeAssignments -= 1;
          final id = request.url.queryParameters['workId']!;
          return http.Response(
            '<title>作业作答</title><input id="workId" value="$id" />'
            '<p>截止时间：2026-07-20 23:59</p>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
        return http.Response('not found', 404);
      }),
    );

    final sync = runner.run(
      const AppConfig(
        cookie: 'UID=1',
        inboxPageLimit: 1,
        inboxItemLimit: 20,
        refreshMinutes: 60,
        remindersEnabled: true,
        courseSourcesEnabled: false,
      ),
    );
    await sixAssignmentsStarted.future.timeout(const Duration(seconds: 2));
    expect(maxActiveAssignments, 6);
    releaseAssignments.complete();

    final response = await sync;
    expect(response.items, hasLength(10));
    expect(response.failures, isEmpty);
    expect(activeAssignments, 0);
  });

  test('parses chaoxing time without year using source send time', () {
    final parsed = parseChaoxingDateTime(
      '01-02 08:30',
      '2025-12-01 00:30:00',
      DateTime.parse('2025-12-31T12:00:00Z'),
    );

    expect(parsed?.toUtc().toIso8601String(), '2026-01-02T00:30:00.000Z');
  });

  test('fails a stalled request with a safe timeout error', () async {
    final runner = LocalSyncRunner(
      requestTimeout: const Duration(milliseconds: 10),
      client: MockClient((_) => Completer<http.Response>().future),
    );

    await expectLater(
      runner.checkAuth('UID=secret'),
      throwsA(
        isA<LocalSyncException>().having(
          (error) => error.message,
          'message',
          allOf(contains('请求 i.chaoxing.com 超时'), isNot(contains('secret'))),
        ),
      ),
    );
  });

  test('applies one timeout budget to the full redirect chain', () async {
    var calls = 0;
    final runner = LocalSyncRunner(
      requestTimeout: const Duration(milliseconds: 100),
      client: MockClient((request) async {
        calls += 1;
        await Future<void>.delayed(const Duration(milliseconds: 70));
        if (calls == 1) {
          return http.Response(
            '',
            302,
            headers: {'location': '/next'},
            request: request,
          );
        }
        return http.Response('ok', 200, request: request);
      }),
    );

    await expectLater(
      runner.checkAuth('UID=1'),
      throwsA(isA<LocalSyncException>()),
    );
    expect(calls, 2);
  });

  test('keeps assignments whose deadline cannot be parsed', () {
    const requirement = AssignmentRequirement(
      sourceTitle: '高等数学作业',
      sourceSendTime: null,
      sourceContent: null,
      entryUrl: 'https://mooc1.chaoxing.com/work?workId=9',
      finalUrl: 'https://mooc1.chaoxing.com/work?workId=9',
      pageTitle: '作业',
      status: 200,
      courseId: '1',
      classId: '2',
      workId: '9',
      answerId: null,
      workStatus: 'answering',
      timeWindowStart: null,
      timeWindowEnd: null,
    );

    final item = buildSyncItem(requirement, DateTime(2026, 7, 16));

    expect(item.id, 'assignment-9');
    expect(item.dueAt, isNull);
    expect(item.displayStatus, SyncDisplayStatus.unscheduled);
  });

  test('resolves relative inbox links against notice host', () {
    expect(
      findInboxUrl(
        '<a href="/pc/notice/myNotice?s=abc123">收件箱</a>',
        'https://i.chaoxing.com/base',
      ),
      'https://notice.chaoxing.com/pc/notice/myNotice?s=abc123',
    );
  });

  test('extracts time windows from chaoxing text fixtures', () {
    final cases = [
      (
        html:
            '<div>作答时间：<em>2026年6月1日 08:00</em>\n至<em>2026年6月2日 23:59</em></div>',
        content: null,
        start: '2026-6-1 08:00',
        end: '2026-6-2 23:59',
      ),
      (
        html: '',
        content: '开始时间：06-01 08:00\n结束时间：06-02 23:59',
        start: '06-01 08:00',
        end: '06-02 23:59',
      ),
      (
        html: '<p>提交截止时间&nbsp;：&nbsp;2026年6月10日&nbsp;23:59</p>',
        content: null,
        start: null,
        end: '2026-6-10 23:59',
      ),
      (html: '', content: '结束时间：06月12日 18:30', start: null, end: '06-12 18:30'),
    ];

    for (final fixture in cases) {
      final requirement = parseAssignmentRequirement(
        html: fixture.html,
        entryUrl: 'https://mooc1.chaoxing.com/work?workId=1',
        finalUrl: 'https://mooc1.chaoxing.com/work?workId=1',
        status: 200,
        sourceTitle: '作业通知',
        sourceSendTime: '2026-06-01 08:00:00',
        sourceContent: fixture.content,
      );

      expect(requirement.timeWindowStart, fixture.start);
      expect(requirement.timeWindowEnd, fixture.end);
    }
  });
}
