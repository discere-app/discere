import 'dart:io';

import 'package:discere/app/wiring/external_wiring.dart';
import 'package:discere/app/wiring/shared_wiring.dart';
import 'package:discere/shared/service/diagnostics_sink.dart';
import 'package:discere/shared/util/constants.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:package_info_plus/package_info_plus.dart';
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

final _installedPackage = PackageInfo(
  appName: 'Discere',
  packageName: 'ch.feberle.discere',
  version: '2.3.4',
  buildNumber: '56',
);

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
        packageInfo: _installedPackage,
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
        packageInfo: _installedPackage,
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

    group("sends the installed app's User-Agent", () {
      final appUserAgent = AppConstants.userAgentFor(_installedPackage.version);
      late List<http.BaseRequest> sent;
      late SharedServices shared;

      setUp(() async {
        sent = [];
        shared = buildSharedServices(
          sharedPreferences: await preferences(),
          diagnostics: _RecordingDiagnostics(),
          packageInfo: _installedPackage,
          httpClient: MockClient((request) async {
            sent.add(request);
            return http.Response('{}', 200);
          }),
        );
      });

      test('on a request of the shared client itself', () async {
        await shared.sharedHttpClient.get(
          Uri.https('raw.githubusercontent.com', '/decks/index.json'),
        );

        expect(sent.single.headers['User-Agent'], appUserAgent);
      });

      test('on an image download', () async {
        final documents = await Directory.systemTemp.createTemp(
          'shared_wiring_test',
        );
        addTearDown(() => documents.delete(recursive: true));
        const pathProvider = MethodChannel('plugins.flutter.io/path_provider');
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(
          pathProvider,
          (call) async => documents.path,
        );
        addTearDown(
          () => messenger.setMockMethodCallHandler(pathProvider, null),
        );

        await shared.imageService.downloadAndSaveDeckCover(
          'https://www.fishbase.se/images/species/Ptmil_u0.jpg',
        );

        expect(sent.single.headers['User-Agent'], appUserAgent);
      });

      test('on the iNaturalist and Wikipedia requests', () async {
        final external = buildExternalClients(shared.sharedHttpClient);

        await external.iNatSearch.searchTaxa('Pterois miles');
        await external.wikipediaApi.getSummary(
          wikipediaUrl: 'https://en.wikipedia.org/wiki/Pterois_miles',
          localeCode: 'en',
        );

        expect(sent.map((request) => request.url.host), [
          'api.inaturalist.org',
          'en.wikipedia.org',
        ]);
        expect(
          sent.map((request) => request.headers['User-Agent']),
          everyElement(appUserAgent),
        );
      });
    });
  });
}
