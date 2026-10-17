-- =============================================================================
-- distribution_regions.sql — Verbreitung einer Quelle im FishBase-Format (DuckDB)
--
-- Eingebunden von plugins/fishbase und plugins/sealifebase an der Zeile
-- „-- @include distribution_regions.sql“ ihrer export.sql (plugin_render_sql
-- in core/plugin_api.sh), nach dem Makro is_placeholder_species und nach
-- core/sql/source_codes.sql (src_species). Liest country und countrysub aus
-- ${PARQUET_DIR}.
--
-- Ein Schlüssel ist eine Art in einem Land (SpecCode, C_Code) bzw. in einer
-- Teilregion (SpecCode, C_Code, CSub_Code). Die Quelle führt für einen
-- Schlüssel teils mehrere Zeilen, meist für verschiedene Populationen oder
-- Unterarten im selben Land, mit verschiedenem Status (Oreochromis
-- niloticus in Kenia: native im Turkana-Becken, introduced im Viktoriasee,
-- endemic als Unterart im Baringo-See) oder mit gleichem Status und anderem
-- Kommentar. Die Datenbank hält je Schlüssel eine Zeile, und sie gilt für die
-- Art als Ganzes. Deshalb, verglichen ohne Groß- und Kleinschreibung:
--
--   1. native, sobald eine Zeile native sagt;
--   2. endemic nur, wenn alle Zeilen endemic sagen — endemisch im Land ist
--      die Art nicht, wenn es nur eine ihrer Unterarten ist;
--   3. introduced, wenn keine Zeile native oder endemic sagt;
--   4. sonst der erste Status in der Rangfolge questionable, error,
--      misidentification, extirpated, stray, not established, reintroduced,
--      established, ohne Status. Vorn steht, was weniger über die Präsenz
--      der Art behauptet: Zweifel, dann ein als falsch erkannter Nachweis,
--      dann eine frühere Präsenz, dann eine gelegentliche oder eingeführte
--      und zuletzt eine dauerhafte. Ohne Status steht hinten, weil die App
--      eine Region ohne Status als heimisch zeigt.
--
-- Endemic neben einem anderen Status als native, und jeder Status, den die
-- Rangfolge nicht kennt, brechen den Export ab, sobald sie in einem
-- Schlüssel mit mehreren Zeilen vorkommen: Keine der Regeln sagt, welcher
-- Status dann für die Art gilt.
--
-- Die übrigen Spalten kommen aus der Zeile, die den Status liefert. Unter
-- gleichrangigen Zeilen entscheiden Präsenz, Status (in der Schreibweise der
-- Quelle), threatened, Häufigkeit, Bedeutung und Kommentar in dieser
-- Reihenfolge, je aufsteigend, leere Werte zuletzt. Da die Zeilen nach
-- DISTINCT in mindestens einer dieser Spalten verschieden sind, ist die Wahl
-- vollständig und hängt nicht von der Reihenfolge der Eingabe ab.
--
-- Ergebnis:
--   t_distribution_regions  — je Schlüssel eine Zeile (SpecCode,
--                             region_scope, region_key und die Spalten von
--                             taxonomy_distribution_regions)
--   distribution_report.tsv — Build-Bericht (Kategorie, Schlüssel, Name,
--                             Detail), je Schlüssel mit mehreren Zeilen:
--     distribution_status_merged  Zeilen mit verschiedenem Status
--     distribution_rows_merged    Zeilen mit gleichem Status
--     Detail: Anzahl Zeilen, Status der Zeilen mit Anzahl, gewählter Status
--     und die Spalten, in denen die Zeilen voneinander abweichen.
-- =============================================================================

CREATE TEMP TABLE t_distribution_rows AS
SELECT DISTINCT
    c.SpecCode                                 AS speccode,
    'country'                                  AS region_scope,
    CAST(c.C_Code AS VARCHAR)                  AS region_key,
    NULLIF(TRIM(c.CurrentPresence), '')        AS presence_status,
    NULLIF(TRIM(c.Status), '')                 AS establishment_status,
    c.Threatened                               AS threatened_flag,
    NULLIF(TRIM(c.Abundance), '')              AS abundance,
    NULLIF(TRIM(c.Importance), '')             AS importance,
    NULLIF(TRIM(c.Comments), '')               AS comment
FROM read_parquet('${PARQUET_DIR}/country.parquet') c
WHERE c.SpecCode IS NOT NULL
  AND NOT is_placeholder_species(c.SpecCode)
  AND NULLIF(TRIM(CAST(c.C_Code AS VARCHAR)), '') IS NOT NULL

UNION ALL

SELECT DISTINCT
    cs.SpecCode,
    'subregion',
    CAST(cs.C_Code AS VARCHAR) || ':' || CAST(cs.CSub_Code AS VARCHAR),
    NULLIF(TRIM(cs.CurrentPresence), ''),
    NULLIF(TRIM(cs.Status), ''),
    CAST(NULL AS INTEGER),
    NULLIF(TRIM(cs.Abundance), ''),
    CAST(NULL AS VARCHAR),
    NULLIF(TRIM(cs.Comments), '')
FROM read_parquet('${PARQUET_DIR}/countrysub.parquet') cs
WHERE cs.SpecCode IS NOT NULL
  AND NOT is_placeholder_species(cs.SpecCode)
  AND NULLIF(TRIM(CAST(cs.C_Code AS VARCHAR)), '') IS NOT NULL
  AND NULLIF(TRIM(CAST(cs.CSub_Code AS VARCHAR)), '') IS NOT NULL;

