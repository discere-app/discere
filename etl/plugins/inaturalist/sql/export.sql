-- =============================================================================
-- iNaturalist Export — eine DuckDB-Session
--
-- Liest taxa.csv.gz (iNaturalist Open Data) und schreibt die Datensätze, die
-- der Abgleich (core/match.sh) zuordnen soll.
--
-- taxa.csv Schema (tabgetrennt):
--   taxon_id, ancestry, rank_level, rank, name, active
--   ancestry — IDs der Vorfahren, mit / getrennt, ohne das Taxon selbst
--
-- Berücksichtigt werden aktive Taxa der Ränge species, genus, family, order
-- und class, deren Name auf diesem Rang in der Referenz-DB vorkommt
-- (${REFERENCE_NAMES}, aus reference_names.sql). iNaturalist führt die ganze
-- Lebenswelt; ohne diese Eingrenzung landeten über eine Million Taxa als
-- „none“ im Build-Bericht.
--
-- Stammprüfung (docs/datenquellen.md, iNaturalist-Abgleich): Der Name allein
-- trennt keine Homonyme über Reiche und Stämme hinweg. Ein iNaturalist-Taxon
-- geht nur in den Abgleich, wenn sein Stamm zu jeder Entität passt, die
-- seinen Namen auf diesem Rang trägt — bei Arten auch als Synonym:
--   - Stamm der Kette gleich dem iNaturalist-Stamm oder ihm gleichwertig
--     (${PHYLUM_EQUIVALENTS}: Stamm der Kette, iNaturalist-Stamm);
--   - ist der Stamm der Kette ein Rang-Platzhalter, der ein Reich nennt
--     („Not Assigned (Plantae)“), das iNaturalist führt, das Reich — nur
--     beim einzigen Träger des Namens;
--   - sonst — Kette ohne Stamm, Platzhalter ohne Reich, iNaturalist-Taxon
--     ohne Stamm bzw. Reich in seiner Ahnenkette — ist nichts prüfbar.
-- Den Stamm und das Reich eines iNaturalist-Taxons liefern die eigenen
-- Zeilen von taxa.csv über ancestry, ohne API.
--
-- Abgelehnt wird mit Grund, in dieser Reihenfolge:
--   phylum_mixed     der Stamm passt zu einem Teil der Entitäten des Namens,
--                    zu einem anderen nicht: Der Name steht in der DB für
--                    Taxa verschiedener Stämme (bei höheren Taxa teilen sie
--                    sich einen Namensschlüssel)
--   phylum_unknown   für mindestens eine Entität nicht prüfbar
--   phylum_mismatch  zu keiner Entität passend
--
-- Mehrere aktive iNaturalist-Taxa mit gleichem Namen und Rang (Homonyme)
-- bekommen keine Zuordnung, wenn nach der Stammprüfung mehr als eines übrig
-- bleibt: Welches gemeint ist, lässt sich dann nicht entscheiden. Bleibt
-- genau eines, geht es in den Abgleich.
--
-- Alle TSVs hier sind ohne Quoting: Ein " gehört zum Namen (es gibt
-- Gattungsnamen in Anführungszeichen), Tabs und Zeilenumbrüche kommen in den
-- Namen nicht vor.
--
-- Platzhalter (via sed in import.sh):
--   ${TAXA_FILE}             — taxa.csv.gz
--   ${REFERENCE_NAMES}       — TSV aus reference_names.sql
--   ${PHYLUM_EQUIVALENTS}    — data/phylum_equivalents.csv
--   ${PLACEHOLDER_PATTERNS}  — core/data/placeholder_patterns.csv
--   ${EXPORT_DIR}            — Ausgabeverzeichnis
--
-- Ausgaben in ${EXPORT_DIR}:
--   match_input.tsv  record_key, rank, name — Eingabe für core/match.sh
--   report.tsv       Zeilen für plugin_report: Kategorie, Schlüssel, Name,
--                    Detail (abgelehnte Taxa und Homonyme)
-- =============================================================================

