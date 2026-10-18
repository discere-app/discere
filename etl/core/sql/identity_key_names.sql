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
--
-- Gleichnamige Taxa — etwa zwei Ordnungen „Not assigned“ verschiedener
-- Klassen — unterscheidet der Name nicht. Für Ordnungen und Familien zählt
-- deshalb auch der Elternschlüssel: Hängt eine Ordnung unter dem Schlüssel
-- einer anderen Klasse bzw. eine Familie unter dem einer anderen Ordnung als
-- im Vorgänger, bricht der Build ebenso ab. Verglichen werden Schlüssel der
-- Quelle, nicht IDs; fehlt die Elternstufe auf einer Seite, ist das kein
-- Wechsel des Taxons.
--
-- Hängt ein Export eine Familie nach einer Regel gezielt unter eine andere
-- Ordnung, als ihr Code nennt (SeaLifeBase: Stamm der Familie gegen die
-- Kette über ihren Ordnungscode), steht das in source_parent_overrides. Ein
-- Wechsel genau auf diesen Elternschlüssel ist kein Wechsel des Taxons: Der
-- Name der Familie bleibt (Prüfung oben), nur ihre Einordnung wird
-- berichtigt. Jeder andere Wechsel bricht weiter ab.
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

-- Elternschlüssel einer Ordnung (Klasse) bzw. Familie (Ordnung): in diesem
-- Build über die vorläufige ID, im Vorgänger über das Register.
INSERT INTO identity_failure (message)
SELECT COUNT(*) || ' Schlüssel von Ordnungen bzw. Familien hängen unter einem anderen Elternschlüssel als im Vorgänger (Typ Quelle:Schlüssel Name, Eltern Vorgänger → jetzt): '
       || group_concat(entity_type || ' ' || source || ':' || external_id || ' ' || name
                       || ', ' || prev_parent_key || ' → ' || parent_key, '; ')
FROM (
    SELECT r.entity_type, r.source, r.external_id, cur.name, cp.external_id AS parent_key,
           pg.external_id AS prev_parent_key
    FROM identity_rows r
    JOIN (
        SELECT 'order' AS entity_type, id, name, class AS parent FROM main.orders
        UNION ALL SELECT 'family', id, name, "order" FROM main.families
    ) cur ON cur.id = r.provisional_id
    JOIN identity_rows cp ON cp.provisional_id = cur.parent
    JOIN identity_prev_ids pi ON pi.entity_id = r.anchor_id AND pi.entity_type = r.entity_type
    JOIN (
        SELECT 'order' AS entity_type, id, class AS parent FROM prev.orders
        UNION ALL SELECT 'family', id, "order" FROM prev.families
    ) p ON p.id = pi.prev_id AND p.entity_type = r.entity_type
    JOIN identity_prev_ids ppi ON ppi.prev_id = p.parent
    JOIN identity_register pg
      ON pg.entity_id = ppi.entity_id AND pg.entity_type = ppi.entity_type AND pg.source = r.source
    WHERE r.assignment = 'known'
      AND cp.external_id <> pg.external_id
      AND NOT EXISTS (
          SELECT 1 FROM main.source_parent_overrides po
          WHERE po.source = r.source AND po.entity_type = r.entity_type
            AND po.external_id = r.external_id AND po.parent_external_id = cp.external_id
      )
    ORDER BY r.entity_type, r.source, r.external_id
)
HAVING COUNT(*) > 0;
