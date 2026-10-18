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

-- Namen, die species_name_lookup auflösen muss (core/sql/rebuild_lookup.sql),
-- unabhängig davon formuliert: je Name aktiver Arten ohne falsch angewandte
-- die einzige Art, bei der er bevorzugt ist, oder — bevorzugt nirgends und
-- keiner Quelle als Synonym mehrerer Arten bekannt
-- (ambiguous_scientific_names) — die einzige, die ihn führt. Jeder andere
-- Name hat keinen Eintrag.
CREATE TEMP VIEW validate_lookup_expected AS
SELECT normalized_name,
       CASE WHEN SUM(is_preferred) = 1
            THEN MAX(CASE WHEN is_preferred = 1 THEN species_id END)
            ELSE MIN(species_id)
       END AS species_id
FROM (
    SELECT ssn.normalized_name, ssn.species_id, MAX(ssn.is_preferred) AS is_preferred
    FROM species_scientific_names ssn
    JOIN species s ON s.id = ssn.species_id
    WHERE s.status = 'active' AND ssn.name_status != 'misapplied name'
    GROUP BY ssn.normalized_name, ssn.species_id
)
GROUP BY normalized_name
HAVING SUM(is_preferred) = 1
    OR (SUM(is_preferred) = 0 AND COUNT(*) = 1
        AND normalized_name NOT IN (SELECT normalized_name FROM ambiguous_scientific_names));

-- Höhere Taxa mit ihrem Namensschlüssel (genus:barbus, wie die
-- iNaturalist-Zuordnung ihn ablegt) und ob ihre Kette bis zu einer Klasse
-- mit Stamm reicht. Gattungen, Familien und Ordnungen nur, wenn an ihnen
-- bzw. darunter eine Art hängt (aktiv oder veraltet): Eine Zeile ohne Art
-- zeigt die App unter keinem Schlüssel.
CREATE TEMP VIEW validate_taxon_chain AS
SELECT 'genus:' || LOWER(TRIM(g.name)) AS name_key, TRIM(COALESCE(c.super_class, '')) != '' AS has_chain
FROM genera g
LEFT JOIN families f ON f.id = g.family
LEFT JOIN orders o ON o.id = f."order"
LEFT JOIN classes c ON c.id = o.class
WHERE EXISTS (SELECT 1 FROM species s2 WHERE s2.genus = g.id)
UNION ALL
SELECT 'family:' || LOWER(TRIM(f.name)), TRIM(COALESCE(c.super_class, '')) != ''
FROM families f
LEFT JOIN orders o ON o.id = f."order"
LEFT JOIN classes c ON c.id = o.class
WHERE EXISTS (SELECT 1 FROM genera g2 JOIN species s2 ON s2.genus = g2.id WHERE g2.family = f.id)
UNION ALL
SELECT 'order:' || LOWER(TRIM(o.name)), TRIM(COALESCE(c.super_class, '')) != ''
FROM orders o
LEFT JOIN classes c ON c.id = o.class
WHERE EXISTS (SELECT 1 FROM families f2 JOIN genera g2 ON g2.family = f2.id JOIN species s2 ON s2.genus = g2.id WHERE f2."order" = o.id)
UNION ALL
SELECT 'class:' || LOWER(TRIM(name)), TRIM(super_class) != '' FROM classes;

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
-- Rang-Platzhalter (Stage 02d): v26.06 hat 197, alle aus SeaLifeBase. Trifft
-- die Namensregel kaum noch etwas, haben sich die Namen der Quelle geändert.
SELECT 'rank placeholders',
    (SELECT COUNT(*) FROM classes WHERE is_placeholder = 1)
    + (SELECT COUNT(*) FROM orders WHERE is_placeholder = 1)
    + (SELECT COUNT(*) FROM families WHERE is_placeholder = 1),
    150, 'sealifebase'                                                                                 UNION ALL

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

-- Bevorzugter wissenschaftlicher Name: Jede aktive Art mit Gattung hat einen,
-- und er ist ihr eigener Name — Gattung und Epitheton, normalisiert wie im
-- Export der Quellen (trim, lower; SQLite senkt nur ASCII, ein Name mit
-- großem Nicht-ASCII-Buchstaben fiele hier laut auf). Keine Art hat mehr
-- als einen je Quelle (eine Art aus zwei Quellen trägt je Quelle ihren, der
-- der anderen Quelle darf deshalb abweichen). Ohne ihn, oder mit einem
-- fremden, verweist ein Name im species_name_lookup womöglich auf die falsche
-- Art. Eine Art ohne Gattung ist ausgenommen: Ihr bevorzugter Name ist der,
-- den ihre Quelle ihr gibt, und eine Gattung, gegen die er sich prüfen ließe,
-- gibt es nicht. Übernommene Arten tragen die Namen ihres Vorgängers.
SELECT 'species (preferred name)',
    (SELECT COUNT(*) FROM species s
     JOIN genera g ON g.id = s.genus
     WHERE s.status = 'active'
       AND EXISTS (SELECT 1 FROM species_scientific_names ssn
                   WHERE ssn.species_id = s.id AND ssn.is_preferred = 1
                     AND ssn.normalized_name = lower(trim(g.name) || ' ' || trim(s.name)))),
    (SELECT COUNT(*) FROM species WHERE status = 'active' AND genus IS NOT NULL),
    'always'
