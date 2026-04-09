-- =============================================================================
-- iNaturalist Enrichment — External ID Mapping
--
-- Lädt taxa.csv von iNaturalist (AWS Open Data) und schreibt das
-- Mapping zwischen Discere-Entities und iNaturalist taxon_id.
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
-- Species werden über den vollen Binomialnamen (Genus + Epitheton) gematcht.
-- Taxonomie-Ränge (genus/family/order/class) werden über ihren
-- wissenschaftlichen Namen gematcht und als normalisierte Entity-Keys
-- (`genus:barbus`, `family:cyprinidae`, ...) exportiert.
--
-- Platzhalter (via sed in enrich.sh):
--   ${TAXA_CSV}    — Pfad zur entpackten taxa.csv
--   ${SPECIES_CSV} — Pfad zur exportierten species.csv aus SQLite
--   ${TAXONOMY_CSV} — Pfad zur exportierten Taxonomie-Tabelle aus SQLite
--   ${EXPORT_DIR}   — Ausgabeverzeichnis für CSVs
--   ${SYNCED_AT}    — UTC-Datum des Enrichment-Runs
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Schritt 1: taxa.csv laden, auf aktive Ziel-Ränge filtern
-- ---------------------------------------------------------------------------
CREATE TEMP TABLE t_inat_taxa AS
SELECT
    taxon_id,
    rank,
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
WHERE rank IN ('species', 'genus', 'family', 'order', 'class')
  AND active = true;

-- ---------------------------------------------------------------------------
-- Schritt 2: JOIN auf Species und Taxonomie-Entities, External-ID-Mapping
-- exportieren
-- ---------------------------------------------------------------------------
COPY (
    WITH species_mappings AS (
        SELECT DISTINCT
        s.entity_id                                                AS entity_id,
        'species'                                                  AS entity_type,
        'inaturalist'                                              AS provider,
        CAST(t.taxon_id AS VARCHAR)                                AS external_id,
        '${SYNCED_AT}'                                             AS last_synced_at,
        NULL                                                       AS metadata_json
        FROM read_csv('${SPECIES_CSV}',
            delim   = '\t',
            header  = true,
            columns = {
                'entity_id':        'VARCHAR',
                'scientific_name':  'VARCHAR'
            }
        ) s
        JOIN t_inat_taxa t
          ON t.rank = 'species'
         AND t.name = s.scientific_name
    ),
    taxonomy_mappings AS (
        SELECT DISTINCT
        e.entity_id                                                AS entity_id,
        e.entity_type                                              AS entity_type,
        'inaturalist'                                              AS provider,
        CAST(t.taxon_id AS VARCHAR)                                AS external_id,
        '${SYNCED_AT}'                                             AS last_synced_at,
        NULL                                                       AS metadata_json
        FROM read_csv('${TAXONOMY_CSV}',
            delim   = '\t',
            header  = true,
            columns = {
                'entity_id':        'VARCHAR',
                'entity_type':      'VARCHAR',
                'rank':             'VARCHAR',
                'scientific_name':  'VARCHAR'
            }
        ) e
        JOIN t_inat_taxa t
          ON t.rank = e.rank
         AND t.name = e.scientific_name
    )
    SELECT * FROM species_mappings
    UNION
    SELECT * FROM taxonomy_mappings
    ORDER BY entity_type, entity_id
)
TO '${EXPORT_DIR}/entity_external_ids.csv' (FORMAT csv, HEADER true);
