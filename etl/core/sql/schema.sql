PRAGMA foreign_keys = OFF;
-- ---------------------------------------------------------------------------
-- Taxonomie
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS classes (
    id              TEXT NOT NULL PRIMARY KEY CHECK(id GLOB 'discere:*_*:*'),
    external_id     TEXT NOT NULL,
    external_source TEXT NOT NULL,
    name            TEXT NOT NULL,
    body_shape      TEXT,
    super_class     TEXT NOT NULL,
    UNIQUE (external_source, external_id)
);

CREATE TABLE IF NOT EXISTS orders (
    id              TEXT NOT NULL PRIMARY KEY CHECK(id GLOB 'discere:*_*:*'),
    external_id     TEXT NOT NULL,
    external_source TEXT NOT NULL,
    name            TEXT NOT NULL,
    sister_order    TEXT,
    class           TEXT REFERENCES classes(id),
    UNIQUE (external_source, external_id)
);

CREATE TABLE IF NOT EXISTS families (
    id              TEXT NOT NULL PRIMARY KEY CHECK(id GLOB 'discere:*_*:*'),
    external_id     TEXT NOT NULL,
    external_source TEXT NOT NULL,
    name            TEXT NOT NULL,
    body_shape      TEXT,
    division        TEXT,
    "order"         TEXT REFERENCES orders(id),
    UNIQUE (external_source, external_id)
);

CREATE TABLE IF NOT EXISTS genera (
    id              TEXT NOT NULL PRIMARY KEY CHECK(id GLOB 'discere:*_*:*'),
    external_id     TEXT NOT NULL,
    external_source TEXT NOT NULL,
    name            TEXT NOT NULL,
    subfamily       TEXT,
    body_shape      TEXT,
    family          TEXT REFERENCES families(id),
    UNIQUE (external_source, external_id)
);

CREATE TABLE IF NOT EXISTS species (
    id              TEXT NOT NULL PRIMARY KEY CHECK(id GLOB 'discere:*_*:*'),
    external_id     TEXT NOT NULL,
    external_source TEXT NOT NULL,
    name            TEXT NOT NULL,
    max_length_cm   NUMERIC,  -- Max. length in cm (FishBase: Length / LTypeMaxM), meist Total Length
    depth_min_m     NUMERIC,  -- Min. depth in m (FishBase/SLB: DepthRangeShallow bzw. Common fallback)
    depth_max_m     NUMERIC,  -- Max. depth in m (FishBase/SLB: DepthRangeDeep bzw. Common fallback)
    habitat         TEXT,     -- Verdichtetes Habitat-Label aus ecology.parquet / DemersPelag-Fallback
    vulnerability   REAL,     -- FishBase/SLB Vulnerability score (0-100)
    dangerous_to_humans TEXT,
    fisheries_importance TEXT,
    longevity_years REAL,
    body_shape      TEXT,
    trophic_level_food REAL,
    -- genus ist nullable: deprecated Species können auf ein nicht mehr existierendes Genus zeigen
    genus           TEXT REFERENCES genera(id),
    -- Soft Delete: Species werden nie physisch gelöscht.
    -- Falls eine Art aus der Quelle verschwindet, wird sie auf 'deprecated'
    -- gesetzt. Damit bleiben Referenzen aus flashcard_stats gültig.
    status          TEXT NOT NULL DEFAULT 'active',
    deprecated_at   INTEGER,
    UNIQUE (external_source, external_id)
);

-- ---------------------------------------------------------------------------
-- Taxonomy Traits
-- Einfache, app-nahe Merkmale/Tags für taxonomische Entitäten.
-- entity_id verweist auf die generierte Discere-ID der Entität.
-- taxonomie-weit gedacht, initial vor allem für Species-Habitat-Associations.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS taxonomy_traits (
    entity_id         TEXT    NOT NULL,
    entity_type       TEXT    NOT NULL,
    trait_key         TEXT    NOT NULL,
    trait_value_text  TEXT,
    trait_value_num   REAL,
    trait_value_bool  INTEGER,
    source            TEXT    NOT NULL,
    PRIMARY KEY (entity_id, trait_key, source)
);

-- ---------------------------------------------------------------------------
-- Taxonomy Distribution Regions
-- Normalisierte mehrwertige Verbreitungsdaten (z.B. country/countrysub).
-- entity_id verweist auf die generierte Discere-ID der Entität.
-- In v1 wird die Tabelle nur für Species befüllt, bleibt aber generisch.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS taxonomy_distribution_regions (
    entity_id             TEXT    NOT NULL,
    entity_type           TEXT    NOT NULL,
    source                TEXT    NOT NULL,
    region_scope          TEXT    NOT NULL,
    region_key            TEXT    NOT NULL,
    region_label          TEXT    NOT NULL,
    presence_status       TEXT,
    establishment_status  TEXT,
    threatened_flag       INTEGER,
    abundance             TEXT,
    importance            TEXT,
    comment               TEXT,
    PRIMARY KEY (entity_id, source, region_scope, region_key)
);

