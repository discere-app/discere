#!/usr/bin/env bash
# =============================================================================
# import.sh — <Plugin-Name> Plugin
#
# Kurze Beschreibung: woher kommen die Daten, was wird importiert.
#
# Usage:
#   ./import.sh --db /path/to/discere.db --download
#   ./import.sh --db /path/to/discere.db --no-download
#
# Flags:
#   --db <path>    Ziel-Datenbank (Pflichtfeld)
#   --download     Quelldaten herunterladen
#   --keep         Heruntergeladene Dateien behalten
#
# Plugin-Konventionen:
#   - Kein CREATE TABLE — Schema ist Aufgabe von core/create_db.sh
#   - Logs auf stderr, nichts auf stdout
#   - Eigenes Cleanup (temporäre Dateien ohne --keep)
#   - Idempotent: bestehende Daten der Quelle werden vor dem Import gelöscht
#   - IDs werden ausschliesslich über discere_uuid() in export.sql erzeugt
# =============================================================================

set -Eeuo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="$PLUGIN_DIR/sql"
EXPORT_DIR="$(mktemp -d)"

DB_PATH="${DB_PATH:-}"
SOURCE_NAME="example"   # Muss mit plugin.yaml:source übereinstimmen
DOWNLOAD=false
KEEP_FILES=false

# ---------------------------------------------------------------------------
# Argumente
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)          DB_PATH="$2"; shift ;;
        --download)    DOWNLOAD=true ;;
        --no-download) DOWNLOAD=false ;;
        --keep)        KEEP_FILES=true ;;
        --help|-h)
            sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "[WARN] [$SOURCE_NAME] Unbekanntes Argument: $1" >&2 ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[$(date '+%H:%M:%S')] [$SOURCE_NAME] $*" >&2; }
fail() { echo "[ERROR] [$SOURCE_NAME] $*" >&2; exit 1; }

cleanup() {
    rm -rf "$EXPORT_DIR"
    # Bei --keep: Quelldateien behalten. Sonst löschen.
    # if [[ "$DOWNLOAD" == true && "$KEEP_FILES" == false ]]; then
    #     rm -rf "$DATA_DIR"
    # fi
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
}

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
download_data() {
    log "Lade Quelldaten herunter..."
    # TODO: Download-Logik implementieren
    fail "Download noch nicht implementiert."
}

# ---------------------------------------------------------------------------
# ETL
# ---------------------------------------------------------------------------
clear_existing_data() {
    log "Räume bestehende ${SOURCE_NAME}-Daten auf..."
    sqlite3 "$DB_PATH" << EOF
PRAGMA foreign_keys = OFF;
-- Nur Tabellen löschen die kein Soft-Delete verwenden.
-- species und genera nicht löschen (Soft-Delete / FK-Referenzen).
DELETE FROM pictures WHERE origin = '$SOURCE_NAME';
DELETE FROM families WHERE external_source = '$SOURCE_NAME';
DELETE FROM orders   WHERE external_source = '$SOURCE_NAME';
DELETE FROM classes  WHERE external_source = '$SOURCE_NAME';
DELETE FROM sources  WHERE id = '$SOURCE_NAME';
PRAGMA foreign_keys = ON;
EOF
}

export_to_csv() {
    log "Exportiere Quelldaten nach CSV..."
    local duck_db="${EXPORT_DIR}/tmp.duckdb"

    local sql
    sql=$(sed \
        -e "s|\${DATA_DIR}|${DATA_DIR}|g" \
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
    # TODO: Import-Logik implementieren (analog zu fishbase/import.sh)
    fail "Import noch nicht implementiert."
}

# ---------------------------------------------------------------------------
# Source-Metadaten schreiben
#
# Liest sql/source.sql und ersetzt ${VERSION} und ${NOW}.
# Alle inhaltlichen Angaben (Zitierung, Lizenz, URL etc.) stehen dort —
# nicht hier in import.sh, damit Sonderzeichen in Zitierungen kein Problem
# sind (Apostrophe in Autorennamen, Klammern, etc.).
# Zusätzlich wird die Version in metadata geschrieben für den
# Flutter Update-Mechanismus.
# ---------------------------------------------------------------------------
write_source_metadata() {
    local version="${SOURCE_VERSION:-unknown}"
    local now
    now="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    log "Schreibe Quellenangabe für '${SOURCE_NAME}'..."
    sed -e "s|\${VERSION}|$version|g" \
        -e "s|\${NOW}|$now|g" \
        "$SQL_DIR/source.sql" \
    | sqlite3 "$DB_PATH" \
    || fail "source.sql fehlgeschlagen."

    # metadata-Tabelle: wird vom Flutter Update-Mechanismus ausgelesen
    sqlite3 "$DB_PATH" \
        "INSERT INTO metadata (key, value) VALUES ('$SOURCE_NAME', '$version')
         ON CONFLICT (key) DO UPDATE SET value = excluded.value;" \
    || fail "metadata-Eintrag fehlgeschlagen."

    log "Quellenangabe geschrieben (version=$version)."
}

validate() {
    local species_count
    species_count=$(sqlite3 "$DB_PATH" \
        "SELECT COUNT(*) FROM species WHERE external_source='$SOURCE_NAME';")
    [[ "$species_count" -ge 1 ]] \
        || fail "Keine Species importiert für Quelle '$SOURCE_NAME'."
    log "OK: $species_count species importiert."

    # Sicherstellen dass der sources-Eintrag vorhanden ist
    local sources_count
    sources_count=$(sqlite3 "$DB_PATH" \
        "SELECT COUNT(*) FROM sources WHERE id='$SOURCE_NAME';")
    [[ "$sources_count" -eq 1 ]] \
        || fail "Kein sources-Eintrag für '$SOURCE_NAME' — write_source_metadata() fehlgeschlagen?"
    log "OK: sources-Eintrag vorhanden."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log "=== ${SOURCE_NAME} Import ==="
log "DB: $DB_PATH"

check_deps
[[ "$DOWNLOAD" == true ]] && download_data
clear_existing_data
export_to_csv
import_to_sqlite
write_source_metadata
validate

log "=== ${SOURCE_NAME} Import abgeschlossen ==="
