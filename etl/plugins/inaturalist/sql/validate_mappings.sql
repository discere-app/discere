-- =============================================================================
-- validate_mappings.sql — jede iNaturalist-Zuordnung erneut gegen die Kette
--
-- Läuft in validate() von import.sh gegen die Referenz-DB, nach dem Import.
-- Bewusst unabhängig von export.sql formuliert: Grundlage sind
-- entity_external_ids samt metadata_json (Stamm, Klasse, Ordnung, Familie
-- des iNaturalist-Taxons, matched_by, homonym) und die Kette in der DB.
-- Gibt je Verstoß eine Zeile aus (Schlüssel, iNaturalist-ID, Regel, Entität);
-- keine Ausgabe heißt bestanden.
--
-- Regeln (docs/datenquellen.md, Stamm und Kette bei der
-- iNaturalist-Zuordnung):
--   stamm     jede Entität des Schlüssels hat einen Stamm, der kein
--             Platzhalter ist und gleich dem iNaturalist-Stamm oder ihm
--             gleichwertig ist (FishBase: Chordata)
--   klassen   die Entitäten eines Namensschlüssels liegen in höchstens
--             einer Klasse (ohne Platzhalter)
--   rang      bei Gattung, Familie, Ordnung und bei einer Art, deren Name
--             bei iNaturalist mehrere Taxa trägt: Klasse (gleich oder
--             gleichwertig), Ordnung oder Familie passt zu jeder Entität
--   synonym   eine Art, die über ein Synonym zugeordnet ist, hat die
--             Familie des iNaturalist-Taxons
--
-- Platzhalter (via sed in import.sh): ${PHYLUM_EQUIVALENTS},
-- ${CLASS_EQUIVALENTS}, ${PLACEHOLDER_PATTERNS}
-- =============================================================================

.bail on
CREATE TEMP TABLE v_phylum_equivalents (phylum TEXT, inat_phylum TEXT, reason TEXT);
.import --csv --skip 1 "${PHYLUM_EQUIVALENTS}" v_phylum_equivalents
CREATE TEMP TABLE v_class_equivalents (class TEXT, inat_class TEXT, reason TEXT);
.import --csv --skip 1 "${CLASS_EQUIVALENTS}" v_class_equivalents
CREATE TEMP TABLE v_placeholder_patterns (pattern TEXT);
.import --csv --skip 1 "${PLACEHOLDER_PATTERNS}" v_placeholder_patterns

-- Jede Entität mit dem Schlüssel, unter dem eine Zuordnung für sie stünde,
-- und ihrer Kette (nur die Ränge über dem eigenen).
CREATE TEMP TABLE v_chain AS
WITH cls AS (
    SELECT id, name AS class,
           CASE WHEN external_source = 'fishbase' THEN 'Chordata' ELSE super_class END AS phylum
    FROM classes
)
SELECT s.id AS mapping_key, s.id AS carrier, c.phylum, c.class, o.name AS "order", f.name AS family
FROM species s
LEFT JOIN genera g ON g.id = s.genus
LEFT JOIN families f ON f.id = g.family
LEFT JOIN orders o ON o.id = f."order"
LEFT JOIN cls c ON c.id = o.class
UNION ALL
SELECT 'genus:' || LOWER(TRIM(g.name)), g.id, c.phylum, c.class, o.name, f.name
FROM genera g
LEFT JOIN families f ON f.id = g.family
LEFT JOIN orders o ON o.id = f."order"
LEFT JOIN cls c ON c.id = o.class
UNION ALL
SELECT 'family:' || LOWER(TRIM(f.name)), f.id, c.phylum, c.class, o.name, NULL
FROM families f
LEFT JOIN orders o ON o.id = f."order"
LEFT JOIN cls c ON c.id = o.class
UNION ALL
SELECT 'order:' || LOWER(TRIM(o.name)), o.id, c.phylum, c.class, NULL, NULL
FROM orders o
LEFT JOIN cls c ON c.id = o.class
UNION ALL
SELECT 'class:' || LOWER(TRIM(c.class)), c.id, c.phylum, NULL, NULL, NULL
FROM cls c;
CREATE INDEX temp.idx_v_chain ON v_chain (mapping_key);

-- Je Zuordnung jede Entität, für die sie steht.
CREATE TEMP TABLE v_carriers AS
SELECT e.entity_id AS mapping_key, e.entity_type, e.external_id,
       json_extract(e.metadata_json, '$.phylum') AS inat_phylum,
       json_extract(e.metadata_json, '$.class') AS inat_class,
       json_extract(e.metadata_json, '$.order') AS inat_order,
       json_extract(e.metadata_json, '$.family') AS inat_family,
       json_extract(e.metadata_json, '$.matched_by') AS matched_by,
       COALESCE(json_extract(e.metadata_json, '$.homonym'), 0) AS homonym,
       c.carrier, c.phylum, c.class, c."order", c.family
FROM entity_external_ids e
JOIN v_chain c ON c.mapping_key = e.entity_id
WHERE e.provider = 'inaturalist';

.mode tabs
.headers off

SELECT e.entity_id, e.external_id, 'ohne Entität', ''
FROM entity_external_ids e
WHERE e.provider = 'inaturalist'
  AND NOT EXISTS (SELECT 1 FROM v_chain c WHERE c.mapping_key = e.entity_id);

SELECT mapping_key, external_id, 'stamm', carrier
FROM v_carriers c
WHERE c.phylum IS NULL OR TRIM(c.phylum) = '' OR c.inat_phylum IS NULL
   OR EXISTS (SELECT 1 FROM v_placeholder_patterns p WHERE LOWER(TRIM(c.phylum)) GLOB p.pattern)
   OR NOT (c.phylum = c.inat_phylum
           OR EXISTS (SELECT 1 FROM v_phylum_equivalents e
                      WHERE e.phylum = c.phylum AND e.inat_phylum = c.inat_phylum));

SELECT mapping_key, MIN(external_id), 'klassen', group_concat(DISTINCT LOWER(TRIM(class)))
FROM v_carriers c
WHERE class IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM v_placeholder_patterns p WHERE LOWER(TRIM(c.class)) GLOB p.pattern)
GROUP BY mapping_key
HAVING COUNT(DISTINCT LOWER(TRIM(class))) > 1;

SELECT mapping_key, external_id, 'rang', carrier
FROM v_carriers c
WHERE (entity_type IN ('genera', 'families', 'orders') OR (entity_type = 'species' AND homonym = 1))
  AND NOT COALESCE(
        LOWER(TRIM(c.class)) = LOWER(c.inat_class)
        OR EXISTS (SELECT 1 FROM v_class_equivalents e
                   WHERE LOWER(e.class) = LOWER(TRIM(c.class)) AND LOWER(e.inat_class) = LOWER(c.inat_class))
        OR LOWER(TRIM(c."order")) = LOWER(c.inat_order)
        OR LOWER(TRIM(c.family)) = LOWER(c.inat_family),
        0);

SELECT mapping_key, external_id, 'synonym', carrier
FROM v_carriers c
WHERE entity_type = 'species' AND matched_by = 'synonym'
  AND NOT COALESCE(LOWER(TRIM(c.family)) = LOWER(c.inat_family), 0);