-- Rang eines Status nach Regel 4; native, endemic und introduced vorweg nach
-- den Regeln 1 bis 3. NULL für einen Status, den die Rangfolge nicht kennt.
CREATE OR REPLACE MACRO distribution_status_rank(status) AS
    CASE COALESCE(LOWER(status), '')
        WHEN 'native'            THEN 1
        WHEN 'endemic'           THEN 2
        WHEN 'introduced'        THEN 3
        WHEN 'questionable'      THEN 4
        WHEN 'error'             THEN 5
        WHEN 'misidentification' THEN 6
        WHEN 'extirpated'        THEN 7
        WHEN 'stray'             THEN 8
        WHEN 'not established'   THEN 9
        WHEN 'reintroduced'      THEN 10
        WHEN 'established'       THEN 11
        WHEN ''                  THEN 12
    END;

CREATE TEMP TABLE t_distribution_keys AS
SELECT
    speccode,
    region_scope,
    region_key,
    COUNT(*)                                                         AS row_count,
    COUNT(DISTINCT COALESCE(LOWER(establishment_status), ''))       AS status_count,
    BOOL_OR(LOWER(establishment_status) = 'native')                  AS has_native,
    BOOL_OR(LOWER(establishment_status) = 'endemic')                 AS has_endemic,
    BOOL_OR(distribution_status_rank(establishment_status) IS NULL)  AS has_unknown_status
FROM t_distribution_rows
GROUP BY speccode, region_scope, region_key
HAVING COUNT(*) > 1;

-- Bricht den Export bei einem Schlüssel ohne Regel ab; als Tabelle, damit
-- die Prüfung im Erfolgsfall keine Ausgabe schreibt.
CREATE TEMP TABLE t_distribution_unruled AS
SELECT error(
    'Verbreitung: keine Regel für SpecCode ' || CAST(speccode AS VARCHAR) || ', '
    || region_scope || ' ' || region_key || ': '
    || CASE WHEN has_unknown_status THEN 'unbekannter Status' ELSE 'endemic neben einem anderen Status als native' END)
FROM t_distribution_keys
WHERE has_unknown_status OR (has_endemic AND NOT has_native AND status_count > 1);

CREATE TEMP TABLE t_distribution_regions AS
SELECT *
FROM t_distribution_rows
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY speccode, region_scope, region_key
    ORDER BY distribution_status_rank(establishment_status),
             presence_status      ASC NULLS LAST,
             establishment_status ASC NULLS LAST,
             threatened_flag      ASC NULLS LAST,
             abundance            ASC NULLS LAST,
             importance           ASC NULLS LAST,
             comment              ASC NULLS LAST
) = 1;

COPY (
    SELECT
        CASE WHEN k.status_count > 1 THEN 'distribution_status_merged' ELSE 'distribution_rows_merged' END,
        'SpecCode ' || CAST(k.speccode AS VARCHAR) || ', ' || k.region_scope || ' ' || k.region_key,
        COALESCE(CONCAT_WS(' ', TRIM(s.Genus), TRIM(s.Species)), '?'),
        CAST(k.row_count AS VARCHAR) || ' Zeilen ('
            || (SELECT STRING_AGG(COALESCE(st, 'ohne Status') || ' ' || CAST(n AS VARCHAR), ', ' ORDER BY COALESCE(st, ''))
                FROM (SELECT LOWER(r.establishment_status) AS st, COUNT(*) AS n
                      FROM t_distribution_rows r
                      WHERE r.speccode = k.speccode AND r.region_scope = k.region_scope AND r.region_key = k.region_key
                      GROUP BY 1))
            || ') → ' || COALESCE(d.establishment_status, 'ohne Status')
            || '; abweichend: '
            || (SELECT CONCAT_WS(', ',
                    CASE WHEN COUNT(DISTINCT COALESCE(r.presence_status, '')) > 1 THEN 'presence_status' END,
                    CASE WHEN COUNT(DISTINCT COALESCE(r.establishment_status, '')) > 1 THEN 'establishment_status' END,
                    CASE WHEN COUNT(DISTINCT COALESCE(CAST(r.threatened_flag AS VARCHAR), '')) > 1 THEN 'threatened_flag' END,
                    CASE WHEN COUNT(DISTINCT COALESCE(r.abundance, '')) > 1 THEN 'abundance' END,
                    CASE WHEN COUNT(DISTINCT COALESCE(r.importance, '')) > 1 THEN 'importance' END,
                    CASE WHEN COUNT(DISTINCT COALESCE(r.comment, '')) > 1 THEN 'comment' END)
                FROM t_distribution_rows r
                WHERE r.speccode = k.speccode AND r.region_scope = k.region_scope AND r.region_key = k.region_key)
    FROM t_distribution_keys k
    JOIN t_distribution_regions d
      ON d.speccode = k.speccode AND d.region_scope = k.region_scope AND d.region_key = k.region_key
    LEFT JOIN src_species s ON s.SpecCode = k.speccode
    ORDER BY 1, k.speccode, k.region_scope, k.region_key
)
TO '${EXPORT_DIR}/distribution_report.tsv' (FORMAT csv, DELIMITER '\t', HEADER false, QUOTE '');
