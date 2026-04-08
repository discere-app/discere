CREATE TABLE IF NOT EXISTS runtime_common_name_search_documents (
  entity_key             TEXT NOT NULL PRIMARY KEY,
  entity_id              TEXT NOT NULL,
  entity_type            TEXT NOT NULL,
  scientific_name        TEXT NOT NULL,
  common_name_en         TEXT,
  common_name_de         TEXT,
  common_name_fr         TEXT,
  common_name_es         TEXT,
  normalized_search_text TEXT NOT NULL
)
