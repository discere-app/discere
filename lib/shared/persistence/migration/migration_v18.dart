part of '../user_db_schema.dart';

/// Migration v17 → v18: folds `enrichment_job_stages` into a `cover_state`
/// column on `enrichment_jobs` and drops the table.
///
/// The stages table held one row per deck — `(deck_id, 'cover', state)` —
/// ever since migration v12 deleted every row with another stage. A 1:1 side
/// table cost every read a second query and a join, and every write a second
/// statement in the same transaction, for a single enum value.
///
/// `enrichment_jobs` is rebuilt rather than altered in place, because
/// `current_stage` goes at the same time: it only ever held `'cover'` while a
/// job was running, which `status` already says. SQLite could not drop it
/// with `ALTER TABLE` on the older runtimes this app still runs against, and
/// leaving it behind would mean an upgraded database and a fresh install no
/// longer have the same schema.
Future<void> migrateUserDbToV18(Database db) async {
  if (!await _tableExists(db, 'enrichment_jobs')) return;

  _log.debug(
    'Migrating user DB v17 → v18: folding enrichment_job_stages into '
    'enrichment_jobs.cover_state',
  );

  final hasStages = await _tableExists(db, 'enrichment_job_stages');

  await db.execute('DROP TABLE IF EXISTS enrichment_jobs_v18');
  await db.execute('''
    CREATE TABLE enrichment_jobs_v18 (
      deck_id             TEXT PRIMARY KEY,
      status              TEXT NOT NULL,
      attempted_at        INTEGER,
      completed_at        INTEGER,
      cover_state         TEXT NOT NULL DEFAULT 'pending',
      payload_json        TEXT NOT NULL,
      failure_kind        TEXT,
      last_error          TEXT,
      progress_completed  INTEGER NOT NULL DEFAULT 0,
      progress_total      INTEGER NOT NULL DEFAULT 0,
      retry_count         INTEGER NOT NULL DEFAULT 0,
      next_attempt_at     INTEGER,
      lease_owner         TEXT,
      lease_expires_at    INTEGER,
      updated_at          INTEGER NOT NULL
    )
  ''');

  // A job with no stage row reads as `skipped`, which is what the record
  // assembly defaulted a missing stage to before this migration existed.
  final coverState = hasStages
      ? '''COALESCE(
             (SELECT s.state FROM enrichment_job_stages s
               WHERE s.deck_id = j.deck_id AND s.stage = 'cover'),
             'skipped')'''
      : "'skipped'";

  await db.execute('''
    INSERT INTO enrichment_jobs_v18 (
      deck_id, status, attempted_at, completed_at, cover_state, payload_json,
      failure_kind, last_error, progress_completed, progress_total,
      retry_count, next_attempt_at, lease_owner, lease_expires_at, updated_at
    )
    SELECT
      j.deck_id, j.status, j.attempted_at, j.completed_at, $coverState,
      j.payload_json, j.failure_kind, j.last_error, j.progress_completed,
      j.progress_total, j.retry_count, j.next_attempt_at, j.lease_owner,
      j.lease_expires_at, j.updated_at
    FROM enrichment_jobs j
  ''');

  await db.execute('DROP TABLE enrichment_jobs');
  await db.execute('ALTER TABLE enrichment_jobs_v18 RENAME TO enrichment_jobs');
  await db.execute('DROP TABLE IF EXISTS enrichment_job_stages');

  // The indexes went with the old table; _createCurrentUserSchema recreates
  // them right after the migrations run, but a failure between here and there
  // would otherwise leave the table unindexed.
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_enrichment_jobs_status_updated '
    'ON enrichment_jobs(status, updated_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_enrichment_jobs_lease '
    'ON enrichment_jobs(lease_expires_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_enrichment_jobs_next_attempt '
    'ON enrichment_jobs(next_attempt_at)',
  );
  await db.execute(
    'CREATE INDEX IF NOT EXISTS idx_enrichment_jobs_cover_state '
    'ON enrichment_jobs(cover_state)',
  );
}
