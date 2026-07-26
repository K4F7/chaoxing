import 'dart:io';

import 'package:chaoxing_app/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('reports a newer release without sending account information', () async {
    late http.Request captured;
    final service = UpdateService(
      currentBuildLoader: () async => 41,
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          '{"tag_name":"app-42-abcdef","html_url":"https://evil.example"}',
          HttpStatus.ok,
        );
      }),
    );

    final update = await service.check();

    expect(captured.url, trustedLatestReleaseApi);
    expect(
      captured.headers.keys.map((key) => key.toLowerCase()),
      isNot(contains('cookie')),
    );
    expect(captured.headers.values.join(' '), isNot(contains('fid=')));
    expect(update?.buildNumber, 42);
    expect(update?.releasePage, trustedReleasesPage);
  });

  test('stays silent for current, malformed, and failed responses', () async {
    Future<UpdateInfo?> check(http.Client client) => UpdateService(
      currentBuildLoader: () async => 42,
      client: client,
    ).check();

    expect(
      await check(
        MockClient(
          (_) async =>
              http.Response('{"tag_name":"app-42-current"}', HttpStatus.ok),
        ),
      ),
      isNull,
    );
    expect(
      await check(MockClient((_) async => http.Response('not-json', 200))),
      isNull,
    );
    expect(
      await check(MockClient((_) async => throw const SocketException('off'))),
      isNull,
    );
  });
}
