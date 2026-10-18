-- =============================================================================
-- validate_mappings.sql — jede iNaturalist-Zuordnung erneut gegen die Kette
--
-- Läuft in validate() von import.sh gegen die Referenz-DB, nach dem Import.
-- Bewusst unabhängig von export.sql und seiner Ableitung der Ahnenkette
-- formuliert: Stamm, Klasse, Ordnung, Familie und Name des iNaturalist-Taxons
-- leitet diese Datei selbst aus taxa.csv ab (${TAXA_TSV}, entpackt), ob ein
-- Name bei iNaturalist mehrere aktive Taxa trägt ebenso, und ob eine Art über
-- ein Synonym zugeordnet ist, aus ihren bevorzugten Namen. metadata_json muss
-- dazu passen. Gibt je Verstoß eine Zeile aus (Schlüssel, iNaturalist-ID,
-- Regel, Entität); keine Ausgabe heißt bestanden.
--
-- Regeln (docs/datenquellen.md, Stamm und Kette bei der
-- iNaturalist-Zuordnung):
--   stamm      jede Entität des Schlüssels hat einen Stamm, der kein
--              Platzhalter ist und gleich dem iNaturalist-Stamm oder ihm
--              gleichwertig ist (FishBase: Chordata)
--   klassen    die Entitäten eines Namensschlüssels liegen in höchstens
--              einer Klasse (ohne Platzhalter)
--   rang       bei Gattung, Familie, Ordnung und bei einer Art, deren Name
--              bei iNaturalist mehrere Taxa trägt: Klasse (gleich oder
--              gleichwertig), Ordnung oder Familie passt zu jeder Entität
--   synonym    eine Art, die über ein Synonym zugeordnet ist, hat die
--              Familie des iNaturalist-Taxons, und dessen Epitheton gleicht
--              ihrem in den ersten vier Buchstaben
--   metadata   metadata_json nennt dieselbe Kette, matched_by und homonym
--
-- Platzhalter (via sed in import.sh): ${TAXA_TSV}, ${PHYLUM_EQUIVALENTS},
-- ${CLASS_EQUIVALENTS}, ${PLACEHOLDER_PATTERNS}
-- =============================================================================

.bail on
CREATE TEMP TABLE v_phylum_equivalents (phylum TEXT, inat_phylum TEXT, reason TEXT);
.import --csv --skip 1 "${PHYLUM_EQUIVALENTS}" v_phylum_equivalents
CREATE TEMP TABLE v_class_equivalents (class TEXT, inat_class TEXT, reason TEXT);
.import --csv --skip 1 "${CLASS_EQUIVALENTS}" v_class_equivalents
CREATE TEMP TABLE v_placeholder_patterns (pattern TEXT);
.import --csv --skip 1 "${PLACEHOLDER_PATTERNS}" v_placeholder_patterns

CREATE TEMP TABLE v_taxa (taxon_id TEXT, ancestry TEXT, rank_level TEXT, rank TEXT, name TEXT, active TEXT);
.mode ascii
.separator "\t" "\n"
.import --skip 1 "${TAXA_TSV}" v_taxa
DELETE FROM v_taxa WHERE active != 'true';
CREATE INDEX temp.idx_v_taxa_id ON v_taxa (CAST(taxon_id AS INTEGER));
CREATE INDEX temp.idx_v_taxa_name ON v_taxa (rank, LOWER(TRIM(name)));

-- Das iNaturalist-Taxon jeder Zuordnung, aus taxa.csv.
CREATE TEMP TABLE v_inat AS
SELECT e.entity_id AS mapping_key, e.entity_type, e.external_id, e.metadata_json,
       TRIM(t.name) AS name, t.rank,
       (SELECT COUNT(*) FROM v_taxa x
        WHERE x.rank = t.rank AND LOWER(TRIM(x.name)) = LOWER(TRIM(t.name))) > 1 AS homonym,
       (SELECT MAX(CASE a.rank WHEN 'phylum' THEN TRIM(a.name) END)
        FROM json_each('["' || REPLACE(t.ancestry, '/', '","') || '"]') j
        JOIN v_taxa a ON CAST(a.taxon_id AS INTEGER) = CAST(j.value AS INTEGER)) AS phylum,
       (SELECT MAX(CASE a.rank WHEN 'class' THEN TRIM(a.name) END)
        FROM json_each('["' || REPLACE(t.ancestry, '/', '","') || '"]') j
        JOIN v_taxa a ON CAST(a.taxon_id AS INTEGER) = CAST(j.value AS INTEGER)) AS class,
       (SELECT MAX(CASE a.rank WHEN 'order' THEN TRIM(a.name) END)
        FROM json_each('["' || REPLACE(t.ancestry, '/', '","') || '"]') j
        JOIN v_taxa a ON CAST(a.taxon_id AS INTEGER) = CAST(j.value AS INTEGER)) AS "order",
       (SELECT MAX(CASE a.rank WHEN 'family' THEN TRIM(a.name) END)
        FROM json_each('["' || REPLACE(t.ancestry, '/', '","') || '"]') j
        JOIN v_taxa a ON CAST(a.taxon_id AS INTEGER) = CAST(j.value AS INTEGER)) AS family
FROM entity_external_ids e
LEFT JOIN v_taxa t ON CAST(t.taxon_id AS INTEGER) = CAST(e.external_id AS INTEGER)
WHERE e.provider = 'inaturalist';

-- Jede Entität mit dem Schlüssel, unter dem eine Zuordnung für sie stünde,
-- und ihrer Kette (nur die Ränge über dem eigenen).
CREATE TEMP TABLE v_chain AS
WITH cls AS (
    SELECT id, name AS class,
           CASE WHEN external_source = 'fishbase' THEN 'Chordata' ELSE super_class END AS phylum
    FROM classes
)
SELECT s.id AS mapping_key, s.id AS carrier, c.phylum, c.class, o.name AS "order", f.name AS family,
       LOWER(TRIM(s.name)) AS epithet
