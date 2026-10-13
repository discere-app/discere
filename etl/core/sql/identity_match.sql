-- =============================================================================
-- identity_match.sql — Arten mit unbekanntem Schlüssel einer Quelle abgleichen
--
-- Teil der Identitäts-Stage (core/identity.sh). Läuft je Quelle einmal, in
-- der Reihenfolge ihrer placement_priority; identity_current_source nennt die
-- Quelle dieses Laufs.
--
-- Kandidaten sind die Arten anderer Quellen, die in diesem Build schon eine
-- Entität haben: über einen bekannten Schlüssel oder als neue oder
-- zusammengeführte Art einer Quelle, die vorher an der Reihe war. Eine
-- Entität, an der die Quelle schon eine Zeile hat, ist kein Kandidat — je
-- Quelle hat eine Entität höchstens einen Schlüssel. Abgeglichen wird mit
-- core/sql/match.sql über alle Namen der Kandidaten.
--
--   matched    — dieselbe Art: Die Zeile gehört zur getroffenen Entität, ihr
--                Schlüssel wird darauf eingetragen
--   none       — eine neue Art
--   ambiguous  — eine neue Art; der Build-Bericht nennt die Kandidaten
-- =============================================================================

DROP TABLE IF EXISTS temp.match_input;
CREATE TEMP TABLE match_input AS
SELECT
    r.provisional_id                     AS record_key,
    'species'                            AS rank,
    COALESCE(g.name || ' ' || s.name, s.name) AS name
FROM identity_rows r
JOIN species s ON s.id = r.provisional_id
LEFT JOIN genera g ON g.id = s.genus
WHERE r.entity_type = 'species'
  AND r.assignment IS NULL
  AND r.source = (SELECT source FROM identity_current_source);

DROP TABLE IF EXISTS temp.match_candidate_names;
CREATE TEMP TABLE match_candidate_names AS
SELECT
    'species'              AS rank,
    r.anchor_id            AS entity_id,
    n.normalized_name,
    MAX(n.is_preferred)    AS by_accepted_name
FROM identity_rows r
JOIN species_scientific_names n ON n.species_id = r.provisional_id
WHERE r.entity_type = 'species'
  AND r.anchor_id IS NOT NULL
  AND n.name_status != 'misapplied name'
  AND NOT EXISTS (
      SELECT 1 FROM identity_rows own
      WHERE own.entity_type = 'species'
        AND own.anchor_id   = r.anchor_id
        AND own.source      = (SELECT source FROM identity_current_source)
  )
GROUP BY r.anchor_id, n.normalized_name;

.read "${MATCH_SQL}"

UPDATE identity_rows
SET anchor_id = m.entity_id, assignment = 'matched'
FROM match_result m
WHERE m.record_key = identity_rows.provisional_id
  AND m.status = 'matched';

INSERT INTO identity_report (category, key, name, detail)
SELECT 'ambiguous', r.source || ':species:' || r.external_id, m.name, m.detail
FROM match_result m
JOIN identity_rows r ON r.provisional_id = m.record_key
WHERE m.status = 'ambiguous';

UPDATE identity_rows
SET anchor_id = provisional_id, assignment = 'new'
WHERE entity_type = 'species'
  AND assignment IS NULL
  AND source = (SELECT source FROM identity_current_source);
