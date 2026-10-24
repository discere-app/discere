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
-- Prüfung gegen die eigene Kette (docs/datenquellen.md, Stamm und Kette bei
-- der iNaturalist-Zuordnung): Der Name allein trennt keine Homonyme. Ein
-- iNaturalist-Taxon geht nur in den Abgleich, wenn es zu jeder Entität
-- passt, die seinen Namen auf diesem Rang trägt — bei Arten auch als
-- Synonym. Stamm, Klasse, Ordnung und Familie des iNaturalist-Taxons kommen
-- aus den eigenen Zeilen von taxa.csv über ancestry, ohne API.
--
--   Stamm    gleich dem der Kette oder gleichwertig (${PHYLUM_EQUIVALENTS}).
--            Nicht prüfbar sind eine Kette ohne Stamm (etwa eine Art ohne
--            Gattung), ein Platzhalter-Stamm („Not Assigned (Plantae)“ —
--            SeaLifeBase ordnet darunter Einzeller auch falschen Reichen zu)
--            und ein iNaturalist-Taxon ohne Stamm in seiner Ahnenkette.
--   Klasse   Die Entitäten eines Namens liegen in höchstens einer Klasse
--            (Platzhalter zählen nicht): Sonst steht der Name für Taxa
--            verschiedener Klassen, und jedes iNaturalist-Taxon ist für
--            eine davon falsch.
--   Rang     Bei Gattungen, Familien und Ordnungen, und bei Arten, deren
--            Name bei iNaturalist mehrere aktive Taxa trägt: Klasse oder
--            Ordnung oder Familie des iNaturalist-Taxons passt zu jeder
--            Entität — verglichen werden nur die Ränge über dem eigenen,
--            die Klasse gleich oder gleichwertig (${CLASS_EQUIVALENTS}),
--            Ordnung und Familie gleich. Klassen prüft nur der Stamm.
--
-- Abgelehnt wird mit Grund, in dieser Reihenfolge:
--   phylum_mixed     der Stamm passt zu einem Teil der Entitäten des Namens,
--                    zu einem anderen nicht
--   phylum_unknown   der Stamm ist für mindestens eine Entität nicht prüfbar
--   phylum_mismatch  der Stamm passt zu keiner Entität
--   class_mixed      die Entitäten des Namens liegen in mehreren Klassen
--   rank_mismatch    weder Klasse noch Ordnung noch Familie passen zu jeder
--                    Entität
--
-- Mehrere aktive iNaturalist-Taxa mit gleichem Namen und Rang (Homonyme)
-- bekommen keine Zuordnung, wenn nach diesen Prüfungen mehr als eines übrig
-- bleibt. Bleibt genau eines, geht es in den Abgleich.
--
-- Alle TSVs hier sind ohne Quoting: Ein " gehört zum Namen (es gibt
-- Gattungsnamen in Anführungszeichen), Tabs und Zeilenumbrüche kommen in den
-- Namen nicht vor.
--
-- Platzhalter (via sed in import.sh):
--   ${TAXA_FILE}             — taxa.csv.gz
--   ${REFERENCE_NAMES}       — TSV aus reference_names.sql
--   ${PHYLUM_EQUIVALENTS}    — data/phylum_equivalents.csv
--   ${CLASS_EQUIVALENTS}     — data/class_equivalents.csv
--   ${PLACEHOLDER_PATTERNS}  — core/data/placeholder_patterns.csv
--   ${EXPORT_DIR}            — Ausgabeverzeichnis
--
-- Ausgaben in ${EXPORT_DIR}:
--   match_input.tsv  record_key, rank, name — Eingabe für core/match.sh
--   lineage.tsv      record_key, phylum, class, order, family, homonym — je
--                    Datensatz aus match_input.tsv, für die Prüfung der
--                    Synonym-Treffer und metadata_json in import.sh
--   report.tsv       Zeilen für plugin_report: Kategorie, Schlüssel, Name,
--                    Detail (abgelehnte Taxa und Homonyme)
--   rejected_carriers.tsv
--                    rank, entity_id, normalized_name, reason — jede
--                    Entität, die den Namen eines abgelehnten Taxons bzw.
--                    eines Homonyms (ambiguous) trägt; import.sh schreibt
--                    daraus entity_external_id_rejections
--   allowed_ancestors.tsv
--                    class_id, rank, inat_taxon_id — für
--                    inat_allowed_ancestors
-- =============================================================================

