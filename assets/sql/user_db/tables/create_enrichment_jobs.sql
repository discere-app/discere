CREATE TABLE IF NOT EXISTS enrichment_jobs (
  deck_id             TEXT PRIMARY KEY,
  status              TEXT NOT NULL,
  attempted_at        INTEGER,
  completed_at        INTEGER,
  current_stage       TEXT,
  payload_json        TEXT NOT NULL,
  failure_kind        TEXT,
  last_error          TEXT,
  progress_completed  INTEGER NOT NULL DEFAULT 0,
  progress_total      INTEGER NOT NULL DEFAULT 0,
  lease_owner         TEXT,
  lease_expires_at    INTEGER,
  updated_at          INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_enrichment_jobs_status_updated
  ON enrichment_jobs(status, updated_at);

CREATE INDEX IF NOT EXISTS idx_enrichment_jobs_lease
  ON enrichment_jobs(lease_expires_at);
