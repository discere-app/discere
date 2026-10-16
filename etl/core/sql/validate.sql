-- ---------------------------------------------------------------------------
-- validate.sql — Mindest-Zeilenzahlen + Invarianten nach dem Import
-- Wird von core/validate.sh in Stage 05 von build.sh ausgeführt.
--
-- Spalten: tbl | n | min | requires
-- Fehlschlag wenn n < min — sofern geprüft wird:
--
-- requires sagt, was in diesem Build gelaufen sein muss, damit die Prüfung
-- gilt, und ist Pflicht in jeder Zeile:
--   always                Invariante, gilt für jeden Build
--   enrich                Stage 01b (core/seed_locale_place_mappings.sh)
--   <plugin>[,<plugin>]   alle genannten Plugins
-- Eine Mindestzahl nennt die Plugins, deren Zeilen sie allein erreichen
-- (gemessen an refdb-v2); reicht eine Quelle nicht, alle nötigen.
-- Eine Zeile ohne oder mit unbekannter Angabe bricht den Build ab.
--
-- ID-Format-Checks: zählt gültige IDs — Entitäten discere:<typ>:<nr> (nach
-- der Identitäts-Stage), Bilder discere:<quelle>_<art>:<schlüssel>.
-- n = Anzahl gültiger IDs, min = Gesamtanzahl.
-- Bei ungültigen IDs gilt n < min → Fehlschlag.
-- ---------------------------------------------------------------------------

-- Mindest-Zeilenzahlen
SELECT
    'classes'         AS tbl, COUNT(*) AS n, 10     AS min, 'fishbase' AS requires FROM classes  UNION ALL
SELECT 'orders',               COUNT(*), 50,     'fishbase'             FROM orders              UNION ALL
SELECT 'families',             COUNT(*), 400,    'fishbase'             FROM families            UNION ALL
SELECT 'genera',               COUNT(*), 5000,   'fishbase'             FROM genera              UNION ALL
SELECT 'species (all)',        COUNT(*), 30000,  'fishbase'             FROM species             UNION ALL
SELECT 'species (active)',     COUNT(*), 30000,  'fishbase'             FROM species WHERE status = 'active' UNION ALL
SELECT 'pictures',             COUNT(*), 10000,  'fishbase'             FROM pictures            UNION ALL
SELECT 'pictures (usable)',    COUNT(*), 1000,   'fishbase'             FROM pictures WHERE is_usable = 1 UNION ALL
SELECT 'common_names',         COUNT(*), 100000, 'fishbase'             FROM common_names        UNION ALL
SELECT 'common_names (en)',    COUNT(*), 30000,  'fishbase'             FROM common_names WHERE language = 'en' UNION ALL
SELECT 'common_names (de)',    COUNT(*), 10000,  'fishbase,sealifebase' FROM common_names WHERE language = 'de' UNION ALL
SELECT 'taxonomy_traits',      COUNT(*), 10000,  'fishbase,sealifebase' FROM taxonomy_traits     UNION ALL
SELECT 'taxonomy_distribution_regions', COUNT(*), 400000, 'fishbase,sealifebase' FROM taxonomy_distribution_regions UNION ALL
SELECT 'locale_place_mappings',         COUNT(*), 70,     'enrich'               FROM locale_place_mappings         UNION ALL

