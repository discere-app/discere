-- =============================================================================
-- match.sql — Abgleich von Datensätzen einer Quelle mit vorhandenen Entitäten
--
-- Läuft in der sqlite3-Sitzung des Aufrufers gegen die Referenz-DB (per
-- .read, meist über match_records in core/match.sh).
--
-- Eingabe:  TEMP TABLE match_input (record_key, rank, name)
--   record_key — Schlüssel des Datensatzes in der Quelle, je Eingabe eindeutig
--   rank       — species, genus, family, order oder class
--   name       — wissenschaftlicher Name, bei Arten Gattung + Epitheton
--
-- Ausgabe:  TEMP TABLE match_result
--   (record_key, rank, name, entity_id, status, matched_by, detail)
--   status     — matched, none oder ambiguous; entity_id nur bei matched
--   matched_by — name (akzeptierter Name, bei höheren Taxa der Name in der
--                Rangtabelle) oder synonym
--
-- Regeln (docs/datenquellen.md, Abgleich):
--   - Namen werden wie species_scientific_names.normalized_name verglichen:
--     klein geschrieben, ohne Leerzeichen am Rand.
--   - Arten: Kandidaten sind die Namen in species_scientific_names, akzeptierte
--     und Synonyme, nur aktiver Arten — nie species_name_lookup, das je Name
--     schon einen Gewinner gewählt hat und Mehrdeutigkeit verdecken würde.
--     Ausgenommen ist name_status 'misapplied name': Ein falsch angewandter
--     Name meint per Definition ein anderes Taxon und belegt deshalb keine
--     Identität. 'ambiguous synonym' bleibt Kandidat — er kann die Art meinen,
--     und trifft er zugleich eine andere, macht die Regel unten den Datensatz
--     ambiguous, statt zu wählen.
--   - Höhere Taxa: der Name in der Tabelle ihres Rangs.
--   - Trifft ein Datensatz mehrere Entitäten, ist er ambiguous; gewählt wird
--     nie.
--   - Treffen mehrere Datensätze dieselbe Entität — auch einer, der selbst
--     mehrdeutig ist —, behält sie nur der eine, der sie über ihren
--     akzeptierten Namen trifft und dabei eindeutig ist; die übrigen sind
--     ambiguous. Eine Entität hat damit höchstens einen Treffer.
--
-- Ein Abgleich über externe IDs, die beide Seiten kennen, käme als eigener
-- Kandidatenweg vor dem Namen hinzu (matched_by = external_id); keine Quelle
-- braucht ihn bisher.
-- =============================================================================

-- Ein Rang ohne Tabelle ist ein Fehler des Aufrufers und bricht ab, statt als
-- „none“ im Bericht zu landen.
CREATE TEMP TABLE match_records (
    record_key      TEXT NOT NULL PRIMARY KEY,
    rank            TEXT NOT NULL CHECK (rank IN ('species', 'genus', 'family', 'order', 'class')),
    name            TEXT NOT NULL,
    normalized_name TEXT NOT NULL
);
INSERT INTO match_records
SELECT record_key, rank, name, LOWER(TRIM(name)) FROM match_input;

CREATE TEMP TABLE match_rank_names AS
SELECT 'genus' AS rank, id AS entity_id, LOWER(TRIM(name)) AS normalized_name FROM genera
UNION ALL
SELECT 'family', id, LOWER(TRIM(name)) FROM families
UNION ALL
SELECT 'order', id, LOWER(TRIM(name)) FROM orders
UNION ALL
SELECT 'class', id, LOWER(TRIM(name)) FROM classes;
CREATE INDEX temp.idx_match_rank_names ON match_rank_names (rank, normalized_name);

-- Je Datensatz und Entität eine Zeile; by_accepted_name = 1, wenn einer der
-- getroffenen Namen der akzeptierte ist.
CREATE TEMP TABLE match_candidates AS
SELECT r.record_key, ssn.species_id AS entity_id, MAX(ssn.is_preferred) AS by_accepted_name
FROM match_records r
JOIN species_scientific_names ssn ON ssn.normalized_name = r.normalized_name
JOIN species s ON s.id = ssn.species_id AND s.status = 'active'
WHERE r.rank = 'species'
  AND ssn.name_status != 'misapplied name'
GROUP BY r.record_key, ssn.species_id
UNION ALL
SELECT r.record_key, n.entity_id, 1
FROM match_records r
JOIN match_rank_names n ON n.rank = r.rank AND n.normalized_name = r.normalized_name;
CREATE INDEX temp.idx_match_candidates ON match_candidates (record_key);
CREATE INDEX temp.idx_match_candidates_entity ON match_candidates (entity_id);

CREATE TEMP TABLE match_per_record AS
SELECT
    r.record_key,
    r.rank,
    r.name,
    COUNT(c.entity_id)    AS candidate_count,
    MIN(c.entity_id)      AS entity_id,
    MAX(c.by_accepted_name) AS by_accepted_name
FROM match_records r
LEFT JOIN match_candidates c ON c.record_key = r.record_key
GROUP BY r.record_key;

-- Wie viele Datensätze jede Entität treffen — auch solche, die selbst
-- mehrdeutig sind — und wie viele davon über ihren akzeptierten Namen.
CREATE TEMP TABLE match_entity_hits AS
SELECT
    entity_id,
    COUNT(*)              AS hits,
    SUM(by_accepted_name) AS accepted_hits
FROM match_candidates
GROUP BY entity_id;

-- Ein eindeutiger Treffer gilt, wenn kein anderer Datensatz dieselbe Entität
-- trifft, oder wenn er sie als einziger über ihren akzeptierten Namen trifft.
-- Ein Synonym-Treffer verliert also gegen jeden anderen Datensatz, der die
-- Entität erreicht: Führt die Quelle ihren akzeptierten Namen als eigenen
-- Datensatz, meint sie mit dem Synonym ein anderes Taxon.
CREATE TEMP TABLE match_status AS
SELECT
    p.*,
    CASE
        WHEN p.candidate_count = 0 THEN 'none'
        WHEN p.candidate_count > 1 THEN 'ambiguous'
        WHEN h.hits = 1 THEN 'matched'
        WHEN p.by_accepted_name = 1 AND h.accepted_hits = 1 THEN 'matched'
        ELSE 'ambiguous'
    END AS status
FROM match_per_record p
LEFT JOIN match_entity_hits h ON h.entity_id = p.entity_id AND p.candidate_count = 1;

CREATE TEMP TABLE match_result AS
SELECT
    s.record_key,
    s.rank,
    s.name,
    CASE WHEN s.status = 'matched' THEN s.entity_id END AS entity_id,
    s.status,
    CASE WHEN s.status = 'matched'
         THEN CASE WHEN s.by_accepted_name = 1 THEN 'name' ELSE 'synonym' END
    END AS matched_by,
    CASE
        WHEN s.candidate_count > 1 THEN
            'mehrere Entitäten: ' || (
                SELECT group_concat(entity_id, ', ')
                FROM (SELECT c.entity_id FROM match_candidates c
                      WHERE c.record_key = s.record_key ORDER BY c.entity_id))
        WHEN s.status = 'ambiguous' THEN
            'weitere Datensätze treffen ' || s.entity_id || ': ' || (
                SELECT group_concat(record_key, ', ')
                FROM (SELECT o.record_key FROM match_candidates o
                      WHERE o.entity_id = s.entity_id
                        AND o.record_key != s.record_key
                      ORDER BY o.record_key))
        ELSE ''
    END AS detail
FROM match_status s;
