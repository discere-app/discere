-- The subdeck of an imported name that did not resolve locally. The
-- enrichment queue resolves such names later and adds the species by name;
-- the row says which subdeck it goes to and is consumed then.
CREATE TABLE IF NOT EXISTS deck_subdeck_unresolved_names (
  deck_id    TEXT NOT NULL REFERENCES decks(id) ON DELETE CASCADE,
  name       TEXT NOT NULL,
  subdeck_id TEXT NOT NULL,
  PRIMARY KEY (deck_id, name),
  FOREIGN KEY (deck_id, subdeck_id)
    REFERENCES deck_subdecks(deck_id, subdeck_id) ON DELETE CASCADE
)
