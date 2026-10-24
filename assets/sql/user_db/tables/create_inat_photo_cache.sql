CREATE TABLE IF NOT EXISTS inat_photo_cache (
  species_id   TEXT NOT NULL,
  photo_url    TEXT NOT NULL,
  thumb_url    TEXT,
  attribution  TEXT,
  license_code TEXT,
  fetched_at   INTEGER NOT NULL,
  -- The iNat taxon the photos were fetched from; NULL on an empty marker
  -- that no taxon was found for (docs/enrichment.md, "Herkunft der iNat-Daten")
  inat_taxon_id INTEGER,
  PRIMARY KEY (species_id, photo_url)
)
