-- Identity/ownership row for cross-deck species dedup, plus OR'd-across-decks
-- consent flags. Per-capability queue state lives in
-- enrichment_species_capability_state; deck membership lives in
-- enrichment_species_deck_membership. The old per-stage columns
-- (base_state/inat_primary_state/species_common_names_state/
-- inat_backfill_state) and deck_ids_json were dropped in the v12->v13
-- migration once the producer-consumer workers replaced the job executor
-- that used to read/write them.
CREATE TABLE IF NOT EXISTS enrichment_species_work (
  species_id          TEXT PRIMARY KEY,
  owner_deck_id       TEXT NOT NULL,
  deck_count          INTEGER NOT NULL DEFAULT 0,
  wants_inat_photos   INTEGER NOT NULL DEFAULT 0,
  wants_common_names  INTEGER NOT NULL DEFAULT 0,
  updated_at          INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_enrichment_species_work_owner
  ON enrichment_species_work(owner_deck_id);
