PRAGMA foreign_keys = OFF;
-- ---------------------------------------------------------------------------
-- Taxonomie
--
-- Entitäts-IDs haben die Form discere:<typ>:<nr> (species, genus, family,
-- order, class) und tragen keine Quelle. Quellen mit Entitäten schreiben
-- vorläufige IDs (discere:<quelle>_<typ>:<external_id>); die Identitäts-Stage
-- (core/identity.sh) ersetzt sie durch die endgültigen aus dem ID-Register,
-- bevor die ergänzenden Quellen laufen. Der CHECK lässt deshalb beide Formen zu.
--
-- is_placeholder (höhere Taxa): 1 für einen Rang-Platzhalter einer Quelle,
-- etwa die SeaLifeBase-Familie „Not assigned“. Er hält echte Arten in der
-- Kette und bleibt deshalb Entität; die App zeigt ihn als „nicht zugeordnet“,
-- bietet ihn nie als Distraktor an und findet ihn nicht in der Suche. Gesetzt
-- nach allen Quellen von core/placeholders.sh.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS classes (
    id              TEXT NOT NULL PRIMARY KEY CHECK(id GLOB 'discere:*:*'),
    external_id     TEXT NOT NULL,
    external_source TEXT NOT NULL,
    name            TEXT NOT NULL,
    body_shape      TEXT,
    super_class     TEXT NOT NULL,
    is_placeholder  INTEGER NOT NULL DEFAULT 0 CHECK (is_placeholder IN (0, 1)),
    UNIQUE (external_source, external_id)
);

CREATE TABLE IF NOT EXISTS orders (
    id              TEXT NOT NULL PRIMARY KEY CHECK(id GLOB 'discere:*:*'),
    external_id     TEXT NOT NULL,
    external_source TEXT NOT NULL,
    name            TEXT NOT NULL,
    sister_order    TEXT,
    class           TEXT REFERENCES classes(id),
    is_placeholder  INTEGER NOT NULL DEFAULT 0 CHECK (is_placeholder IN (0, 1)),
    UNIQUE (external_source, external_id)
);

CREATE TABLE IF NOT EXISTS families (
    id              TEXT NOT NULL PRIMARY KEY CHECK(id GLOB 'discere:*:*'),
    external_id     TEXT NOT NULL,
    external_source TEXT NOT NULL,
    name            TEXT NOT NULL,
    body_shape      TEXT,
    division        TEXT,
    "order"         TEXT REFERENCES orders(id),
    is_placeholder  INTEGER NOT NULL DEFAULT 0 CHECK (is_placeholder IN (0, 1)),
    UNIQUE (external_source, external_id)
);

CREATE TABLE IF NOT EXISTS genera (
    id              TEXT NOT NULL PRIMARY KEY CHECK(id GLOB 'discere:*:*'),
    external_id     TEXT NOT NULL,
    external_source TEXT NOT NULL,
    name            TEXT NOT NULL,
    subfamily       TEXT,
    body_shape      TEXT,
    family          TEXT REFERENCES families(id),
    is_placeholder  INTEGER NOT NULL DEFAULT 0 CHECK (is_placeholder IN (0, 1)),
    UNIQUE (external_source, external_id)
);

