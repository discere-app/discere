CREATE TABLE IF NOT EXISTS deck_config (
  deck_id              TEXT PRIMARY KEY REFERENCES decks(id) ON DELETE CASCADE,
  desired_retention    REAL    DEFAULT 0.9,
  maximum_interval     INTEGER DEFAULT 36500,
  learning_steps       TEXT    DEFAULT '1,10',
  relearning_steps     TEXT    DEFAULT '10',
  learning_mode        TEXT    NOT NULL DEFAULT 'species',
  name_type            TEXT    NOT NULL DEFAULT 'commonName',
  review_mode          TEXT    NOT NULL DEFAULT 'flip'
)
