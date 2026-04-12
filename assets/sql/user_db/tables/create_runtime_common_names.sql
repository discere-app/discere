CREATE TABLE IF NOT EXISTS runtime_common_names (
  entity_key     TEXT    NOT NULL,
  entity_type    TEXT    NOT NULL,
  language_code  TEXT    NOT NULL,
  name           TEXT    NOT NULL,
  position       INTEGER,           -- globales iNat-Ranking (niedriger = besser)
  place_id       INTEGER,           -- iNat Place-ID, NULL = globaler Name
  place_position INTEGER,           -- Ranking innerhalb dieses Place
  fetched_at     INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_runtime_common_names_lookup
  ON runtime_common_names(entity_key, language_code);
