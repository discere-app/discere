import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'test_utils.dart';

/// [initializeIntegrationTest] installs `OfflineHttpOverrides`, which every
/// other integration test relies on to stay off the network. A server on
/// loopback answers at once, so a connection that is merely bounded in time
/// would reach it; only one refused before it is made never does. The
/// request count is what tells the two apart.
void main() {
  initializeIntegrationTest();

  group('offline HTTP overrides', () {
    late HttpServer server;
    late int requestsReceived;
    late Uri serverUrl;

    setUp(() async {
      requestsReceived = 0;
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) {
        requestsReceived++;
        request.response
          ..statusCode = HttpStatus.ok
          ..write('reached');
        request.response.close();
      });
      serverUrl = Uri.http('${server.address.address}:${server.port}', '/');
    });

    tearDown(() async {
      await server.close(force: true);
    });

    testWidgets(
      'an HttpClient has its connection to a loopback server refused before '
      'a request is sent',
      (tester) async {
        final client = HttpClient();
        addTearDown(() => client.close(force: true));

        await expectLater(
          () async => (await client.getUrl(serverUrl)).close(),
          throwsA(isA<SocketException>()),
        );
        expect(requestsReceived, 0);
      },
    );

    testWidgets(
      'an http.Client has its connection to a loopback server refused before '
      'a request is sent',
      (tester) async {
        final client = http.Client();
        addTearDown(client.close);

        await expectLater(
          client.get(serverUrl),
          throwsA(isA<http.ClientException>()),
        );
        expect(requestsReceived, 0);
      },
    );
  });
}
