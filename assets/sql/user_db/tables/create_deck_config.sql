CREATE TABLE IF NOT EXISTS deck_config (
  deck_id              TEXT PRIMARY KEY REFERENCES decks(id) ON DELETE CASCADE,
  desired_retention    REAL    DEFAULT 0.9,
  maximum_interval     INTEGER DEFAULT 36500,
  learning_steps       TEXT    DEFAULT '1,10',
  relearning_steps     TEXT    DEFAULT '10',
  new_cards_per_day    INTEGER DEFAULT 20,
  max_reviews_per_day  INTEGER DEFAULT 200,
  learning_mode        TEXT    NOT NULL DEFAULT 'species'
)
