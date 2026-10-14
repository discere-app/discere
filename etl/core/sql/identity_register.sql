-- =============================================================================
-- identity_register.sql — Arbeitstabellen der Identitäts-Stage
--
-- Teil der Identitäts-Stage (core/identity.sh), läuft als erstes in ihrer
-- sqlite3-Sitzung. Legt die Tabellen an, die identity_register_load.sql bzw.
-- identity_register_derive.sql aus dem vorigen Release füllen. Ohne
-- Vorgänger (--initial) bleiben sie leer.
--
--   identity_register      — Register des Vorgängers: Schlüssel → ID
--   identity_prev_ids      — jede Entitäts-ID des Vorgängers → ihre ID in
--                            diesem Build (gleich, außer beim Ableiten aus
--                            einem Release ohne Register)
--   identity_prev_aliases  — Aliase des Vorgängers, wie er sie führt
--   identity_prev_species_names
--                          — gültiger Name (Gattung + Epitheton) jeder Art
--                            des Vorgängers, für die Nachfolger
--                            (identity_successor.sql)
--
-- identity_failure bricht die Sitzung ab: Jede eingefügte Zeile wird zur
-- Fehlermeldung (mit .bail on endet sqlite3 dann mit Exit-Code 1).
-- =============================================================================

CREATE TEMP TABLE identity_failure (message TEXT NOT NULL);
CREATE TEMP TRIGGER identity_failure_abort BEFORE INSERT ON identity_failure
BEGIN
    SELECT RAISE(ABORT, 'Identität: ' || NEW.message);
END;

CREATE TEMP TABLE identity_register (
    source       TEXT NOT NULL,
    entity_type  TEXT NOT NULL,
    external_id  TEXT NOT NULL,
    entity_id    TEXT NOT NULL,
    PRIMARY KEY (source, entity_type, external_id)
);

CREATE TEMP TABLE identity_prev_ids (
    prev_id      TEXT NOT NULL PRIMARY KEY,
    entity_type  TEXT NOT NULL,
    entity_id    TEXT NOT NULL
);

CREATE TEMP TABLE identity_prev_aliases (
    alias_id   TEXT NOT NULL PRIMARY KEY,
    entity_id  TEXT NOT NULL
);

CREATE TEMP TABLE identity_prev_species_names (
    prev_id  TEXT NOT NULL PRIMARY KEY,
    name     TEXT NOT NULL
);
