-- =============================================================================
-- iNaturalist Enrichment — External ID Mapping
--
-- Lädt taxa.csv von iNaturalist (AWS Open Data) und schreibt das
-- Mapping zwischen Species-Entity-ID und iNaturalist taxon_id.
--
-- Ermöglicht der App, beim iNat-Foto-Download den Name-Search-API-Call
-- zu überspringen und direkt per external_id (taxon_id) abzufragen.
--
-- taxa.csv Schema:
--   taxon_id        INTEGER
--   ancestry        TEXT
--   rank_level      INTEGER
--   rank            TEXT    -- 'species', 'genus', 'family', ...
--   name            TEXT    -- wissenschaftlicher Name
--   active          BOOLEAN
--
-- Nur rank = 'species' und active = true werden verarbeitet.
-- Match auf species.name (wissenschaftlicher Name).
--
-- Platzhalter (via sed in enrich.sh):
--   ${TAXA_CSV}    — Pfad zur entpackten taxa.csv
--   ${SPECIES_CSV} — Pfad zur exportierten species.csv aus SQLite
--   ${EXPORT_DIR}  — Ausgabeverzeichnis für CSVs
--   ${SYNCED_AT}   — UTC-Datum des Enrichment-Runs
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Schritt 1: taxa.csv laden, auf aktive Species filtern
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_inat_taxa AS
SELECT
    taxon_id,
    name
FROM read_csv('${TAXA_CSV}',
    delim         = '\t',
    header        = true,
    ignore_errors = true,
    columns = {
        'taxon_id':   'INTEGER',
        'ancestry':   'VARCHAR',
        'rank_level': 'INTEGER',
        'rank':       'VARCHAR',
        'name':       'VARCHAR',
        'active':     'BOOLEAN'
    }
)
WHERE rank = 'species'
  AND active = true;

-- ---------------------------------------------------------------------------
-- Schritt 2: JOIN auf bestehende Species, External-ID-Mapping exportieren
-- ---------------------------------------------------------------------------
COPY (
    SELECT DISTINCT
        s.species_id                                               AS entity_id,
        'species'                                                  AS entity_type,
        'inaturalist'                                              AS provider,
        CAST(t.taxon_id AS VARCHAR)                                AS external_id,
        '${SYNCED_AT}'                                             AS last_synced_at,
        NULL                                                       AS metadata_json
    FROM read_csv('${SPECIES_CSV}',
        delim   = '\t',
        header  = true,
        columns = {
            'species_id': 'VARCHAR',
            'name':       'VARCHAR'
        }
    ) s
    JOIN t_inat_taxa t ON t.name = s.name
    ORDER BY s.species_id
)
TO '${EXPORT_DIR}/entity_external_ids.csv' (FORMAT csv, HEADER true);
