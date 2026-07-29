CREATE TABLE IF NOT EXISTS enrichment_species_deck_membership (
  species_id TEXT NOT NULL,
  deck_id    TEXT NOT NULL,
  PRIMARY KEY (species_id, deck_id)
);

CREATE INDEX IF NOT EXISTS idx_enrichment_species_deck_membership_deck
  ON enrichment_species_deck_membership(deck_id);
