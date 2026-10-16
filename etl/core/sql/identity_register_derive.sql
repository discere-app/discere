-- =============================================================================
-- identity_register_derive.sql — Register aus einem Vorgänger ohne Register
--
-- Teil der Identitäts-Stage (core/identity.sh). Der Vorgänger ist als prev
-- angehängt und stammt aus der Zeit, in der IDs ihre Quelle trugen
-- (discere:<quelle>_<typ>:<external_id>). Jede seiner Entitäten ergibt einen
-- Schlüssel; jeder Schlüssel bekommt einmalig eine neue ID ohne Quelle, und
-- die alte wird zum Alias (identity_finish.sql).
--
-- Neue IDs zählen je Typ ab 1, in der Reihenfolge Quelle, dann external_id —
-- numerische Schlüssel nach ihrem Wert und vor den übrigen, die nach Text
-- sortiert werden (dieselbe Ordnung wie in identity_number.sql). Zwei Builds
-- mit demselben Vorgänger leiten so dasselbe Register ab.
-- =============================================================================

CREATE TEMP TABLE identity_prev_keys AS
SELECT 'species' AS entity_type, id AS prev_id, external_source AS source, external_id FROM prev.species
UNION ALL SELECT 'genus',  id, external_source, external_id FROM prev.genera
UNION ALL SELECT 'family', id, external_source, external_id FROM prev.families
UNION ALL SELECT 'order',  id, external_source, external_id FROM prev.orders
UNION ALL SELECT 'class',  id, external_source, external_id FROM prev.classes;

-- Die ID muss den Schlüssel nennen, den die Zeile führt; sonst ist das
-- Release nicht von der erwarteten Form und ein abgeleitetes Register falsch.
INSERT INTO identity_failure (message)
SELECT 'Vorgänger ohne Register: ' || COUNT(*) || ' IDs passen nicht zu ihrem Quellenschlüssel, z. B. '
       || MIN(prev_id)
FROM identity_prev_keys
WHERE prev_id != 'discere:' || source || '_' || entity_type || ':' || external_id
HAVING COUNT(*) > 0;

INSERT INTO identity_register (source, entity_type, external_id, entity_id)
SELECT
    source,
    entity_type,
    external_id,
    'discere:' || entity_type || ':' || ROW_NUMBER() OVER (
        PARTITION BY entity_type
        ORDER BY
            source,
            CASE WHEN external_id GLOB '[0-9]*' AND external_id NOT GLOB '*[^0-9]*' THEN 0 ELSE 1 END,
            CASE WHEN external_id GLOB '[0-9]*' AND external_id NOT GLOB '*[^0-9]*' THEN CAST(external_id AS INTEGER) END,
            external_id
    )
FROM identity_prev_keys;

INSERT INTO identity_prev_active_species (source, external_id)
SELECT external_source, external_id
FROM prev.species
WHERE status = 'active';

INSERT INTO identity_prev_ids (prev_id, entity_type, entity_id)
SELECT k.prev_id, k.entity_type, g.entity_id
FROM identity_prev_keys k
JOIN identity_register g
  ON g.source      = k.source
 AND g.entity_type = k.entity_type
 AND g.external_id = k.external_id;
