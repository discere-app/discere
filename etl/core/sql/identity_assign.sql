-- =============================================================================
-- identity_assign.sql — Entitäten dieses Builds und bekannte Schlüssel
--
-- Teil der Identitäts-Stage (core/identity.sh), nach dem Register.
-- Erwartet identity_sources (source, priority): jede Quelle, die in diesem
-- Build Entitäten liefert, mit ihrer placement_priority.
--
-- identity_rows hält je Zeile der fünf Entitätstabellen ihren Schlüssel
-- (Quelle, Typ, external_id) und wohin sie gehört:
--   anchor_id   — die Entität, zu der die Zeile gehört: bei known die ID aus
--                 dem Register, bei new die eigene vorläufige ID, bei matched
--                 der anchor_id der getroffenen Zeile
--   assignment  — known (Schlüssel im Register), matched (Abgleich trifft die
--                 Art einer anderen Quelle, identity_match.sql) oder new
--
-- Höhere Taxa mit unbekanntem Schlüssel sind immer neu: Gleichnamige höhere
-- Taxa verschiedener Quellen können Homonyme sein (verschiedene Reiche), und
-- der Name allein entscheidet das nicht. Arten mit unbekanntem Schlüssel
-- gleicht identity_match.sql je Quelle ab.
-- =============================================================================

CREATE TEMP TABLE identity_rows (
    provisional_id  TEXT    NOT NULL PRIMARY KEY,
    entity_type     TEXT    NOT NULL,
    source          TEXT    NOT NULL,
    external_id     TEXT    NOT NULL,
    priority        INTEGER NOT NULL,
    anchor_id       TEXT,
    assignment      TEXT CHECK (assignment IN ('known', 'matched', 'new')),
    UNIQUE (source, entity_type, external_id)
);

INSERT INTO identity_rows (provisional_id, entity_type, source, external_id, priority)
SELECT e.id, e.entity_type, e.external_source, e.external_id, s.priority
FROM (
    SELECT 'species' AS entity_type, id, external_source, external_id FROM species
    UNION ALL SELECT 'genus',  id, external_source, external_id FROM genera
    UNION ALL SELECT 'family', id, external_source, external_id FROM families
    UNION ALL SELECT 'order',  id, external_source, external_id FROM orders
    UNION ALL SELECT 'class',  id, external_source, external_id FROM classes
) e
JOIN identity_sources s ON s.source = e.external_source;
CREATE INDEX temp.idx_identity_rows_anchor ON identity_rows (entity_type, anchor_id);

UPDATE identity_rows
SET anchor_id = g.entity_id, assignment = 'known'
FROM identity_register g
WHERE g.source      = identity_rows.source
  AND g.entity_type = identity_rows.entity_type
  AND g.external_id = identity_rows.external_id;

UPDATE identity_rows
SET anchor_id = provisional_id, assignment = 'new'
WHERE assignment IS NULL
  AND entity_type != 'species';

-- Abweichungen von der Einordnung und mehrdeutige Abgleiche, für den
-- Build-Bericht (Kategorie, Schlüssel, Name, Detail).
CREATE TEMP TABLE identity_report (
    category  TEXT NOT NULL,
    key       TEXT NOT NULL,
    name      TEXT NOT NULL,
    detail    TEXT NOT NULL
);

CREATE TEMP TABLE identity_current_source (source TEXT NOT NULL);
