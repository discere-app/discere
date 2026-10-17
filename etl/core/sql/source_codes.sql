-- =============================================================================
-- source_codes.sql — doppelte Codes einer Quelle im FishBase-Format (DuckDB)
--
-- Eingebunden von plugins/fishbase und plugins/sealifebase an der Zeile
-- „-- @include source_codes.sql“ ihrer export.sql (plugin_render_sql in
-- core/plugin_api.sh), nach dem Makro is_placeholder_species. Liest
-- classes, orders, families, genera und species aus ${PARQUET_DIR}.
--
-- Der Code einer Zeile (ClassNum, Ordnum, FamCode, GenCode, SpecCode) ist
-- ihr Quellenschlüssel: Die Identitäts-Stage ordnet ihn einer Entität zu,
-- und eine Zeile, die auf einen Code zeigt, meint diese Entität. Vergibt die
-- Quelle einen Code mehrfach (SeaLifeBase v26.06: drei Ordnum), nennt er
-- kein Taxon. Ein zufällig gewählter Eintrag hinge Familien unter eine
-- Ordnung aus einem anderen Stamm, und der Schlüssel könnte von Build zu
-- Build das Taxon wechseln. Deshalb:
--
--   - Ordnung einer Familie: Bei eindeutigem Ordnum die Ordnung dieses Codes.
--     Bei doppeltem die Zeile, deren Name gleich dem Namen ist, den die
--     Familie selbst nennt (families.Order; ohne Leerzeichen am Rand und
--     Groß- und Kleinschreibung), und deren ClassNum gleich families.ClassNum
--     ist. Trifft das nicht genau eine Zeile, hat die Familie keine Ordnung.
--   - Entität unter einem doppelten Ordnum: höchstens eine Zeile, nämlich die
--     einzige, an deren Familien (nach der Regel oben) Arten hängen — über
--     den FamCode der Art oder über ihre Gattung. Die übrigen Zeilen werden
--     nicht exportiert, und ihre Familien haben keine Ordnung: Den Schlüssel
--     trägt schon das Taxon, das Arten hält, und eine zweite Entität mit
--     eigenem Schlüssel gibt es nicht. Halten keine oder mehrere Zeilen
--     Arten, wird keine exportiert. Dass der Schlüssel dabei kein anderes
--     Taxon nennt als im Vorgänger, prüft die Identitäts-Stage
--     (core/sql/identity_key_names.sql).
--   - Übrige Ränge: Für einen doppelten ClassNum, FamCode, GenCode oder
--     SpecCode nennt die Quelle keinen Namen, über den sich eine Zeile wählen
--     ließe. Keine davon wird exportiert; was auf den Code zeigt, bleibt
--     ohne diese Stufe.
--
-- Ergebnis, je Code höchstens eine Zeile:
--   src_classes, src_orders, src_families, src_genera, src_species
--                    — die Zeilen der Parquets, die als Entität gelten
--   t_family_order   — Ordnum der Ordnung jeder Familie aus src_families,
--                      NULL ohne Ordnung
--   code_report.tsv  — Build-Bericht (Kategorie, Schlüssel, Name, Detail):
--     code_duplicate           jede Zeile eines doppelten Codes, mit Ausgang
--     family_order_resolved    Familie unter doppeltem Ordnum, Ordnung über
--                              Name und ClassNum gefunden
--     family_order_rejected    Familie unter doppeltem Ordnum ohne Ordnung
-- =============================================================================

