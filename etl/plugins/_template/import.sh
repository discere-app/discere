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

# shellcheck source=../../core/plugin_api.sh
source "$PLUGIN_DIR/../../core/plugin_api.sh"
plugin_init "$PLUGIN_DIR"

SQL_DIR="$PLUGIN_SQL_DIR"
EXPORT_DIR="$(mktemp -d)"

DB_PATH="${DB_PATH:-}"
DOWNLOAD=false
KEEP_FILES=false
DATA_DIR="${DATA_DIR:-$PLUGIN_DIR/cache}"

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
            plugin_print_help_from_header "$0" 2 18
            exit 0
            ;;
        *) plugin_warn "Unbekanntes Argument: $1" ;;
    esac
    shift
done

cleanup() {
    plugin_cleanup_dir "$EXPORT_DIR"
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
    plugin_require_db_path "$DB_PATH"
    plugin_require_command duckdb sqlite3
}

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
download_data() {
    plugin_log "Lade Quelldaten herunter..."
    # TODO: Download-Logik implementieren
    plugin_fail "Download noch nicht implementiert."
}

# ---------------------------------------------------------------------------
# ETL
# ---------------------------------------------------------------------------
clear_existing_data() {
    plugin_log "Räume bestehende ${PLUGIN_SOURCE}-Daten auf..."
    sqlite3 "$DB_PATH" << EOF
PRAGMA foreign_keys = OFF;
-- Nur Tabellen löschen die kein Soft-Delete verwenden.
-- species und genera nicht löschen (Soft-Delete / FK-Referenzen).
DELETE FROM pictures WHERE origin = '${PLUGIN_SOURCE}';
DELETE FROM families WHERE external_source = '${PLUGIN_SOURCE}';
DELETE FROM orders   WHERE external_source = '${PLUGIN_SOURCE}';
DELETE FROM classes  WHERE external_source = '${PLUGIN_SOURCE}';
DELETE FROM sources  WHERE id = '${PLUGIN_SOURCE}';
PRAGMA foreign_keys = ON;
EOF
}

export_to_csv() {
    plugin_log "Exportiere Quelldaten nach CSV..."
    local duck_db="${EXPORT_DIR}/tmp.duckdb"

    local sql
    sql=$(sed \
        -e "s|\${DATA_DIR}|${DATA_DIR}|g" \
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
    # TODO: Import-Logik implementieren (analog zu fishbase/import.sh)
    plugin_fail "Import noch nicht implementiert."
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
    plugin_write_source_metadata "$DB_PATH" "$SQL_DIR/source.sql" "$version"
}

validate() {
    plugin_validate_min_count \
        "$DB_PATH" \
        "species" \
        "external_source='${PLUGIN_SOURCE}'" \
        1 \
        "Species für Quelle '${PLUGIN_SOURCE}'"
    plugin_validate_source_entry_exists "$DB_PATH"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
plugin_log "=== ${PLUGIN_NAME} Import ==="
plugin_log "DB: $DB_PATH"

check_deps
[[ "$DOWNLOAD" == true ]] && download_data
clear_existing_data
export_to_csv
import_to_sqlite
write_source_metadata
validate

plugin_log "=== ${PLUGIN_NAME} Import abgeschlossen ==="
