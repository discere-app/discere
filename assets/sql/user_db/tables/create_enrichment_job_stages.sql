CREATE TABLE IF NOT EXISTS enrichment_job_stages (
  deck_id      TEXT NOT NULL,
  stage        TEXT NOT NULL,
  state        TEXT NOT NULL,
  updated_at   INTEGER NOT NULL,
  PRIMARY KEY (deck_id, stage)
);

CREATE INDEX IF NOT EXISTS idx_enrichment_job_stages_lookup
  ON enrichment_job_stages(deck_id, state);
