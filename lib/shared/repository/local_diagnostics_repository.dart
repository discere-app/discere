import 'dart:convert';

import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class LocalDiagnosticsEventRecord {
  final DateTime createdAt;
  final String category;
  final String eventType;
  final String? runId;
  final String? owner;
  final String? subjectType;
  final String? subjectId;
  final int? durationMs;
  final String? level;
  final String? message;
  final Map<String, Object?> details;

  const LocalDiagnosticsEventRecord({
    required this.createdAt,
    required this.category,
    required this.eventType,
    required this.runId,
    required this.owner,
    required this.subjectType,
    required this.subjectId,
    required this.durationMs,
    required this.level,
    required this.message,
    this.details = const <String, Object?>{},
  });
}

class LocalDiagnosticsNetworkFailureRecord {
  final DateTime createdAt;
  final String category;
  final String? runId;
  final String? subjectType;
  final String? subjectId;
  final String host;
  final String method;
  final String urlPath;
  final int? statusCode;
  final String? exceptionType;
  final String? message;
  final int? durationMs;
  final bool retryable;
  final Map<String, Object?> details;

  const LocalDiagnosticsNetworkFailureRecord({
    required this.createdAt,
    required this.category,
    required this.runId,
    required this.subjectType,
    required this.subjectId,
    required this.host,
    required this.method,
    required this.urlPath,
    required this.statusCode,
    required this.exceptionType,
    required this.message,
    required this.durationMs,
    required this.retryable,
    this.details = const <String, Object?>{},
  });
}

class LocalDiagnosticsHostFailureSummary {
  final String host;
  final int failureCount;
  final int retryableFailureCount;
  final DateTime lastFailureAt;

  const LocalDiagnosticsHostFailureSummary({
    required this.host,
    required this.failureCount,
    required this.retryableFailureCount,
    required this.lastFailureAt,
  });
}

class LocalDiagnosticsStageSummary {
  final String stage;
  final int startedCount;
  final int successCount;
  final int yieldedCount;
  final int retryCount;
  final int failedPermanentCount;

  const LocalDiagnosticsStageSummary({
    required this.stage,
    required this.startedCount,
    required this.successCount,
    required this.yieldedCount,
    required this.retryCount,
    required this.failedPermanentCount,
  });
}

class LocalDiagnosticsRunSummary {
  final String runId;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final String runnerKind;
  final int? durationMs;
  final int processedStages;
  final int retryCount;
  final int permanentFailureCount;
  final int networkFailureCount;
  final bool pendingWorkAtEnd;
  final String? completionStatus;
  final bool? queueDrained;
  final bool? fullyEnriched;
  final bool? allErrorsResolved;
  final int? plannedSpeciesCount;
  final int? fullyEnrichedSpeciesCount;
  final int? partialSpeciesCount;
  final int? remainingFailureSpeciesCount;

  const LocalDiagnosticsRunSummary({
    required this.runId,
    required this.startedAt,
    required this.finishedAt,
    required this.runnerKind,
    required this.durationMs,
    required this.processedStages,
    required this.retryCount,
    required this.permanentFailureCount,
    required this.networkFailureCount,
    required this.pendingWorkAtEnd,
    required this.completionStatus,
    required this.queueDrained,
    required this.fullyEnriched,
    required this.allErrorsResolved,
    required this.plannedSpeciesCount,
    required this.fullyEnrichedSpeciesCount,
    required this.partialSpeciesCount,
    required this.remainingFailureSpeciesCount,
  });
}

class LocalDiagnosticsRecentFailureSummary {
  final DateTime createdAt;
  final String host;
  final String method;
  final String urlPath;
  final String? stage;
  final int? statusCode;
  final String? exceptionType;
  final String? message;
  final bool retryable;

  const LocalDiagnosticsRecentFailureSummary({
    required this.createdAt,
    required this.host,
    required this.method,
    required this.urlPath,
    required this.stage,
    required this.statusCode,
    required this.exceptionType,
    required this.message,
    required this.retryable,
  });
}

class LocalDiagnosticsLogEntrySummary {
  final DateTime createdAt;
  final String level;
  final String scope;
  final String message;

  const LocalDiagnosticsLogEntrySummary({
    required this.createdAt,
    required this.level,
    required this.scope,
    required this.message,
  });
}

class LocalDiagnosticsReport {
  final int totalRunCount;
  final int totalRetryCount;
  final int totalNetworkFailureCount;
  final Duration? averageRunDuration;
  final List<LocalDiagnosticsHostFailureSummary> hostFailures;
  final List<LocalDiagnosticsStageSummary> stageSummaries;
  final List<LocalDiagnosticsRunSummary> recentRuns;
  final List<LocalDiagnosticsRecentFailureSummary> recentFailures;
  final List<LocalDiagnosticsLogEntrySummary> recentLogs;

