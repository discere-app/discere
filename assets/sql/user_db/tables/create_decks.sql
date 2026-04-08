CREATE TABLE decks (
  id              TEXT PRIMARY KEY,
  name            TEXT NOT NULL,
  description     TEXT,
  coverImagePath  TEXT,
  language        INTEGER NOT NULL DEFAULT 1
)
