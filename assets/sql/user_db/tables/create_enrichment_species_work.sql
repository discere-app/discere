CREATE TABLE IF NOT EXISTS enrichment_species_work (
  species_id                  TEXT PRIMARY KEY,
  owner_deck_id               TEXT NOT NULL,
  deck_ids_json               TEXT NOT NULL,
  deck_count                  INTEGER NOT NULL DEFAULT 0,
  base_state                  TEXT NOT NULL DEFAULT 'pending',
  inat_primary_state          TEXT NOT NULL DEFAULT 'pending',
  species_common_names_state  TEXT NOT NULL DEFAULT 'pending',
  inat_backfill_state         TEXT NOT NULL DEFAULT 'pending',
  updated_at                  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_enrichment_species_work_owner
  ON enrichment_species_work(owner_deck_id);
