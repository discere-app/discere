-- Rebuild species_name_lookup — laeuft nach allen Plugins, vor Validierung.
-- Ein Name bekommt nur einen Eintrag, wenn er genau eine aktive Art meint;
-- lieber kein Treffer als einer auf die falsche Art:
--   1. ist er bei genau einer aktiven Art bevorzugt (is_preferred), sie —
--      auch wenn andere Arten ihn als Synonym fuehren;
--   2. ist er nirgends bevorzugt, die einzige aktive Art, die ihn fuehrt —
--      sofern keine Quelle ihn als Synonym mehrerer Arten kennt
--      (ambiguous_scientific_names, auch ueber Synonymzeilen anderer Ebenen,
--      die nicht in species_scientific_names stehen);
--   3. sonst (bei mehreren bevorzugt, oder Synonym mehrerer Arten) keiner.
-- Falsch angewandte Namen (misapplied name) zaehlen nicht: Sie meinen ein
-- anderes Taxon (wie im Abgleich, core/sql/match.sql).
-- lookup_names bleibt fuer den Bericht (core/sql/lookup_report.sql) in der
-- Sitzung stehen.

DELETE FROM species_name_lookup;

DROP TABLE IF EXISTS temp.lookup_candidates;
CREATE TEMP TABLE lookup_candidates AS
SELECT ssn.normalized_name, ssn.species_id, MAX(ssn.is_preferred) AS is_preferred
FROM species_scientific_names ssn
JOIN species s ON s.id = ssn.species_id AND s.status = 'active'
WHERE ssn.name_status != 'misapplied name'
GROUP BY ssn.normalized_name, ssn.species_id;
CREATE INDEX temp.idx_lookup_candidates ON lookup_candidates (normalized_name, species_id);

DROP TABLE IF EXISTS temp.lookup_names;
CREATE TEMP TABLE lookup_names (
    normalized_name  TEXT PRIMARY KEY,
    species_count    INTEGER NOT NULL,
    preferred_count  INTEGER NOT NULL,
    source_ambiguous INTEGER NOT NULL
);
INSERT INTO lookup_names
SELECT normalized_name,
       COUNT(*)          AS species_count,
       SUM(is_preferred) AS preferred_count,
       EXISTS (SELECT 1 FROM ambiguous_scientific_names a
               WHERE a.normalized_name = c.normalized_name) AS source_ambiguous
FROM lookup_candidates c
GROUP BY normalized_name;

INSERT INTO species_name_lookup (normalized_name, species_id)
SELECT c.normalized_name, c.species_id
FROM lookup_candidates c
JOIN lookup_names n ON n.normalized_name = c.normalized_name
WHERE (n.preferred_count = 1 AND c.is_preferred = 1)
   OR (n.preferred_count = 0 AND n.species_count = 1 AND n.source_ambiguous = 0);
