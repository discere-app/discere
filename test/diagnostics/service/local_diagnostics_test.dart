import 'package:discere/diagnostics/repository/local_diagnostics_repository.dart';
import 'package:discere/diagnostics/service/local_diagnostics.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/util/logging_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';

import '../../support/in_memory_user_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late LocalDiagnosticsRepository repository;
  late LocalDiagnostics diagnostics;

  setUp(() async {
    database = await openInMemoryUserDatabase();
    repository = LocalDiagnosticsRepository(database);
    diagnostics = LocalDiagnostics(repository: repository, enabled: true);
  });

  tearDown(() async {
    await database.close();
  });

  test('records HTTP failures with response status', () async {
    final client = LoggingHttpClient(
      _FakeHttpClient(
        handler: (_) async => http.StreamedResponse(
          Stream<List<int>>.empty(),
          503,
          reasonPhrase: 'Service Unavailable',
        ),
      ),
      diagnostics: diagnostics,
      hostCooldownTracker: HostCooldownTracker(),
    );

    final response = await client.send(
      http.Request('GET', Uri.parse('https://fishbase.se/images/species')),
    );
    await response.stream.drain<void>();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final failures = await repository.loadRecentNetworkFailures(limit: 10);
    expect(failures, hasLength(1));
    expect(failures.single.host, 'fishbase.se');
    expect(failures.single.statusCode, 503);
    expect(failures.single.message, 'HTTP 503 Service Unavailable');
    expect(failures.single.retryable, isTrue);
  });

  test('records client exception details for transport failures', () async {
    final client = LoggingHttpClient(
      _FakeHttpClient(
        handler: (request) async {
          throw http.ClientException(
            'Connection closed before full header was received',
            request.url,
          );
        },
      ),
      diagnostics: diagnostics,
      hostCooldownTracker: HostCooldownTracker(),
    );

    await expectLater(
      client.send(
        http.Request('GET', Uri.parse('https://api.inaturalist.org/v2/taxa/1')),
      ),
      throwsA(isA<http.ClientException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final failures = await repository.loadRecentNetworkFailures(limit: 10);
    expect(failures, hasLength(1));
    expect(failures.single.statusCode, isNull);
    expect(failures.single.exceptionType, 'ClientException');
    expect(failures.single.host, 'api.inaturalist.org');
  });

  test('does not record failures when disabled', () async {
    final disabledDiagnostics = LocalDiagnostics(
      repository: repository,
      enabled: false,
    );
    final client = LoggingHttpClient(
      _FakeHttpClient(
        handler: (_) async =>
            http.StreamedResponse(Stream<List<int>>.empty(), 500),
      ),
      diagnostics: disabledDiagnostics,
      hostCooldownTracker: HostCooldownTracker(),
    );

    final response = await client.send(
      http.Request('GET', Uri.parse('https://fishbase.se/images/species')),
    );
    await response.stream.drain<void>();
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(await repository.loadRecentNetworkFailures(limit: 10), isEmpty);
  });
}

class _FakeHttpClient extends http.BaseClient {
  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  handler;

  _FakeHttpClient({required this.handler});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return handler(request);
  }
}
