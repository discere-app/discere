CREATE TABLE IF NOT EXISTS decks (
  id              TEXT PRIMARY KEY,
  name            TEXT NOT NULL,
  description     TEXT,
  coverImagePath  TEXT,
  language        INTEGER NOT NULL DEFAULT 1,
  sortOrder       INTEGER NOT NULL DEFAULT 0
)
