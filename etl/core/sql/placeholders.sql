-- ---------------------------------------------------------------------------
-- placeholders.sql — Rang-Platzhalter markieren (core/placeholders.sh)
--
-- Ein Rang-Platzhalter ist ein höheres Taxon, mit dem eine Quelle ausdrückt,
-- dass eine Gruppe auf diesem Rang keinem Taxon zugeordnet ist (SeaLifeBase:
-- „Not assigned“, „Incertae sedis (Nemertea)“). Erkannt wird er am Namen,
-- ohne Rücksicht auf Groß- und Kleinschreibung und umgebende Leerzeichen:
--
--   not assigned*          „Not assigned“
--   *incer[a-z]* sedis*    „Incertae sedis“ an beliebiger Stelle, auch in der
--                          Schreibweise „Incerate sedis“ — „sedis“ allein
--                          reicht nicht, es kommt in echten Namen vor
--
-- Jeder Treffer steht im Build-Bericht; ein Fehltreffer fällt dort auf.
-- Gesetzt wird das Flag in beide Richtungen, damit eine Zeile, die aus dem
-- Vorgänger übernommen wurde, die Regel dieses Builds trägt.
-- ---------------------------------------------------------------------------

CREATE TEMP TABLE placeholder_patterns (pattern TEXT NOT NULL);
INSERT INTO placeholder_patterns (pattern) VALUES
    ('not assigned*'),
    ('*incer[a-z]* sedis*');

UPDATE classes SET is_placeholder = EXISTS (
    SELECT 1 FROM placeholder_patterns WHERE lower(trim(name)) GLOB pattern);
UPDATE orders SET is_placeholder = EXISTS (
    SELECT 1 FROM placeholder_patterns WHERE lower(trim(name)) GLOB pattern);
UPDATE families SET is_placeholder = EXISTS (
    SELECT 1 FROM placeholder_patterns WHERE lower(trim(name)) GLOB pattern);
UPDATE genera SET is_placeholder = EXISTS (
    SELECT 1 FROM placeholder_patterns WHERE lower(trim(name)) GLOB pattern);

-- Bericht: Rang, ID, Name, Quelle und Anzahl aktiver Arten darunter.
.mode tabs
.headers off
SELECT 'class', c.id, c.name, c.external_source || ', aktive Arten: ' || (
    SELECT COUNT(*) FROM orders o
    JOIN families f ON f."order" = o.id
    JOIN genera g ON g.family = f.id
    JOIN species s ON s.genus = g.id AND s.status = 'active'
    WHERE o.class = c.id)
FROM classes c WHERE c.is_placeholder = 1
UNION ALL
SELECT 'order', o.id, o.name, o.external_source || ', aktive Arten: ' || (
    SELECT COUNT(*) FROM families f
    JOIN genera g ON g.family = f.id
    JOIN species s ON s.genus = g.id AND s.status = 'active'
    WHERE f."order" = o.id)
FROM orders o WHERE o.is_placeholder = 1
UNION ALL
SELECT 'family', f.id, f.name, f.external_source || ', aktive Arten: ' || (
    SELECT COUNT(*) FROM genera g
    JOIN species s ON s.genus = g.id AND s.status = 'active'
    WHERE g.family = f.id)
FROM families f WHERE f.is_placeholder = 1
UNION ALL
SELECT 'genus', g.id, g.name, g.external_source || ', aktive Arten: ' || (
    SELECT COUNT(*) FROM species s
    WHERE s.genus = g.id AND s.status = 'active')
FROM genera g WHERE g.is_placeholder = 1
ORDER BY 1, 3, 2;
