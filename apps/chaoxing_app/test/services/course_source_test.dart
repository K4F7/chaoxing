import 'dart:async';
import 'dart:convert';

import 'package:chaoxing_app/models/app_config.dart';
import 'package:chaoxing_app/models/course_catalog.dart';
import 'package:chaoxing_app/services/chaoxing_cookie_store.dart';
import 'package:chaoxing_app/services/local_sync_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('supplemental course sources are enabled by default', () {
    expect(AppConfig.empty.courseSourcesEnabled, isTrue);
    expect(AppConfig.empty.courseLimit, 20);
  });

  test('parses course spaces from backclazzdata response', () {
    final courses = parseCourseSpaces(
      jsonEncode({
        'channelList': [
          {
            'cpi': 9001,
            'content': {
              'course': {
                'data': [
                  {
                    'name': '线性代数',
                    'courseSquareUrl':
                        'https://mooc1.chaoxing.com/course?courseId=101&classId=202&userId=303',
                  },
                ],
              },
            },
          },
        ],
      }),
    );

    expect(courses, hasLength(1));
    expect(courses.single.courseId, '101');
    expect(courses.single.classId, '202');
    expect(courses.single.cpi, '9001');
    expect(courses.single.title, '线性代数');
  });

  test('parses course spaces from current courselistdata html', () {
    final courses = parseCourseSpaces('''
      <ul id="courseList">
        <li class="course" courseid="301" clazzid="401" personid="501">
          <div class="course-info">
            <a href="https://mooc2-ans.chaoxing.com/mooc2-ans/mycourse/stu?courseid=301&amp;clazzid=401&amp;cpi=501"></a>
            <h3 class="course-name">大学物理</h3>
          </div>
        </li>
      </ul>
    ''');

    expect(courses, hasLength(1));
    expect(courses.single.courseId, '301');
    expect(courses.single.classId, '401');
    expect(courses.single.cpi, '501');
    expect(courses.single.title, '大学物理');
  });

  test('uses current course endpoint before the legacy fallback', () async {
    final calls = <String>[];
    final runner = LocalSyncRunner(
      client: MockClient((request) async {
        calls.add('${request.method} ${request.url}');
        if (request.url.host == 'i.chaoxing.com') {
          return http.Response(
            '<div dataurl="https://mooc1-1.chaoxing.com/visit/interaction?courseId=1&amp;clazzId=2"></div>',
            200,
            headers: {'set-cookie': 'route=home; Path=/; HttpOnly'},
          );
        }
        if (request.url.path == '/visit/interaction') {
          expect(request.headers['Cookie'], isNot(contains('route=home')));
          expect(request.headers['Cookie'], contains('UID=1'));
          return http.Response(
            'course shell',
            200,
            headers: {'set-cookie': 'course_session=ready; Path=/'},
          );
        }
        expect(
          request.url.toString(),
          'https://mooc1-1.chaoxing.com/mooc-ans/visit/courselistdata',
        );
        expect(request.method, 'POST');
        expect(request.bodyFields['courseType'], '1');
        expect(request.headers['Cookie'], contains('course_session=ready'));
        return http.Response(
          '<ul id="courseList"><li class="course" courseid="1" '
          'clazzid="2" personid="3"><span class="course-name">测试课程</span>'
          '</li></ul>',
          200,
          headers: {'content-type': 'text/html; charset=utf-8'},
        );
      }),
    );

    final courses = await runner.fetchCourseSpaces('UID=1');

    expect(courses.single.title, '测试课程');
    expect(calls, hasLength(3));
  });

  test('runs course list requests concurrently without exceeding six', () async {
    final releaseLists = Completer<void>();
    final concurrentListsStarted = Completer<void>();
    var activeLists = 0;
    var maxActiveLists = 0;
    final calls = <String>[];
    final runner = LocalSyncRunner(
      client: MockClient((request) async {
        final url = request.url.toString();
        calls.add('${request.method} $url');
        if (request.url.host == 'i.chaoxing.com') {
          return http.Response(
            'https://notice.chaoxing.com/pc/notice/myNotice?s=parallel '
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
              'notices': {'list': <Object>[], 'lastPage': true},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path == '/visit/interaction') {
          return http.Response('course shell', 200);
        }
        if (request.url.path == '/mooc-ans/visit/courselistdata') {
          return http.Response(
            '<ul id="courseList">${List.generate(4, (index) {
              final id = index + 1;
              return '<li class="course" courseid="$id" clazzid="1" '
                  'personid="1"><span class="course-name">课程$id</span></li>';
            }).join()}</ul>',
            200,
            headers: {'content-type': 'text/html; charset=utf-8'},
          );
        }
        if (request.url.path == '/mycourse/backclazzdata') {
          return http.Response(
            jsonEncode({
              'channelList': List.generate(4, (index) {
                final id = index + 1;
                return {
                  'cpi': '1',
                  'content': {
                    'course': {
                      'data': [
                        {'name': '课程$id', 'courseId': '$id', 'classId': '1'},
                      ],
                    },
                  },
                };
              }),
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        if (request.url.path == '/work/task-list' ||
            request.url.path == '/mooc-ans/exam/phone/task-list') {
          activeLists += 1;
          maxActiveLists = maxActiveLists < activeLists
              ? activeLists
              : maxActiveLists;
          if (activeLists >= 3 && !concurrentListsStarted.isCompleted) {
            concurrentListsStarted.complete();
          }
          await releaseLists.future;
          activeLists -= 1;
          if (request.url.path == '/work/task-list' &&
              request.url.queryParameters['courseId'] == '4') {
            return http.Response('failed', 500);
          }
          return http.Response('<ul></ul>', 200);
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
        courseLimit: 4,
      ),
    );
    await concurrentListsStarted.future.timeout(
      const Duration(seconds: 2),
      onTimeout: () => throw StateError('calls=$calls active=$activeLists'),
    );
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(maxActiveLists, inInclusiveRange(3, 6));
    releaseLists.complete();

    final response = await sync;
    expect(response.stats.courses, 4);
    expect(response.stats.courseTaskLinksDiscovered, 0);
    expect(response.failures, hasLength(1));
    expect(activeLists, 0);
  });

  test('sync scans only monitored courses without rediscovery', () async {
    final calls = <String>[];
    final runner = LocalSyncRunner(
      clock: () => DateTime(2026, 7, 27, 10),
      client: MockClient((request) async {
        calls.add('${request.method} ${request.url}');
        if (request.url.host == 'i.chaoxing.com') {
          return http.Response(
            'https://notice.chaoxing.com/pc/notice/myNotice?s=monitored',
            200,
          );
        }
        if (request.url.host == 'notice.chaoxing.com' &&
            request.url.path == '/pc/notice/myNotice') {
          return http.Response("window.nowYear='2026';", 200);
        }
        if (request.url.path == '/pc/notice/getNoticeList') {
          return http.Response(
            jsonEncode({
              'status': true,
              'notices': {'list': <Object>[], 'lastPage': true},
            }),
            200,
          );
        }
        if (request.url.path == '/work/task-list' ||
            request.url.path == '/mooc-ans/exam/phone/task-list') {
          return http.Response('<ul></ul>', 200);
        }
        return http.Response('unexpected', 500);
      }),
    );
    final catalog = CourseCatalog(
      lastDiscoveredAt: DateTime(2026, 7, 27, 9),
      courses: const [
        CoursePreference(
          course: CourseSpace(
            courseId: 'monitored',
            classId: '1',
            cpi: '1',
            title: '受监控课程',
          ),
        ),
        CoursePreference(
          course: CourseSpace(
            courseId: 'ignored',
            classId: '2',
            cpi: '2',
            title: '已取消课程',
          ),
          monitored: false,
        ),
      ],
    );

    await runner.run(
      const AppConfig(
        cookie: 'UID=1',
        inboxPageLimit: 1,
        inboxItemLimit: 20,
        refreshMinutes: 60,
        remindersEnabled: true,
      ),
      courseCatalog: catalog,
    );

    expect(calls, isNot(anyElement(contains('/visit/interaction'))));
    final taskCalls = calls.where((call) => call.contains('task-list'));
    expect(taskCalls, hasLength(2));
    expect(taskCalls, everyElement(contains('courseId=monitored')));
    expect(taskCalls, isNot(anyElement(contains('courseId=ignored'))));
  });

  test('falls back to legacy course endpoint when current html fails', () async {
    final calls = <String>[];
    final runner = LocalSyncRunner(
      client: MockClient((request) async {
        calls.add('${request.method} ${request.url}');
        if (request.url.host == 'i.chaoxing.com') {
          return http.Response(
            '<div dataurl="https://mooc1-1.chaoxing.com/visit/interaction"></div>',
            200,
          );
        }
        if (request.url.path == '/visit/interaction') {
          return http.Response('course entry', 200);
        }
        if (request.url.host == 'mooc1-1.chaoxing.com') {
          return http.Response('temporarily unavailable', 503);
        }
        return http.Response(
          jsonEncode({
            'channelList': [
              {
                'cpi': '3',
                'content': {
                  'course': {
                    'data': [
                      {'name': '旧版课程', 'courseId': '1', 'classId': '2'},
                    ],
                  },
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final courses = await runner.fetchCourseSpaces('UID=1');

    expect(courses.single.title, '旧版课程');
    expect(calls, [
      'GET https://i.chaoxing.com/base?ws=1&t=1780231212848',
      'GET https://mooc1-1.chaoxing.com/visit/interaction',
      'POST https://mooc1-1.chaoxing.com/mooc-ans/visit/courselistdata',
      'GET https://mooc1-api.chaoxing.com/mycourse/backclazzdata',
    ]);
  });

  test('extracts trusted interaction entry and merges response cookies', () {
    final interaction = findCourseInteractionUrl(
      '<div dataurl="https://mooc1-1.chaoxing.com/visit/interaction?courseId=1&amp;clazzId=2"></div>',
    );
    final merged = mergeChaoxingResponseCookies(
      'UID=1; route=old',
      Uri.parse('https://mooc1-1.chaoxing.com/visit/interaction'),
      'route=new; Expires=Wed, 21 Oct 2026 07:28:00 GMT; Path=/; HttpOnly, '
          'course_session=ready; Path=/',
    );
    final scoped = cookieHeaderForChaoxingUri(
      merged,
      Uri.parse('https://mooc1-1.chaoxing.com/mooc-ans/visit/courselistdata'),
    );

    expect(interaction, contains('courseId=1&clazzId=2'));
    expect(scoped, contains('UID=1'));
    expect(scoped, contains('route=new'));
    expect(scoped, contains('course_session=ready'));
    expect(scoped, isNot(contains('Path=')));
    expect(scoped, isNot(contains('Expires=')));
  });

  test('resolves relative interaction entries but rejects foreign hosts', () {
    expect(
      findCourseInteractionUrl(
        '<div dataurl="/visit/interaction?courseId=1&amp;clazzId=2"></div>',
      ),
      'https://mooc1-1.chaoxing.com/visit/interaction?courseId=1&clazzId=2',
    );
    expect(
      findCourseInteractionUrl(
        '<div dataurl="https://evil.example/visit/interaction"></div>',
      ),
      isNull,
    );
  });

  test('keeps inherited cpi scoped to each course channel', () {
    final courses = parseCourseSpaces(
      jsonEncode({
        'channelList': [
          {
            'cpi': 9001,
            'content': {
              'course': {
                'data': [
                  {'name': '课程一', 'courseId': '101', 'classId': '201'},
                ],
              },
            },
          },
          {
            'cpi': 9002,
            'content': {
              'course': {
                'data': [
                  {'name': '课程二', 'courseId': '102', 'classId': '202'},
                ],
              },
            },
          },
        ],
      }),
    );

    expect(
      {for (final course in courses) course.courseId: course.cpi},
      {'101': '9001', '102': '9002'},
    );
  });

  test('extracts trusted work and exam task links from task page', () {
    final links = parseCourseTaskLinks(
      '''
      <a data="/mooc-ans/work/phone/task-work?taskrefId=11&amp;courseId=101&amp;classId=202">第一次作业</a>
      <li data="https://mooc1-api.chaoxing.com/exam-ans/exam/phone/task-exam?taskrefId=22&amp;courseId=101&amp;classId=202">期中考试</li>
      <a href="https://evil.example/work?workId=33">不可信链接</a>
      <a href="/work/task-list?courseId=101">列表自身</a>
      ''',
      'https://mooc1-api.chaoxing.com/work/task-list?courseId=101',
      fallbackTitle: '线性代数',
    );

    expect(links.map((link) => link.title), ['第一次作业', '期中考试']);
    expect(links[0].url, contains('taskrefId=11'));
    expect(links[1].url, contains('taskrefId=22'));
  });

  test('recognizes completed, submitted, and expired course tasks', () {
    final links = parseCourseTaskLinks(
      '''
      <ul id="chaoxing-assignment-wrapper">
        <li data="/mooc-ans/work/phone/task-work?taskrefId=11&amp;courseId=101">
          <p>待做作业</p><span class="status">未提交</span>
        </li>
        <li data="/mooc-ans/work/phone/task-work?taskrefId=12&amp;courseId=101">
          <p>作业二</p><span class="status">已完成</span>
        </li>
        <li data="/mooc-ans/work/phone/task-work?taskrefId=13&amp;courseId=101">
          <p>作业三</p><span class="status">待批阅</span>
        </li>
        <li data="/exam-ans/exam/phone/task-exam?taskrefId=14&amp;courseId=101">
          <div class="ks_pic"><img src="/images/ks_02.png"></div>
          <dl><dt>旧考试</dt></dl><span class="ks_state">已结束</span>
        </li>
      </ul>
      ''',
      'https://mooc1-api.chaoxing.com/work/task-list?courseId=101',
      fallbackTitle: '线性代数',
    );

    expect(links.map((link) => link.title), ['待做作业', '作业二', '作业三', '旧考试']);
    expect(links.map((link) => link.status), [
      'unknown',
      'completed',
      'submitted',
      'expired',
    ]);
    expect(links.map((link) => link.isActionable), [true, false, false, false]);
  });

  test('rejects arbitrary chaoxing subdomains for cookie-bearing requests', () {
    expect(isTrustedChaoxingUrl('https://mooc1.chaoxing.com/work'), isTrue);
    expect(isTrustedChaoxingUrl('https://mooc1-12.chaoxing.com/work'), isTrue);
    expect(isTrustedChaoxingUrl('https://evil.chaoxing.com/work'), isFalse);
    expect(isTrustedChaoxingUrl('http://mooc1.chaoxing.com/work'), isFalse);
  });

  test('uses taskrefId as stable work id for course work source', () {
    final requirement = parseAssignmentRequirement(
      html: '<title>作业作答</title><p>截止时间：2026-07-20 23:59</p>',
      entryUrl:
          'https://mooc1-api.chaoxing.com/mooc-ans/work/phone/task-work?taskrefId=11&courseId=101&classId=202',
      finalUrl:
          'https://mooc1-api.chaoxing.com/mooc-ans/work/phone/task-work?taskrefId=11&courseId=101&classId=202',
      status: 200,
      sourceTitle: '第一次作业',
      sourceSendTime: null,
      sourceContent: null,
      source: 'course_work',
    );
    final item = buildSyncItem(requirement, DateTime(2026, 7, 16));

    expect(item.id, 'assignment-11');
    expect(item.workId, '11');
    expect(item.sources, ['course_work']);
  });

  test('marks explicitly completed detail pages as non-actionable', () {
    final requirement = parseAssignmentRequirement(
      html: '<title>作业详情</title><div class="status">已完成</div>',
      entryUrl: 'https://mooc1.chaoxing.com/work?workId=99',
      finalUrl: 'https://mooc1.chaoxing.com/work/view?workId=99',
      status: 200,
      sourceTitle: '已完成作业',
      sourceSendTime: null,
      sourceContent: null,
    );

    expect(requirement.workStatus, 'completed');
    expect(isActionableWorkStatus(requirement.workStatus), isFalse);
  });

  test('treats read-only detail states as completed work', () {
    expect(isActionableWorkStatus('view'), isFalse);
    expect(isActionableWorkStatus('preview'), isFalse);
    expect(isActionableWorkStatus('prompt'), isTrue);
    expect(isActionableWorkStatus('unknown'), isTrue);
  });
}
