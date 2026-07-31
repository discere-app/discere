-- No owner_deck_id: the shared INatWorker queue claims a row purely by
-- common_names_state/work_key, independent of any deck, so there is nothing
-- for a per-row "owning" deck to control. deck_ids_json still tracks which
-- decks reference this taxon, needed only for the deck-progress projection.
CREATE TABLE IF NOT EXISTS enrichment_taxonomy_work (
  work_key                     TEXT PRIMARY KEY,
  runtime_entity_key           TEXT NOT NULL UNIQUE,
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

CREATE INDEX IF NOT EXISTS idx_enrichment_taxonomy_work_runtime_entity
  ON enrichment_taxonomy_work(runtime_entity_key);