CREATE TEMP TABLE t_code_rows AS
SELECT 'ClassNum' AS code_name, ClassNum AS code, TRIM(Class) AS name, ClassNum AS classnum
FROM read_parquet('${PARQUET_DIR}/classes.parquet')
UNION ALL
SELECT 'Ordnum', Ordnum, TRIM("Order"), ClassNum
FROM read_parquet('${PARQUET_DIR}/orders.parquet')
UNION ALL
SELECT 'FamCode', FamCode, TRIM(Family), NULL
FROM read_parquet('${PARQUET_DIR}/families.parquet')
UNION ALL
SELECT 'GenCode', GenCode, TRIM(GenName), NULL
FROM read_parquet('${PARQUET_DIR}/genera.parquet')
UNION ALL
SELECT 'SpecCode', SpecCode, CONCAT_WS(' ', TRIM(Genus), TRIM(Species)), NULL
FROM read_parquet('${PARQUET_DIR}/species.parquet')
WHERE NOT is_placeholder_species(SpecCode);

CREATE TEMP TABLE t_duplicate_codes AS
SELECT code_name, code, COUNT(*) AS code_rows
FROM t_code_rows
WHERE code IS NOT NULL
GROUP BY code_name, code
HAVING COUNT(*) > 1;

CREATE OR REPLACE MACRO is_duplicate_code(kind, value) AS
    EXISTS (SELECT 1 FROM t_duplicate_codes d WHERE d.code_name = kind AND d.code = value);

CREATE TEMP VIEW src_classes AS
SELECT * FROM read_parquet('${PARQUET_DIR}/classes.parquet') WHERE NOT is_duplicate_code('ClassNum', ClassNum);

CREATE TEMP VIEW src_families AS
SELECT * FROM read_parquet('${PARQUET_DIR}/families.parquet') WHERE NOT is_duplicate_code('FamCode', FamCode);

CREATE TEMP VIEW src_genera AS
SELECT * FROM read_parquet('${PARQUET_DIR}/genera.parquet') WHERE NOT is_duplicate_code('GenCode', GenCode);

CREATE TEMP VIEW src_species AS
SELECT * FROM read_parquet('${PARQUET_DIR}/species.parquet') WHERE NOT is_duplicate_code('SpecCode', SpecCode);

-- Ordnungszeilen, die zu einer Familie passen: bei eindeutigem Ordnum die
-- eine, bei doppeltem die mit Name und ClassNum der Familie.
CREATE TEMP TABLE t_family_order_match AS
SELECT
    f.FamCode                      AS famcode,
    o.Ordnum                       AS ordnum,
    TRIM(o."Order")                AS order_name,
    o.ClassNum                     AS classnum
FROM src_families f
JOIN read_parquet('${PARQUET_DIR}/orders.parquet') o ON o.Ordnum = f.Ordnum
WHERE NOT is_duplicate_code('Ordnum', o.Ordnum)
   OR (LOWER(TRIM(o."Order")) = LOWER(TRIM(f."Order")) AND o.ClassNum = f.ClassNum);

-- Je Familie die Ordnungszeile, wenn genau eine passt.
CREATE TEMP TABLE t_family_order_row AS
SELECT famcode, ANY_VALUE(ordnum) AS ordnum, ANY_VALUE(order_name) AS order_name,
       ANY_VALUE(classnum) AS classnum, COUNT(*) AS matches
FROM t_family_order_match
GROUP BY famcode;

-- Familien, an denen Arten hängen (FamCode der Art oder ihrer Gattung).
CREATE TEMP TABLE t_families_with_species AS
SELECT FamCode AS famcode FROM src_species WHERE NOT is_placeholder_species(SpecCode)
UNION
SELECT g.FamCode
FROM src_species s
JOIN src_genera g ON g.GenCode = s.GenCode
WHERE NOT is_placeholder_species(s.SpecCode);

-- Zeilen doppelter Ordnum, an deren Familien Arten hängen; die einzige je
-- Ordnum gilt als Entität.
CREATE TEMP TABLE t_order_rows_with_species AS
SELECT DISTINCT r.ordnum, r.order_name, r.classnum
FROM t_family_order_row r
WHERE r.matches = 1
  AND is_duplicate_code('Ordnum', r.ordnum)
  AND r.famcode IN (SELECT famcode FROM t_families_with_species);

