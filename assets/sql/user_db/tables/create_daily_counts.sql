CREATE TABLE IF NOT EXISTS daily_counts (
  deck_id      TEXT    NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
  date         TEXT    NOT NULL,
  new_count    INTEGER DEFAULT 0,
  review_count INTEGER DEFAULT 0,
  PRIMARY KEY (deck_id, date)
)
