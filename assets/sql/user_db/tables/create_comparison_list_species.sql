-- The species of a comparison list, each at most once, shown by position
-- (then insertion order for a position two rows share). A species removed and
-- put back takes its old position again. Deleting a list takes its rows along.
CREATE TABLE IF NOT EXISTS comparison_list_species (
  list_id    TEXT NOT NULL REFERENCES comparison_lists(id) ON DELETE CASCADE,
  species_id TEXT NOT NULL,
  position   INTEGER NOT NULL,
  PRIMARY KEY (list_id, species_id)
)