-- ID-Format-Validierung
-- n = Anzahl Zeilen mit gültigem Format; min = Gesamtanzahl.
-- Abweichung bedeutet: mindestens eine ID entspricht nicht dem Schema.
SELECT 'id:classes',  COUNT(CASE WHEN id GLOB 'discere:class:[1-9]*'   AND substr(id, 15) NOT GLOB '*[^0-9]*' THEN 1 END), COUNT(*), 'always' FROM classes  UNION ALL
SELECT 'id:orders',   COUNT(CASE WHEN id GLOB 'discere:order:[1-9]*'   AND substr(id, 15) NOT GLOB '*[^0-9]*' THEN 1 END), COUNT(*), 'always' FROM orders   UNION ALL
SELECT 'id:families', COUNT(CASE WHEN id GLOB 'discere:family:[1-9]*'  AND substr(id, 16) NOT GLOB '*[^0-9]*' THEN 1 END), COUNT(*), 'always' FROM families UNION ALL
SELECT 'id:genera',   COUNT(CASE WHEN id GLOB 'discere:genus:[1-9]*'   AND substr(id, 15) NOT GLOB '*[^0-9]*' THEN 1 END), COUNT(*), 'always' FROM genera   UNION ALL
SELECT 'id:species',  COUNT(CASE WHEN id GLOB 'discere:species:[1-9]*' AND substr(id, 17) NOT GLOB '*[^0-9]*' THEN 1 END), COUNT(*), 'always' FROM species  UNION ALL
SELECT 'id:pictures', COUNT(CASE WHEN id GLOB 'discere:*_*:*' THEN 1 END), COUNT(*), 'always' FROM pictures UNION ALL

-- ID-Register: jede Art hat mindestens einen Schlüssel, und die übrigen
-- Invarianten hat die Identitäts-Stage geprüft. Gezählt werden nur IDs, die
-- Arten sind: Ein inaktiver Schlüssel einer Art mit Nachfolger zeigt auf
-- einen Alias.
SELECT 'entity_source_keys (Arten)',
    (SELECT COUNT(DISTINCT k.entity_id) FROM entity_source_keys k
     JOIN species s ON s.id = k.entity_id WHERE k.entity_type = 'species'),
    (SELECT COUNT(*) FROM species),
    'always'
UNION ALL

-- species_name_lookup: Anzahl muss exakt mit DISTINCT normalized_name aktiver
-- Species uebereinstimmen.
-- Der Validator kennt nur "n >= min". Deshalb pruefen wir Gleichheit in beide
-- Richtungen: lookup >= expected UND expected >= lookup.
SELECT 'species_name_lookup (>= expected)',
    (SELECT COUNT(*) FROM species_name_lookup),
    (SELECT COUNT(DISTINCT ssn.normalized_name)
     FROM species_scientific_names ssn
     JOIN species s ON s.id = ssn.species_id
     WHERE s.status = 'active'),
    'always'
UNION ALL
SELECT 'species_name_lookup (<= expected)',
    (SELECT COUNT(DISTINCT ssn.normalized_name)
     FROM species_scientific_names ssn
     JOIN species s ON s.id = ssn.species_id
     WHERE s.status = 'active'),
    (SELECT COUNT(*) FROM species_name_lookup),
    'always'
UNION ALL

-- species_name_lookup: kein aktiver normalized_name darf fehlen.
-- Auch hier pruefen wir die Gleichheit der erwarteten und gefundenen Coverage
-- in beide Richtungen.
SELECT 'species_name_lookup coverage (>= expected)',
    (SELECT COUNT(*)
     FROM (
         SELECT DISTINCT ssn.normalized_name
         FROM species_scientific_names ssn
         JOIN species s ON s.id = ssn.species_id
         WHERE s.status = 'active'
     ) expected
     JOIN species_name_lookup l
       ON l.normalized_name = expected.normalized_name),
    (SELECT COUNT(DISTINCT ssn.normalized_name)
     FROM species_scientific_names ssn
     JOIN species s ON s.id = ssn.species_id
     WHERE s.status = 'active'),
    'always'
UNION ALL
SELECT 'species_name_lookup coverage (<= expected)',
    (SELECT COUNT(DISTINCT ssn.normalized_name)
     FROM species_scientific_names ssn
     JOIN species s ON s.id = ssn.species_id
     WHERE s.status = 'active'),
    (SELECT COUNT(*)
     FROM (
         SELECT DISTINCT ssn.normalized_name
         FROM species_scientific_names ssn
         JOIN species s ON s.id = ssn.species_id
         WHERE s.status = 'active'
     ) expected
     JOIN species_name_lookup l
       ON l.normalized_name = expected.normalized_name),
    'always';
