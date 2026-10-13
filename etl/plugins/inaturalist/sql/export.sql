-- =============================================================================
-- iNaturalist Export — eine DuckDB-Session
--
-- Liest taxa.csv.gz (iNaturalist Open Data) und schreibt die Datensätze, die
-- der Abgleich (core/match.sh) zuordnen soll.
--
-- taxa.csv Schema (tabgetrennt):
--   taxon_id, ancestry, rank_level, rank, name, active
--
-- Berücksichtigt werden aktive Taxa der Ränge species, genus, family, order
-- und class, deren Name auf diesem Rang in der Referenz-DB vorkommt
-- (${REFERENCE_NAMES}, normalisiert wie species_scientific_names). iNaturalist
-- führt die ganze Lebenswelt; ohne diese Eingrenzung landeten über eine
-- Million Taxa als „none“ im Build-Bericht.
--
-- Mehrere aktive iNaturalist-Taxa mit gleichem Namen und Rang (Homonyme,
-- meist über Reiche hinweg) bekommen keine Zuordnung: Welches gemeint ist,
-- lässt sich am Namen nicht entscheiden. Sie gehen nach homonyms.tsv, von
-- dort in den Build-Bericht.
--
-- Platzhalter (via sed in import.sh):
--   ${TAXA_FILE}        — taxa.csv.gz
--   ${REFERENCE_NAMES}  — TSV mit rank, normalized_name aus der Referenz-DB
--   ${EXPORT_DIR}       — Ausgabeverzeichnis
-- =============================================================================

CREATE TEMP TABLE t_reference_names AS
SELECT DISTINCT rank, normalized_name
FROM read_csv('${REFERENCE_NAMES}', delim = '\t', header = true, columns = {
    'rank':            'VARCHAR',
    'normalized_name': 'VARCHAR'
});

CREATE TEMP TABLE t_inat_taxa AS
SELECT
    CAST(t.taxon_id AS VARCHAR) AS record_key,
    t.rank,
    TRIM(t.name)                AS name,
    LOWER(TRIM(t.name))         AS normalized_name
FROM read_csv('${TAXA_FILE}',
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
) t
SEMI JOIN t_reference_names r
  ON r.rank = t.rank
 AND r.normalized_name = LOWER(TRIM(t.name))
WHERE t.active = true;

CREATE TEMP TABLE t_homonyms AS
SELECT rank, normalized_name
FROM t_inat_taxa
GROUP BY rank, normalized_name
HAVING COUNT(*) > 1;

COPY (
    SELECT t.record_key, t.rank, t.name
    FROM t_inat_taxa t
    ANTI JOIN t_homonyms h
      ON h.rank = t.rank
     AND h.normalized_name = t.normalized_name
    ORDER BY t.rank, t.record_key
) TO '${EXPORT_DIR}/match_input.tsv' (FORMAT csv, DELIMITER '\t', HEADER true);

-- Zeilen für plugin_report: Kategorie, Schlüssel, Name, Detail
COPY (
    SELECT
        'ambiguous',
        string_agg(t.record_key, ', ' ORDER BY t.record_key),
        MIN(t.name),
        'mehrere aktive iNaturalist-Taxa auf Rang ' || t.rank
    FROM t_inat_taxa t
    JOIN t_homonyms h
      ON h.rank = t.rank
     AND h.normalized_name = t.normalized_name
    GROUP BY t.rank, t.normalized_name
    ORDER BY t.rank, t.normalized_name
) TO '${EXPORT_DIR}/homonyms.tsv' (FORMAT csv, DELIMITER '\t', HEADER false);
