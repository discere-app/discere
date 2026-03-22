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
    # Idempotenz: bestehende FishBase-Daten löschen bevor neu importiert wird.
    # Reihenfolge beachten wegen FK-Constraints (Kind vor Elterntabelle).
    log "Lösche bestehende FishBase-Daten..."
    sqlite3 "$DB_PATH" << 'EOF'
PRAGMA foreign_keys = OFF;
DELETE FROM pictures       WHERE origin = 'fishbase';
DELETE FROM species        WHERE external_source = 'fishbase';
DELETE FROM genera         WHERE external_source = 'fishbase';
DELETE FROM families       WHERE external_source = 'fishbase';
DELETE FROM orders         WHERE external_source = 'fishbase';
DELETE FROM classes        WHERE external_source = 'fishbase';
DELETE FROM metadata       WHERE key = 'fishbase';
PRAGMA foreign_keys = ON;
EOF
}

export_to_csv() {
    # HINWEIS: Verbesserungsvorschlag (nicht umgesetzt)
    # Idealerweise würde DuckDB direkt nach SQLite schreiben (kein CSV-Zwischenschritt):
    #   ATTACH 'discere.db' AS sqlite_db (TYPE sqlite);
    #   CREATE TABLE sqlite_db.species AS SELECT ...
    # Das würde Disk-I/O, temporäre Dateien und Encoding-Risiken eliminieren.
    #
    # Nicht umgesetzt weil:
    # 1. DuckDB's SQLite-Extension benötigt beim ersten Laden eine Internetverbindung
    #    (INSTALL sqlite; LOAD sqlite;) — bricht in Offline- und CI-Umgebungen.
    # 2. Type-Affinity-Konflikte: DuckDB ist stark typisiert, SQLite schwach.
    #    FishBase-Spalten mit gemischten Typen werfen Fehler die im CSV-Weg nicht auftreten.
    # 3. Die Extension ist versionsgebunden — DuckDB-Updates erfordern Reinstall.
    #
    # Revisit wenn DuckDB's SQLite-Integration stabiler und offline-fähig wird.
    log "Exportiere Parquets nach CSV..."
    local duck_db="${EXPORT_DIR}/tmp.duckdb"
    local combined_sql=""

    for script in "$SQL_DIR"/0*.sql; do
        local sql
        # HINWEIS (nicht umgesetzt): sed ist anfällig bei Pfaden mit &, | oder \
        # Sauberere Alternative wären DuckDB SET-Variablen. Für typische Pfade unkritisch.
        sql=$(sed \
            -e "s|\${FISHBASE_DIR}|${FISHBASE_DIR}|g" \
            -e "s|\${EXPORT_DIR}|${EXPORT_DIR}|g" \
            "$script")
        combined_sql="${combined_sql}${sql}"$'\n'
    done

    duckdb "$duck_db" -c "$combined_sql" || fail "DuckDB-Export fehlgeschlagen."

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
.import --skip 1 ${EXPORT_DIR}/classes.csv classes
.import --skip 1 ${EXPORT_DIR}/orders.csv orders
.import --skip 1 ${EXPORT_DIR}/families.csv families
.import --skip 1 ${EXPORT_DIR}/genera.csv genera
.import --skip 1 ${EXPORT_DIR}/species.csv species
.import --skip 1 ${EXPORT_DIR}/pictures.csv pictures
PRAGMA foreign_keys = ON;
EOF
    sqlite3 "$DB_PATH" < "$import_script" || fail "SQLite-Import fehlgeschlagen."
}

rebuild_fts() {
    log "FTS rebuild..."
    sqlite3 "$DB_PATH" << 'EOF'
INSERT INTO species_fts(species_fts)   VALUES('rebuild');
INSERT INTO genera_fts(genera_fts)     VALUES('rebuild');
INSERT INTO families_fts(families_fts) VALUES('rebuild');
INSERT INTO orders_fts(orders_fts)     VALUES('rebuild');
INSERT INTO classes_fts(classes_fts)   VALUES('rebuild');
EOF
}

write_metadata() {
    log "Schreibe Metadata..."
    sqlite3 "$DB_PATH" << EOF
INSERT INTO metadata (key, value) VALUES ('fishbase', '${FISHBASE_VERSION}')
ON CONFLICT (key) DO UPDATE SET value = excluded.value;
EOF
    log "Metadata: fishbase = ${FISHBASE_VERSION}"
}

validate() {
    # Plugin-seitige Schnellprüfung — nur FishBase-spezifisch.
    # Die vollständige Validierung aller Tabellen übernimmt build.sh (validate.sql).
    local species_count
    species_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM species WHERE external_source='fishbase';")
    [[ "$species_count" -ge 30000 ]] || fail "Zu wenige FishBase-Spezies: $species_count (erwartet >= 30000)"
    local pictures_count
    pictures_count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM pictures WHERE origin='fishbase';")
    [[ "$pictures_count" -ge 10000 ]] || fail "Zu wenige FishBase-Bilder: $pictures_count (erwartet >= 10000)"
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
rebuild_fts
write_metadata
validate

log "=== FishBase Import abgeschlossen ==="
