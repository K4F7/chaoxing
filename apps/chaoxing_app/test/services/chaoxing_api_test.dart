import 'package:chaoxing_app/models/app_config.dart';
import 'package:chaoxing_app/services/chaoxing_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('fetches app sync payload with bearer token', () async {
    late http.Request captured;
    final api = ChaoxingApi(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          '''
          {
            "lastSyncedAt": "2026-06-05T08:00:00.000Z",
            "authStatus": "ok",
            "items": [
              {
                "id": "exam-1",
                "kind": "exam",
                "title": "期末测验",
                "url": "https://example.com/exam",
                "sourceTitle": "考试通知",
                "status": "answering",
                "displayStatus": "upcoming",
                "dueAt": "2026-06-06T10:00:00.000Z",
                "dueInHours": 24
              }
            ],
            "failures": []
          }
          ''',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final response = await api.fetchAppSync(
      const AppConfig(
        baseUrl: 'https://worker.example.com/',
        token: 'secret',
        refreshMinutes: 60,
      ),
    );

    expect(captured.url.toString(), 'https://worker.example.com/app/sync');
    expect(captured.headers['Authorization'], 'Bearer secret');
    expect(response.items.single.title, '期末测验');
  });

  test('turns unauthorized responses into a user-facing exception', () async {
    final api = ChaoxingApi(
      client: MockClient((_) async => http.Response('unauthorized', 401)),
    );

    expect(
      () => api.fetchAppSync(
        const AppConfig(
          baseUrl: 'https://worker.example.com',
          token: 'bad',
          refreshMinutes: 60,
        ),
      ),
      throwsA(isA<ChaoxingApiException>()),
    );
  });
}
