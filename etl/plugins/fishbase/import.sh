#!/usr/bin/env bash
# =============================================================================
# import.sh — FishBase Plugin
#
# Lädt FishBase-Parquet-Dateien herunter (optional) und importiert sie
# in eine bestehende Discere-Datenbank.
#
# Usage:
#   ./import.sh --db /path/to/discere.db --download
#   ./import.sh --db /path/to/discere.db --fishbase-dir ./cache/v25.04/parquet
#
# Flags:
#   --db <path>              Ziel-Datenbank (Pflichtfeld)
#   --download               Parquets von HuggingFace herunterladen
#   --keep                   Heruntergeladene Parquets behalten
#   --version <v25.04>       FishBase-Version
#   --fishbase-dir <path>    Lokaler Parquet-Pfad (überschreibt --version)
#
# Umgebungsvariablen:
#   DB_PATH, FISHBASE_VERSION, FISHBASE_DIR
#
# Wird das Script ohne expliziten lokalen Pfad aufgerufen, werden Parquets
# standardmäßig relativ zum Plugin in ./cache/<version>/parquet gespeichert.
#
# Ohne --download/--no-download wird --download als Default gesetzt und
# heruntergeladene Parquets werden nach dem Import gelöscht, außer mit --keep.
#
# Plugin-Konventionen:
#   - Kein CREATE TABLE — Schema ist Aufgabe von core/create_db.sh
#   - Logs auf stderr, kein stdout
#   - Eigenes Cleanup (temporäre Dateien + Parquets ohne --keep)
#   - Idempotent: bestehende Daten der Quelle werden vor dem Import gelöscht
# =============================================================================

set -Eeuo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../core/plugin_api.sh
source "$PLUGIN_DIR/../../core/plugin_api.sh"
plugin_init "$PLUGIN_DIR"

SQL_DIR="$PLUGIN_SQL_DIR"
EXPORT_DIR="$(mktemp -d)"

DB_PATH="${DB_PATH:-}"
FISHBASE_VERSION="${FISHBASE_VERSION:-v25.04}"
FISHBASE_DIR="${FISHBASE_DIR:-}"
DOWNLOAD=false
KEEP_PARQUETS=false

HF_BASE_URL="https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb"

REQUIRED_PARQUETS=(
    "classes" "orders" "families" "genera"
    "species" "comnames" "ecology" "picturesmain" "fieldguide_pic"
)

# ---------------------------------------------------------------------------
# Argumente
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)            DB_PATH="$2"; shift ;;
        --download)      DOWNLOAD=true;  _EXPLICIT_DOWNLOAD=true ;;
        --no-download)   DOWNLOAD=false; _EXPLICIT_DOWNLOAD=true ;;
        --keep)          KEEP_PARQUETS=true ;;
        --version)       FISHBASE_VERSION="$2"; shift ;;
        --fishbase-dir)  FISHBASE_DIR="$2"; shift ;;
        --help|-h)
            plugin_print_help_from_header "$0" 2 20
            exit 0
            ;;
        *) plugin_warn "Unbekanntes Argument: $1" ;;
    esac
    shift
done

FISHBASE_DIR="${FISHBASE_DIR:-$PLUGIN_DIR/cache/${FISHBASE_VERSION}/parquet}"

# Default: --download wenn kein --download/--no-download und kein lokaler Pfad gesetzt.
# Gilt nur wenn das Plugin direkt aufgerufen wird — build.sh übergibt --download explizit.
if [[ "$DOWNLOAD" == false && "${_EXPLICIT_DOWNLOAD:-false}" == false ]]; then
    DOWNLOAD=true
fi