CREATE TABLE IF NOT EXISTS species (
    id              TEXT NOT NULL PRIMARY KEY CHECK(id GLOB 'discere:*:*'),
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
    -- genus ist nullable: nicht jede Quelle ordnet jede Art einer Gattung zu
    genus           TEXT REFERENCES genera(id),
    -- Soft Delete: Species werden nie physisch gelöscht.
    -- Liefert keine Quelle eine Art mehr, übernimmt die Identitäts-Stage sie
    -- aus dem vorigen Release als 'deprecated', samt Namen und Elternkette.
    -- Damit bleiben Referenzen aus flashcard_stats gültig.
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
-- Species Scientific Names
-- Wissenschaftliche Namen und Synonyme für Species-Lookups.
-- Enthält den kanonischen Namen aus species plus Alias-/Synonym-Einträge
-- aus den Quellsystemen (z.B. FishBase-Nomenklatur).
--
-- species_id       — verweist auf die kanonische Discere-Species-ID
-- name             — wissenschaftlicher Name in Anzeigeform
-- normalized_name  — normalisierte Lookup-Form (lowercase, Single-Space)
-- name_status      — z.B. 'valid', 'synonym', 'misapplied name'
-- source           — 'fishbase' | 'sealifebase'
-- source_ref       — optionale Referenz/RefNo aus der Quelle
-- is_preferred     — 1 für den kanonischen Namen, sonst 0
-- synonymy         — Rohklassifikation der Quelle (z.B. 'junior synonym')
-- combination      — Rohklassifikation der Quelle (z.B. 'new combination')
-- misspelling      — 0/1 laut Quelle
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS species_scientific_names (
    species_id       TEXT    NOT NULL REFERENCES species(id),
    name             TEXT    NOT NULL,
    normalized_name  TEXT    NOT NULL,
    name_status      TEXT    NOT NULL,
    source           TEXT    NOT NULL,
    source_ref       TEXT,
    is_preferred     INTEGER NOT NULL DEFAULT 0,
    synonymy         TEXT,
    combination      TEXT,
    misspelling      INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (species_id, normalized_name, source)
);

CREATE INDEX IF NOT EXISTS idx_species_scientific_names_lookup
    ON species_scientific_names(normalized_name, source);
CREATE INDEX IF NOT EXISTS idx_species_scientific_names_species
    ON species_scientific_names(species_id);

-- ---------------------------------------------------------------------------
-- Namen, die eine Quelle als Synonym mehr als einer Art fuehrt, ueber alle
-- Ebenen ihrer Synonymtabelle — auch ueber Zeilen, die nicht in
-- species_scientific_names stehen (dort nur Synonyme der Ebene Species).
-- species_name_lookup loest einen solchen Namen nicht ueber ein Synonym auf
-- (core/sql/rebuild_lookup.sql).
--
-- normalized_name  — wie species_scientific_names.normalized_name
-- source           — Quelle, die den Namen mehrdeutig fuehrt
-- species_count    — Zahl ihrer Arten mit diesem Namen als Synonym
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS ambiguous_scientific_names (
    normalized_name  TEXT    NOT NULL,
    source           TEXT    NOT NULL,
    species_count    INTEGER NOT NULL CHECK (species_count > 1),
    PRIMARY KEY (normalized_name, source)
) WITHOUT ROWID;

-- ---------------------------------------------------------------------------
-- Materialisierte Lookup-Tabelle fuer schnelle Name->Species-Aufloesung.
-- Pro normalized_name genau ein Eintrag, bereits disambiguiert nach:
--   1. is_preferred DESC
--   2. source-Ranking (fishbase > sealifebase)
--   3. species_id (deterministischer Tie-Breaker)
-- Wird im ETL nach allen Plugin-Imports befuellt (rebuild_lookup.sql).
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS species_name_lookup (
    normalized_name  TEXT NOT NULL PRIMARY KEY,
    species_id       TEXT NOT NULL REFERENCES species(id)
);

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

-- ---------------------------------------------------------------------------
-- Abgelehnte Zuordnungen (docs/datenquellen.md, Stamm und Kette bei der
-- iNaturalist-Zuordnung)
-- Jede Entität, der eine Quelle eine externe ID bewusst nicht zuordnet,
-- obwohl der Name ein Taxon trifft: Das Taxon passt nicht zur eigenen Kette,
-- ist nicht prüfbar oder nicht eindeutig. Die App sucht für sie nicht selbst
-- nach einer ID. Schlüssel wie in entity_external_ids (Art-ID bzw.
-- Namensschlüssel 'genus:megalomma'); eine Entität mit Zuordnung steht hier
-- nie. Eine Zeile je Grund.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS entity_external_id_rejections (
    entity_id    TEXT NOT NULL,
    entity_type  TEXT NOT NULL,
    provider     TEXT NOT NULL,
    reason       TEXT NOT NULL,
    PRIMARY KEY (entity_id, provider, reason)
);

-- ---------------------------------------------------------------------------
-- Erlaubte iNaturalist-Vorfahren je Klasse
-- Die iNaturalist-Taxon-IDs des Stamms (rank 'phylum') und der Klasse (rank
-- 'class'), die zur eigenen Klasse passen: gleicher Name oder gleichwertig
-- laut plugins/inaturalist/data/{phylum,class}_equivalents.csv. Die App
-- prüft damit einen Treffer ihrer Laufzeitsuche über dessen ancestor_ids,
-- ohne Namen. Eine Klasse mit Platzhalter- oder ohne Stamm hat keine
-- Stamm-Zeile, eine Platzhalter-Klasse keine Klassen-Zeile: Dort ist nichts
-- prüfbar.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS inat_allowed_ancestors (
    class_id       TEXT    NOT NULL REFERENCES classes(id),
    rank           TEXT    NOT NULL CHECK (rank IN ('phylum', 'class')),
    inat_taxon_id  INTEGER NOT NULL,
    PRIMARY KEY (class_id, rank, inat_taxon_id)
);

-- ---------------------------------------------------------------------------
-- ID-Register (docs/datenquellen.md, Identität)
-- Hält über alle Releases fest, welcher Quellenschlüssel zu welcher
-- Entitäts-ID gehört. Ein Build übernimmt es aus dem vorigen Release und
-- schreibt es fortgeschrieben in die neue DB (core/identity.sh).
--
-- source       — Quelle, die die Entität geliefert hat ('fishbase', ...)
-- entity_type  — species | genus | family | order | class
-- external_id  — Schlüssel der Entität in dieser Quelle (z.B. SpecCode)
-- entity_id    — Entitäts-ID (discere:<typ>:<nr>); bei einem inaktiven
--                Schlüssel einer Art, die einen Nachfolger bekommen hat, ihre
--                bisherige ID, die nun ein Alias auf den Nachfolger ist
-- active       — 1, wenn die Quelle den Schlüssel in diesem Build geliefert
--                hat; eine Entität ohne aktiven Schlüssel ist übernommen
--                (Arten: status = 'deprecated') oder, als Art mit
--                Nachfolger, ein Alias
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS entity_source_keys (
    source       TEXT    NOT NULL,
    entity_type  TEXT    NOT NULL CHECK (entity_type IN ('species', 'genus', 'family', 'order', 'class')),
    external_id  TEXT    NOT NULL,
    entity_id    TEXT    NOT NULL,
    active       INTEGER NOT NULL CHECK (active IN (0, 1)),
    PRIMARY KEY (source, entity_type, external_id)
) WITHOUT ROWID;

CREATE INDEX IF NOT EXISTS idx_entity_source_keys_entity
    ON entity_source_keys (entity_id);

-- ---------------------------------------------------------------------------
-- Elternstufen gegen den Code der Quelle (docs/datenquellen.md, Stamm einer
-- Familie gegen ihren Ordnungscode)
-- Ein Export, der eine Entität nach einer Regel unter eine andere
-- Elternstufe hängt, als ihr Code nennt, hält das hier fest. Die
-- Identitäts-Stage lässt einen Wechsel des Elternschlüssels gegen den
-- Vorgänger nur zu, wenn er hier steht (core/sql/identity_key_names.sql).
--
-- source              — Quelle der Entität
-- entity_type         — family
-- external_id         — Schlüssel der Entität in dieser Quelle
-- parent_external_id  — Schlüssel der Elternstufe in dieser Quelle, unter
--                       der die Entität hängt
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS source_parent_overrides (
    source              TEXT NOT NULL,
    entity_type         TEXT NOT NULL CHECK (entity_type IN ('family')),
    external_id         TEXT NOT NULL,
    parent_external_id  TEXT NOT NULL,
    PRIMARY KEY (source, entity_type, external_id)
) WITHOUT ROWID;

-- ---------------------------------------------------------------------------
-- Aliase (docs/datenquellen.md, Aliase führen Entitäten zusammen)
-- Jede ID eines früheren Releases, die keine Entität mehr bezeichnet, zeigt
-- hier direkt auf die gültige. Die App schreibt Verweise der Nutzer-DB beim
-- Wechsel der Referenz-DB darüber um. Keine alias_id ist zugleich
-- Entitäts-ID, jede entity_id existiert, Ketten gibt es nicht.
--
-- Beide Tabellen sind WITHOUT ROWID: Der Primärschlüssel ist fast ihr ganzer
-- Inhalt, und ohne rowid entfällt der zweite B-Baum, der ihn noch einmal
-- speichert.
-- ---------------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS entity_aliases (
    alias_id   TEXT NOT NULL PRIMARY KEY,
    entity_id  TEXT NOT NULL
) WITHOUT ROWID;

-- ---------------------------------------------------------------------------
-- Locale Place Mappings
-- Ordnet BCP-47-Locale-Codes ISO-3166-Ländercodes und iNaturalist-Place-IDs zu.
-- Wird zur Auflösung regionaler Trivialnamen verwendet (de-CH → de → en).
--
-- locale               — BCP-47 Locale:          'de-CH', 'en-AU'
-- language_code        — Basis-Sprache:           'de', 'en', 'fr', 'es'
-- country_code_alpha2  — ISO-3166 Alpha-2:        'CH', 'AU'  (entspricht Dart Locale.countryCode)
-- country_code_numeric — ISO-3166 Numeric 3-Stlg: '756', '036' (entspricht common_names.country)
-- inat_place_id        — iNaturalist Place-ID für regionale Namenssuche
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS locale_place_mappings (
    locale               TEXT    NOT NULL PRIMARY KEY,
    language_code        TEXT    NOT NULL,
    country_code_alpha2  TEXT    NOT NULL,
    country_code_numeric TEXT    NOT NULL,
    inat_place_id        INTEGER NOT NULL,
    country_name_en      TEXT                       -- Englischer Ländername (Debugging/Lesbarkeit)
);

CREATE INDEX IF NOT EXISTS idx_locale_place_mappings_lang
    ON locale_place_mappings(language_code);

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
--   fishbase       | v26.06
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
CREATE INDEX IF NOT EXISTS idx_species_genus_status_name ON species(genus, status, name);
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
