-- FTS rebuild — läuft nach allen Plugins.
-- Synchronisiert alle FTS content tables mit den finalen Rohdaten.
-- Muss nach dem letzten INSERT laufen, nicht pro Plugin.
INSERT INTO species_fts(species_fts)   VALUES('rebuild');
INSERT INTO genera_fts(genera_fts)     VALUES('rebuild');
INSERT INTO families_fts(families_fts) VALUES('rebuild');
INSERT INTO orders_fts(orders_fts)     VALUES('rebuild');
INSERT INTO classes_fts(classes_fts)   VALUES('rebuild');
