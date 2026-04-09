CREATE TABLE flashcard_stats (
  species_id       TEXT NOT NULL,
  deck_id          TEXT NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
  next_review_date INTEGER,
  interval         INTEGER DEFAULT 0,
  repetition       INTEGER DEFAULT 0,
  ease_factor      REAL    DEFAULT 2.5,
  stability        REAL    DEFAULT 0.0,
  difficulty       REAL    DEFAULT 0.0,
  last_review_date INTEGER,
  PRIMARY KEY (deck_id, species_id)
)
