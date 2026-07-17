import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:discere/enrichment/repository/enrichment_job_repository.dart';
import 'package:discere/shared/repository/local_diagnostics_repository.dart';
import 'package:discere/shared/service/host_cooldown_tracker.dart';
import 'package:discere/shared/service/local_diagnostics.dart';
import 'package:discere/shared/util/logging_http_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Database database;
  late LocalDiagnosticsRepository repository;
  late LocalDiagnostics diagnostics;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    database = await openDatabase(inMemoryDatabasePath, version: 1);
    await database.execute(
      await File(
        'assets/sql/user_db/tables/create_local_diagnostics_events.sql',
      ).readAsString(),
    );
    await database.execute(
      await File(
        'assets/sql/user_db/tables/create_local_diagnostics_network_failures.sql',
      ).readAsString(),
    );
    repository = LocalDiagnosticsRepository(database);
    diagnostics = LocalDiagnostics(repository: repository, enabled: true);
  });

  tearDown(() async {
    await database.close();
  });

  test('records run events locally and trims old history', () async {
    for (var i = 0; i < LocalDiagnosticsRepository.maxEvents + 5; i++) {
      await repository.insertEvent(
        LocalDiagnosticsEventRecord(
          createdAt: DateTime.now(),
          category: 'enrichment',
          eventType: 'stage_started',
          runId: 'run-$i',
          owner: 'owner',
          subjectType: 'deck',
          subjectId: 'deck-$i',
          durationMs: i,
          level: 'info',
          message: null,
        ),
      );
    }

    final rows = await repository.loadRecentEvents(limit: 1100);
    expect(rows, hasLength(LocalDiagnosticsRepository.maxEvents));
    expect(rows.first['run_id'], 'run-1004');
    expect(rows.last['run_id'], 'run-5');
  });

  test('records HTTP failures with enrichment stage context', () async {
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

    await diagnostics.runScope(
      category: 'enrichment',
      timelineName: 'enrichment:base',
      runId: 'run-1',
      subjectType: 'deck',
      subjectId: 'deck-1',
      details: {
        'runnerKind': EnrichmentRunnerKind.background.name,
        'stage': EnrichmentStage.base.name,
      },
      action: () async {
        final response = await client.send(
          http.Request('GET', Uri.parse('https://fishbase.se/images/species')),
        );
        await response.stream.drain<void>();
      },
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final failures = await repository.loadRecentNetworkFailures(limit: 10);
    expect(failures, hasLength(1));
    expect(failures.single['run_id'], 'run-1');
    expect(failures.single['category'], 'enrichment');
    expect(failures.single['subject_type'], 'deck');
    expect(failures.single['subject_id'], 'deck-1');
    expect(failures.single['host'], 'fishbase.se');
    expect(failures.single['status_code'], 503);
    expect(failures.single['message'], 'HTTP 503 Service Unavailable');
    expect(failures.single['retryable'], 1);
    final details =
        jsonDecode(failures.single['details_json']! as String)
            as Map<String, dynamic>;
    expect(details['reasonPhrase'], 'Service Unavailable');
    expect(details['requestUrl'], 'https://fishbase.se/images/species');
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
      diagnostics.runScope(
        category: 'enrichment',
        timelineName: 'enrichment:inatPrimary',
        runId: 'run-2',
        subjectType: 'deck',
        subjectId: 'deck-2',
        details: {
          'runnerKind': EnrichmentRunnerKind.foreground.name,
          'stage': EnrichmentStage.inatPrimary.name,
        },
        action: () async {
          await client.send(
            http.Request(
              'GET',
              Uri.parse('https://api.inaturalist.org/v2/taxa/1'),
            ),
          );
        },
      ),
      throwsA(isA<http.ClientException>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final failures = await repository.loadRecentNetworkFailures(limit: 10);
    expect(failures, hasLength(1));
    expect(failures.single['status_code'], isNull);
    expect(failures.single['exception_type'], 'ClientException');
    expect(
      failures.single['message'],
      'ClientException: Connection closed before full header was received: https://api.inaturalist.org/v2/taxa/1',
    );
    final details =
        jsonDecode(failures.single['details_json']! as String)
            as Map<String, dynamic>;
    expect(details['stage'], EnrichmentStage.inatPrimary.name);
    expect(details['runnerKind'], EnrichmentRunnerKind.foreground.name);
    expect(details['requestUrl'], 'https://api.inaturalist.org/v2/taxa/1');
  });

  test(
    'builds aggregate diagnostics report for recent enrichment runs',
    () async {
      await repository.insertEvent(
        LocalDiagnosticsEventRecord(
          createdAt: DateTime.now().subtract(const Duration(seconds: 30)),
          category: 'enrichment',
          eventType: 'run_started',
          runId: 'run-aggregate',
          owner: 'foreground',
          subjectType: null,
          subjectId: null,
          durationMs: null,
          level: null,
          message: null,
          details: {'runnerKind': 'foreground'},
        ),
      );
      await repository.insertEvent(
        LocalDiagnosticsEventRecord(
          createdAt: DateTime.now().subtract(const Duration(seconds: 20)),
          category: 'enrichment',
          eventType: 'stage_retry_scheduled',
          runId: 'run-aggregate',
          owner: null,
          subjectType: 'deck',
          subjectId: 'deck-1',
          durationMs: null,
          level: null,
          message: null,
          details: {'stage': EnrichmentStage.names.name},
        ),
      );
      await repository.insertEvent(
        LocalDiagnosticsEventRecord(
          createdAt: DateTime.now().subtract(const Duration(seconds: 10)),
          category: 'enrichment',
          eventType: 'run_finished',
          runId: 'run-aggregate',
          owner: null,
          subjectType: null,
          subjectId: null,
          durationMs: 12000,
          level: null,
          message: null,
          details: {
            'runnerKind': 'foreground',
            'processedStages': 4,
            'pendingWork': false,
            'completionStatus': 'complete_with_warnings',
            'queueDrained': true,
            'fullyEnriched': false,
            'allErrorsResolved': false,
            'plannedSpeciesCount': 12,
            'fullyEnrichedSpeciesCount': 9,
            'partialSpeciesCount': 3,
            'remainingFailureSpeciesCount': 3,
            'permanentFailureCount': 1,
          },
        ),
      );
      await repository.insertNetworkFailure(
        LocalDiagnosticsNetworkFailureRecord(
          createdAt: DateTime.now().subtract(const Duration(seconds: 18)),
          category: 'enrichment',
          runId: 'run-aggregate',
          subjectType: 'deck',
          subjectId: 'deck-1',
          host: 'api.inaturalist.org',
          method: 'GET',
          urlPath: '/v2/taxa/1',
          statusCode: 503,
          exceptionType: null,
          message: 'HTTP 503 Service Unavailable',
          durationMs: 1000,
          retryable: true,
          details: {'stage': EnrichmentStage.names.name},
        ),
      );

      final report = await repository.loadReport();

      expect(report.totalRunCount, 1);
      expect(report.totalRetryCount, 1);
      expect(report.totalNetworkFailureCount, 1);
      expect(report.averageRunDuration, const Duration(seconds: 12));
      expect(report.hostFailures.single.host, 'api.inaturalist.org');
      expect(report.hostFailures.single.failureCount, 1);
      expect(report.stageSummaries.single.stage, EnrichmentStage.names.name);
      expect(report.stageSummaries.single.retryCount, 1);
      expect(report.recentRuns.single.runId, 'run-aggregate');
      expect(report.recentRuns.single.networkFailureCount, 1);
      expect(report.recentRuns.single.processedStages, 4);
      expect(
        report.recentRuns.single.completionStatus,
        'complete_with_warnings',
      );
      expect(report.recentRuns.single.queueDrained, isTrue);
      expect(report.recentRuns.single.fullyEnriched, isFalse);
      expect(report.recentRuns.single.allErrorsResolved, isFalse);
      expect(report.recentRuns.single.plannedSpeciesCount, 12);
      expect(report.recentRuns.single.fullyEnrichedSpeciesCount, 9);
      expect(report.recentRuns.single.partialSpeciesCount, 3);
      expect(report.recentRuns.single.remainingFailureSpeciesCount, 3);
      expect(report.recentRuns.single.permanentFailureCount, 1);
      expect(report.recentFailures.single.stage, EnrichmentStage.names.name);
    },
  );

  test(
    'includes persisted warning/error log entries in diagnostics report',
    () async {
      await repository.insertEvent(
        LocalDiagnosticsEventRecord(
          createdAt: DateTime.now(),
          category: 'log',
          eventType: 'logger_entry',
          runId: null,
          owner: null,
          subjectType: 'scope',
          subjectId: 'LoggingHttpClient',
          durationMs: null,
          level: 'warning',
          message: 'Transient DNS issue',
          details: const {'scope': 'LoggingHttpClient', 'level': 'warning'},
        ),
      );

      final report = await repository.loadReport();

      expect(report.recentLogs, hasLength(1));
      expect(report.recentLogs.single.level, 'warning');
      expect(report.recentLogs.single.scope, 'LoggingHttpClient');
      expect(report.recentLogs.single.message, 'Transient DNS issue');
    },
  );
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
