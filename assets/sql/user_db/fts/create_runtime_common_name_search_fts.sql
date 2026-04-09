CREATE VIRTUAL TABLE IF NOT EXISTS runtime_common_name_search_fts
USING fts4(
  scientific_name,
  common_name_en,
  common_name_de,
  common_name_fr,
  common_name_es,
  tokenize=unicode61
)