  const LocalDiagnosticsReport({
    required this.totalRunCount,
    required this.totalRetryCount,
    required this.totalNetworkFailureCount,
    required this.averageRunDuration,
    required this.hostFailures,
    required this.stageSummaries,
    required this.recentRuns,
    required this.recentFailures,
    required this.recentLogs,
  });
}

class LocalDiagnosticsRepository {
  static const eventsTable = 'local_diagnostics_events';
  static const networkFailuresTable = 'local_diagnostics_network_failures';
  static const maxEvents = 1000;
  static const maxNetworkFailures = 500;

  final Database? _injectedDb;

  const LocalDiagnosticsRepository([this._injectedDb]);

  Future<Database> get _db async => _injectedDb ?? DatabaseHelper.userDb;

  Future<void> insertEvent(LocalDiagnosticsEventRecord event) async {
    final db = await _db;
    await db.insert(eventsTable, {
      'created_at': event.createdAt.millisecondsSinceEpoch,
      'category': event.category,
      'event_type': event.eventType,
      'run_id': event.runId,
      'owner': event.owner,
      'subject_type': event.subjectType,
      'subject_id': event.subjectId,
      'duration_ms': event.durationMs,
      'level': event.level,
      'message': event.message,
      'details_json': jsonEncode(event.details),
    });
    await _trimTable(db, eventsTable, maxEvents);
  }

  Future<void> insertNetworkFailure(
    LocalDiagnosticsNetworkFailureRecord failure,
  ) async {
    final db = await _db;
    await db.insert(networkFailuresTable, {
      'created_at': failure.createdAt.millisecondsSinceEpoch,
      'category': failure.category,
      'run_id': failure.runId,
      'subject_type': failure.subjectType,
      'subject_id': failure.subjectId,
      'host': failure.host,
      'method': failure.method,
      'url_path': failure.urlPath,
      'status_code': failure.statusCode,
      'exception_type': failure.exceptionType,
      'message': failure.message,
      'duration_ms': failure.durationMs,
      'retryable': failure.retryable ? 1 : 0,
      'details_json': jsonEncode(failure.details),
    });
    await _trimTable(db, networkFailuresTable, maxNetworkFailures);
  }

  Future<List<Map<String, Object?>>> loadRecentEvents({int limit = 100}) async {
    final db = await _db;
    final rows = await db.query(eventsTable, orderBy: 'id DESC', limit: limit);
    return rows.cast<Map<String, Object?>>();
  }