CREATE TEMP TABLE t_placeholder_patterns AS
SELECT pattern FROM read_csv('${PLACEHOLDER_PATTERNS}', header = true, columns = {'pattern': 'VARCHAR'});

CREATE OR REPLACE MACRO is_rank_placeholder(name) AS
    EXISTS (SELECT 1 FROM t_placeholder_patterns p WHERE LOWER(TRIM(name)) GLOB p.pattern);

CREATE TEMP TABLE t_carriers AS
SELECT DISTINCT
    rank, normalized_name, entity_id,
    NULLIF(chain_phylum, '') AS chain_phylum,
    NULLIF(chain_class, '')  AS chain_class,
    NULLIF(chain_order, '')  AS chain_order,
    NULLIF(chain_family, '') AS chain_family
FROM read_csv('${REFERENCE_NAMES}', delim = '\t', header = true, quote = '', escape = '', columns = {
    'rank':            'VARCHAR',
    'normalized_name': 'VARCHAR',
    'entity_id':       'VARCHAR',
    'chain_phylum':    'VARCHAR',
    'chain_class':     'VARCHAR',
    'chain_order':     'VARCHAR',
    'chain_family':    'VARCHAR'
});

CREATE TEMP TABLE t_phylum_equivalents AS
SELECT phylum, inat_phylum
FROM read_csv('${PHYLUM_EQUIVALENTS}', header = true, columns = {
    'phylum':      'VARCHAR',
    'inat_phylum': 'VARCHAR',
    'reason':      'VARCHAR'
});

CREATE TEMP TABLE t_class_equivalents AS
SELECT LOWER(class) AS class, LOWER(inat_class) AS inat_class
FROM read_csv('${CLASS_EQUIVALENTS}', header = true, columns = {
    'class':      'VARCHAR',
    'inat_class': 'VARCHAR',
    'reason':     'VARCHAR'
});

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

CREATE TEMP TABLE t_inat_taxa AS
SELECT
    CAST(t.taxon_id AS VARCHAR) AS record_key,
    t.rank,
    t.name,
    LOWER(t.name) AS normalized_name,
    t.ancestry,
    COUNT(*) OVER (PARTITION BY t.rank, LOWER(t.name)) > 1 AS is_homonym
FROM t_taxa t
SEMI JOIN t_carriers c
  ON c.rank = t.rank
 AND c.normalized_name = LOWER(t.name);

-- Stamm, Klasse, Ordnung und Familie aus der Ahnenkette; ein Rang, den die
-- Kette zweimal nennt, zählt als fehlend.
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
    CASE WHEN COUNT(DISTINCT t.name) FILTER (WHERE t.rank = 'class') = 1
         THEN MAX(t.name) FILTER (WHERE t.rank = 'class') END AS class,
    CASE WHEN COUNT(DISTINCT t.name) FILTER (WHERE t.rank = 'order') = 1
         THEN MAX(t.name) FILTER (WHERE t.rank = 'order') END AS "order",
    CASE WHEN COUNT(DISTINCT t.name) FILTER (WHERE t.rank = 'family') = 1
         THEN MAX(t.name) FILTER (WHERE t.rank = 'family') END AS family
FROM t_inat_taxa i
LEFT JOIN ancestors a ON a.record_key = i.record_key
LEFT JOIN t_taxa t ON t.taxon_id = a.ancestor_id AND t.rank IN ('phylum', 'class', 'order', 'family')
GROUP BY i.record_key;

-- Klassen der Entitäten eines Namens, ohne Platzhalter.
CREATE TEMP TABLE t_name_classes AS
SELECT rank, normalized_name, COUNT(DISTINCT LOWER(TRIM(chain_class))) AS classes
FROM t_carriers
WHERE chain_class IS NOT NULL AND NOT is_rank_placeholder(chain_class)
GROUP BY rank, normalized_name;

