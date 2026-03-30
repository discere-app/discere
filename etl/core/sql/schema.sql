PRAGMA foreign_keys = OFF;
-- ---------------------------------------------------------------------------
-- Taxonomie
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS classes (
    id              TEXT NOT NULL PRIMARY KEY CHECK(id GLOB 'discere:*_*:*'),
    external_id     TEXT NOT NULL,
    external_source TEXT NOT NULL,
    name            TEXT NOT NULL,
    common_name     TEXT,
    super_class     TEXT NOT NULL,
    UNIQUE (external_source, external_id)
);

CREATE TABLE IF NOT EXISTS orders (
    id              TEXT NOT NULL PRIMARY KEY CHECK(id GLOB 'discere:*_*:*'),
    external_id     TEXT NOT NULL,
    external_source TEXT NOT NULL,
    name            TEXT NOT NULL,
    common_name_en  TEXT,
    common_name_de  TEXT,
    common_name_fr  TEXT,
    common_name_es  TEXT,
    class           TEXT REFERENCES classes(id),
    UNIQUE (external_source, external_id)
);

CREATE TABLE IF NOT EXISTS families (
    id              TEXT NOT NULL PRIMARY KEY CHECK(id GLOB 'discere:*_*:*'),
    external_id     TEXT NOT NULL,
    external_source TEXT NOT NULL,
    name            TEXT NOT NULL,
    common_name_en  TEXT,
    common_name_de  TEXT,
    common_name_fr  TEXT,
    common_name_es  TEXT,
    "order"         TEXT REFERENCES orders(id),
    UNIQUE (external_source, external_id)
);

CREATE TABLE IF NOT EXISTS genera (
    id              TEXT NOT NULL PRIMARY KEY CHECK(id GLOB 'discere:*_*:*'),
    external_id     TEXT NOT NULL,
    external_source TEXT NOT NULL,
    name            TEXT NOT NULL,
    subfamily       TEXT,
    common_name     TEXT,
    family          TEXT REFERENCES families(id),
    UNIQUE (external_source, external_id)
);

CREATE TABLE IF NOT EXISTS species (
    id              TEXT NOT NULL PRIMARY KEY CHECK(id GLOB 'discere:*_*:*'),
    external_id     TEXT NOT NULL,
    external_source TEXT NOT NULL,
    name            TEXT NOT NULL,
    common_name_de  TEXT,
    common_name_en  TEXT,
    common_name_fr  TEXT,
    common_name_es  TEXT,
    max_length_cm   NUMERIC,  -- Max. length in cm (FishBase: Length / LTypeMaxM), meist Total Length
    -- genus ist nullable: deprecated Species können auf ein nicht mehr existierendes Genus zeigen
    genus           TEXT REFERENCES genera(id),
    -- Soft Delete: Species werden nie physisch gelöscht.
    -- Falls eine Art aus der Quelle verschwindet, wird sie auf 'deprecated'
    -- gesetzt. Damit bleiben Referenzen aus flashcard_stats gültig.
    status          TEXT NOT NULL DEFAULT 'active',
    deprecated_at   INTEGER,
    UNIQUE (external_source, external_id)
);

CREATE TABLE IF NOT EXISTS pictures (
    id          TEXT NOT NULL PRIMARY KEY CHECK(id GLOB 'discere:*_*:*'),
    species     TEXT REFERENCES species(id),
    picname     TEXT,
    picturetype TEXT,
    lifestage   TEXT,
    author      TEXT,
    copyright   TEXT,
    url         TEXT,
    origin      TEXT NOT NULL,
    -- Normierter Lizenz-Key aus dem Parquet (z.B. 'CC BY-NC 4.0').
    -- Nicht aus copyright (Freitext) abgeleitet — zu fehleranfällig.
    -- is_usable = 1: Bild darf in der App angezeigt werden.
    -- Nur CC BY* Lizenzen sind laut FishBase-Nutzungsbedingungen erlaubt.
    license_key TEXT,
    is_usable   INTEGER NOT NULL DEFAULT 0
);

