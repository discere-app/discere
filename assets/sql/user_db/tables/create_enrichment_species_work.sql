-- Additive superset of the original shape: base_state/inat_primary_state/
-- species_common_names_state/inat_backfill_state/deck_ids_json are still
-- read/written unchanged by EnrichmentJobExecutor/EnrichmentWorkRepository.
-- wants_inat_photos/wants_common_names are the new OR'd-across-decks consent
-- flags backfilled by the v11->v12 migration for the producer-consumer
-- rewrite; the old per-stage columns get dropped in a later migration once
-- that rewrite's workers replace the executor (see
-- DatabaseHelper._migrateUserSchemaV11ToV12's doc comment).
CREATE TABLE IF NOT EXISTS enrichment_species_work (
  species_id                  TEXT PRIMARY KEY,
  owner_deck_id               TEXT NOT NULL,
  deck_ids_json               TEXT NOT NULL,
  deck_count                  INTEGER NOT NULL DEFAULT 0,
  base_state                  TEXT NOT NULL DEFAULT 'pending',
  inat_primary_state          TEXT NOT NULL DEFAULT 'pending',
  species_common_names_state  TEXT NOT NULL DEFAULT 'pending',
  inat_backfill_state         TEXT NOT NULL DEFAULT 'pending',
  wants_inat_photos           INTEGER NOT NULL DEFAULT 0,
  wants_common_names          INTEGER NOT NULL DEFAULT 0,
  updated_at                  INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_enrichment_species_work_owner
  ON enrichment_species_work(owner_deck_id);
