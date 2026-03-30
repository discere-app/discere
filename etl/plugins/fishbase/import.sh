#!/usr/bin/env bash
# =============================================================================
# import.sh — FishBase Plugin
#
# Lädt FishBase-Parquet-Dateien herunter (optional) und importiert sie
# in eine bestehende Discere-Datenbank.
#
# Usage:
#   ./import.sh --db /path/to/discere.db --download
#   ./import.sh --db /path/to/discere.db --fishbase-dir ~/data/parquet
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
# Wird das Script ohne --db aufgerufen (direkt, nicht via build.sh),
# wird --download als Default gesetzt und Parquets werden nach dem Import gelöscht.
#
# Plugin-Konventionen:
#   - Kein CREATE TABLE — Schema ist Aufgabe von core/create_db.sh
#   - Logs auf stderr, kein stdout
#   - Eigenes Cleanup (temporäre Dateien + Parquets ohne --keep)
#   - Idempotent: bestehende Daten der Quelle werden vor dem Import gelöscht
# =============================================================================

set -Eeuo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="$PLUGIN_DIR/sql"
EXPORT_DIR="$(mktemp -d)"

DB_PATH="${DB_PATH:-}"
FISHBASE_VERSION="${FISHBASE_VERSION:-v25.04}"
FISHBASE_DIR="${FISHBASE_DIR:-}"
DOWNLOAD=false
KEEP_PARQUETS=false

HF_BASE_URL="https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/fb"

