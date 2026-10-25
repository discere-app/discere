-- FTS rebuild — läuft nach allen Plugins und nach dem Enrichment.
-- Synchronisiert alle FTS-Tabellen mit den finalen Rohdaten.

-- Taxonomie-FTS (content tables — rebuild genügt)
INSERT INTO species_fts(species_fts)   VALUES('rebuild');
INSERT INTO genera_fts(genera_fts)     VALUES('rebuild');
INSERT INTO families_fts(families_fts) VALUES('rebuild');
INSERT INTO orders_fts(orders_fts)     VALUES('rebuild');
INSERT INTO classes_fts(classes_fts)   VALUES('rebuild');

-- species_synonyms_fts: je aktive Art und normalisierten Namen eine Zeile
-- für jeden Namen, den sie als Synonym führt — nicht falsch angewandt (meint
-- ein anderes Taxon) und nicht bei derselben Art bevorzugt (bei einer aus
-- zwei Quellen zusammengeführten Art kann der Name der einen Quelle Synonym
-- der anderen sein). Anders als species_name_lookup steht ein Synonym
-- mehrerer Arten bei jeder: Die Suche zeigt alle Arten, die es meinen kann.
-- Schreiben zwei Quellen den Namen verschieden, gilt MAX(name), damit jeder
-- Build dieselbe Zeile wählt; unterscheiden sie sich nur in Groß- und
-- Kleinschreibung, ist das die, die an der ersten Abweichung klein schreibt.
DELETE FROM species_synonyms_fts;
INSERT INTO species_synonyms_fts (species_id, name)
SELECT ssn.species_id, MAX(ssn.name)
FROM species_scientific_names ssn
JOIN species s ON s.id = ssn.species_id AND s.status = 'active'
WHERE ssn.is_preferred = 0
  AND ssn.name_status != 'misapplied name'
  AND NOT EXISTS (
      SELECT 1 FROM species_scientific_names p
      WHERE p.species_id = ssn.species_id
        AND p.normalized_name = ssn.normalized_name
        AND p.is_preferred = 1
  )
GROUP BY ssn.species_id, ssn.normalized_name;

-- common_names_fts: indexiert alle Trivialnamen (species + genus + family + order + class)
-- aus beiden Quellen (fishbase + sealifebase).
INSERT INTO common_names_fts(common_names_fts) VALUES('rebuild');
