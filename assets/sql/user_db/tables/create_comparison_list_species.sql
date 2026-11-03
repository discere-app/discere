-- The species of a comparison list, each at most once, shown in the order
-- they were added (added_at, then insertion order for species added together).
-- Deleting a list takes its rows along.
CREATE TABLE IF NOT EXISTS comparison_list_species (
  list_id    TEXT NOT NULL REFERENCES comparison_lists(id) ON DELETE CASCADE,
  species_id TEXT NOT NULL,
  added_at   INTEGER NOT NULL,
  PRIMARY KEY (list_id, species_id)
)
