-- The subdecks of a deck. subdeck_id is the id from the catalog entry or
-- shared JSON the subdeck came from, so an update finds it again and keeps
-- whether the user switched it off, or a generated one for a subdeck the user
-- added in Edit Deck.
CREATE TABLE IF NOT EXISTS deck_subdecks (
  deck_id    TEXT NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
  subdeck_id TEXT NOT NULL,
  name       TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active  INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (deck_id, subdeck_id)
)