-- ---------------------------------------------------------------------------
-- Common Names
-- Trivialnamen für alle taxonomischen Entitäten aus ETL-Quellen (FishBase, SLB).
-- Ersetzt die common_name_* Spalten in species, orders, families, genera, classes.
--
-- entity_id  — Discere-ID der Entität (z.B. 'discere:fishbase_species:12345')
-- entity_type — 'species' | 'genus' | 'family' | 'order' | 'class'
-- language   — BCP-47: 'de', 'en', 'fr', 'es', ...
-- country    — ISO-Numeric-Code (z.B. '276' = Deutschland), NULL = global
-- name       — der Trivialname
-- source     — 'fishbase' | 'sealifebase'
-- rank       — Rang innerhalb (entity, language, source, country), kleiner = besser
-- is_preferred — expliziter Preferred-Flag der Quelle (0/1)
-- name_type  — 'FAO' | 'FAO ctry' | 'AFS' | 'Vernacular' | 'Market' | 'Aquarium' | NULL
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS common_names (
    entity_id       TEXT    NOT NULL,
    entity_type     TEXT    NOT NULL,
    language        TEXT    NOT NULL,
    country         TEXT,
    name            TEXT    NOT NULL,
    source          TEXT    NOT NULL,
    rank            INTEGER,
    is_preferred    INTEGER NOT NULL DEFAULT 0,
    name_type       TEXT,
    UNIQUE (entity_id, name, language, source, country)
);

CREATE INDEX IF NOT EXISTS idx_common_names_lookup ON common_names (entity_id, language);
CREATE INDEX IF NOT EXISTS idx_common_names_source ON common_names (source);

-- ---------------------------------------------------------------------------
-- External Identifier Mapping (Enrichment)
-- Speichert generische Zuordnungen zwischen Discere-Entity-Keys und
-- IDs externer Systeme (z.B. iNaturalist, GBIF, WoRMS).
-- entity_id verweist absichtlich nicht per FK auf eine einzelne Tabelle,
-- da dieselbe Mapping-Tabelle Species und taxonomische Name-Keys
-- (z.B. 'genus:barbus', 'family:cyprinidae') aufnehmen soll.
-- Die ETL-Schritte stellen sicher, dass entity_id im jeweiligen Kontext
-- eindeutig und stabil ist.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS entity_external_ids (
    entity_id       TEXT    NOT NULL,
    entity_type     TEXT    NOT NULL,
    provider        TEXT    NOT NULL,
    external_id     TEXT    NOT NULL,
    last_synced_at  TEXT,
    metadata_json   TEXT,
    PRIMARY KEY (entity_id, provider),
    UNIQUE (provider, external_id)
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
    species_url_template TEXT,
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
CREATE INDEX IF NOT EXISTS idx_taxonomy_traits_entity
    ON taxonomy_traits(entity_id);
CREATE INDEX IF NOT EXISTS idx_taxonomy_traits_key
    ON taxonomy_traits(trait_key);
CREATE INDEX IF NOT EXISTS idx_taxonomy_distribution_regions_entity
    ON taxonomy_distribution_regions(entity_id);
CREATE INDEX IF NOT EXISTS idx_taxonomy_distribution_regions_scope
    ON taxonomy_distribution_regions(region_scope);
CREATE INDEX IF NOT EXISTS idx_taxonomy_distribution_regions_status
    ON taxonomy_distribution_regions(establishment_status, presence_status);

-- ---------------------------------------------------------------------------
-- FTS (Full-Text Search)
-- Verwendet fts4 — fts5 ist im sqflite SQLite-Build auf iOS/Android
-- nicht zuverlässig verfügbar (nicht Teil des SQLite-Core).
-- fts4 content tables vermeiden duplizierte Daten.
-- Erfordert nach jedem Import ein rebuild:
--   INSERT INTO species_fts(species_fts) VALUES('rebuild');
-- Das übernimmt das jeweilige Plugin automatisch.
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- FTS (Full-Text Search) — vorläufig nur wissenschaftliche Namen
-- Common-Name-Suche wird in einem späteren Schritt neu aufgebaut,
-- sobald die common_names-Tabelle vollständig befüllt ist.
-- ---------------------------------------------------------------------------

DROP TABLE IF EXISTS species_fts;
CREATE VIRTUAL TABLE species_fts USING fts4(
    content='species',
    id,
    name,
    tokenize=unicode61
);

DROP TABLE IF EXISTS common_names_fts;
CREATE VIRTUAL TABLE common_names_fts USING fts4(
    content='common_names',
    entity_id,
    entity_type,
    name,
    language,
    tokenize=unicode61
);

DROP TABLE IF EXISTS genera_fts;
CREATE VIRTUAL TABLE genera_fts USING fts4(
    content='genera',
    id,
    name,
    subfamily,
    tokenize=unicode61
);

DROP TABLE IF EXISTS families_fts;
CREATE VIRTUAL TABLE families_fts USING fts4(
    content='families',
    id,
    name,
    tokenize=unicode61
);

DROP TABLE IF EXISTS orders_fts;
CREATE VIRTUAL TABLE orders_fts USING fts4(
    content='orders',
    id,
    name,
    tokenize=unicode61
);

DROP TABLE IF EXISTS classes_fts;
CREATE VIRTUAL TABLE classes_fts USING fts4(
    content='classes',
    id,
    name,
    super_class,
    tokenize=unicode61
);

PRAGMA foreign_keys = ON;
