-- Which subdeck a species of the deck belongs to; at most one. A species
-- without a row here belongs to no subdeck and is always a card. Removing a
-- subdeck takes its rows along, leaving its species without one.
CREATE TABLE IF NOT EXISTS deck_subdeck_species (
  deck_id    TEXT NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
  species_id TEXT NOT NULL,
  subdeck_id TEXT NOT NULL,
  PRIMARY KEY (deck_id, species_id),
  FOREIGN KEY (deck_id, subdeck_id)
    REFERENCES deck_subdecks(deck_id, subdeck_id) ON DELETE CASCADE
)
