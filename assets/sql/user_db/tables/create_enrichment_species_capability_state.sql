CREATE TABLE IF NOT EXISTS enrichment_species_capability_state (
  species_id        TEXT NOT NULL,
  capability        TEXT NOT NULL,
  state             TEXT NOT NULL DEFAULT 'pending',
  priority_tier     INTEGER NOT NULL DEFAULT 0,
  attempt_count     INTEGER NOT NULL DEFAULT 0,
  next_attempt_at   INTEGER,
  last_error        TEXT,
  last_failure_kind TEXT,
  updated_at        INTEGER NOT NULL,
  PRIMARY KEY (species_id, capability)
);

CREATE INDEX IF NOT EXISTS idx_enrichment_species_capability_queue
  ON enrichment_species_capability_state(capability, state, priority_tier, updated_at);
