CREATE TABLE IF NOT EXISTS enrichment_taxonomy_work (
  work_key                     TEXT PRIMARY KEY,
  runtime_entity_key           TEXT NOT NULL UNIQUE,
  owner_deck_id                TEXT NOT NULL,
  deck_ids_json                TEXT NOT NULL,
  species_ids_json             TEXT NOT NULL,
  rank                         TEXT NOT NULL,
  scientific_name              TEXT NOT NULL,
  common_names_state           TEXT NOT NULL DEFAULT 'pending',
  updated_at                   INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_enrichment_taxonomy_work_owner
  ON enrichment_taxonomy_work(owner_deck_id);

CREATE INDEX IF NOT EXISTS idx_enrichment_taxonomy_work_runtime_entity
  ON enrichment_taxonomy_work(runtime_entity_key);
