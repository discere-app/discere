CREATE TABLE IF NOT EXISTS inat_photo_cache (
  species_id   TEXT NOT NULL,
  photo_url    TEXT NOT NULL,
  thumb_url    TEXT,
  attribution  TEXT,
  license_code TEXT,
  fetched_at   INTEGER NOT NULL,
  PRIMARY KEY (species_id, photo_url)
)
