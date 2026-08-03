CREATE TABLE IF NOT EXISTS species_photo_gap_ack (
  deck_id         TEXT NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
  species_id      TEXT NOT NULL,
  acknowledged_at INTEGER NOT NULL,
  PRIMARY KEY (deck_id, species_id)
)