-- Je iNaturalist-Taxon und Entität seines Namens:
--   phylum_fits  passt (true), passt nicht (false), nicht prüfbar (NULL)
--   rank_fits    Klasse, Ordnung oder Familie passt
CREATE TEMP TABLE t_checks AS
SELECT
    i.record_key, i.rank, i.name, i.normalized_name, i.is_homonym,
    l.phylum AS inat_phylum, l.class AS inat_class, l."order" AS inat_order, l.family AS inat_family,
    c.entity_id, c.chain_phylum, c.chain_class, c.chain_order, c.chain_family,
    CASE
        WHEN c.chain_phylum IS NULL OR is_rank_placeholder(c.chain_phylum) OR l.phylum IS NULL THEN NULL
        ELSE l.phylum = c.chain_phylum
             OR EXISTS (SELECT 1 FROM t_phylum_equivalents e
                        WHERE e.phylum = c.chain_phylum AND e.inat_phylum = l.phylum)
    END AS phylum_fits,
    COALESCE(
        LOWER(TRIM(c.chain_class)) = LOWER(l.class)
        OR EXISTS (SELECT 1 FROM t_class_equivalents e
                   WHERE e.class = LOWER(TRIM(c.chain_class)) AND e.inat_class = LOWER(l.class))
        OR LOWER(TRIM(c.chain_order)) = LOWER(l."order")
        OR LOWER(TRIM(c.chain_family)) = LOWER(l.family),
        false) AS rank_fits
FROM t_inat_taxa i
JOIN t_inat_lineage l ON l.record_key = i.record_key
JOIN t_carriers c ON c.rank = i.rank AND c.normalized_name = i.normalized_name;

CREATE TEMP TABLE t_verdicts AS
SELECT
    k.record_key, k.rank, k.name, k.normalized_name, k.is_homonym,
    CASE
        WHEN bool_or(k.phylum_fits) AND bool_or(NOT k.phylum_fits) THEN 'phylum_mixed'
        WHEN bool_or(k.phylum_fits IS NULL) THEN 'phylum_unknown'
        WHEN NOT bool_or(k.phylum_fits) THEN 'phylum_mismatch'
        WHEN MAX(COALESCE(n.classes, 0)) > 1 THEN 'class_mixed'
        WHEN (k.rank IN ('genus', 'family', 'order') OR (k.rank = 'species' AND k.is_homonym))
             AND NOT bool_and(k.rank_fits) THEN 'rank_mismatch'
    END AS rejection,
    'iNaturalist: ' || concat_ws(' / ',
            COALESCE(MIN(k.inat_phylum), '-'), COALESCE(MIN(k.inat_class), '-'),
            COALESCE(MIN(k.inat_order), '-'), COALESCE(MIN(k.inat_family), '-'))
        || '; Kette: '
        || string_agg(k.entity_id || ' ' || concat_ws(' / ',
               COALESCE(k.chain_phylum, '-'), COALESCE(k.chain_class, '-'),
               COALESCE(k.chain_order, '-'), COALESCE(k.chain_family, '-')),
               ', ' ORDER BY k.entity_id)
        AS detail
FROM t_checks k
LEFT JOIN t_name_classes n ON n.rank = k.rank AND n.normalized_name = k.normalized_name
GROUP BY k.record_key, k.rank, k.name, k.normalized_name, k.is_homonym;

CREATE TEMP TABLE t_homonyms AS
SELECT rank, normalized_name
FROM t_verdicts
WHERE rejection IS NULL
GROUP BY rank, normalized_name
HAVING COUNT(*) > 1;

CREATE TEMP TABLE t_accepted AS
SELECT v.record_key, v.rank, v.name, v.is_homonym
FROM t_verdicts v
ANTI JOIN t_homonyms h
  ON h.rank = v.rank
 AND h.normalized_name = v.normalized_name
WHERE v.rejection IS NULL;