UNION ALL
-- Eine Art ohne Gattung: Ihr bevorzugter Name endet auf ihr Epitheton. Ob
-- sie einen hat, prüft der Export der Quelle; höchstens einen je Quelle die
-- Zeile danach.
SELECT 'species without genus (preferred name)',
    (SELECT COUNT(*) FROM species s
     WHERE s.status = 'active' AND s.genus IS NULL
       AND EXISTS (SELECT 1 FROM species_scientific_names ssn
                   WHERE ssn.species_id = s.id AND ssn.is_preferred = 1)
       AND NOT EXISTS (SELECT 1 FROM species_scientific_names ssn
                       WHERE ssn.species_id = s.id AND ssn.is_preferred = 1
                         AND substr(ssn.normalized_name, -length(' ' || lower(trim(s.name))))
                             != ' ' || lower(trim(s.name)))),
    (SELECT COUNT(*) FROM species s
     WHERE s.status = 'active' AND s.genus IS NULL
       AND EXISTS (SELECT 1 FROM species_scientific_names ssn
                   WHERE ssn.species_id = s.id AND ssn.is_preferred = 1)),
    'always'
UNION ALL
SELECT 'preferred names (per source)',
    (SELECT COUNT(*) FROM (SELECT DISTINCT species_id, source FROM species_scientific_names
                           WHERE is_preferred = 1)),
    (SELECT COUNT(*) FROM species_scientific_names WHERE is_preferred = 1),
    'always'
UNION ALL

-- species_name_lookup: genau die eindeutig auflösbaren Namen
-- (validate_lookup_expected), jeder auf seine Art. Der Validator kennt nur
-- "n >= min"; gleiche Anzahl in beide Richtungen und jeder erwartete Name
-- mit seiner Art im Lookup heißt: beide Mengen sind gleich — ein
-- mehrdeutiger Name mit Eintrag fällt so ebenso auf wie ein fehlender.
SELECT 'species_name_lookup (>= expected)',
    (SELECT COUNT(*) FROM species_name_lookup),
    (SELECT COUNT(*) FROM validate_lookup_expected),
    'always'
UNION ALL
SELECT 'species_name_lookup (<= expected)',
    (SELECT COUNT(*) FROM validate_lookup_expected),
    (SELECT COUNT(*) FROM species_name_lookup),
    'always'
UNION ALL
SELECT 'species_name_lookup (targets)',
    (SELECT COUNT(*) FROM validate_lookup_expected e
     JOIN species_name_lookup l
       ON l.normalized_name = e.normalized_name AND l.species_id = e.species_id),
    (SELECT COUNT(*) FROM validate_lookup_expected),
    'always'
UNION ALL

-- iNaturalist-Zuordnungen nur mit eigener Kette: Das Plugin übernimmt eine
-- Zuordnung nur, wenn der Stamm des iNaturalist-Taxons zur Kette jeder
-- Entität seines Namens passt (plugins/inaturalist/sql/export.sql). Den
-- iNaturalist-Stamm kennt die DB nicht; prüfen lässt sich hier, was ohne
-- ihn feststeht: Jede zugeordnete Art hat eine Kette bis zu einer Klasse
-- mit Stamm, und jede Entität hinter einem zugeordneten Namensschlüssel
-- ebenso. Den Abgleich mit dem iNaturalist-Stamm prüft das Plugin selbst
-- (plugins/inaturalist/sql/validate_mappings.sql). Ein
-- Schlüssel ohne Entität fiele auch auf.
SELECT 'inaturalist (species with chain)',
    (SELECT COUNT(*) FROM entity_external_ids e
     JOIN species s ON s.id = e.entity_id
     JOIN genera g ON g.id = s.genus
     JOIN families f ON f.id = g.family
     JOIN orders o ON o.id = f."order"
     JOIN classes c ON c.id = o.class AND TRIM(c.super_class) != ''
     WHERE e.provider = 'inaturalist' AND e.entity_type = 'species'),
    (SELECT COUNT(*) FROM entity_external_ids
     WHERE provider = 'inaturalist' AND entity_type = 'species'),
    'inaturalist'
UNION ALL
SELECT 'inaturalist (name keys with chain)',
    (SELECT COUNT(*) FROM entity_external_ids
     WHERE provider = 'inaturalist' AND entity_type != 'species'
       AND entity_id IN (SELECT name_key FROM validate_taxon_chain)
       AND entity_id NOT IN (SELECT name_key FROM validate_taxon_chain WHERE NOT has_chain)),
    (SELECT COUNT(*) FROM entity_external_ids
     WHERE provider = 'inaturalist' AND entity_type != 'species'),
    'inaturalist';