CREATE TEMP TABLE t_carriers AS
SELECT DISTINCT rank, normalized_name, entity_id, NULLIF(chain_phylum, '') AS chain_phylum
FROM read_csv('${REFERENCE_NAMES}', delim = '\t', header = true, quote = '', escape = '', columns = {
    'rank':            'VARCHAR',
    'normalized_name': 'VARCHAR',
    'entity_id':       'VARCHAR',
    'chain_phylum':    'VARCHAR'
});

CREATE TEMP TABLE t_phylum_equivalents AS
SELECT phylum, inat_phylum
FROM read_csv('${PHYLUM_EQUIVALENTS}', header = true, columns = {
    'phylum':      'VARCHAR',
    'inat_phylum': 'VARCHAR',
    'reason':      'VARCHAR'
});

CREATE TEMP TABLE t_placeholder_patterns AS
SELECT pattern FROM read_csv('${PLACEHOLDER_PATTERNS}', header = true, columns = {'pattern': 'VARCHAR'});

CREATE TEMP TABLE t_taxa AS
SELECT t.taxon_id, t.ancestry, t.rank, TRIM(t.name) AS name
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
WHERE t.active = true;

-- Was je Entität geprüft wird: check_rank 'phylum' oder 'kingdom' mit dem
-- Wert, gegen den verglichen wird; ohne check_rank ist nichts prüfbar. Das
-- Reich allein genügt nur für den einzigen Träger eines Namens: Neben
-- weiteren gleichnamigen Entitäten ließe es offen, ob alle zum selben Stamm
-- gehören.
CREATE TEMP TABLE t_carrier_checks AS
WITH classified AS (
    SELECT
        c.*,
        EXISTS (SELECT 1 FROM t_placeholder_patterns p
                WHERE LOWER(TRIM(c.chain_phylum)) GLOB p.pattern) AS is_placeholder,
        regexp_extract(TRIM(c.chain_phylum), '\(([^()]*)\)$', 1) AS named_kingdom,
        COUNT(*) OVER (PARTITION BY c.rank, c.normalized_name) AS carriers_of_name
    FROM t_carriers c
)
SELECT
    rank, normalized_name, entity_id, chain_phylum,
    CASE
        WHEN chain_phylum IS NULL THEN NULL
        WHEN NOT is_placeholder THEN 'phylum'
        WHEN carriers_of_name = 1
         AND named_kingdom IN (SELECT name FROM t_taxa WHERE rank = 'kingdom') THEN 'kingdom'
    END AS check_rank,
    CASE WHEN is_placeholder THEN named_kingdom ELSE chain_phylum END AS check_value
FROM classified;

CREATE TEMP TABLE t_inat_taxa AS
SELECT
    CAST(t.taxon_id AS VARCHAR) AS record_key,
    t.rank,
    t.name,
    LOWER(t.name) AS normalized_name,
    t.ancestry
FROM t_taxa t
SEMI JOIN t_carriers c
  ON c.rank = t.rank
 AND c.normalized_name = LOWER(t.name);

-- Stamm und Reich aus der Ahnenkette; eine Kette mit zwei Stämmen oder
-- Reichen zählt als ohne.
CREATE TEMP TABLE t_inat_lineage AS
WITH ancestors AS (
    SELECT i.record_key, TRY_CAST(a.ancestor_id AS INTEGER) AS ancestor_id
    FROM t_inat_taxa i,
         UNNEST(string_split(i.ancestry, '/')) AS a(ancestor_id)
)
SELECT
    i.record_key,
    CASE WHEN COUNT(DISTINCT t.name) FILTER (WHERE t.rank = 'phylum') = 1
         THEN MAX(t.name) FILTER (WHERE t.rank = 'phylum') END AS phylum,
    CASE WHEN COUNT(DISTINCT t.name) FILTER (WHERE t.rank = 'kingdom') = 1
         THEN MAX(t.name) FILTER (WHERE t.rank = 'kingdom') END AS kingdom
