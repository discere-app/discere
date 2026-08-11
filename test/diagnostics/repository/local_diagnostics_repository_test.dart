import 'package:discere/diagnostics/repository/local_diagnostics_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import '../../support/in_memory_user_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late LocalDiagnosticsRepository repository;

  setUp(() async {
    database = await openInMemoryUserDatabase();
    repository = LocalDiagnosticsRepository(database);
  });

  tearDown(() async {
    await database.close();
  });

  LocalDiagnosticsNetworkFailureRecord buildFailure({
    required String host,
    bool retryable = false,
    DateTime? createdAt,
  }) {
    return LocalDiagnosticsNetworkFailureRecord(
      createdAt: createdAt ?? DateTime.now(),
      host: host,
      method: 'GET',
      urlPath: '/v2/taxa/1',
      statusCode: 503,
      exceptionType: null,
      message: 'HTTP 503',
      durationMs: 100,
      retryable: retryable,
    );
  }

  test('groups failures by host in loadReport', () async {
    await repository.insertNetworkFailure(
      buildFailure(host: 'api.inaturalist.org', retryable: true),
    );
    await repository.insertNetworkFailure(
      buildFailure(host: 'api.inaturalist.org'),
    );
    await repository.insertNetworkFailure(buildFailure(host: 'fishbase.se'));

    final report = await repository.loadReport();

    expect(report.totalNetworkFailureCount, 3);
    expect(report.hostFailures, hasLength(2));
    final iNatSummary = report.hostFailures.firstWhere(
      (summary) => summary.host == 'api.inaturalist.org',
    );
    expect(iNatSummary.failureCount, 2);
    expect(iNatSummary.retryableFailureCount, 1);
  });

  test('trims network failures beyond the retention limit', () async {
    for (var i = 0; i < LocalDiagnosticsRepository.maxNetworkFailures + 5; i++) {
      await repository.insertNetworkFailure(buildFailure(host: 'host-$i'));
    }

    final failures = await repository.loadRecentNetworkFailures(limit: 1000);
    expect(failures, hasLength(LocalDiagnosticsRepository.maxNetworkFailures));
    expect(failures.first.host, 'host-504');
  });

  test('clearNetworkFailures removes all rows', () async {
    await repository.insertNetworkFailure(buildFailure(host: 'fishbase.se'));
    await repository.clearNetworkFailures();

    expect(await repository.loadRecentNetworkFailures(), isEmpty);
  });
}
