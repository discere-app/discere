CREATE TABLE IF NOT EXISTS flashcard_stats (
  species_id       TEXT NOT NULL,
  deck_id          TEXT NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
  learning_mode    TEXT NOT NULL DEFAULT 'species',
  next_review_date INTEGER,
  stability        REAL    DEFAULT 0.0,
  difficulty       REAL    DEFAULT 0.0,
  last_review_date INTEGER,
  card_state       INTEGER DEFAULT 0,
  step_index       INTEGER DEFAULT 0,
  PRIMARY KEY (deck_id, species_id, learning_mode)
)
