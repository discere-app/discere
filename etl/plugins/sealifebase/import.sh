#!/usr/bin/env bash
# =============================================================================
# import.sh — SeaLifeBase Plugin
#
# Lädt SeaLifeBase-Parquet-Dateien herunter (optional) und importiert sie
# in eine bestehende Discere-Datenbank.
#
# SeaLifeBase hat dieselbe Tabellenstruktur wie FishBase. SpecCodes sind
# datenbankspezifisch und unabhängig — Überschneidungen mit FishBase-Codes
# sind möglich aber kein Problem (external_source trennt die Quellen).
#
# Usage:
#   ./import.sh --db /path/to/discere.db --download
#   ./import.sh --db /path/to/discere.db --slb-dir ./cache/v26.04/parquet
#
# Flags:
#   --db <path>              Ziel-Datenbank (Pflichtfeld)
#   --download               Parquets von Source Cooperative herunterladen
#   --keep                   Heruntergeladene Parquets behalten
#   --version <v26.04>       SeaLifeBase-Version
#   --slb-dir <path>         Lokaler Parquet-Pfad (überschreibt --version)
#
# Umgebungsvariablen:
#   DB_PATH, SLB_VERSION, SLB_DIR
#
# Ohne expliziten lokalen Pfad werden Parquets standardmäßig relativ zum
# Plugin in ./cache/<version>/parquet gespeichert.
# =============================================================================

set -Eeuo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../core/plugin_api.sh
source "$PLUGIN_DIR/../../core/plugin_api.sh"
plugin_init "$PLUGIN_DIR"

SQL_DIR="$PLUGIN_SQL_DIR"
EXPORT_DIR="$(mktemp -d)"

DB_PATH="${DB_PATH:-}"
SLB_VERSION="${SLB_VERSION:-v26.04}"
SLB_DIR="${SLB_DIR:-}"
DOWNLOAD=false
KEEP_PARQUETS=false

SOURCE_COOP_BASE_URL="https://data.source.coop/cboettig/fishbase/slb"

REQUIRED_PARQUETS=(
    "classes" "orders" "families" "genera"
    "species" "synonyms" "comnames" "ecology" "country" "countrysub" "picturesmain"
)
# fieldguide_pic ist optional — nicht alle SLB-Versionen enthalten diese Tabelle
OPTIONAL_PARQUETS=("fieldguide_pic")

# ---------------------------------------------------------------------------
# Argumente
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)            DB_PATH="$2"; shift ;;
        --download)      DOWNLOAD=true;  _EXPLICIT_DOWNLOAD=true ;;
        --no-download)   DOWNLOAD=false; _EXPLICIT_DOWNLOAD=true ;;
        --keep)          KEEP_PARQUETS=true ;;
        --version)       SLB_VERSION="$2"; shift ;;
        --slb-dir)       SLB_DIR="$2"; shift ;;
        --help|-h)
            plugin_print_help_from_header "$0" 2 20
            exit 0
            ;;
        *) plugin_warn "Unbekanntes Argument: $1" ;;
    esac
    shift
done

SLB_DIR="${SLB_DIR:-$PLUGIN_DIR/cache/${SLB_VERSION}/parquet}"

if [[ "$DOWNLOAD" == false && "${_EXPLICIT_DOWNLOAD:-false}" == false ]]; then
    DOWNLOAD=true
fi

