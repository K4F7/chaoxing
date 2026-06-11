import 'dart:convert';

import 'package:chaoxing_app/models/app_config.dart';
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

  test('runs local sync and builds sorted app response', () async {
    final calls = <String>[];
    final runner = LocalSyncRunner(
      clock: () => DateTime.parse('2026-06-05T09:00:00+08:00'),
      client: MockClient((request) async {
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

    final response = await runner.run(
      const AppConfig(
        cookie: 'UID=1',
        inboxPageLimit: 2,
        inboxItemLimit: 20,
        refreshMinutes: 60,
        remindersEnabled: true,
      ),
    );

    expect(response.authStatus, 'ok');
    expect(response.items.map((item) => item.id), ['assignment-1', 'exam-2']);
    expect(response.items.first.displayStatus, SyncDisplayStatus.today);
    expect(response.items.first.dueInHours, 15);
    expect(response.items.last.displayStatus, SyncDisplayStatus.upcoming);
    expect(
      calls,
      contains('POST https://notice.chaoxing.com/pc/notice/getNoticeList'),
    );
  });

  test('parses chaoxing time without year using source send time', () {
    final parsed = parseChaoxingDateTime(
      '01-02 08:30',
      '2025-12-01 00:30:00',
      DateTime.parse('2025-12-31T12:00:00Z'),
    );

    expect(parsed?.toUtc().toIso8601String(), '2026-01-02T00:30:00.000Z');
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