FROM t_inat_taxa i
LEFT JOIN ancestors a ON a.record_key = i.record_key
LEFT JOIN t_taxa t ON t.taxon_id = a.ancestor_id AND t.rank IN ('phylum', 'kingdom')
GROUP BY i.record_key;

-- Je iNaturalist-Taxon und Entität seines Namens: passt (true), passt nicht
-- (false) oder nicht prüfbar (NULL).
CREATE TEMP TABLE t_phylum_checks AS
SELECT
    i.record_key, i.rank, i.name, i.normalized_name,
    l.phylum AS inat_phylum, l.kingdom AS inat_kingdom,
    c.entity_id, c.chain_phylum,
    CASE c.check_rank
        WHEN 'phylum' THEN
            l.phylum = c.check_value
            OR EXISTS (SELECT 1 FROM t_phylum_equivalents e
                       WHERE e.phylum = c.check_value AND e.inat_phylum = l.phylum)
        WHEN 'kingdom' THEN l.kingdom = c.check_value
    END AS fits
FROM t_inat_taxa i
JOIN t_inat_lineage l ON l.record_key = i.record_key
JOIN t_carrier_checks c ON c.rank = i.rank AND c.normalized_name = i.normalized_name;

CREATE TEMP TABLE t_phylum_verdicts AS
SELECT
    record_key, rank, name, normalized_name,
    CASE
        WHEN bool_or(fits) AND bool_or(NOT fits) THEN 'phylum_mixed'
        WHEN bool_or(fits IS NULL) THEN 'phylum_unknown'
        WHEN NOT bool_or(fits) THEN 'phylum_mismatch'
    END AS rejection,
    'iNaturalist: ' || COALESCE(MIN(inat_phylum), 'ohne Stamm')
        || ' (' || COALESCE(MIN(inat_kingdom), 'ohne Reich') || '); Kette: '
        || string_agg(entity_id || ' ' || COALESCE(chain_phylum, 'ohne Stamm'), ', ' ORDER BY entity_id)
        AS detail
FROM t_phylum_checks
GROUP BY record_key, rank, name, normalized_name;

CREATE TEMP TABLE t_homonyms AS
SELECT rank, normalized_name
FROM t_phylum_verdicts
WHERE rejection IS NULL
GROUP BY rank, normalized_name
HAVING COUNT(*) > 1;

COPY (
    SELECT v.record_key, v.rank, v.name
    FROM t_phylum_verdicts v
    ANTI JOIN t_homonyms h
      ON h.rank = v.rank
     AND h.normalized_name = v.normalized_name
    WHERE v.rejection IS NULL
    ORDER BY v.rank, v.record_key
) TO '${EXPORT_DIR}/match_input.tsv' (FORMAT csv, DELIMITER '\t', HEADER true, QUOTE '', ESCAPE '');

COPY (
    SELECT rejection, record_key, name, detail
    FROM t_phylum_verdicts
    WHERE rejection IS NOT NULL
    UNION ALL
    SELECT
        'ambiguous',
        string_agg(v.record_key, ', ' ORDER BY v.record_key),
        MIN(v.name),
        'mehrere aktive iNaturalist-Taxa mit passendem Stamm auf Rang ' || v.rank
    FROM t_phylum_verdicts v
    JOIN t_homonyms h
      ON h.rank = v.rank
     AND h.normalized_name = v.normalized_name
    WHERE v.rejection IS NULL
    GROUP BY v.rank, v.normalized_name
    ORDER BY 1, 3, 2
) TO '${EXPORT_DIR}/report.tsv' (FORMAT csv, DELIMITER '\t', HEADER false, QUOTE '', ESCAPE '');
