-- FTS rebuild — läuft nach allen Plugins und nach dem Enrichment.
-- Synchronisiert alle FTS content tables mit den finalen Rohdaten.

-- Taxonomie-FTS (content tables — rebuild genügt)
INSERT INTO species_fts(species_fts)   VALUES('rebuild');
INSERT INTO genera_fts(genera_fts)     VALUES('rebuild');
INSERT INTO families_fts(families_fts) VALUES('rebuild');
INSERT INTO orders_fts(orders_fts)     VALUES('rebuild');
INSERT INTO classes_fts(classes_fts)   VALUES('rebuild');

-- species_names_fts: external content table (content="species_names")
-- rebuild liest alle Zeilen aus species_names neu ein.
INSERT INTO species_names_fts(species_names_fts) VALUES('rebuild');