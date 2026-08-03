-- Deduplicated taxonomy common-name work (one row per taxon, keyed by
-- work_key; runtime_entity_key is the merge key and the iNat fetch key). No
-- deck or species columns: species membership lives in the
-- enrichment_taxonomy_work_species junction, and deck scoping is derived from
-- that junction joined against enrichment_species_deck_membership rather than
-- stored (deck<->taxon is fully derivable from species<->taxon and
-- species<->deck). rank/scientific_name are likewise not stored — they were
-- write-only and are already encoded in runtime_entity_key (`rank:<name>`).
CREATE TABLE IF NOT EXISTS enrichment_taxonomy_work (
  work_key                     TEXT PRIMARY KEY,
  runtime_entity_key           TEXT NOT NULL UNIQUE,
  common_names_state           TEXT NOT NULL DEFAULT 'pending',
  attempt_count                INTEGER NOT NULL DEFAULT 0,
  next_attempt_at              INTEGER,
  last_error                   TEXT,
  last_failure_kind            TEXT,
  updated_at                   INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_enrichment_taxonomy_work_runtime_entity
  ON enrichment_taxonomy_work(runtime_entity_key);