COPY (
    SELECT record_key, rank, name FROM t_accepted ORDER BY rank, record_key
) TO '${EXPORT_DIR}/match_input.tsv' (FORMAT csv, DELIMITER '\t', HEADER true, QUOTE '', ESCAPE '');

COPY (
    SELECT a.record_key, l.phylum, l.class, l."order", l.family, CAST(a.is_homonym AS INTEGER) AS homonym
    FROM t_accepted a JOIN t_inat_lineage l ON l.record_key = a.record_key
    ORDER BY a.record_key
) TO '${EXPORT_DIR}/lineage.tsv' (FORMAT csv, DELIMITER '\t', HEADER true, QUOTE '', ESCAPE '');

COPY (
    SELECT rejection, record_key, name, detail
    FROM t_verdicts
    WHERE rejection IS NOT NULL
    UNION ALL
    SELECT
        'ambiguous',
        string_agg(v.record_key, ', ' ORDER BY v.record_key),
        MIN(v.name),
        'mehrere aktive iNaturalist-Taxa passend zur Kette auf Rang ' || v.rank
    FROM t_verdicts v
    JOIN t_homonyms h
      ON h.rank = v.rank
     AND h.normalized_name = v.normalized_name
    WHERE v.rejection IS NULL
    GROUP BY v.rank, v.normalized_name
    ORDER BY 1, 3, 2
) TO '${EXPORT_DIR}/report.tsv' (FORMAT csv, DELIMITER '\t', HEADER false, QUOTE '', ESCAPE '');

-- Jede Entität hinter einem abgelehnten Taxon und hinter einem Homonym: Für
-- sie hat der Abgleich ein Taxon ihres Namens gesehen und bewusst nicht
-- genommen. import.sh lässt die weg, die trotzdem eine Zuordnung bekommen.
COPY (
    SELECT DISTINCT c.rank, c.entity_id, c.normalized_name, r.reason
    FROM (
        SELECT rank, normalized_name, rejection AS reason
        FROM t_verdicts
        WHERE rejection IS NOT NULL
        UNION ALL
        SELECT rank, normalized_name, 'ambiguous' FROM t_homonyms
    ) r
    JOIN t_carriers c ON c.rank = r.rank AND c.normalized_name = r.normalized_name
    ORDER BY 1, 2, 4
) TO '${EXPORT_DIR}/rejected_carriers.tsv' (FORMAT csv, DELIMITER '\t', HEADER true, QUOTE '', ESCAPE '');

-- Je eigener Klasse die iNaturalist-Taxa, die als Stamm bzw. Klasse in der
-- Ahnenkette eines passenden Treffers stehen dürfen — dieselben Vergleiche
-- wie in t_checks, nur als IDs, damit die App ohne Namen und ohne Listen
-- prüft. Kein Stamm ohne prüfbaren Stamm der Kette, keine Klasse für eine
-- Platzhalter-Klasse.
COPY (
    WITH upper_taxa AS (
        SELECT taxon_id, rank, name FROM t_taxa WHERE rank IN ('phylum', 'class')
    )
    SELECT DISTINCT c.entity_id AS class_id, t.rank, t.taxon_id AS inat_taxon_id
    FROM t_carriers c
    JOIN upper_taxa t
      ON (t.rank = 'phylum'
          AND c.chain_phylum IS NOT NULL
          AND NOT is_rank_placeholder(c.chain_phylum)
          AND (t.name = c.chain_phylum
               OR EXISTS (SELECT 1 FROM t_phylum_equivalents e
                          WHERE e.phylum = c.chain_phylum AND e.inat_phylum = t.name)))
      OR (t.rank = 'class'
          AND NOT is_rank_placeholder(c.normalized_name)
          AND (LOWER(t.name) = c.normalized_name
               OR EXISTS (SELECT 1 FROM t_class_equivalents e
                          WHERE e.class = c.normalized_name AND e.inat_class = LOWER(t.name))))
    WHERE c.rank = 'class'
    ORDER BY 1, 2, 3
) TO '${EXPORT_DIR}/allowed_ancestors.tsv' (FORMAT csv, DELIMITER '\t', HEADER true, QUOTE '', ESCAPE '');
