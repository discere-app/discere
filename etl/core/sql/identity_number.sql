-- =============================================================================
-- identity_number.sql — Neue IDs vergeben, Zuordnung vorläufig → endgültig
--
-- Teil der Identitäts-Stage (core/identity.sh), nach dem Abgleich.
--
-- Neue IDs: discere:<typ>:<n>, n je Typ laufend ab der größten Nummer, die
-- das Register, die Aliase oder der Vorgänger schon verwenden — eine
-- Nummer wird nie zweimal vergeben, auch nicht die eines Alias. Reihenfolge
-- der neuen Entitäten: Quelle, dann external_id, numerische Schlüssel nach
-- ihrem Wert vor den übrigen nach Text (wie identity_register_derive.sql).
--
-- identity_id_map ordnet jeder vorläufigen ID ihre endgültige zu. Gehören
-- mehrere Zeilen zu einer Entität (eine Art aus zwei Quellen), ist genau eine
-- davon is_winner: die der Quelle mit dem kleinsten placement_priority. Ihre
-- Zeile bleibt, samt Einordnung und Kernspalten; die übrigen gehen in ihr auf
-- (identity.sh, Umschreiben).
-- =============================================================================

CREATE TEMP TABLE identity_used_numbers AS
WITH used_ids (id) AS (
    SELECT entity_id FROM identity_register
    UNION SELECT prev_id   FROM identity_prev_ids
    UNION SELECT entity_id FROM identity_prev_ids
    UNION SELECT alias_id  FROM identity_prev_aliases
    UNION SELECT entity_id FROM identity_prev_aliases
),
types (entity_type) AS (
    VALUES ('species'), ('genus'), ('family'), ('order'), ('class')
)
SELECT
    t.entity_type,
    MAX(CAST(substr(u.id, length('discere:' || t.entity_type || ':') + 1) AS INTEGER)) AS max_number
FROM types t
JOIN used_ids u
  ON u.id GLOB 'discere:' || t.entity_type || ':[0-9]*'
 AND substr(u.id, length('discere:' || t.entity_type || ':') + 1) NOT GLOB '*[^0-9]*'
GROUP BY t.entity_type;

CREATE TEMP TABLE identity_new_ids AS
SELECT
    r.provisional_id,
    'discere:' || r.entity_type || ':' || (
        COALESCE(u.max_number, 0) + ROW_NUMBER() OVER (
            PARTITION BY r.entity_type
            ORDER BY
                r.source,
                CASE WHEN r.external_id GLOB '[0-9]*' AND r.external_id NOT GLOB '*[^0-9]*' THEN 0 ELSE 1 END,
                CASE WHEN r.external_id GLOB '[0-9]*' AND r.external_id NOT GLOB '*[^0-9]*' THEN CAST(r.external_id AS INTEGER) END,
                r.external_id
        )
    ) AS entity_id
FROM identity_rows r
LEFT JOIN identity_used_numbers u ON u.entity_type = r.entity_type
WHERE r.assignment = 'new';
CREATE UNIQUE INDEX temp.idx_identity_new_ids ON identity_new_ids (provisional_id);

INSERT INTO identity_failure (message)
SELECT COUNT(*) || ' Zeilen ohne Zuordnung, z. B. ' || MIN(provisional_id)
FROM identity_rows
WHERE assignment IS NULL
HAVING COUNT(*) > 0;

-- anchor_id ist eine ID aus dem Register oder die vorläufige ID einer neuen
-- Zeile; im zweiten Fall gilt deren neue ID.
CREATE TEMP TABLE identity_id_map (
    provisional_id  TEXT    NOT NULL PRIMARY KEY,
    entity_type     TEXT    NOT NULL,
    entity_id       TEXT    NOT NULL,
    is_winner       INTEGER NOT NULL
);
INSERT INTO identity_id_map (provisional_id, entity_type, entity_id, is_winner)
SELECT
    provisional_id,
    entity_type,
    entity_id,
    ROW_NUMBER() OVER (
        PARTITION BY entity_id
        ORDER BY
            priority,
            source,
            CASE WHEN external_id GLOB '[0-9]*' AND external_id NOT GLOB '*[^0-9]*' THEN CAST(external_id AS INTEGER) END,
            external_id
    ) = 1
FROM (
    SELECT r.*, COALESCE(n.entity_id, r.anchor_id) AS entity_id
    FROM identity_rows r
    LEFT JOIN identity_new_ids n ON n.provisional_id = r.anchor_id
);
CREATE INDEX temp.idx_identity_id_map_entity ON identity_id_map (entity_id);

-- Abweichende Einordnung: Zeilen, die in einer Art aufgehen, deren Kette
-- Gattung › Familie › Ordnung › Klasse (nach Namen) eine andere ist als die
-- der gewichtigeren Quelle. Es gilt die der gewichtigeren; der Bericht nennt
-- beide.
CREATE TEMP TABLE identity_placement AS
SELECT
    s.id AS provisional_id,
    COALESCE(g.name, '?') || ' › ' || COALESCE(f.name, '?') || ' › '
        || COALESCE(o.name, '?') || ' › ' || COALESCE(c.name, '?') AS chain
FROM identity_id_map m
JOIN species s ON s.id = m.provisional_id
LEFT JOIN genera g   ON g.id = s.genus
LEFT JOIN families f ON f.id = g.family
LEFT JOIN orders o   ON o.id = f."order"
LEFT JOIN classes c  ON c.id = o.class
WHERE m.entity_id IN (SELECT entity_id FROM identity_id_map GROUP BY entity_id HAVING COUNT(*) > 1);

INSERT INTO identity_report (category, key, name, detail)
SELECT
    'placement',
    lr.source || ':species:' || lr.external_id,
    COALESCE(lg.name || ' ' || ls.name, ls.name),
    'gilt ' || wr.source || ': ' || wp.chain || '; ' || lr.source || ': ' || lp.chain
FROM identity_id_map loser
JOIN identity_id_map winner     ON winner.entity_id = loser.entity_id AND winner.is_winner = 1
JOIN identity_rows lr           ON lr.provisional_id = loser.provisional_id
JOIN identity_rows wr           ON wr.provisional_id = winner.provisional_id
JOIN identity_placement lp      ON lp.provisional_id = loser.provisional_id
JOIN identity_placement wp      ON wp.provisional_id = winner.provisional_id
JOIN species ls                 ON ls.id = loser.provisional_id
LEFT JOIN genera lg             ON lg.id = ls.genus
WHERE loser.is_winner = 0
  AND loser.entity_type = 'species'
  AND LOWER(lp.chain) != LOWER(wp.chain);

-- Lebenszyklus: Entitäten des Vorgängers, zu denen dieser Build keine Zeile
-- hat, deren Schlüssel also keine Quelle mehr geliefert hat. identity.sh
-- übernimmt ihre Zeilen samt wissenschaftlichen Namen und Volksnamen aus dem
-- Vorgänger, Arten als deprecated. Das gilt für jeden Typ; damit ist auch die
-- Elternkette jeder übernommenen Art vollständig.
CREATE TEMP TABLE identity_carried AS
SELECT prev_id, entity_type, entity_id
FROM identity_prev_ids
WHERE entity_id NOT IN (SELECT entity_id FROM identity_id_map);
CREATE UNIQUE INDEX temp.idx_identity_carried ON identity_carried (prev_id);
