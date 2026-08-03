-- Which species belong to a taxonomy work item (genus/family/... common-name
-- fetch), normalized out of the old species_ids_json column. The only stored
-- association on taxonomy work: deck scoping is derived from here joined
-- against enrichment_species_deck_membership (deck<->taxon = species<->taxon
-- composed with species<->deck), so it is never persisted separately.
CREATE TABLE IF NOT EXISTS enrichment_taxonomy_work_species (
  work_key    TEXT NOT NULL,
  species_id  TEXT NOT NULL,
  PRIMARY KEY (work_key, species_id)
);

-- Drives both the per-species terminal check (pruneSpeciesMembership) and the
-- per-deck projection join, so index the species side.
CREATE INDEX IF NOT EXISTS idx_enrichment_taxonomy_work_species_species
  ON enrichment_taxonomy_work_species(species_id);
