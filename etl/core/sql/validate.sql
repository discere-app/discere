-- ---------------------------------------------------------------------------
-- validate.sql — Mindest-Zeilenzahlen + UUID-Format nach dem Import
-- Wird von build.sh nach allen Plugins ausgeführt.
-- Bei Unterschreitung bricht das Script ab.
--
-- Spalten: tbl | n | min
-- Fehlschlag wenn n < min.
--
-- UUID-Format-Checks: zählt gültige IDs (GLOB 'discere:*_*:*').
-- n = Anzahl gültiger IDs, min = Gesamtanzahl.
-- Bei ungültigen IDs gilt n < min → Fehlschlag.
-- ---------------------------------------------------------------------------

-- Mindest-Zeilenzahlen
SELECT
    'classes'         AS tbl, COUNT(*) AS n, 10     AS min FROM classes                          UNION ALL
SELECT 'orders',               COUNT(*), 50    FROM orders                                        UNION ALL
SELECT 'families',             COUNT(*), 400   FROM families                                      UNION ALL
SELECT 'genera',               COUNT(*), 5000  FROM genera                                        UNION ALL
SELECT 'species (all)',        COUNT(*), 30000 FROM species                                       UNION ALL
SELECT 'species (active)',     COUNT(*), 30000 FROM species WHERE status = 'active'               UNION ALL
SELECT 'pictures',             COUNT(*), 10000 FROM pictures                                      UNION ALL
SELECT 'pictures (usable)',    COUNT(*), 1000  FROM pictures WHERE is_usable = 1                    UNION ALL
SELECT 'species_names',       COUNT(*), 0     FROM species_names                                    UNION ALL
SELECT 'species_names (en)',  COUNT(*), 0     FROM species_names WHERE language = 'en'              UNION ALL
SELECT 'taxonomy_traits',      COUNT(*), 10000 FROM taxonomy_traits                                 UNION ALL
SELECT 'taxonomy_distribution_regions', COUNT(*), 400000 FROM taxonomy_distribution_regions         UNION ALL

-- UUID-Format-Validierung
-- n = Anzahl Zeilen mit gültigem Format; min = Gesamtanzahl.
-- Abweichung bedeutet: mindestens eine ID entspricht nicht dem Schema.
SELECT 'uuid:classes',  COUNT(CASE WHEN id GLOB 'discere:*_*:*' THEN 1 END), COUNT(*) FROM classes  UNION ALL
SELECT 'uuid:orders',   COUNT(CASE WHEN id GLOB 'discere:*_*:*' THEN 1 END), COUNT(*) FROM orders   UNION ALL
SELECT 'uuid:families', COUNT(CASE WHEN id GLOB 'discere:*_*:*' THEN 1 END), COUNT(*) FROM families UNION ALL
SELECT 'uuid:genera',   COUNT(CASE WHEN id GLOB 'discere:*_*:*' THEN 1 END), COUNT(*) FROM genera   UNION ALL
SELECT 'uuid:species',  COUNT(CASE WHEN id GLOB 'discere:*_*:*' THEN 1 END), COUNT(*) FROM species  UNION ALL
SELECT 'uuid:pictures', COUNT(CASE WHEN id GLOB 'discere:*_*:*' THEN 1 END), COUNT(*) FROM pictures;