CREATE TEMP TABLE t_order_key_holder AS
SELECT ordnum, ANY_VALUE(order_name) AS order_name, ANY_VALUE(classnum) AS classnum
FROM t_order_rows_with_species
GROUP BY ordnum
HAVING COUNT(*) = 1;

CREATE TEMP VIEW src_orders AS
SELECT o.*
FROM read_parquet('${PARQUET_DIR}/orders.parquet') o
WHERE NOT is_duplicate_code('Ordnum', o.Ordnum)
   OR EXISTS (
       SELECT 1 FROM t_order_key_holder k
       WHERE k.ordnum = o.Ordnum AND k.order_name = TRIM(o."Order") AND k.classnum = o.ClassNum
   );

CREATE TEMP TABLE t_family_order AS
SELECT
    f.FamCode                                                  AS famcode,
    CASE WHEN r.matches = 1 AND o.Ordnum IS NOT NULL THEN r.ordnum END AS ordnum
FROM src_families f
LEFT JOIN t_family_order_row r ON r.famcode = f.FamCode
LEFT JOIN src_orders o
  ON o.Ordnum = r.ordnum AND TRIM(o."Order") = r.order_name AND o.ClassNum = r.classnum;

COPY (
    -- Jede Zeile eines doppelten Codes
    SELECT
        'code_duplicate',
        c.code_name || ' ' || CAST(c.code AS VARCHAR),
        c.name,
        CAST(d.code_rows AS VARCHAR) || ' Zeilen; '
            || CASE
                   WHEN c.code_name <> 'Ordnum'
                       THEN 'keine exportiert, ohne Name zur Auswahl'
                   WHEN k.ordnum IS NULL
                       THEN 'keine exportiert, ' || CASE
                                WHEN (SELECT COUNT(*) FROM t_order_rows_with_species w WHERE w.ordnum = c.code) = 0
                                    THEN 'keine Zeile hält Arten'
                                ELSE 'mehrere Zeilen halten Arten'
                            END
                   WHEN k.order_name = c.name AND k.classnum = c.classnum
                       THEN 'Entität unter diesem Schlüssel (einzige Zeile mit Arten)'
                   ELSE 'nicht exportiert, Schlüssel bei ' || k.order_name
               END
    FROM t_code_rows c
    JOIN t_duplicate_codes d ON d.code_name = c.code_name AND d.code = c.code
    LEFT JOIN t_order_key_holder k ON c.code_name = 'Ordnum' AND k.ordnum = c.code

    UNION ALL

    -- Familien unter einem doppelten Ordnum
    SELECT
        CASE WHEN fo.ordnum IS NOT NULL THEN 'family_order_resolved' ELSE 'family_order_rejected' END,
        CAST(f.FamCode AS VARCHAR),
        TRIM(f.Family),
        'Ordnum ' || CAST(f.Ordnum AS VARCHAR) || ' doppelt, Familie nennt '
            || COALESCE(TRIM(f."Order"), '?') || ' (ClassNum ' || COALESCE(CAST(f.ClassNum AS VARCHAR), '?') || '): '
            || CASE
                   WHEN fo.ordnum IS NOT NULL                   THEN 'Ordnung ' || r.order_name
                   WHEN r.famcode IS NULL                       THEN 'keine Ordnungszeile mit diesem Namen und dieser ClassNum'
                   WHEN r.matches > 1                           THEN CAST(r.matches AS VARCHAR) || ' Ordnungszeilen mit diesem Namen und dieser ClassNum'
                   ELSE 'Ordnung ' || r.order_name || ' nicht exportiert'
               END
    FROM src_families f
    JOIN t_family_order fo ON fo.famcode = f.FamCode
    LEFT JOIN t_family_order_row r ON r.famcode = f.FamCode
    WHERE is_duplicate_code('Ordnum', f.Ordnum)

    ORDER BY 1, 2, 3
)
TO '${EXPORT_DIR}/code_report.tsv' (FORMAT csv, DELIMITER '\t', HEADER false, QUOTE '');