cleanup() {
    plugin_cleanup_dir "$EXPORT_DIR"
    if [[ "$DOWNLOAD" == true && "$KEEP_PARQUETS" == false && -d "$SLB_DIR" ]]; then
        plugin_log "Lösche Parquet-Verzeichnis: $SLB_DIR"
        rm -rf "$SLB_DIR"
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Validierung
# ---------------------------------------------------------------------------
check_deps() {
    plugin_require_db_path "$DB_PATH"
    plugin_require_command duckdb sqlite3
    [[ "$DOWNLOAD" == true ]] && plugin_require_command curl
}

check_parquet_files() {
    plugin_log "Prüfe Parquet-Dateien in: $SLB_DIR"
    local missing=()
    for name in "${REQUIRED_PARQUETS[@]}"; do
        [[ -f "$SLB_DIR/${name}.parquet" ]] || missing+=("${name}.parquet")
    done
    [[ ${#missing[@]} -eq 0 ]] || plugin_fail "Fehlende Parquets: ${missing[*]} — verwende --download"

    # Optionale Parquets loggen
    for name in "${OPTIONAL_PARQUETS[@]}"; do
        if [[ -f "$SLB_DIR/${name}.parquet" ]]; then
            plugin_log "  Optional vorhanden: ${name}.parquet"
        else
            plugin_log "  Optional nicht vorhanden (wird übersprungen): ${name}.parquet"
        fi
    done

    plugin_log "Pflicht-Parquets vorhanden (${SLB_VERSION})"
}

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
download_parquets() {
    local base_url="${SOURCE_COOP_BASE_URL}/${SLB_VERSION}/parquet"
    plugin_log "Download: $base_url"
    plugin_log "Ziel    : $SLB_DIR"
    mkdir -p "$SLB_DIR"

    local failed=()

    # Pflicht-Parquets
    for name in "${REQUIRED_PARQUETS[@]}"; do
        local dest="${SLB_DIR}/${name}.parquet"
        if [[ -f "$dest" ]]; then
            plugin_log "  ✓ ${name}.parquet (bereits vorhanden)"
            continue
        fi
        plugin_log "  ↓ ${name}.parquet"
        if ! curl --silent --show-error --location --fail --progress-bar \
                  --output "$dest" "${base_url}/${name}.parquet"; then
            rm -f "$dest"
            failed+=("$name")
        fi
    done

    [[ ${#failed[@]} -eq 0 ]] || plugin_fail "Download fehlgeschlagen: ${failed[*]}"

    # Optionale Parquets — Fehler werden ignoriert
    for name in "${OPTIONAL_PARQUETS[@]}"; do
        local dest="${SLB_DIR}/${name}.parquet"
        if [[ -f "$dest" ]]; then
            plugin_log "  ✓ ${name}.parquet (bereits vorhanden)"
            continue
        fi
        plugin_log "  ↓ ${name}.parquet (optional)"
        if ! curl --silent --show-error --location --fail --progress-bar \
                  --output "$dest" "${base_url}/${name}.parquet" 2>/dev/null; then
            rm -f "$dest"
            plugin_log "  ✗ ${name}.parquet nicht verfügbar — wird übersprungen"
        fi
    done

    plugin_log "Download abgeschlossen."
}

# ---------------------------------------------------------------------------
# ETL
# ---------------------------------------------------------------------------
clear_existing_data() {
    plugin_log "Räume bestehende ${PLUGIN_SOURCE}-Daten auf..."
    sqlite3 "$DB_PATH" << EOF
PRAGMA foreign_keys = OFF;
DELETE FROM pictures WHERE origin = '${PLUGIN_SOURCE}';
DELETE FROM taxonomy_distribution_regions WHERE source = '${PLUGIN_SOURCE}';
DELETE FROM taxonomy_traits WHERE source = '${PLUGIN_SOURCE}';
DELETE FROM species_scientific_names WHERE source = '${PLUGIN_SOURCE}';
DELETE FROM families WHERE external_source = '${PLUGIN_SOURCE}';
DELETE FROM orders   WHERE external_source = '${PLUGIN_SOURCE}';
DELETE FROM classes  WHERE external_source = '${PLUGIN_SOURCE}';
DELETE FROM sources  WHERE id = '${PLUGIN_SOURCE}';
-- common_names wird in import_to_sqlite per source gelöscht (nach Species-Import,
-- damit entity_ids aus tmp_species bereits vorhanden sind)
PRAGMA foreign_keys = ON;
EOF
}

export_to_csv() {
    plugin_log "Exportiere Parquets nach CSV..."
    local duck_db="${EXPORT_DIR}/tmp.duckdb"

    local sql
    sql=$(sed \
        -e "s|\${SLB_DIR}|${SLB_DIR}|g" \
        -e "s|\${EXPORT_DIR}|${EXPORT_DIR}|g" \
        "$SQL_DIR/export.sql")

    duckdb "$duck_db" -c "$sql" || plugin_fail "DuckDB-Export fehlgeschlagen."

    # fieldguide_pic separat — optional
    if [[ -f "$SLB_DIR/fieldguide_pic.parquet" ]]; then
        plugin_log "Exportiere fieldguide_pic..."
        local fieldguide_sql="
            CREATE OR REPLACE MACRO discere_uuid(source, entity, external_id) AS
                'discere:' || source || '_' || entity || ':' || CAST(external_id AS VARCHAR);

            CREATE TEMP TABLE t_species AS
                SELECT id, external_id FROM read_csv_auto('${EXPORT_DIR}/species.csv', HEADER = TRUE);

            COPY (
                SELECT
                    discere_uuid('${PLUGIN_SOURCE}', 'fieldguide', CAST(fg.speccode AS VARCHAR) || ':' || fg.picname)  AS id,
                    sp.id                                                                AS species,
                    fg.picname                                                           AS picname,
                    'field guide'                                                        AS picturetype,
                    'unsexed'                                                            AS lifestage,
                    NULL                                                                 AS author,
                    NULL                                                                 AS copyright,
                    CONCAT('https://sealifebase.org/images/species/', fg.picname)        AS url,
                    '${PLUGIN_SOURCE}'                                                   AS origin,
                    'ARR'                                                                AS license_key,
                    0                                                                    AS is_usable
                FROM read_parquet('${SLB_DIR}/fieldguide_pic.parquet') fg
                LEFT JOIN t_species sp ON sp.external_id = CAST(fg.speccode AS VARCHAR)
            ) TO '${EXPORT_DIR}/fieldguide.csv' (FORMAT csv, HEADER true);
        "
        duckdb "${EXPORT_DIR}/tmp_fg.duckdb" -c "$fieldguide_sql" \
            && plugin_log "fieldguide_pic exportiert." \
            || plugin_warn "fieldguide_pic-Export fehlgeschlagen — wird übersprungen."
    fi

    local csv_count
    csv_count=$(ls "$EXPORT_DIR"/*.csv 2>/dev/null | wc -l | tr -d ' ')
    [[ "$csv_count" -gt 0 ]] || plugin_fail "Keine CSVs generiert."
    plugin_log "$csv_count CSV-Dateien exportiert."
}

import_to_sqlite() {
    plugin_log "Importiere in Datenbank: $DB_PATH"
    local import_script="${EXPORT_DIR}/import.sql"

    # fieldguide.csv optional einbinden
    local fieldguide_import=""
    if [[ -f "${EXPORT_DIR}/fieldguide.csv" ]]; then
        fieldguide_import=".import --skip 1 ${EXPORT_DIR}/fieldguide.csv tmp_pictures_fg"
    fi

    cat > "$import_script" << EOF
PRAGMA foreign_keys = OFF;
.mode csv

CREATE TEMP TABLE tmp_classes (
    id TEXT,
    external_id TEXT,
    external_source TEXT,
    name TEXT,
    body_shape TEXT,
    super_class TEXT
);
CREATE TEMP TABLE tmp_orders (
    id TEXT,
    external_id TEXT,
    external_source TEXT,
    name TEXT,
    sister_order TEXT,
    class TEXT
);
CREATE TEMP TABLE tmp_families (
    id TEXT,
    external_id TEXT,
    external_source TEXT,
    name TEXT,
    body_shape TEXT,
    division TEXT,
    "order" TEXT
);
CREATE TEMP TABLE tmp_genera (
    id TEXT,
    external_id TEXT,
    external_source TEXT,
    name TEXT,
    subfamily TEXT,
    body_shape TEXT,
    family TEXT
);
CREATE TEMP TABLE tmp_species (
    id TEXT,
    external_id TEXT,
    external_source TEXT,
    name TEXT,
    max_length_cm NUMERIC,
    depth_min_m NUMERIC,
    depth_max_m NUMERIC,
    habitat TEXT,
    vulnerability REAL,
    dangerous_to_humans TEXT,
    fisheries_importance TEXT,
    longevity_years REAL,
    body_shape TEXT,
    trophic_level_food REAL,
    genus TEXT,
    status TEXT,
    deprecated_at INTEGER
);
CREATE TEMP TABLE tmp_pictures (
    id TEXT,
    species TEXT,
    picname TEXT,
    picturetype TEXT,
    lifestage TEXT,
    author TEXT,
    copyright TEXT,
    url TEXT,
    origin TEXT,
    license_key TEXT,
    is_usable INTEGER
);
CREATE TEMP TABLE tmp_taxonomy_traits (
    entity_id TEXT,
    entity_type TEXT,
    trait_key TEXT,
    trait_value_text TEXT,
    trait_value_num REAL,
    trait_value_bool INTEGER,
    source TEXT
);
CREATE TEMP TABLE tmp_common_names (
    entity_id TEXT,
    entity_type TEXT,
    language TEXT,
    country TEXT,
    name TEXT,
    source TEXT,
    rank INTEGER,
    is_preferred INTEGER,
    name_type TEXT
);
CREATE TEMP TABLE tmp_species_scientific_names (
    species_id TEXT,
    name TEXT,
    normalized_name TEXT,
    name_status TEXT,
    source TEXT,
    source_ref TEXT,
    is_preferred INTEGER,
    synonymy TEXT,
    combination TEXT,
    misspelling INTEGER
);
CREATE TEMP TABLE tmp_taxonomy_distribution_regions (
    entity_id TEXT,
    entity_type TEXT,
    source TEXT,
    region_scope TEXT,
    region_key TEXT,
    region_label TEXT,
    presence_status TEXT,
    establishment_status TEXT,
    threatened_flag INTEGER,
    abundance TEXT,
    importance TEXT,
    comment TEXT
);

.import --skip 1 ${EXPORT_DIR}/classes.csv  tmp_classes
.import --skip 1 ${EXPORT_DIR}/orders.csv   tmp_orders
.import --skip 1 ${EXPORT_DIR}/families.csv tmp_families
.import --skip 1 ${EXPORT_DIR}/genera.csv   tmp_genera
.import --skip 1 ${EXPORT_DIR}/species.csv  tmp_species
.import --skip 1 ${EXPORT_DIR}/common_names.csv tmp_common_names
.import --skip 1 ${EXPORT_DIR}/species_scientific_names.csv tmp_species_scientific_names
.import --skip 1 ${EXPORT_DIR}/pictures.csv tmp_pictures
.import --skip 1 ${EXPORT_DIR}/taxonomy_traits.csv tmp_taxonomy_traits
.import --skip 1 ${EXPORT_DIR}/taxonomy_distribution_regions.csv tmp_taxonomy_distribution_regions

INSERT OR IGNORE INTO classes (
    id, external_id, external_source, name, body_shape, super_class
) SELECT
    id, external_id, external_source, name, body_shape, super_class
FROM tmp_classes;
INSERT OR IGNORE INTO orders (
    id, external_id, external_source, name, sister_order, class
) SELECT
    id, external_id, external_source, name, sister_order, class
FROM tmp_orders;
INSERT OR IGNORE INTO families (
    id, external_id, external_source, name, body_shape, division, "order"
) SELECT
    id, external_id, external_source, name, body_shape, division, "order"
FROM tmp_families;

UPDATE classes
SET
    name        = tmp.name,
    body_shape  = tmp.body_shape,
    super_class = tmp.super_class
FROM tmp_classes tmp
WHERE classes.external_id     = tmp.external_id
  AND classes.external_source = tmp.external_source;

UPDATE orders
SET
    name         = tmp.name,
    sister_order = tmp.sister_order,
    class        = tmp.class
FROM tmp_orders tmp
WHERE orders.external_id     = tmp.external_id
  AND orders.external_source = tmp.external_source;

UPDATE families
SET
    name        = tmp.name,
    body_shape  = tmp.body_shape,
    division    = tmp.division,
    "order"     = tmp."order"
FROM tmp_families tmp
WHERE families.external_id     = tmp.external_id
  AND families.external_source = tmp.external_source;

INSERT OR IGNORE INTO genera (
    id, external_id, external_source, name, subfamily, body_shape, family
) SELECT
    id, external_id, external_source, name, subfamily, body_shape, family
FROM tmp_genera;
UPDATE genera
SET
    name      = tmp.name,
    subfamily = tmp.subfamily,
    body_shape = tmp.body_shape,
    family    = tmp.family
FROM tmp_genera tmp
WHERE genera.external_id     = tmp.external_id
  AND genera.external_source = tmp.external_source;

-- Species: Soft Delete Logik
-- 1. Neue Species einfügen
INSERT OR IGNORE INTO species (
    id, external_id, external_source, name,
    max_length_cm, depth_min_m, depth_max_m, habitat, vulnerability,
    dangerous_to_humans, fisheries_importance, longevity_years, body_shape,
    trophic_level_food, genus, status, deprecated_at
) SELECT
    id, external_id, external_source, name,
    max_length_cm, depth_min_m, depth_max_m, habitat, vulnerability,
    dangerous_to_humans, fisheries_importance, longevity_years, body_shape,
    trophic_level_food, genus, status, deprecated_at
FROM tmp_species;

-- 2. Bestehende Species aktualisieren
UPDATE species
SET
    name           = tmp.name,
    max_length_cm  = tmp.max_length_cm,
    depth_min_m    = tmp.depth_min_m,
    depth_max_m    = tmp.depth_max_m,
    habitat        = tmp.habitat,
    vulnerability  = tmp.vulnerability,
    dangerous_to_humans = tmp.dangerous_to_humans,
    fisheries_importance = tmp.fisheries_importance,
    longevity_years = tmp.longevity_years,
    body_shape     = tmp.body_shape,
    trophic_level_food = tmp.trophic_level_food,
    genus          = tmp.genus,
    status         = 'active',
    deprecated_at  = NULL
FROM tmp_species tmp
WHERE species.external_id     = tmp.external_id
  AND species.external_source = tmp.external_source;

-- 3. Species die im neuen Import fehlen → deprecated
UPDATE species
SET
    status        = 'deprecated',
    deprecated_at = CAST(strftime('%s', 'now') AS INTEGER)
WHERE external_source = '${PLUGIN_SOURCE}'
  AND status         != 'deprecated'
  AND external_id NOT IN (SELECT external_id FROM tmp_species);

-- Common Names: Bestehende Einträge dieser Quelle löschen und neu importieren
DELETE FROM common_names WHERE source = '${PLUGIN_SOURCE}';
INSERT OR IGNORE INTO common_names (
    entity_id, entity_type, language, country, name,
    source, rank, is_preferred, name_type
) SELECT
    entity_id, entity_type, language, NULLIF(country, ''), name,
    source, NULLIF(rank, ''), CAST(COALESCE(NULLIF(is_preferred, ''), '0') AS INTEGER), NULLIF(name_type, '')
FROM tmp_common_names
WHERE entity_id != '' AND name != '' AND language != '';

INSERT OR REPLACE INTO species_scientific_names (
    species_id, name, normalized_name, name_status, source,
    source_ref, is_preferred, synonymy, combination, misspelling
) SELECT
    species_id,
    name,
    normalized_name,
    name_status,
    source,
    NULLIF(source_ref, ''),
    CAST(COALESCE(NULLIF(is_preferred, ''), '0') AS INTEGER),
    NULLIF(synonymy, ''),
    NULLIF(combination, ''),
    CAST(COALESCE(NULLIF(misspelling, ''), '0') AS INTEGER)
FROM tmp_species_scientific_names
WHERE species_id != '' AND name != '' AND normalized_name != '';

INSERT OR IGNORE INTO pictures (
    id, species, picname, picturetype, lifestage, author,
    copyright, url, origin, license_key, is_usable
) SELECT
    id, species, picname, picturetype, lifestage, author,
    copyright, url, origin, license_key, is_usable
FROM tmp_pictures;
INSERT OR IGNORE INTO taxonomy_traits (
    entity_id, entity_type, trait_key, trait_value_text,
    trait_value_num, trait_value_bool, source
) SELECT
    entity_id, entity_type, trait_key, trait_value_text,
    trait_value_num, trait_value_bool, source
FROM tmp_taxonomy_traits;
INSERT OR IGNORE INTO taxonomy_distribution_regions (
    entity_id, entity_type, source, region_scope, region_key, region_label,
    presence_status, establishment_status, threatened_flag, abundance,
    importance, comment
) SELECT
    entity_id, entity_type, source, region_scope, region_key, region_label,
    presence_status, establishment_status, threatened_flag, abundance,
    importance, comment
FROM tmp_taxonomy_distribution_regions;

PRAGMA foreign_keys = ON;
EOF

    # fieldguide optional importieren
    if [[ -f "${EXPORT_DIR}/fieldguide.csv" ]]; then
        cat >> "$import_script" << EOF2
PRAGMA foreign_keys = OFF;
.mode csv
CREATE TEMP TABLE tmp_pictures_fg AS SELECT * FROM pictures WHERE 0;
.import --skip 1 ${EXPORT_DIR}/fieldguide.csv tmp_pictures_fg
INSERT OR IGNORE INTO pictures (
    id, species, picname, picturetype, lifestage, author,
    copyright, url, origin, license_key, is_usable
) SELECT
    id, species, picname, picturetype, lifestage, author,
    copyright, url, origin, license_key, is_usable
FROM tmp_pictures_fg;
PRAGMA foreign_keys = ON;
EOF2
    fi

    sqlite3 "$DB_PATH" < "$import_script" || plugin_fail "SQLite-Import fehlgeschlagen."
}

write_source_metadata() {
    plugin_write_source_metadata "$DB_PATH" "$SQL_DIR/source.sql" "$SLB_VERSION"
}


validate() {
    plugin_validate_min_count \
        "$DB_PATH" \
        "species" \
        "external_source='${PLUGIN_SOURCE}'" \
        50000 \
        "SeaLifeBase-Spezies"
    plugin_validate_min_count \
        "$DB_PATH" \
        "taxonomy_traits" \
        "source='${PLUGIN_SOURCE}'" \
        5000 \
        "SeaLifeBase-Taxonomy-Traits"
    plugin_validate_min_count \
        "$DB_PATH" \
        "taxonomy_distribution_regions" \
        "source='${PLUGIN_SOURCE}'" \
        200000 \
        "SeaLifeBase-Regionsdaten"
    local pictures_count
    pictures_count=$(sqlite3 "$DB_PATH" \
        "SELECT COUNT(*) FROM pictures WHERE origin='${PLUGIN_SOURCE}';")
    plugin_validate_source_entry_exists "$DB_PATH"
    plugin_log "SeaLifeBase-Daten OK: ${PLUGIN_SOURCE}, $pictures_count pictures."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
plugin_log "=== ${PLUGIN_NAME} Import ==="
plugin_log "Version : $SLB_VERSION"
plugin_log "Parquets: $SLB_DIR"
plugin_log "DB      : $DB_PATH"

check_deps
[[ "$DOWNLOAD" == true ]] && download_parquets
check_parquet_files
clear_existing_data
export_to_csv
import_to_sqlite
write_source_metadata
validate

plugin_log "=== ${PLUGIN_NAME} Import abgeschlossen ==="
