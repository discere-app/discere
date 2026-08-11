import 'dart:convert';

import 'package:discere/shared/persistence/database_helper.dart';
import 'package:sqflite/sqflite.dart';

class LocalDiagnosticsNetworkFailureRecord {
  final DateTime createdAt;
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

class LocalDiagnosticsReport {
  final int totalNetworkFailureCount;
  final List<LocalDiagnosticsHostFailureSummary> hostFailures;
  final List<LocalDiagnosticsNetworkFailureRecord> recentFailures;

  const LocalDiagnosticsReport({
    required this.totalNetworkFailureCount,
    required this.hostFailures,
    required this.recentFailures,
  });
}

class LocalDiagnosticsRepository {
  static const networkFailuresTable = 'local_diagnostics_network_failures';
  static const maxNetworkFailures = 500;

  final Database? _injectedDb;

  const LocalDiagnosticsRepository([this._injectedDb]);

  Future<Database> get _db async => _injectedDb ?? DatabaseHelper.userDb;

  Future<void> insertNetworkFailure(
    LocalDiagnosticsNetworkFailureRecord failure,
  ) async {
    final db = await _db;
    await db.insert(networkFailuresTable, {
      'created_at': failure.createdAt.millisecondsSinceEpoch,
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

  Future<List<LocalDiagnosticsNetworkFailureRecord>> loadRecentNetworkFailures({
    int limit = 100,
  }) async {
    final db = await _db;
    final rows = await db.query(
      networkFailuresTable,
      orderBy: 'id DESC',
      limit: limit,
    );
    return rows.map(_recordFromRow).toList(growable: false);
  }

  Future<void> clearNetworkFailures() async {
    final db = await _db;
    await db.delete(networkFailuresTable);
  }

  Future<LocalDiagnosticsReport> loadReport({int networkFailureLimit = 200}) async {
    final failures = await loadRecentNetworkFailures(limit: networkFailureLimit);
    return LocalDiagnosticsReport(
      totalNetworkFailureCount: failures.length,
      hostFailures: _buildHostSummaries(failures),
      recentFailures: failures,
    );
  }

  List<LocalDiagnosticsHostFailureSummary> _buildHostSummaries(
    List<LocalDiagnosticsNetworkFailureRecord> failures,
  ) {
    final hosts = <String, _MutableHostSummary>{};
    for (final failure in failures) {
      final summary = hosts.putIfAbsent(
        failure.host,
        () => _MutableHostSummary(
          host: failure.host,
          lastFailureAt: failure.createdAt,
        ),
      );
      summary.failureCount += 1;
      if (failure.retryable) summary.retryableFailureCount += 1;
      if (failure.createdAt.isAfter(summary.lastFailureAt)) {
        summary.lastFailureAt = failure.createdAt;
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

  LocalDiagnosticsNetworkFailureRecord _recordFromRow(
    Map<String, Object?> row,
  ) {
    return LocalDiagnosticsNetworkFailureRecord(
      createdAt:
          _millisToDateTime(row['created_at'] as int?) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      host: row['host'] as String? ?? '-',
      method: row['method'] as String? ?? 'GET',
      urlPath: row['url_path'] as String? ?? '/',
      statusCode: row['status_code'] as int?,
      exceptionType: row['exception_type'] as String?,
      message: row['message'] as String?,
      durationMs: row['duration_ms'] as int?,
      retryable: (row['retryable'] as int? ?? 0) == 1,
      details: _decodeDetails(row['details_json']),
    );
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

class _MutableHostSummary {
  final String host;
  int failureCount = 0;
  int retryableFailureCount = 0;
  DateTime lastFailureAt;

  _MutableHostSummary({required this.host, required this.lastFailureAt});
}
