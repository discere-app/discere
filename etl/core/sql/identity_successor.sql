-- =============================================================================
-- identity_successor.sql — Nachfolger für Arten, die keine Quelle mehr liefert
--
-- Teil der Identitäts-Stage (core/identity.sh), nach identity_number.sql und
-- vor dem Umschreiben. Erwartet identity_carried, identity_id_map,
-- identity_prev_ids, identity_prev_aliases und identity_prev_species_names.
--
-- Weder FishBase noch SeaLifeBase führen ein Feld „ersetzt durch“. Nimmt eine
-- Quelle Art A in Art B auf oder benennt sie um, führt sie A's Namen danach
-- als Synonym unter B. Daraus folgt die Regel: Eine Art des Vorgängers ohne
-- aktiven Schlüssel (identity_carried) bekommt einen Nachfolger, wenn ihr
-- gültiger Name im Vorgänger (Gattung + Epitheton, normalisiert wie im
-- Abgleich) in diesem Build ein Name — gültig oder Synonym, nicht
-- 'misapplied name' — genau einer aktiven Art ist. Dann
--   - wird sie nicht übernommen, sondern ihre ID wird zum Alias auf den
--     Nachfolger: identity_prev_ids bildet sie auf ihn ab, und
--     identity_finish.sql führt so auch die Aliase des Vorgängers, die auf
--     sie zeigten, auf ihn nach;
--   - bleiben ihre Schlüssel im Register inaktiv auf ihrer bisherigen ID, die
--     nun ein Alias ist. Taucht ein solcher Schlüssel wieder auf, bekommt er
--     diese ID zurück, statt still in den Nachfolger aufzugehen; der Alias
--     wird dann zurückgenommen (identity_successor_withdrawn).
-- Mehrere Kandidaten: keine Wahl, die Art wird übernommen wie ohne Kandidat.
--
-- Build-Bericht: successor (alte ID, Name, Nachfolger), successor_ambiguous
-- (alte ID, Name, alle Kandidaten), successor_withdrawn (zurückgenommener
-- Alias). Bisherige Synonyme
-- der alten Art zählen nicht als Brücke, höhere Taxa bekommen nie einen
-- Nachfolger (Gattungshomonyme, siehe docs/datenquellen.md).
--
-- Kandidaten sind die Entitäten dieses Builds (identity_id_map), mit den
-- Namen aller ihrer Zeilen: Geht der Nachfolger hier aus zwei Quellen
-- hervor, zählen die Namen beider. Übernommene Arten sind keine Kandidaten,
-- deshalb entsteht keine Kette.
-- =============================================================================

CREATE TEMP TABLE identity_successor_names AS
SELECT DISTINCT m.entity_id, n.normalized_name
FROM identity_id_map m
JOIN species s                   ON s.id = m.provisional_id AND s.status = 'active'
JOIN species_scientific_names n  ON n.species_id = m.provisional_id
WHERE m.entity_type = 'species'
  AND n.name_status != 'misapplied name';
CREATE INDEX temp.idx_identity_successor_names ON identity_successor_names (normalized_name);

-- old_id ist die ID der alten Art in der Zählung dieses Builds — die, auf
-- die ihre Schlüssel im Register zeigen. Beim Ableiten des Registers ist das
-- eine andere als prev_id, die ID, die Nutzerdaten tragen.
CREATE TEMP TABLE identity_successor_candidates AS
SELECT c.entity_id AS old_id, MIN(c.prev_id) AS prev_id, MIN(p.name) AS name, n.entity_id AS successor_id
FROM identity_carried c
JOIN identity_prev_species_names p     ON p.prev_id = c.prev_id
JOIN identity_successor_names n        ON n.normalized_name = LOWER(TRIM(p.name))
WHERE c.entity_type = 'species'
GROUP BY c.entity_id, n.entity_id;

CREATE TEMP TABLE identity_successors (
    old_id        TEXT NOT NULL PRIMARY KEY,
    successor_id  TEXT NOT NULL
);
INSERT INTO identity_successors (old_id, successor_id)
SELECT old_id, MIN(successor_id)
FROM identity_successor_candidates
GROUP BY old_id
HAVING COUNT(*) = 1;

-- Für den Build-Bericht: Kandidat mit dem Namen der Zeile, die gilt.
CREATE TEMP TABLE identity_successor_labels AS
SELECT m.entity_id, m.entity_id || ' ' || COALESCE(g.name || ' ' || s.name, s.name) AS label
FROM identity_id_map m
JOIN species s      ON s.id = m.provisional_id
LEFT JOIN genera g  ON g.id = s.genus
WHERE m.is_winner = 1
  AND m.entity_id IN (SELECT successor_id FROM identity_successor_candidates);

INSERT INTO identity_report (category, key, name, detail)
SELECT 'successor', c.prev_id, c.name, 'Alias auf ' || l.label
FROM identity_successor_candidates c
JOIN identity_successors s        ON s.old_id = c.old_id
JOIN identity_successor_labels l  ON l.entity_id = c.successor_id;

INSERT INTO identity_report (category, key, name, detail)
SELECT
    'successor_ambiguous',
    MIN(c.prev_id),
    MIN(c.name),
    'mehrere Arten: ' || (
        SELECT group_concat(label, ', ')
        FROM (SELECT l.label FROM identity_successor_candidates o
              JOIN identity_successor_labels l ON l.entity_id = o.successor_id
              WHERE o.old_id = c.old_id ORDER BY o.successor_id))
FROM identity_successor_candidates c
GROUP BY c.old_id
HAVING COUNT(*) > 1;

UPDATE identity_prev_ids
SET entity_id = s.successor_id
FROM identity_successors s
WHERE identity_prev_ids.entity_id = s.old_id;

DELETE FROM identity_carried
WHERE entity_id IN (SELECT old_id FROM identity_successors);

-- Ein Alias des Vorgängers, dessen ID in diesem Build wieder eine Entität ist,
-- ohne dass sie im Vorgänger eine war: Der Schlüssel einer ersetzten Art ist
-- wieder aufgetaucht und hat seine ID zurückbekommen. Der Alias entfällt;
-- Nutzerdaten, die er schon auf den Nachfolger umgeschrieben hat, bleiben
-- dort. Eine ID, die im Vorgänger zugleich Entität und Alias war, ist kein
-- solcher Fall und bricht in identity_finish.sql ab.
CREATE TEMP TABLE identity_successor_withdrawn AS
SELECT a.alias_id, a.entity_id
FROM identity_prev_aliases a
WHERE a.alias_id IN (SELECT entity_id FROM identity_id_map)
  AND a.alias_id NOT IN (SELECT prev_id FROM identity_prev_ids);

INSERT INTO identity_report (category, key, name, detail)
SELECT
    'successor_withdrawn',
    w.alias_id,
    COALESCE(g.name || ' ' || s.name, s.name),
    'Schlüssel wieder geliefert, Alias auf ' || w.entity_id || ' zurückgenommen'
FROM identity_successor_withdrawn w
JOIN identity_id_map m  ON m.entity_id = w.alias_id AND m.is_winner = 1
JOIN species s          ON s.id = m.provisional_id
LEFT JOIN genera g      ON g.id = s.genus;
