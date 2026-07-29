CREATE TABLE IF NOT EXISTS enrichment_unresolved_names (
  deck_id         TEXT NOT NULL,
  name            TEXT NOT NULL,
  state           TEXT NOT NULL DEFAULT 'pending',
  attempt_count   INTEGER NOT NULL DEFAULT 0,
  next_attempt_at INTEGER,
  last_error      TEXT,
  updated_at      INTEGER NOT NULL,
  PRIMARY KEY (deck_id, name)
);

CREATE INDEX IF NOT EXISTS idx_enrichment_unresolved_names_state
  ON enrichment_unresolved_names(state, next_attempt_at);