REQUIRED_PARQUETS=(
    "classes" "orders" "families" "genera"
    "species" "comnames" "picturesmain" "fieldguide_pic"
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
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "[WARN] [fishbase] Unbekanntes Argument: $1" >&2 ;;
    esac
    shift
done

FISHBASE_DIR="${FISHBASE_DIR:-$HOME/fishbase/data/fb/${FISHBASE_VERSION}/parquet}"

# Default: --download wenn kein --download/--no-download und kein lokaler Pfad gesetzt.
# Gilt nur wenn das Plugin direkt aufgerufen wird — build.sh übergibt --download explizit.
if [[ "$DOWNLOAD" == false && "${_EXPLICIT_DOWNLOAD:-false}" == false ]]; then
    DOWNLOAD=true
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[$(date '+%H:%M:%S')] [fishbase] $*" >&2; }
fail() { echo "[ERROR] [fishbase] $*" >&2; exit 1; }

cleanup() {
    rm -rf "$EXPORT_DIR"
    if [[ "$DOWNLOAD" == true && "$KEEP_PARQUETS" == false && -d "$FISHBASE_DIR" ]]; then
        log "Lösche Parquet-Verzeichnis: $FISHBASE_DIR"
        rm -rf "$FISHBASE_DIR"
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Validierung
# ---------------------------------------------------------------------------
check_deps() {
    [[ -n "$DB_PATH" ]] || fail "--db ist ein Pflichtfeld."
    [[ -f "$DB_PATH" ]] || fail "Datenbank nicht gefunden: $DB_PATH"
    command -v duckdb  >/dev/null 2>&1 || fail "duckdb nicht gefunden."
    command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 nicht gefunden."
    [[ "$DOWNLOAD" == true ]] && { command -v curl >/dev/null 2>&1 || fail "curl nicht gefunden."; }
}

check_parquet_files() {
    log "Prüfe Parquet-Dateien in: $FISHBASE_DIR"
    local missing=()
    for name in "${REQUIRED_PARQUETS[@]}"; do
        [[ -f "$FISHBASE_DIR/${name}.parquet" ]] || missing+=("${name}.parquet")
    done
    [[ ${#missing[@]} -eq 0 ]] || fail "Fehlende Parquets: ${missing[*]} — verwende --download"
    log "Alle Parquet-Dateien vorhanden (${FISHBASE_VERSION})"
}

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
download_parquets() {
    local base_url="${HF_BASE_URL}/${FISHBASE_VERSION}/parquet"
    log "Download: $base_url"
    log "Ziel    : $FISHBASE_DIR"
    mkdir -p "$FISHBASE_DIR"

    local failed=()
    for name in "${REQUIRED_PARQUETS[@]}"; do
        local dest="${FISHBASE_DIR}/${name}.parquet"
        if [[ -f "$dest" ]]; then
            log "  ✓ ${name}.parquet (bereits vorhanden)"
            continue
        fi
        log "  ↓ ${name}.parquet"
        if ! curl --silent --show-error --location --fail --progress-bar \
                  --output "$dest" "${base_url}/${name}.parquet"; then
            rm -f "$dest"
            failed+=("$name")
        fi
    done

    [[ ${#failed[@]} -eq 0 ]] || fail "Download fehlgeschlagen: ${failed[*]}"
    log "Download abgeschlossen."
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
    log "Räume bestehende FishBase-Daten auf..."
    sqlite3 "$DB_PATH" << 'EOF'
PRAGMA foreign_keys = OFF;
DELETE FROM pictures WHERE origin = 'fishbase';
DELETE FROM families WHERE external_source = 'fishbase';
DELETE FROM orders   WHERE external_source = 'fishbase';
DELETE FROM classes  WHERE external_source = 'fishbase';
DELETE FROM sources  WHERE id = 'fishbase';
PRAGMA foreign_keys = ON;
EOF
}

export_to_csv() {
    log "Exportiere Parquets nach CSV..."
    local duck_db="${EXPORT_DIR}/tmp.duckdb"

    local sql
    sql=$(sed \
        -e "s|\${FISHBASE_DIR}|${FISHBASE_DIR}|g" \
        -e "s|\${EXPORT_DIR}|${EXPORT_DIR}|g" \
        "$SQL_DIR/export.sql")

    duckdb "$duck_db" -c "$sql" || fail "DuckDB-Export fehlgeschlagen."

    local csv_count
    csv_count=$(ls "$EXPORT_DIR"/*.csv 2>/dev/null | wc -l | tr -d ' ')
    [[ "$csv_count" -gt 0 ]] || fail "Keine CSVs generiert."
    log "$csv_count CSV-Dateien exportiert."
}

import_to_sqlite() {
    log "Importiere in Datenbank: $DB_PATH"
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
WHERE external_source = 'fishbase'
  AND status         != 'deprecated'
  AND external_id NOT IN (SELECT external_id FROM tmp_species);

-- Pictures: INSERT OR IGNORE (neu importiert nach clear_existing_data)
INSERT OR IGNORE INTO pictures SELECT * FROM tmp_pictures;

PRAGMA foreign_keys = ON;
EOF
    sqlite3 "$DB_PATH" < "$import_script" || fail "SQLite-Import fehlgeschlagen."
}

# ---------------------------------------------------------------------------
# Source-Metadaten schreiben
#
# Liest sql/source.sql und ersetzt ${VERSION} und ${NOW}.
# Schreibt zusätzlich die Version in metadata für den Flutter Update-Mechanismus.
# ---------------------------------------------------------------------------
write_source_metadata() {
    local version="${FISHBASE_VERSION}"
    local now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    log "Schreibe Quellenangabe für 'fishbase'..."
    sed -e "s|\${VERSION}|$version|g" \
        -e "s|\${NOW}|$now|g" \
        "$SQL_DIR/source.sql" \
    | sqlite3 "$DB_PATH" \
    || fail "source.sql fehlgeschlagen."

    # metadata-Tabelle: wird vom Flutter Update-Mechanismus ausgelesen
    sqlite3 "$DB_PATH" \
        "INSERT INTO metadata (key, value) VALUES ('fishbase', '$version')
         ON CONFLICT (key) DO UPDATE SET value = excluded.value;" \
    || fail "metadata-Eintrag fehlgeschlagen."

    log "Quellenangabe geschrieben (version=$version)."
}

validate() {
    local species_count
    species_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM species WHERE external_source='fishbase';")
    [[ "$species_count" -ge 30000 ]] || fail "Zu wenige FishBase-Spezies: $species_count (erwartet >= 30000)"
    local pictures_count
    pictures_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM pictures WHERE origin='fishbase';")
    [[ "$pictures_count" -ge 10000 ]] || fail "Zu wenige FishBase-Bilder: $pictures_count (erwartet >= 10000)"
    local sources_count
    sources_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM sources WHERE id='fishbase';")
    [[ "$sources_count" -eq 1 ]] || fail "Kein sources-Eintrag für 'fishbase'."
    log "FishBase-Daten OK: $species_count species, $pictures_count pictures."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log "=== FishBase Import ==="
log "Version : $FISHBASE_VERSION"
log "Parquets: $FISHBASE_DIR"
log "DB      : $DB_PATH"

check_deps
[[ "$DOWNLOAD" == true ]] && download_parquets
check_parquet_files
clear_existing_data
export_to_csv
import_to_sqlite
write_source_metadata
validate

log "=== FishBase Import abgeschlossen ==="
