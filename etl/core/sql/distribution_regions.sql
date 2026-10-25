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
--   1. native, sobald eine Zeile native oder endemic sagt und nicht alle
--      endemic sagen — endemic ist eine Form von native: Die Art ist im
--      Land heimisch, nur nicht als Ganzes endemisch;
--   2. endemic nur, wenn alle Zeilen endemic sagen — endemisch im Land ist
--      die Art nicht, wenn es nur eine ihrer Unterarten ist;
--   3. introduced, wenn keine Zeile native oder endemic sagt;
--   4. sonst der erste Status in der Rangfolge questionable, error,
--      misidentification, extirpated, stray, not established, reintroduced,
--      established, unbekannter Status, ohne Status. Vorn steht, was weniger
--      über die Präsenz der Art behauptet: Zweifel, dann ein als falsch
--      erkannter Nachweis, dann eine frühere Präsenz, dann eine
--      gelegentliche oder eingeführte und zuletzt eine dauerhafte. Ein
--      Status, den die Rangfolge nicht kennt, steht hinter allen bekannten,
--      weil er weniger sagt, mehrere unbekannte alphabetisch; ohne Status
--      steht ganz hinten, weil die App eine Region ohne Status als heimisch
--      zeigt, eine mit unbekanntem Status nicht.
--
-- Die übrigen Spalten (Präsenz, threatened, Häufigkeit, Bedeutung,
-- Kommentar) behalten ihren Wert nur, wenn alle Zeilen des Schlüssels ihn
-- teilen; sonst bleiben sie leer, ein leerer Wert zählt dabei als eigener
-- Wert. Was nur eine Teilmenge der Zeilen sagt, gilt nicht für die Art als
-- Ganzes: Salmo trutta ist in der Schweiz native, und eine zweite Zeile
-- führt sie dort als ausgestorben — ihre Präsenz bleibt leer. Den Status
-- liefert bei Zeilen gleichen Rangs, die sich nur in der Schreibweise
-- unterscheiden, die erste in Sortierung („Native“ vor „native“). Das
-- Ergebnis hängt so nicht von der Reihenfolge der Eingabe ab.
--
-- Ist das Ergebnis mehrerer Zeilen introduced und sagt eine von ihnen not
-- established oder Präsenz absent, entsteht für den Schlüssel keine Zeile:
-- Ob die Einführung gelang, bleibt offen, und eine Zeile mit leerer Präsenz
-- läse die App als vorkommend, eine ohne Status als heimisch (Salmo trutta
-- in Nepal: introduced/present neben not established/absent, „Introduction
-- was unsuccessful“). Bei native gilt das nicht: Dort betrifft ein
-- ausgestorbener oder fehlender Bestand eine Population, nicht die
-- Heimat der Art.
--
-- Ergebnis:
--   t_distribution_regions  — je Schlüssel höchstens eine Zeile (SpecCode,
--                             region_scope, region_key und die Spalten von
--                             taxonomy_distribution_regions)
--   distribution_report.tsv — Build-Bericht (Kategorie, Schlüssel, Name,
--                             Detail):
--     distribution_status_merged  Schlüssel mit mehreren Zeilen, deren
--                                 Status sich unterscheidet
--     distribution_rows_merged    Schlüssel mit mehreren Zeilen gleichen
--                                 Status
--     Detail: Anzahl Zeilen, Status der Zeilen mit Anzahl, gewählter Status
--     und die Spalten, die wegen Widerspruchs leer bleiben, bzw.
--     „ausgelassen: Einführung widersprüchlich“.
--     distribution_status_unknown Schlüssel mit einem Status, den die
--                                 Rangfolge nicht kennt, auch mit nur
--                                 einer Zeile; Detail: diese Status. So
--                                 zeigt der Bericht neues Vokabular der
--                                 Quelle, und die Rangfolge lässt sich
--                                 darum erweitern.
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
-- den Regeln 1 bis 3. Ein Status, den die Rangfolge nicht kennt, bekommt
-- Rang 12: hinter allen bekannten, vor ohne Status.
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
        WHEN ''                  THEN 13
        ELSE                          12
    END;
CREATE OR REPLACE MACRO distribution_status_unknown(status) AS
    distribution_status_rank(status) = 12;

CREATE TEMP TABLE t_distribution_keys AS
SELECT
    speccode,
    region_scope,
    region_key,
    COUNT(*)                                                         AS row_count,
    COUNT(DISTINCT COALESCE(LOWER(establishment_status), ''))       AS status_count
FROM t_distribution_rows
GROUP BY speccode, region_scope, region_key
HAVING COUNT(*) > 1;

