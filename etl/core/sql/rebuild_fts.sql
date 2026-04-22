-- FTS rebuild — läuft nach allen Plugins und nach dem Enrichment.
-- Synchronisiert alle FTS content tables mit den finalen Rohdaten.

-- Taxonomie-FTS (content tables — rebuild genügt)
INSERT INTO species_fts(species_fts)   VALUES('rebuild');
INSERT INTO genera_fts(genera_fts)     VALUES('rebuild');
INSERT INTO families_fts(families_fts) VALUES('rebuild');
INSERT INTO orders_fts(orders_fts)     VALUES('rebuild');
INSERT INTO classes_fts(classes_fts)   VALUES('rebuild');

-- common_names_fts: indexiert alle Trivialnamen (species + genus + family + order + class)
-- aus beiden Quellen (fishbase + sealifebase).
INSERT INTO common_names_fts(common_names_fts) VALUES('rebuild');
