-- =============================================================================
-- iNaturalist Enrichment — Taxon ID Mapping
--
-- Lädt taxa.csv von iNaturalist (AWS Open Data) und schreibt das
-- Mapping zwischen species_id und iNaturalist taxon_id.
--
-- Ermöglicht der App, beim iNat-Foto-Download den Name-Search-API-Call
-- zu überspringen und direkt per taxon_id abzufragen.
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
WHERE rank   = 'species'

-- ---------------------------------------------------------------------------
-- Schritt 2: JOIN auf bestehende Species, Taxon-ID-Mapping exportieren
-- ---------------------------------------------------------------------------
COPY (
    SELECT DISTINCT
        s.species_id,
        t.taxon_id
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
TO '${EXPORT_DIR}/inat_taxon_ids.csv' (FORMAT csv, HEADER true);