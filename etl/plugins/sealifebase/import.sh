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
#   ./import.sh --db /path/to/discere.db --slb-dir ~/data/slb/parquet
#
# Flags:
#   --db <path>              Ziel-Datenbank (Pflichtfeld)
#   --download               Parquets von HuggingFace herunterladen
#   --keep                   Heruntergeladene Parquets behalten
#   --version <v25.04>       SeaLifeBase-Version
#   --slb-dir <path>         Lokaler Parquet-Pfad (überschreibt --version)
#
# Umgebungsvariablen:
#   DB_PATH, SLB_VERSION, SLB_DIR
# =============================================================================

set -Eeuo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="$PLUGIN_DIR/sql"
EXPORT_DIR="$(mktemp -d)"

DB_PATH="${DB_PATH:-}"
SLB_VERSION="${SLB_VERSION:-v25.04}"
SLB_DIR="${SLB_DIR:-}"
DOWNLOAD=false
KEEP_PARQUETS=false

HF_BASE_URL="https://huggingface.co/datasets/cboettig/fishbase/resolve/main/data/slb"

REQUIRED_PARQUETS=(
    "classes" "orders" "families" "genera"
    "species" "comnames" "picturesmain"
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
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "[WARN] [sealifebase] Unbekanntes Argument: $1" >&2 ;;
    esac
    shift
done

SLB_DIR="${SLB_DIR:-$HOME/sealifebase/data/slb/${SLB_VERSION}/parquet}"

if [[ "$DOWNLOAD" == false && "${_EXPLICIT_DOWNLOAD:-false}" == false ]]; then
    DOWNLOAD=true
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[$(date '+%H:%M:%S')] [sealifebase] $*" >&2; }
fail() { echo "[ERROR] [sealifebase] $*" >&2; exit 1; }

cleanup() {
    rm -rf "$EXPORT_DIR"
    if [[ "$DOWNLOAD" == true && "$KEEP_PARQUETS" == false && -d "$SLB_DIR" ]]; then
        log "Lösche Parquet-Verzeichnis: $SLB_DIR"
        rm -rf "$SLB_DIR"
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
    log "Prüfe Parquet-Dateien in: $SLB_DIR"
    local missing=()
    for name in "${REQUIRED_PARQUETS[@]}"; do
        [[ -f "$SLB_DIR/${name}.parquet" ]] || missing+=("${name}.parquet")
    done
    [[ ${#missing[@]} -eq 0 ]] || fail "Fehlende Parquets: ${missing[*]} — verwende --download"

    # Optionale Parquets loggen
    for name in "${OPTIONAL_PARQUETS[@]}"; do
        if [[ -f "$SLB_DIR/${name}.parquet" ]]; then
            log "  Optional vorhanden: ${name}.parquet"
        else
            log "  Optional nicht vorhanden (wird übersprungen): ${name}.parquet"
        fi
    done

    log "Pflicht-Parquets vorhanden (${SLB_VERSION})"
}

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
download_parquets() {
    local base_url="${HF_BASE_URL}/${SLB_VERSION}/parquet"
    log "Download: $base_url"
    log "Ziel    : $SLB_DIR"
    mkdir -p "$SLB_DIR"

    local failed=()

    # Pflicht-Parquets
    for name in "${REQUIRED_PARQUETS[@]}"; do
        local dest="${SLB_DIR}/${name}.parquet"
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

    # Optionale Parquets — Fehler werden ignoriert
    for name in "${OPTIONAL_PARQUETS[@]}"; do
        local dest="${SLB_DIR}/${name}.parquet"
        if [[ -f "$dest" ]]; then
            log "  ✓ ${name}.parquet (bereits vorhanden)"
            continue
        fi
        log "  ↓ ${name}.parquet (optional)"
        if ! curl --silent --show-error --location --fail --progress-bar \
                  --output "$dest" "${base_url}/${name}.parquet" 2>/dev/null; then
            rm -f "$dest"
            log "  ✗ ${name}.parquet nicht verfügbar — wird übersprungen"
        fi
    done

    log "Download abgeschlossen."
}

# ---------------------------------------------------------------------------
# ETL
# ---------------------------------------------------------------------------
clear_existing_data() {
    log "Räume bestehende SeaLifeBase-Daten auf..."
    sqlite3 "$DB_PATH" << 'EOF'
PRAGMA foreign_keys = OFF;
DELETE FROM pictures WHERE origin = 'sealifebase';
DELETE FROM families WHERE external_source = 'sealifebase';
DELETE FROM orders   WHERE external_source = 'sealifebase';
DELETE FROM classes  WHERE external_source = 'sealifebase';
DELETE FROM metadata WHERE key = 'sealifebase';
PRAGMA foreign_keys = ON;
EOF
}

export_to_csv() {
    log "Exportiere Parquets nach CSV..."
    local duck_db="${EXPORT_DIR}/tmp.duckdb"

    local sql
    sql=$(sed \
        -e "s|\${SLB_DIR}|${SLB_DIR}|g" \
        -e "s|\${EXPORT_DIR}|${EXPORT_DIR}|g" \
        "$SQL_DIR/export.sql")

    duckdb "$duck_db" -c "$sql" || fail "DuckDB-Export fehlgeschlagen."

    # fieldguide_pic separat — optional
    if [[ -f "$SLB_DIR/fieldguide_pic.parquet" ]]; then
        log "Exportiere fieldguide_pic..."
        local fieldguide_sql="
            CREATE OR REPLACE MACRO discere_uuid(source, entity, external_id) AS
                'discere:' || source || '_' || entity || ':' || CAST(external_id AS VARCHAR);

            CREATE TEMP TABLE t_species AS
                SELECT id, external_id FROM read_parquet('${EXPORT_DIR}/species.csv');

            COPY (
                SELECT
                    discere_uuid('sealifebase', 'fieldguide', CAST(fg.speccode AS VARCHAR) || ':' || fg.picname)  AS id,
                    sp.id                                                                AS species,
                    fg.picname                                                           AS picname,
                    'field guide'                                                        AS picturetype,
                    'unsexed'                                                            AS lifestage,
                    NULL                                                                 AS author,
                    NULL                                                                 AS copyright,
                    CONCAT('https://sealifebase.net.br/images/species/', fg.picname)     AS url,
                    'sealifebase'                                                        AS origin
                FROM read_parquet('${SLB_DIR}/fieldguide_pic.parquet') fg
                LEFT JOIN t_species sp ON sp.external_id = CAST(fg.speccode AS VARCHAR)
            ) TO '${EXPORT_DIR}/fieldguide.csv' (FORMAT csv, HEADER true);
        "
        duckdb "${EXPORT_DIR}/tmp_fg.duckdb" -c "$fieldguide_sql" \
            && log "fieldguide_pic exportiert." \
            || log "[WARN] fieldguide_pic-Export fehlgeschlagen — wird übersprungen."
    fi

    local csv_count
    csv_count=$(ls "$EXPORT_DIR"/*.csv 2>/dev/null | wc -l | tr -d ' ')
    [[ "$csv_count" -gt 0 ]] || fail "Keine CSVs generiert."
    log "$csv_count CSV-Dateien exportiert."
}

import_to_sqlite() {
    log "Importiere in Datenbank: $DB_PATH"
    local import_script="${EXPORT_DIR}/import.sql"

    # fieldguide.csv optional einbinden
    local fieldguide_import=""
    if [[ -f "${EXPORT_DIR}/fieldguide.csv" ]]; then
        fieldguide_import=".import --skip 1 ${EXPORT_DIR}/fieldguide.csv tmp_pictures_fg"
    fi

    cat > "$import_script" << EOF
PRAGMA foreign_keys = OFF;
.mode csv

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

INSERT OR IGNORE INTO classes  SELECT * FROM tmp_classes;
INSERT OR IGNORE INTO orders   SELECT * FROM tmp_orders;
INSERT OR IGNORE INTO families SELECT * FROM tmp_families;

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

INSERT OR IGNORE INTO species SELECT * FROM tmp_species;

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

UPDATE species
SET
    status        = 'deprecated',
    deprecated_at = CAST(strftime('%s', 'now') AS INTEGER)
WHERE external_source = 'sealifebase'
  AND status         != 'deprecated'
  AND external_id NOT IN (SELECT external_id FROM tmp_species);

INSERT OR IGNORE INTO pictures SELECT * FROM tmp_pictures;

PRAGMA foreign_keys = ON;
EOF

    # fieldguide optional importieren
    if [[ -f "${EXPORT_DIR}/fieldguide.csv" ]]; then
        cat >> "$import_script" << EOF2
PRAGMA foreign_keys = OFF;
.mode csv
CREATE TEMP TABLE tmp_pictures_fg AS SELECT * FROM pictures WHERE 0;
.import --skip 1 ${EXPORT_DIR}/fieldguide.csv tmp_pictures_fg
INSERT OR IGNORE INTO pictures SELECT * FROM tmp_pictures_fg;
PRAGMA foreign_keys = ON;
EOF2
    fi

    sqlite3 "$DB_PATH" < "$import_script" || fail "SQLite-Import fehlgeschlagen."
}

write_metadata() {
    log "Schreibe Metadata..."
    sqlite3 "$DB_PATH" << EOF
INSERT INTO metadata (key, value) VALUES ('sealifebase', '${SLB_VERSION}')
ON CONFLICT (key) DO UPDATE SET value = excluded.value;
EOF
    log "Metadata: sealifebase = ${SLB_VERSION}"
}

validate() {
    local species_count
    species_count=$(sqlite3 "$DB_PATH" \
        "SELECT COUNT(*) FROM species WHERE external_source='sealifebase';")
    [[ "$species_count" -ge 50000 ]] \
        || fail "Zu wenige SeaLifeBase-Spezies: $species_count (erwartet >= 50000)"
    local pictures_count
    pictures_count=$(sqlite3 "$DB_PATH" \
        "SELECT COUNT(*) FROM pictures WHERE origin='sealifebase';")
    log "SeaLifeBase-Daten OK: $species_count species, $pictures_count pictures."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log "=== SeaLifeBase Import ==="
log "Version : $SLB_VERSION"
log "Parquets: $SLB_DIR"
log "DB      : $DB_PATH"

check_deps
[[ "$DOWNLOAD" == true ]] && download_parquets
check_parquet_files
clear_existing_data
export_to_csv
import_to_sqlite
write_metadata
validate

log "=== SeaLifeBase Import abgeschlossen ==="