cleanup() {
    plugin_cleanup_dir "$EXPORT_DIR"
    if [[ "$DOWNLOAD" == true && "$KEEP_PARQUETS" == false && -d "$FISHBASE_DIR" ]]; then
        plugin_log "Lösche Parquet-Verzeichnis: $FISHBASE_DIR"
        rm -rf "$FISHBASE_DIR"
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
    plugin_log "Prüfe Parquet-Dateien in: $FISHBASE_DIR"
    local missing=()
    for name in "${REQUIRED_PARQUETS[@]}"; do
        [[ -f "$FISHBASE_DIR/${name}.parquet" ]] || missing+=("${name}.parquet")
    done
    [[ ${#missing[@]} -eq 0 ]] || plugin_fail "Fehlende Parquets: ${missing[*]} — verwende --download"
    plugin_log "Alle Parquet-Dateien vorhanden (${FISHBASE_VERSION})"
}

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
download_parquets() {
    local base_url="${HF_BASE_URL}/${FISHBASE_VERSION}/parquet"
    plugin_log "Download: $base_url"
    plugin_log "Ziel    : $FISHBASE_DIR"
    mkdir -p "$FISHBASE_DIR"

    local failed=()
    for name in "${REQUIRED_PARQUETS[@]}"; do
        local dest="${FISHBASE_DIR}/${name}.parquet"
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
    plugin_log "Download abgeschlossen."
}

# ---------------------------------------------------------------------------
# ETL
# ---------------------------------------------------------------------------
clear_existing_data() {
    # classes / orders / families: hart löschen und neu importieren.
    # genera: NICHT löschen — deprecated Species können noch darauf zeigen
    #         (species.genus FK). Stattdessen: INSERT OR IGNORE + UPDATE.
    # species: NICHT löschen — Soft Delete via status='deprecated'.
    # pictures: hart löschen und neu importieren (keine User-Referenzen).
    plugin_log "Räume bestehende ${PLUGIN_SOURCE}-Daten auf..."
    sqlite3 "$DB_PATH" << EOF
PRAGMA foreign_keys = OFF;
DELETE FROM pictures WHERE origin = '${PLUGIN_SOURCE}';
DELETE FROM families WHERE external_source = '${PLUGIN_SOURCE}';
DELETE FROM orders   WHERE external_source = '${PLUGIN_SOURCE}';
DELETE FROM classes  WHERE external_source = '${PLUGIN_SOURCE}';
DELETE FROM sources  WHERE id = '${PLUGIN_SOURCE}';
PRAGMA foreign_keys = ON;
EOF
}

export_to_csv() {
    plugin_log "Exportiere Parquets nach CSV..."
    local duck_db="${EXPORT_DIR}/tmp.duckdb"

    local sql
    sql=$(sed \
        -e "s|\${FISHBASE_DIR}|${FISHBASE_DIR}|g" \
        -e "s|\${EXPORT_DIR}|${EXPORT_DIR}|g" \
        "$SQL_DIR/export.sql")

    duckdb "$duck_db" -c "$sql" || plugin_fail "DuckDB-Export fehlgeschlagen."

    local csv_count
    csv_count=$(ls "$EXPORT_DIR"/*.csv 2>/dev/null | wc -l | tr -d ' ')
    [[ "$csv_count" -gt 0 ]] || plugin_fail "Keine CSVs generiert."
    plugin_log "$csv_count CSV-Dateien exportiert."
}

import_to_sqlite() {
    plugin_log "Importiere in Datenbank: $DB_PATH"
    local import_script="${EXPORT_DIR}/import.sql"
    cat > "$import_script" << EOF
PRAGMA foreign_keys = OFF;
.mode csv

-- Temp-Tabellen für den Import
CREATE TEMP TABLE tmp_classes  AS SELECT * FROM classes  WHERE 0;
CREATE TEMP TABLE tmp_orders   AS SELECT * FROM orders   WHERE 0;
CREATE TEMP TABLE tmp_families AS SELECT * FROM families WHERE 0;
CREATE TEMP TABLE tmp_genera   AS SELECT * FROM genera   WHERE 0;
CREATE TEMP TABLE tmp_species  AS SELECT * FROM species  WHERE 0;
CREATE TEMP TABLE tmp_pictures AS SELECT * FROM pictures WHERE 0;

.import --skip 1 ${EXPORT_DIR}/classes.csv  tmp_classes
.import --skip 1 ${EXPORT_DIR}/orders.csv   tmp_orders
.import --skip 1 ${EXPORT_DIR}/families.csv tmp_families
.import --skip 1 ${EXPORT_DIR}/genera.csv   tmp_genera
.import --skip 1 ${EXPORT_DIR}/species.csv  tmp_species
.import --skip 1 ${EXPORT_DIR}/pictures.csv tmp_pictures

-- classes / orders / families: frisch importiert (wurden in clear_existing_data gelöscht)
INSERT OR IGNORE INTO classes  SELECT * FROM tmp_classes;
INSERT OR IGNORE INTO orders   SELECT * FROM tmp_orders;
INSERT OR IGNORE INTO families SELECT * FROM tmp_families;

-- genera: INSERT OR IGNORE + UPDATE
INSERT OR IGNORE INTO genera SELECT * FROM tmp_genera;
UPDATE genera
SET
    name        = tmp.name,
    subfamily   = tmp.subfamily,
    common_name = tmp.common_name,
    family      = tmp.family
FROM tmp_genera tmp
WHERE genera.external_id     = tmp.external_id
  AND genera.external_source = tmp.external_source;

-- Species: Soft Delete Logik
-- 1. Neue Species einfügen
INSERT OR IGNORE INTO species SELECT * FROM tmp_species;

-- 2. Bestehende Species aktualisieren
UPDATE species
SET
    name           = tmp.name,
    common_name_de = tmp.common_name_de,
    common_name_en = tmp.common_name_en,
    common_name_fr = tmp.common_name_fr,
    common_name_es = tmp.common_name_es,
    max_length_cm  = tmp.max_length_cm,
    depth_min_m    = tmp.depth_min_m,
    depth_max_m    = tmp.depth_max_m,
    habitat        = tmp.habitat,
    vulnerability  = tmp.vulnerability,
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

-- Pictures: INSERT OR IGNORE (neu importiert nach clear_existing_data)
INSERT OR IGNORE INTO pictures SELECT * FROM tmp_pictures;

PRAGMA foreign_keys = ON;
EOF
    sqlite3 "$DB_PATH" < "$import_script" || plugin_fail "SQLite-Import fehlgeschlagen."
}

# ---------------------------------------------------------------------------
# Source-Metadaten schreiben
#
# Liest sql/source.sql und ersetzt ${VERSION} und ${NOW}.
# Schreibt zusätzlich die Version in metadata für den Flutter Update-Mechanismus.
# ---------------------------------------------------------------------------
write_source_metadata() {
    plugin_write_source_metadata "$DB_PATH" "$SQL_DIR/source.sql" "$FISHBASE_VERSION"
}

validate() {
    plugin_validate_min_count \
        "$DB_PATH" \
        "species" \
        "external_source='${PLUGIN_SOURCE}'" \
        30000 \
        "FishBase-Spezies"
    local pictures_count
    pictures_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM pictures WHERE origin='${PLUGIN_SOURCE}';")
    [[ "$pictures_count" -ge 10000 ]] || plugin_fail "Zu wenige FishBase-Bilder: $pictures_count (erwartet >= 10000)"
    plugin_validate_source_entry_exists "$DB_PATH"
    plugin_log "FishBase-Daten OK: ${PLUGIN_SOURCE}, $pictures_count pictures."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
plugin_log "=== ${PLUGIN_NAME} Import ==="
plugin_log "Version : $FISHBASE_VERSION"
plugin_log "Parquets: $FISHBASE_DIR"
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
