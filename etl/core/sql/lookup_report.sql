-- Build-Bericht zu species_name_lookup (core/lookup.sh), nach
-- core/sql/rebuild_lookup.sql in derselben Sitzung.
-- Kategorie ambiguous: ein Name aktiver Arten ohne Eintrag, weil er keine
-- Art eindeutig meint. Schlüssel ist der normalisierte Name, Detail jede
-- Art mit ihrem Status (preferred bzw. die Status ihrer Zeilen), dazu jede
-- Quelle, die ihn als Synonym mehrerer Arten führt (ambiguous_scientific_names).
-- Kategorie misapplied: ein Name, den aktive Arten nur als falsch angewandten
-- führen; Detail die Arten.
-- Zeilenumbrüche und Tabs in Namen (FishBase führt einzelne) werden zu
-- Leerzeichen, damit jeder Eintrag eine TSV-Zeile bleibt.

.mode tabs
.headers off
SELECT 'ambiguous',
       REPLACE(REPLACE(n.normalized_name, char(10), ' '), char(9), ' '),
       (SELECT REPLACE(REPLACE(MIN(ssn.name), char(10), ' '), char(9), ' ')
        FROM species_scientific_names ssn
        WHERE ssn.normalized_name = n.normalized_name),
       (SELECT GROUP_CONCAT(entry, ', ') FROM (
            SELECT c.species_id || ' ' || CASE WHEN c.is_preferred = 1 THEN 'preferred' ELSE (
                       SELECT GROUP_CONCAT(DISTINCT ssn.name_status) FROM species_scientific_names ssn
                       WHERE ssn.species_id = c.species_id AND ssn.normalized_name = c.normalized_name
                         AND ssn.name_status != 'misapplied name')
                   END AS entry
            FROM lookup_candidates c
            WHERE c.normalized_name = n.normalized_name
            ORDER BY c.species_id))
       || COALESCE((SELECT '; ' || GROUP_CONCAT(a.source || ': Synonym von ' || a.species_count || ' Arten', '; ')
                    FROM ambiguous_scientific_names a WHERE a.normalized_name = n.normalized_name), '')
FROM lookup_names n
WHERE NOT EXISTS (SELECT 1 FROM species_name_lookup l WHERE l.normalized_name = n.normalized_name)
UNION ALL
SELECT 'misapplied',
       REPLACE(REPLACE(ssn.normalized_name, char(10), ' '), char(9), ' '),
       REPLACE(REPLACE(MIN(ssn.name), char(10), ' '), char(9), ' '),
       GROUP_CONCAT(DISTINCT ssn.species_id)
FROM species_scientific_names ssn
JOIN species s ON s.id = ssn.species_id AND s.status = 'active'
WHERE NOT EXISTS (SELECT 1 FROM lookup_names n WHERE n.normalized_name = ssn.normalized_name)
GROUP BY ssn.normalized_name
ORDER BY 1, 2, 4;
