-- The user's comparison lists: named collections of species to look at side
-- by side. Listed newest first, by created_at.
CREATE TABLE IF NOT EXISTS comparison_lists (
  id         TEXT NOT NULL PRIMARY KEY,
  name       TEXT NOT NULL,
  created_at INTEGER NOT NULL
)
