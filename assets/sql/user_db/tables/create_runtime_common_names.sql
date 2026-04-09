CREATE TABLE IF NOT EXISTS runtime_common_names (
  entity_key     TEXT NOT NULL,
  entity_type    TEXT NOT NULL,
  language_code  TEXT NOT NULL,
  names          TEXT NOT NULL,
  fetched_at     INTEGER NOT NULL,
  PRIMARY KEY (entity_key, language_code)
)
