-- A deck whose subdecks the user changed in Edit Deck, not just switched on
-- or off: a deck update then keeps its division unless the user asks for the
-- catalog's.
CREATE TABLE IF NOT EXISTS deck_subdeck_customizations (
  deck_id TEXT PRIMARY KEY REFERENCES decks(id) ON DELETE CASCADE
)
