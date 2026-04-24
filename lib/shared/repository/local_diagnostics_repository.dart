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

  Future<void> _trimTable(Database db, String table, int maxRows) async {
    await db.rawDelete(
      'DELETE FROM $table WHERE id NOT IN (SELECT id FROM $table ORDER BY id DESC LIMIT ?)',
      [maxRows],
    );
  }
}