-- ---------------------------------------------------------------------------
-- Sources & Licenses
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS sources (
    id              TEXT NOT NULL PRIMARY KEY,
    name            TEXT NOT NULL,
    category        TEXT NOT NULL,
    citation        TEXT NOT NULL,
    url             TEXT NOT NULL,
    favicon_url     TEXT,
    license_key     TEXT NOT NULL,
    license_url     TEXT,
    version         TEXT,
    display_order   INTEGER NOT NULL DEFAULT 100,
    last_imported   TEXT
);

-- ---------------------------------------------------------------------------
-- Metadata
-- Wird von jedem Plugin nach erfolgreichem Import befüllt.
-- Ermöglicht Nachvollziehbarkeit welche Quelle in welcher Version importiert wurde.
-- ---------------------------------------------------------------------------

-- Einfache Key-Value-Tabelle für Versionsinformationen der importierten Quellen.
-- Jede Quelle hat genau einen Eintrag — der Wert wird bei jedem Import überschrieben.
--
-- Beispielinhalt:
--   key            | value
--   fishbase       | v25.04
--   seacreatures   | v26.02
--
-- Flutter-Abfrage: SELECT value FROM metadata WHERE key = 'fishbase';
CREATE TABLE IF NOT EXISTS metadata (
    key   TEXT NOT NULL PRIMARY KEY,
    value TEXT NOT NULL
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

CREATE INDEX IF NOT EXISTS idx_species_genus    ON species(genus);
CREATE INDEX IF NOT EXISTS idx_species_name     ON species(name);
CREATE INDEX IF NOT EXISTS idx_genera_family    ON genera(family);
CREATE INDEX IF NOT EXISTS idx_families_order   ON families("order");
CREATE INDEX IF NOT EXISTS idx_orders_class     ON orders(class);
CREATE INDEX IF NOT EXISTS idx_species_status    ON species(status);
CREATE INDEX IF NOT EXISTS idx_pictures_species ON pictures(species);

-- ---------------------------------------------------------------------------
-- FTS (Full-Text Search)
-- Verwendet fts4 — fts5 ist im sqflite SQLite-Build auf iOS/Android
-- nicht zuverlässig verfügbar (nicht Teil des SQLite-Core).
-- fts4 content tables vermeiden duplizierte Daten.
-- Erfordert nach jedem Import ein rebuild:
--   INSERT INTO species_fts(species_fts) VALUES('rebuild');
-- Das übernimmt das jeweilige Plugin automatisch.
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS species_fts;
CREATE VIRTUAL TABLE species_fts USING fts4(
    content='species',
    id,
    name,
    common_name_en,
    common_name_de,
    common_name_fr,
    common_name_es,
    tokenize=unicode61
);

DROP TABLE IF EXISTS genera_fts;
CREATE VIRTUAL TABLE genera_fts USING fts4(
    content='genera',
    id,
    name,
    subfamily,
    common_name,
    tokenize=unicode61
);

DROP TABLE IF EXISTS families_fts;
CREATE VIRTUAL TABLE families_fts USING fts4(
    content='families',
    id,
    name,
    common_name_en,
    common_name_de,
    common_name_fr,
    common_name_es,
    tokenize=unicode61
);

DROP TABLE IF EXISTS orders_fts;
CREATE VIRTUAL TABLE orders_fts USING fts4(
    content='orders',
    id,
    name,
    common_name_en,
    common_name_de,
    common_name_fr,
    common_name_es,
    tokenize=unicode61
);

DROP TABLE IF EXISTS classes_fts;
CREATE VIRTUAL TABLE classes_fts USING fts4(
    content='classes',
    id,
    name,
    common_name,
    super_class,
    tokenize=unicode61
);

PRAGMA foreign_keys = ON;
