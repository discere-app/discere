-- =============================================================================
-- identity_summary.sql — Zusammenfassung der Identitäts-Stage für das Log
--
-- Teil der Identitäts-Stage (core/identity.sh), nach dem Commit. Eine Zeile
-- je Typ, dann Nachfolger, Register, Aliase und Bereinigungen.
-- =============================================================================

WITH types (entity_type, position) AS (
    VALUES ('species', 1), ('genus', 2), ('family', 3), ('order', 4), ('class', 5)
),
merged AS (
    SELECT entity_type, COUNT(*) AS n
    FROM (SELECT entity_type, entity_id FROM identity_id_map GROUP BY entity_id HAVING COUNT(*) > 1)
    GROUP BY entity_type
)
SELECT printf('%s: %d Entitäten — %d neue IDs, %d aus mehreren Quellen zusammengeführt, %d aus dem Vorgänger übernommen',
              t.entity_type,
              (SELECT COUNT(*) FROM identity_entities e WHERE e.entity_type = t.entity_type),
              (SELECT COUNT(*) FROM identity_new_ids n JOIN identity_rows r USING (provisional_id)
               WHERE r.entity_type = t.entity_type),
              COALESCE((SELECT n FROM merged m WHERE m.entity_type = t.entity_type), 0),
              (SELECT COUNT(*) FROM identity_carried c WHERE c.entity_type = t.entity_type))
FROM types t
ORDER BY t.position;

SELECT printf('Nachfolger: %d Arten ohne aktiven Schlüssel werden Alias ihres Nachfolgers, %d bleiben mehrdeutig, %d Aliase zurückgenommen',
              (SELECT COUNT(*) FROM identity_successors),
              (SELECT COUNT(*) FROM (SELECT old_id FROM identity_successor_candidates
                                     GROUP BY old_id HAVING COUNT(*) > 1)),
              (SELECT COUNT(*) FROM identity_successor_withdrawn));

SELECT printf('Arten des Vorgängers nicht mehr geliefert: %s %d von %d (%.1f %%, erlaubt %d %%%s)',
              source, lost, previous, 100.0 * lost / previous, limit_percent,
              CASE WHEN accepted = 1 THEN ', Rückgang angenommen' ELSE '' END)
FROM identity_source_loss
ORDER BY source;

SELECT printf('Register: %d Schlüssel aktiv, %d inaktiv',
              (SELECT COUNT(*) FROM entity_source_keys WHERE active = 1),
              (SELECT COUNT(*) FROM entity_source_keys WHERE active = 0));

SELECT printf('Aliase: %d (davon %d aus dem Vorgänger nachgeführt)',
              (SELECT COUNT(*) FROM entity_aliases),
              (SELECT COUNT(*) FROM identity_prev_aliases));

SELECT printf('%s: %d', label, n) FROM identity_counts WHERE n > 0 ORDER BY label;
