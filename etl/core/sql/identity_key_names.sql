-- =============================================================================
-- identity_key_names.sql — ein Schlüssel wechselt nie das Taxon
--
-- Teil der Identitäts-Stage (core/identity.sh), nach identity_assign.sql und
-- nur mit Vorgänger (Schema prev angehängt).
--
-- Höhere Taxa ordnet die Stage allein über ihren Schlüssel zu, ohne Abgleich
-- über den Namen (identity_assign.sql). Trägt ein bekannter Schlüssel einer
-- Gattung, Familie, Ordnung oder Klasse in diesem Build einen anderen Namen
-- als seine Entität im Vorgänger, bekäme diese ID ein anderes Taxon:
-- Register, Aliase und alles, was Nutzer unter der ID gespeichert haben,
-- zeigten dann auf etwas anderes. So entstünde es, wenn eine Quelle einen
-- Code mehrfach vergibt und der Export eine andere Zeile wählt als zuvor
-- (core/sql/source_codes.sql). Ob ein neuer Name dasselbe Taxon in anderer
-- Schreibweise oder ein anderes Taxon ist, kann der Build nicht entscheiden;
-- er bricht ab und nennt die Fälle.
--
-- Namen werden verglichen wie im Abgleich: ohne Leerzeichen am Rand, ohne
-- Rücksicht auf Groß- und Kleinschreibung. Arten sind ausgenommen: Ihr Name
-- in species ist das Epitheton, und dessen Schreibweise korrigieren die
-- Quellen unter gleichem Schlüssel regelmäßig.
-- =============================================================================

INSERT INTO identity_failure (message)
SELECT COUNT(*) || ' Schlüssel höherer Taxa nennen ein anderes Taxon als im Vorgänger (Typ Quelle:Schlüssel Vorgänger → jetzt): '
       || group_concat(entity_type || ' ' || source || ':' || external_id || ' ' || prev_name || ' → ' || name, '; ')
FROM (
    SELECT r.entity_type, r.source, r.external_id, cur.name, p.name AS prev_name
    FROM identity_rows r
    JOIN (
        SELECT 'genus' AS entity_type, id, name FROM main.genera
        UNION ALL SELECT 'family', id, name FROM main.families
        UNION ALL SELECT 'order',  id, name FROM main.orders
        UNION ALL SELECT 'class',  id, name FROM main.classes
    ) cur ON cur.id = r.provisional_id
    JOIN identity_prev_ids pi ON pi.entity_id = r.anchor_id AND pi.entity_type = r.entity_type
    JOIN (
        SELECT 'genus' AS entity_type, id, name FROM prev.genera
        UNION ALL SELECT 'family', id, name FROM prev.families
        UNION ALL SELECT 'order',  id, name FROM prev.orders
        UNION ALL SELECT 'class',  id, name FROM prev.classes
    ) p ON p.id = pi.prev_id AND p.entity_type = r.entity_type
    WHERE r.assignment = 'known'
      AND LOWER(TRIM(cur.name)) <> LOWER(TRIM(p.name))
    ORDER BY r.entity_type, r.source, r.external_id
)
HAVING COUNT(*) > 0;
