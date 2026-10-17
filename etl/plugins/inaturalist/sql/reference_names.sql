-- =============================================================================
-- reference_names.sql — Namensträger der Referenz-DB mit dem Stamm ihrer Kette
--
-- Läuft in einer sqlite3-Sitzung gegen die Referenz-DB (import.sh) und gibt
-- je Name, den der Abgleich treffen kann, jede Entität aus, die ihn trägt:
--
--   rank, normalized_name, entity_id, chain_phylum
--
-- Die Namen sind die Kandidaten aus core/sql/match.sql: bei Arten alle Namen
-- aktiver Arten außer falsch angewandten, bei höheren Taxa der Name in der
-- Tabelle ihres Rangs — alle gleichnamigen Zeilen, denn sie teilen sich den
-- Namensschlüssel (genus:barbus), unter dem die Zuordnung liegt. Normalisiert
-- wie species_scientific_names.normalized_name.
--
-- chain_phylum ist der Stamm über die eigene Kette (Art › Gattung › Familie
-- › Ordnung › Klasse), wie die Quelle ihn nennt; leer, wenn die Kette vorher
-- abbricht, etwa bei einer Art ohne Gattung. SeaLifeBase führt den Stamm in
-- classes.super_class, teils als Platzhalter („Not Assigned (Plantae)“).
-- FishBase führt dort die Überklasse (Osteichthyes, Agnatha, …); FishBase
-- kennt nur Fische, ihr Stamm ist Chordata.
--
-- Namen mit Tab oder Zeilenumbruch (Tippfehler in den Quelldaten) passen in
-- keine TSV-Zeile und auf keinen iNaturalist-Namen; sie fallen hier weg.
-- =============================================================================

WITH class_phylum AS (
    SELECT id, CASE WHEN external_source = 'fishbase' THEN 'Chordata' ELSE super_class END AS phylum
    FROM classes
),
order_phylum AS (
    SELECT o.id, c.phylum FROM orders o LEFT JOIN class_phylum c ON c.id = o.class
),
family_phylum AS (
    SELECT f.id, o.phylum FROM families f LEFT JOIN order_phylum o ON o.id = f."order"
),
genus_phylum AS (
    SELECT g.id, f.phylum FROM genera g LEFT JOIN family_phylum f ON f.id = g.family
),
carriers AS (
    SELECT DISTINCT 'species' AS rank, n.normalized_name, s.id AS entity_id, g.phylum AS chain_phylum
    FROM species_scientific_names n
    JOIN species s ON s.id = n.species_id AND s.status = 'active'
    LEFT JOIN genus_phylum g ON g.id = s.genus
    WHERE n.name_status != 'misapplied name'
    UNION ALL
    SELECT 'genus', LOWER(TRIM(t.name)), t.id, p.phylum FROM genera t JOIN genus_phylum p ON p.id = t.id
    UNION ALL
    SELECT 'family', LOWER(TRIM(t.name)), t.id, p.phylum FROM families t JOIN family_phylum p ON p.id = t.id
    UNION ALL
    SELECT 'order', LOWER(TRIM(t.name)), t.id, p.phylum FROM orders t JOIN order_phylum p ON p.id = t.id
    UNION ALL
    SELECT 'class', LOWER(TRIM(t.name)), t.id, p.phylum FROM classes t JOIN class_phylum p ON p.id = t.id
)
SELECT rank, normalized_name, entity_id, chain_phylum
FROM carriers
WHERE instr(normalized_name, char(9))  = 0
  AND instr(normalized_name, char(10)) = 0
  AND instr(normalized_name, char(13)) = 0
ORDER BY rank, normalized_name, entity_id;
