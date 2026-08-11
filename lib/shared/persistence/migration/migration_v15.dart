part of '../user_db_schema.dart';

/// Migration v14 → v15: rebuilds local diagnostics storage around a live
/// domain-state model instead of a generic event log the reader side had to
/// reconstruct "runs"/"stages" from by string-matching event types — that
/// reconstruction silently broke when the enrichment pipeline moved to a
/// producer/consumer architecture with a different event vocabulary.
///
/// Drops `local_diagnostics_events` entirely (superseded by the on-disk
/// debug log file) and strips `local_diagnostics_network_failures` down to
/// the columns actually used: `category`/`run_id`/`subject_type`/
/// `subject_id` existed only to correlate failures with the now-gone "run"
/// concept, and the app has only ever had a single shared HTTP client, so
/// `category` never varied in practice either.
Future<void> migrateUserDbToV15(Database db) async {
  _log.debug('Migrating user DB v14 → v15: rebuilding local diagnostics storage');
  await db.execute('DROP TABLE IF EXISTS local_diagnostics_events');

  if (await _tableExists(db, 'local_diagnostics_network_failures')) {
    await db.execute(
      'CREATE TABLE local_diagnostics_network_failures_v15 ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT, '
      'created_at INTEGER NOT NULL, '
      'host TEXT NOT NULL, '
      'method TEXT NOT NULL, '
      'url_path TEXT NOT NULL, '
      'status_code INTEGER, '
      'exception_type TEXT, '
      'message TEXT, '
      'duration_ms INTEGER, '
      'retryable INTEGER NOT NULL DEFAULT 0, '
      'details_json TEXT'
      ')',
    );
    await db.execute(
      'INSERT INTO local_diagnostics_network_failures_v15 '
      '(created_at, host, method, url_path, status_code, exception_type, '
      'message, duration_ms, retryable, details_json) '
      'SELECT created_at, host, method, url_path, status_code, exception_type, '
      'message, duration_ms, retryable, details_json '
      'FROM local_diagnostics_network_failures',
    );
    await db.execute('DROP TABLE local_diagnostics_network_failures');
    await db.execute(
      'ALTER TABLE local_diagnostics_network_failures_v15 '
      'RENAME TO local_diagnostics_network_failures',
    );
  }
}
