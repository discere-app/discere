CREATE TABLE IF NOT EXISTS external_identifier_cache (
  entity_id       TEXT NOT NULL,
  provider        TEXT NOT NULL,
  external_id     TEXT NOT NULL,
  last_synced_at  INTEGER NOT NULL,
  PRIMARY KEY (entity_id, provider)
)
