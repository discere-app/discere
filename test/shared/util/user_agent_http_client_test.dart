import 'package:discere/shared/util/user_agent_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Records whether it was closed — all the close test needs to observe.
class _ClosableClient extends http.BaseClient {
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      throw UnimplementedError();

  @override
  void close() => closed = true;
}

void main() {
  const userAgent = 'TestAgent/1.0';
  final url = Uri.https('example.org', '/image.jpg');

  late List<http.BaseRequest> sent;
  late http.Client transport;

  setUp(() {
    sent = [];
    transport = MockClient((request) async {
      sent.add(request);
      return http.Response('', 200);
    });
  });

  group('UserAgentHttpClient', () {
    test('sends each request on with the User-Agent set', () async {
      final client = UserAgentHttpClient(transport, userAgent);

      await client.get(url);
      await client.post(url, body: '{}');

      expect(sent.map((request) => request.headers['User-Agent']), [
        userAgent,
        userAgent,
      ]);
    });

    test('replaces a User-Agent the caller set', () async {
      final client = UserAgentHttpClient(transport, userAgent);

      await client.get(url, headers: {'user-agent': 'Stale/0.1'});

      expect(sent.single.headers['User-Agent'], userAgent);
    });

    test('closing it closes the client it wraps', () {
      final inner = _ClosableClient();

      UserAgentHttpClient(inner, userAgent).close();

      expect(inner.closed, isTrue);
    });
  });
}
