CREATE TABLE IF NOT EXISTS daily_counts (
  deck_id      TEXT    NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
  date         TEXT    NOT NULL,
  learning_mode TEXT   NOT NULL DEFAULT 'species',
  new_count    INTEGER DEFAULT 0,
  review_count INTEGER DEFAULT 0,
  PRIMARY KEY (deck_id, date, learning_mode)
)
