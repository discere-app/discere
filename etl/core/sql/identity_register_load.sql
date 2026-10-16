-- =============================================================================
-- identity_register_load.sql — Register aus einem Vorgänger mit Register
--
-- Teil der Identitäts-Stage (core/identity.sh). Der Vorgänger ist als prev
-- angehängt und führt entity_source_keys: Seine IDs gelten unverändert weiter.
-- =============================================================================

INSERT INTO identity_register (source, entity_type, external_id, entity_id)
SELECT source, entity_type, external_id, entity_id
FROM prev.entity_source_keys;

INSERT INTO identity_prev_active_species (source, external_id)
SELECT source, external_id
FROM prev.entity_source_keys
WHERE entity_type = 'species' AND active = 1;

INSERT INTO identity_prev_ids (prev_id, entity_type, entity_id)
SELECT id, 'species', id FROM prev.species
UNION ALL SELECT id, 'genus',  id FROM prev.genera
UNION ALL SELECT id, 'family', id FROM prev.families
UNION ALL SELECT id, 'order',  id FROM prev.orders
UNION ALL SELECT id, 'class',  id FROM prev.classes;
