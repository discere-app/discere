-- =============================================================================
-- identity_finish.sql — Register und Aliase schreiben, Invarianten prüfen
--
-- Teil der Identitäts-Stage (core/identity.sh), nach dem Umschreiben und der
-- Übernahme aus dem Vorgänger. Jede verletzte Invariante bricht ab
-- (identity_failure).
-- =============================================================================

CREATE TEMP TABLE identity_entities (
    id           TEXT NOT NULL PRIMARY KEY,
    entity_type  TEXT NOT NULL
);
INSERT INTO identity_entities (id, entity_type)
SELECT id, 'species' FROM species
UNION ALL SELECT id, 'genus'  FROM genera
UNION ALL SELECT id, 'family' FROM families
UNION ALL SELECT id, 'order'  FROM orders
UNION ALL SELECT id, 'class'  FROM classes;

INSERT INTO identity_failure (message)
SELECT COUNT(*) || ' Entitäts-IDs haben nicht die Form discere:<typ>:<nr>, z. B. ' || MIN(id)
FROM identity_entities
WHERE NOT (id GLOB 'discere:' || entity_type || ':[1-9]*'
           AND substr(id, length('discere:' || entity_type || ':') + 1) NOT GLOB '*[^0-9]*')
HAVING COUNT(*) > 0;

-- ---------------------------------------------------------------------------
-- Register: jeder Schlüssel dieses Builds aktiv, jeder übernommene, den keine
-- Quelle mehr geliefert hat, inaktiv mit seiner bisherigen ID.
-- ---------------------------------------------------------------------------
INSERT INTO entity_source_keys (source, entity_type, external_id, entity_id, active)
SELECT r.source, r.entity_type, r.external_id, m.entity_id, 1
FROM identity_rows r
JOIN identity_id_map m ON m.provisional_id = r.provisional_id
UNION ALL
SELECT g.source, g.entity_type, g.external_id, g.entity_id, 0
FROM identity_register g
WHERE NOT EXISTS (
    SELECT 1 FROM identity_rows r
    WHERE r.source      = g.source
      AND r.entity_type = g.entity_type
      AND r.external_id = g.external_id
);

INSERT INTO identity_failure (message)
SELECT 'Register: ' || COUNT(*) || ' Schlüssel zeigen auf keine Entität ihres Typs, z. B. '
       || MIN(k.source || ':' || k.entity_type || ':' || k.external_id || ' → ' || k.entity_id)
FROM entity_source_keys k
LEFT JOIN identity_entities e ON e.id = k.entity_id AND e.entity_type = k.entity_type
WHERE e.id IS NULL
HAVING COUNT(*) > 0;

INSERT INTO identity_failure (message)
SELECT 'Register: ' || COUNT(*) || ' Entitäten ohne Schlüssel, z. B. ' || MIN(e.id)
FROM identity_entities e
WHERE NOT EXISTS (SELECT 1 FROM entity_source_keys k WHERE k.entity_id = e.id)
HAVING COUNT(*) > 0;

-- ---------------------------------------------------------------------------
-- Aliase: jede ID des Vorgängers, die keine Entität mehr bezeichnet, zeigt
-- auf ihre ID in diesem Build; die Aliase des Vorgängers werden auf die
-- aktuelle ID ihres Ziels nachgeführt. Damit zeigt jeder Alias direkt auf
-- eine Entität, auch für Nutzer, die Releases überspringen.
-- ---------------------------------------------------------------------------
INSERT INTO entity_aliases (alias_id, entity_id)
SELECT prev_id, entity_id
FROM identity_prev_ids
WHERE prev_id != entity_id
UNION ALL
SELECT a.alias_id, COALESCE(p.entity_id, a.entity_id)
FROM identity_prev_aliases a
LEFT JOIN identity_prev_ids p ON p.prev_id = a.entity_id;

INSERT INTO identity_failure (message)
SELECT 'Aliase: ' || COUNT(*) || ' Alias-IDs sind zugleich Entitäts-IDs, z. B. ' || MIN(a.alias_id)
FROM entity_aliases a
JOIN identity_entities e ON e.id = a.alias_id
HAVING COUNT(*) > 0;

-- Eine Kette ist zugleich ein Alias ohne Entität als Ziel; sie zuerst zu
-- prüfen, nennt den genaueren Grund.
INSERT INTO identity_failure (message)
SELECT 'Aliase: ' || COUNT(*) || ' zeigen auf einen anderen Alias, z. B. ' || MIN(a.alias_id || ' → ' || a.entity_id)
FROM entity_aliases a
JOIN entity_aliases b ON b.alias_id = a.entity_id
HAVING COUNT(*) > 0;

INSERT INTO identity_failure (message)
SELECT 'Aliase: ' || COUNT(*) || ' zeigen auf keine Entität, z. B. ' || MIN(a.alias_id || ' → ' || a.entity_id)
FROM entity_aliases a
LEFT JOIN identity_entities e ON e.id = a.entity_id
WHERE e.id IS NULL
HAVING COUNT(*) > 0;

-- ---------------------------------------------------------------------------
-- Fremdschlüssel: jeder Verweis löst auf.
-- ---------------------------------------------------------------------------
INSERT INTO identity_failure (message)
SELECT 'Fremdschlüssel: ' || COUNT(*) || ' Verweise lösen nicht auf, z. B. '
       || (SELECT "table" || ' → ' || parent FROM pragma_foreign_key_check(NULL, 'main') LIMIT 1)
FROM pragma_foreign_key_check(NULL, 'main')
HAVING COUNT(*) > 0;