-- Wert einer Spalte über die Zeilen eines Schlüssels: der gemeinsame, sonst
-- NULL. distribution_disagrees sagt, ob die Zeilen darin abweichen.
CREATE OR REPLACE MACRO distribution_disagrees(value) AS
    COUNT(DISTINCT COALESCE(CAST(value AS VARCHAR), chr(0))) > 1;
CREATE OR REPLACE MACRO distribution_common(value) AS
    CASE WHEN distribution_disagrees(value) THEN NULL ELSE MIN(value) END;

CREATE TEMP TABLE t_distribution_merged AS
SELECT
    speccode,
    region_scope,
    region_key,
    distribution_common(presence_status)                                AS presence_status,
    CASE
        -- Regel 1 ohne Zeile, die native sagt: endemic neben einem anderen Status.
        WHEN BOOL_OR(LOWER(establishment_status) = 'endemic')
             AND NOT BOOL_OR(LOWER(establishment_status) = 'native')
             AND NOT BOOL_AND(COALESCE(LOWER(establishment_status), '') = 'endemic')
            THEN 'native'
        ELSE ARG_MIN(establishment_status,
                     (distribution_status_rank(establishment_status), LOWER(establishment_status), establishment_status))
    END                                                                 AS establishment_status,
    distribution_common(threatened_flag)                                AS threatened_flag,
    distribution_common(abundance)                                      AS abundance,
    distribution_common(importance)                                     AS importance,
    distribution_common(comment)                                        AS comment,
    CONCAT_WS(', ',
        CASE WHEN distribution_disagrees(presence_status) THEN 'presence_status' END,
        CASE WHEN distribution_disagrees(threatened_flag) THEN 'threatened_flag' END,
        CASE WHEN distribution_disagrees(abundance)       THEN 'abundance' END,
        CASE WHEN distribution_disagrees(importance)      THEN 'importance' END,
        CASE WHEN distribution_disagrees(comment)         THEN 'comment' END)  AS emptied_columns,
    COUNT(*) > 1
        AND BOOL_OR(LOWER(establishment_status) = 'introduced')
        AND NOT BOOL_OR(LOWER(establishment_status) IN ('native', 'endemic'))
        AND BOOL_OR(LOWER(establishment_status) = 'not established' OR LOWER(presence_status) = 'absent')
                                                                        AS introduction_contradicted
FROM t_distribution_rows
GROUP BY speccode, region_scope, region_key;

CREATE TEMP TABLE t_distribution_regions AS
SELECT * EXCLUDE (emptied_columns, introduction_contradicted)
FROM t_distribution_merged
WHERE NOT introduction_contradicted;

CREATE TEMP TABLE t_distribution_report AS
SELECT
    CASE WHEN k.status_count > 1 THEN 'distribution_status_merged' ELSE 'distribution_rows_merged' END AS category,
    k.speccode,
    k.region_scope,
    k.region_key,
    CAST(k.row_count AS VARCHAR) || ' Zeilen ('
        || (SELECT STRING_AGG(COALESCE(st, 'ohne Status') || ' ' || CAST(n AS VARCHAR), ', ' ORDER BY COALESCE(st, ''))
            FROM (SELECT LOWER(r.establishment_status) AS st, COUNT(*) AS n
                  FROM t_distribution_rows r
                  WHERE r.speccode = k.speccode AND r.region_scope = k.region_scope AND r.region_key = k.region_key
                  GROUP BY 1))
        || ') → ' || CASE
               WHEN d.introduction_contradicted THEN 'ausgelassen: Einführung widersprüchlich'
               ELSE COALESCE(d.establishment_status, 'ohne Status')
                    || '; leer: ' || COALESCE(NULLIF(d.emptied_columns, ''), 'keine')
           END                                                          AS detail
FROM t_distribution_keys k
JOIN t_distribution_merged d
  ON d.speccode = k.speccode AND d.region_scope = k.region_scope AND d.region_key = k.region_key

UNION ALL

SELECT
    'distribution_status_unknown',
    speccode,
    region_scope,
    region_key,
    'Status ' || STRING_AGG(DISTINCT establishment_status, ', ' ORDER BY establishment_status)
FROM t_distribution_rows
WHERE distribution_status_unknown(establishment_status)
GROUP BY speccode, region_scope, region_key;

COPY (
    SELECT
        r.category,
        'SpecCode ' || CAST(r.speccode AS VARCHAR) || ', ' || r.region_scope || ' ' || r.region_key,
        COALESCE(CONCAT_WS(' ', TRIM(s.Genus), TRIM(s.Species)), '?'),
        r.detail
    FROM t_distribution_report r
    LEFT JOIN src_species s ON s.SpecCode = r.speccode
    ORDER BY r.category, r.speccode, r.region_scope, r.region_key
)
TO '${EXPORT_DIR}/distribution_report.tsv' (FORMAT csv, DELIMITER '\t', HEADER false, QUOTE '');