  Future<List<Map<String, Object?>>> loadRecentNetworkFailures({
    int limit = 100,
  }) async {
    final db = await _db;
    final rows = await db.query(
      networkFailuresTable,
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.cast<Map<String, Object?>>();
  }

  Future<LocalDiagnosticsReport> loadReport({
    int eventLimit = 400,
    int networkFailureLimit = 200,
  }) async {
    final events = await loadRecentEvents(limit: eventLimit);
    final failures = await loadRecentNetworkFailures(
      limit: networkFailureLimit,
    );
    final enrichmentEvents = events
        .where((row) => row['category'] == 'enrichment')
        .toList();
    final enrichmentFailures = failures
        .where((row) => row['category'] == 'enrichment')
        .toList();

    final recentRuns = _buildRunSummaries(enrichmentEvents, enrichmentFailures);
    final hostFailures = _buildHostSummaries(enrichmentFailures);
    final stageSummaries = _buildStageSummaries(enrichmentEvents);
    final recentFailures = _buildRecentFailureSummaries(enrichmentFailures);
    final recentLogs = _buildRecentLogs(events);
    final completedRuns = recentRuns
        .where((run) => run.durationMs != null)
        .toList(growable: false);
    final averageRunDuration = completedRuns.isEmpty
        ? null
        : Duration(
            milliseconds:
                completedRuns
                    .map((run) => run.durationMs!)
                    .reduce((left, right) => left + right) ~/
                completedRuns.length,
          );

    return LocalDiagnosticsReport(
      totalRunCount: recentRuns.length,
      totalRetryCount: enrichmentEvents
          .where((row) => row['event_type'] == 'stage_retry_scheduled')
          .length,
      totalNetworkFailureCount: enrichmentFailures.length,
      averageRunDuration: averageRunDuration,
      hostFailures: hostFailures,
      stageSummaries: stageSummaries,
      recentRuns: recentRuns,
      recentFailures: recentFailures,
      recentLogs: recentLogs,
    );
  }

  List<LocalDiagnosticsRunSummary> _buildRunSummaries(
    List<Map<String, Object?>> events,
    List<Map<String, Object?>> failures,
  ) {
    final runs = <String, _MutableRunSummary>{};
    for (final row in events.reversed) {
      final runId = row['run_id'] as String?;
      if (runId == null || runId.isEmpty) continue;
      final eventType = row['event_type'] as String? ?? '';
      final createdAt = _millisToDateTime(row['created_at'] as int?);
      if (createdAt == null) continue;
      final details = _decodeDetails(row['details_json']);
      final run = runs.putIfAbsent(
        runId,
        () => _MutableRunSummary(
          runId: runId,
          startedAt: createdAt,
          runnerKind: details['runnerKind'] as String? ?? 'unknown',
        ),
      );
      if (eventType == 'run_started') {
        run.startedAt = createdAt;
        run.runnerKind = details['runnerKind'] as String? ?? run.runnerKind;
      } else if (eventType == 'run_finished') {
        run.finishedAt = createdAt;
        run.durationMs = row['duration_ms'] as int?;
        run.processedStages =
            (details['processedStages'] as num?)?.toInt() ??
            run.processedStages;
        run.pendingWorkAtEnd =
            details['pendingWork'] as bool? ?? run.pendingWorkAtEnd;
        run.completionStatus = details['completionStatus'] as String?;
        run.queueDrained = details['queueDrained'] as bool?;
        run.fullyEnriched = details['fullyEnriched'] as bool?;
        run.allErrorsResolved = details['allErrorsResolved'] as bool?;
        run.plannedSpeciesCount = (details['plannedSpeciesCount'] as num?)
            ?.toInt();
        run.fullyEnrichedSpeciesCount =
            (details['fullyEnrichedSpeciesCount'] as num?)?.toInt();
        run.partialSpeciesCount = (details['partialSpeciesCount'] as num?)
            ?.toInt();
        run.remainingFailureSpeciesCount =
            (details['remainingFailureSpeciesCount'] as num?)?.toInt();
        run.permanentFailureCount =
            (details['permanentFailureCount'] as num?)?.toInt() ??
            run.permanentFailureCount;
      } else if (eventType == 'stage_retry_scheduled') {
        run.retryCount += 1;
      } else if (eventType == 'stage_failed_permanent') {
        run.permanentFailureCount += 1;
      }
    }

    for (final row in failures) {
      final runId = row['run_id'] as String?;
      if (runId == null || runId.isEmpty) continue;
      final run = runs[runId];
      if (run == null) continue;
      run.networkFailureCount += 1;
    }

    final summaries = runs.values
        .map(
          (run) => LocalDiagnosticsRunSummary(
            runId: run.runId,
            startedAt: run.startedAt,
            finishedAt: run.finishedAt,
            runnerKind: run.runnerKind,
            durationMs: run.durationMs,
            processedStages: run.processedStages,
            retryCount: run.retryCount,
            permanentFailureCount: run.permanentFailureCount,
            networkFailureCount: run.networkFailureCount,
            pendingWorkAtEnd: run.pendingWorkAtEnd,
            completionStatus: run.completionStatus,
            queueDrained: run.queueDrained,
            fullyEnriched: run.fullyEnriched,
            allErrorsResolved: run.allErrorsResolved,
            plannedSpeciesCount: run.plannedSpeciesCount,
            fullyEnrichedSpeciesCount: run.fullyEnrichedSpeciesCount,
            partialSpeciesCount: run.partialSpeciesCount,
            remainingFailureSpeciesCount: run.remainingFailureSpeciesCount,
          ),
        )
        .toList(growable: false);
    summaries.sort((left, right) => right.startedAt.compareTo(left.startedAt));
    return summaries;
  }

  List<LocalDiagnosticsHostFailureSummary> _buildHostSummaries(
    List<Map<String, Object?>> failures,
  ) {
    final hosts = <String, _MutableHostSummary>{};
    for (final row in failures) {
      final host = row['host'] as String?;
      final createdAt = _millisToDateTime(row['created_at'] as int?);
      if (host == null || host.isEmpty || createdAt == null) continue;
      final summary = hosts.putIfAbsent(
        host,
        () => _MutableHostSummary(host: host, lastFailureAt: createdAt),
      );
      summary.failureCount += 1;
      if ((row['retryable'] as int? ?? 0) == 1) {
        summary.retryableFailureCount += 1;
      }
      if (createdAt.isAfter(summary.lastFailureAt)) {
        summary.lastFailureAt = createdAt;
      }
    }
    final summaries = hosts.values
        .map(
          (summary) => LocalDiagnosticsHostFailureSummary(
            host: summary.host,
            failureCount: summary.failureCount,
            retryableFailureCount: summary.retryableFailureCount,
            lastFailureAt: summary.lastFailureAt,
          ),
        )
        .toList(growable: false);
    summaries.sort(
      (left, right) => right.failureCount.compareTo(left.failureCount),
    );
    return summaries;
  }

  List<LocalDiagnosticsStageSummary> _buildStageSummaries(
    List<Map<String, Object?>> events,
  ) {
    final stages = <String, _MutableStageSummary>{};
    for (final row in events) {
      final eventType = row['event_type'] as String? ?? '';
      if (!eventType.startsWith('stage_')) continue;
      final details = _decodeDetails(row['details_json']);
      final stage = details['stage'] as String?;
      if (stage == null || stage.isEmpty) continue;
      final summary = stages.putIfAbsent(
        stage,
        () => _MutableStageSummary(stage: stage),
      );
      switch (eventType) {
        case 'stage_started':
          summary.startedCount += 1;
          break;
        case 'stage_succeeded':
          summary.successCount += 1;
          break;
        case 'stage_yielded':
          summary.yieldedCount += 1;
          break;
        case 'stage_retry_scheduled':
          summary.retryCount += 1;
          break;
        case 'stage_failed_permanent':
          summary.failedPermanentCount += 1;
          break;
      }
    }
    final summaries = stages.values
        .map(
          (summary) => LocalDiagnosticsStageSummary(
            stage: summary.stage,
            startedCount: summary.startedCount,
            successCount: summary.successCount,
            yieldedCount: summary.yieldedCount,
            retryCount: summary.retryCount,
            failedPermanentCount: summary.failedPermanentCount,
          ),
        )
        .toList(growable: false);
    summaries.sort((left, right) => left.stage.compareTo(right.stage));
    return summaries;
  }

  List<LocalDiagnosticsRecentFailureSummary> _buildRecentFailureSummaries(
    List<Map<String, Object?>> failures,
  ) {
    return failures
        .map((row) {
          final details = _decodeDetails(row['details_json']);
          return LocalDiagnosticsRecentFailureSummary(
            createdAt:
                _millisToDateTime(row['created_at'] as int?) ??
                DateTime.fromMillisecondsSinceEpoch(0),
            host: row['host'] as String? ?? '-',
            method: row['method'] as String? ?? 'GET',
            urlPath: row['url_path'] as String? ?? '/',
            stage: details['stage'] as String?,
            statusCode: row['status_code'] as int?,
            exceptionType: row['exception_type'] as String?,
            message: row['message'] as String?,
            retryable: (row['retryable'] as int? ?? 0) == 1,
          );
        })
        .toList(growable: false);
  }

  List<LocalDiagnosticsLogEntrySummary> _buildRecentLogs(
    List<Map<String, Object?>> events,
  ) {
    return events
        .where((row) => row['category'] == 'log')
        .where((row) => row['event_type'] == 'logger_entry')
        .take(40)
        .map((row) {
          final details = _decodeDetails(row['details_json']);
          return LocalDiagnosticsLogEntrySummary(
            createdAt:
                _millisToDateTime(row['created_at'] as int?) ??
                DateTime.fromMillisecondsSinceEpoch(0),
            level: row['level'] as String? ?? 'unknown',
            scope:
                row['subject_id'] as String? ??
                details['scope'] as String? ??
                '-',
            message: row['message'] as String? ?? '',
          );
        })
        .toList(growable: false);
  }

  static DateTime? _millisToDateTime(int? millis) {
    if (millis == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(millis);
  }

  static Map<String, Object?> _decodeDetails(Object? raw) {
    if (raw is! String || raw.isEmpty) {
      return const <String, Object?>{};
    }
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded.cast<String, Object?>();
    }
    return const <String, Object?>{};
  }

  Future<void> _trimTable(Database db, String table, int maxRows) async {
    await db.rawDelete(
      'DELETE FROM $table WHERE id NOT IN (SELECT id FROM $table ORDER BY id DESC LIMIT ?)',
      [maxRows],
    );
  }
}

class _MutableRunSummary {
  final String runId;
  DateTime startedAt;
  DateTime? finishedAt;
  String runnerKind;
  int? durationMs;
  int processedStages = 0;
  int retryCount = 0;
  int permanentFailureCount = 0;
  int networkFailureCount = 0;
  bool pendingWorkAtEnd = false;
  String? completionStatus;
  bool? queueDrained;
  bool? fullyEnriched;
  bool? allErrorsResolved;
  int? plannedSpeciesCount;
  int? fullyEnrichedSpeciesCount;
  int? partialSpeciesCount;
  int? remainingFailureSpeciesCount;

  _MutableRunSummary({
    required this.runId,
    required this.startedAt,
    required this.runnerKind,
  });
}

class _MutableHostSummary {
  final String host;
  int failureCount = 0;
  int retryableFailureCount = 0;
  DateTime lastFailureAt;

  _MutableHostSummary({required this.host, required this.lastFailureAt});
}

class _MutableStageSummary {
  final String stage;
  int startedCount = 0;
  int successCount = 0;
  int yieldedCount = 0;
  int retryCount = 0;
  int failedPermanentCount = 0;

  _MutableStageSummary({required this.stage});
}
