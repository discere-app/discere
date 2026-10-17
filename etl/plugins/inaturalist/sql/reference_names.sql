-- =============================================================================
-- reference_names.sql — Namensträger der Referenz-DB mit dem Stamm ihrer Kette
--
-- Läuft in einer sqlite3-Sitzung gegen die Referenz-DB (import.sh) und gibt
-- je Name, den der Abgleich treffen kann, jede Entität aus, die ihn trägt:
--
--   rank, normalized_name, entity_id, chain_phylum, chain_class,
--   chain_order, chain_family
--
-- Die Namen sind die Kandidaten aus core/sql/match.sql: bei Arten alle Namen
-- aktiver Arten außer falsch angewandten, bei höheren Taxa der Name in der
-- Tabelle ihres Rangs — alle gleichnamigen Zeilen, denn sie teilen sich den
-- Namensschlüssel (genus:barbus), unter dem die Zuordnung liegt. Normalisiert
-- wie species_scientific_names.normalized_name.
--
-- chain_phylum ist der Stamm über die eigene Kette (Art › Gattung › Familie
-- › Ordnung › Klasse), wie die Quelle ihn nennt; leer, wenn die Kette vorher
-- abbricht, etwa bei einer Art ohne Gattung. chain_class, chain_order und
-- chain_family sind die Namen der Ränge darüber, soweit es sie gibt — nur
-- die über dem Rang der Entität (eine Familie hat keine chain_family), wie
-- die Quelle sie nennt, auch Platzhalter. SeaLifeBase führt den Stamm in
-- classes.super_class, teils als Platzhalter („Not Assigned (Plantae)“).
-- FishBase führt dort die Überklasse (Osteichthyes, Agnatha, …); FishBase
-- kennt nur Fische, ihr Stamm ist Chordata.
--
-- Namen mit Tab oder Zeilenumbruch (Tippfehler in den Quelldaten) passen in
-- keine TSV-Zeile und auf keinen iNaturalist-Namen; sie fallen hier weg.
-- =============================================================================

WITH class_chain AS (
    SELECT id,
           CASE WHEN external_source = 'fishbase' THEN 'Chordata' ELSE super_class END AS phylum,
           name AS class
    FROM classes
),
order_chain AS (
    SELECT o.id, c.phylum, c.class, o.name AS "order"
    FROM orders o LEFT JOIN class_chain c ON c.id = o.class
),
family_chain AS (
    SELECT f.id, o.phylum, o.class, o."order", f.name AS family
    FROM families f LEFT JOIN order_chain o ON o.id = f."order"
),
genus_chain AS (
    SELECT g.id, f.phylum, f.class, f."order", f.family
    FROM genera g LEFT JOIN family_chain f ON f.id = g.family
),
carriers AS (
    SELECT DISTINCT 'species' AS rank, n.normalized_name, s.id AS entity_id,
           g.phylum, g.class, g."order", g.family
    FROM species_scientific_names n
    JOIN species s ON s.id = n.species_id AND s.status = 'active'
    LEFT JOIN genus_chain g ON g.id = s.genus
    WHERE n.name_status != 'misapplied name'
    UNION ALL
    SELECT 'genus', LOWER(TRIM(t.name)), t.id, p.phylum, p.class, p."order", p.family
    FROM genera t JOIN genus_chain p ON p.id = t.id
    UNION ALL
    SELECT 'family', LOWER(TRIM(t.name)), t.id, p.phylum, p.class, p."order", NULL
    FROM families t JOIN family_chain p ON p.id = t.id
    UNION ALL
    SELECT 'order', LOWER(TRIM(t.name)), t.id, p.phylum, p.class, NULL, NULL
    FROM orders t JOIN order_chain p ON p.id = t.id
    UNION ALL
    SELECT 'class', LOWER(TRIM(t.name)), t.id, p.phylum, NULL, NULL, NULL
    FROM classes t JOIN class_chain p ON p.id = t.id
)
SELECT rank, normalized_name, entity_id,
       phylum AS chain_phylum, class AS chain_class, "order" AS chain_order, family AS chain_family
FROM carriers
WHERE instr(normalized_name, char(9))  = 0
  AND instr(normalized_name, char(10)) = 0
  AND instr(normalized_name, char(13)) = 0
ORDER BY rank, normalized_name, entity_id;
