import 'package:discere/app/wiring/shared_wiring.dart';
import 'package:discere/shared/service/diagnostics_sink.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Collects what the shared HTTP client reports instead of writing it to a
/// database — the wiring needs a sink, and this test is about the transport
/// underneath it.
class _RecordingDiagnostics implements DiagnosticsSink {
  final List<Uri> failedRequests = [];

  @override
  Future<void> recordHttpFailure({
    required http.BaseRequest request,
    http.StreamedResponse? response,
    Object? error,
    required int durationMs,
  }) async {
    failedRequests.add(request.url);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<SharedPreferences> preferences() {
    SharedPreferences.setMockInitialValues(const {});
    return SharedPreferences.getInstance();
  }

  group('buildSharedServices', () {
    test('sends through the injected transport, not the network', () async {
      final requests = <http.BaseRequest>[];
      final stub = MockClient((request) async {
        requests.add(request);
        return http.Response('{"results":[]}', 200);
      });

      final shared = buildSharedServices(
        sharedPreferences: await preferences(),
        diagnostics: _RecordingDiagnostics(),
        httpClient: stub,
      );
      final response = await shared.sharedHttpClient.get(
        Uri.https('api.inaturalist.org', '/v2/taxa', {'q': 'Pterois miles'}),
      );

      expect(requests, hasLength(1));
      expect(requests.single.url.queryParameters['q'], 'Pterois miles');
      expect(response.body, '{"results":[]}');
    });

    test('keeps the logging wrapper around the injected transport', () async {
      final diagnostics = _RecordingDiagnostics();
      final stub = MockClient((request) async => http.Response('nope', 503));

      final shared = buildSharedServices(
        sharedPreferences: await preferences(),
        diagnostics: diagnostics,
        httpClient: stub,
      );
      final url = Uri.https('api.inaturalist.org', '/v2/taxa');
      final response = await shared.sharedHttpClient.get(url);
      await shared.sharedHttpClient.get(url);

      // What makes the inner client the right seam: a stubbed failure still
      // reaches diagnostics and still arms the host cooldown, so a test runs
      // through the stack the app ships rather than around it. The second
      // request is what arms it — this host activates after two failures —
      // and it is also the surprise `BootstrapApp.httpClient` warns about:
      // the next request to this host now waits.
      expect(response.statusCode, 503);
      expect(diagnostics.failedRequests, [url, url]);
      expect(shared.hostCooldownTracker.cooldownForHost(url.host), isNotNull);
    });
  });
}
