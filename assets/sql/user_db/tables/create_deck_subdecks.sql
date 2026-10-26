-- The subdecks of a deck, as its catalog entry or shared JSON names them.
-- subdeck_id is the id from that JSON, so an update finds a subdeck again
-- and keeps whether the user switched it off.
CREATE TABLE IF NOT EXISTS deck_subdecks (
  deck_id    TEXT NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
  subdeck_id TEXT NOT NULL,
  name       TEXT NOT NULL,
  sort_order INTEGER NOT NULL DEFAULT 0,
  is_active  INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (deck_id, subdeck_id)
)
