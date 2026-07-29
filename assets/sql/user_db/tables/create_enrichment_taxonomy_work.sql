-- attempt_count/next_attempt_at/last_error/last_failure_kind are additive
-- retry-bookkeeping columns for the producer-consumer rewrite's INatWorker;
-- unused by the current executor.
CREATE TABLE IF NOT EXISTS enrichment_taxonomy_work (
  work_key                     TEXT PRIMARY KEY,
  runtime_entity_key           TEXT NOT NULL UNIQUE,
  owner_deck_id                TEXT NOT NULL,
  deck_ids_json                TEXT NOT NULL,
  species_ids_json             TEXT NOT NULL,
  rank                         TEXT NOT NULL,
  scientific_name              TEXT NOT NULL,
  common_names_state           TEXT NOT NULL DEFAULT 'pending',
  attempt_count                INTEGER NOT NULL DEFAULT 0,
  next_attempt_at              INTEGER,
  last_error                   TEXT,
  last_failure_kind            TEXT,
  updated_at                   INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_enrichment_taxonomy_work_owner
  ON enrichment_taxonomy_work(owner_deck_id);

CREATE INDEX IF NOT EXISTS idx_enrichment_taxonomy_work_runtime_entity
  ON enrichment_taxonomy_work(runtime_entity_key);