FROM species s
LEFT JOIN genera g ON g.id = s.genus
LEFT JOIN families f ON f.id = g.family
LEFT JOIN orders o ON o.id = f."order"
LEFT JOIN cls c ON c.id = o.class
UNION ALL
SELECT 'genus:' || LOWER(TRIM(g.name)), g.id, c.phylum, c.class, o.name, f.name, NULL
FROM genera g
LEFT JOIN families f ON f.id = g.family
LEFT JOIN orders o ON o.id = f."order"
LEFT JOIN cls c ON c.id = o.class
UNION ALL
SELECT 'family:' || LOWER(TRIM(f.name)), f.id, c.phylum, c.class, o.name, NULL, NULL
FROM families f
LEFT JOIN orders o ON o.id = f."order"
LEFT JOIN cls c ON c.id = o.class
UNION ALL
SELECT 'order:' || LOWER(TRIM(o.name)), o.id, c.phylum, c.class, NULL, NULL, NULL
FROM orders o
LEFT JOIN cls c ON c.id = o.class
UNION ALL
SELECT 'class:' || LOWER(TRIM(c.class)), c.id, c.phylum, NULL, NULL, NULL, NULL
FROM cls c;
CREATE INDEX temp.idx_v_chain ON v_chain (mapping_key);

-- Je Zuordnung jede Entität, für die sie steht. Synonym heißt: Der Name des
-- iNaturalist-Taxons ist keiner der bevorzugten Namen der Art.
CREATE TEMP TABLE v_carriers AS
SELECT i.*,
       CASE WHEN i.entity_type != 'species' THEN NULL
            WHEN EXISTS (SELECT 1 FROM species_scientific_names n
                         WHERE n.species_id = i.mapping_key AND n.is_preferred = 1
                           AND n.normalized_name = LOWER(TRIM(i.name))) THEN 'name'
            ELSE 'synonym' END AS matched_by,
       LOWER(TRIM(substr(i.name, instr(i.name, ' ') + 1))) AS name_rest,
       c.carrier, c.phylum AS chain_phylum, c.class AS chain_class, c."order" AS chain_order,
       c.family AS chain_family, c.epithet
FROM v_inat i
JOIN v_chain c ON c.mapping_key = i.mapping_key;

.mode tabs
.headers off

SELECT e.entity_id, e.external_id, 'ohne Entität', ''
FROM entity_external_ids e
WHERE e.provider = 'inaturalist'
  AND NOT EXISTS (SELECT 1 FROM v_chain c WHERE c.mapping_key = e.entity_id);

SELECT mapping_key, external_id, 'ohne iNaturalist-Taxon', ''
FROM v_inat WHERE name IS NULL;

SELECT mapping_key, external_id, 'stamm', carrier
FROM v_carriers c
WHERE c.chain_phylum IS NULL OR TRIM(c.chain_phylum) = '' OR c.phylum IS NULL
   OR EXISTS (SELECT 1 FROM v_placeholder_patterns p WHERE LOWER(TRIM(c.chain_phylum)) GLOB p.pattern)
   OR NOT (c.chain_phylum = c.phylum
           OR EXISTS (SELECT 1 FROM v_phylum_equivalents e
                      WHERE e.phylum = c.chain_phylum AND e.inat_phylum = c.phylum));

SELECT mapping_key, MIN(external_id), 'klassen', group_concat(DISTINCT LOWER(TRIM(chain_class)))
FROM v_carriers c
WHERE chain_class IS NOT NULL
  AND NOT EXISTS (SELECT 1 FROM v_placeholder_patterns p WHERE LOWER(TRIM(c.chain_class)) GLOB p.pattern)
GROUP BY mapping_key
HAVING COUNT(DISTINCT LOWER(TRIM(chain_class))) > 1;

SELECT mapping_key, external_id, 'rang', carrier
FROM v_carriers c
WHERE (entity_type IN ('genera', 'families', 'orders') OR (entity_type = 'species' AND homonym))
  AND NOT COALESCE(
        LOWER(TRIM(c.chain_class)) = LOWER(c.class)
        OR EXISTS (SELECT 1 FROM v_class_equivalents e
                   WHERE LOWER(e.class) = LOWER(TRIM(c.chain_class)) AND LOWER(e.inat_class) = LOWER(c.class))
        OR LOWER(TRIM(c.chain_order)) = LOWER(c."order")
        OR LOWER(TRIM(c.chain_family)) = LOWER(c.family),
        0);

SELECT mapping_key, external_id, 'synonym', carrier
FROM v_carriers c
WHERE matched_by = 'synonym'
  AND NOT COALESCE(
        LOWER(TRIM(c.chain_family)) = LOWER(c.family)
        AND substr(CASE WHEN instr(c.name_rest, ' ') > 0
                        THEN substr(c.name_rest, 1, instr(c.name_rest, ' ') - 1)
                        ELSE c.name_rest END, 1, 4) = substr(c.epithet, 1, 4),
        0);

SELECT mapping_key, external_id, 'metadata', ''
FROM v_carriers c
WHERE name IS NOT NULL
  AND (json_extract(metadata_json, '$.phylum') IS NOT phylum
       OR json_extract(metadata_json, '$.class') IS NOT class
       OR json_extract(metadata_json, '$.order') IS NOT "order"
       OR json_extract(metadata_json, '$.family') IS NOT family
       OR json_extract(metadata_json, '$.homonym') IS NOT homonym
       OR (entity_type = 'species' AND json_extract(metadata_json, '$.matched_by') IS NOT matched_by))
GROUP BY mapping_key;
