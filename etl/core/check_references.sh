#!/usr/bin/env bash
# =============================================================================
# check_references.sh — Prüft am Ende des Builds alle Verweise auf Entitäten
#
# Usage:
#   ./core/check_references.sh --db <db>
#
# Läuft in Stage 05 von build.sh, nach den ergänzenden Quellen: Diese
# schreiben ihre Beiträge nach der Identitäts-Stage direkt mit endgültigen
# IDs, und ihre Verweise prüft sonst niemand. Geprüft wird jede Spalte aus
# core/reference_columns.sh:
#   - keine vorläufige ID (discere:<quelle>_<typ>:<schlüssel>);
#   - jede ID in einer Spalte ohne Fremdschlüssel bezeichnet eine Entität;
#   - jeder Fremdschlüssel löst auf (PRAGMA foreign_key_check).
#
# Gibt je Verstoß eine Zeile aus und endet dann mit Exit-Code 1.
# =============================================================================

set -Eeuo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./plugin_api.sh
source "$CORE_DIR/plugin_api.sh"
# shellcheck source=./reference_columns.sh
source "$CORE_DIR/reference_columns.sh"
PLUGIN_SOURCE="check_references"

DB_PATH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --db) DB_PATH="$2"; shift ;;
        --help|-h)
            plugin_print_help "$0"
            exit 0
            ;;
        *) plugin_fail "Unbekanntes Argument: $1" ;;
    esac
    shift
done

plugin_require_command sqlite3
plugin_require_db_path "$DB_PATH"

checks_sql() {
    local table column entry
    echo "CREATE TEMP TABLE entities (id TEXT NOT NULL PRIMARY KEY);"
    for table in "${ENTITY_TABLES[@]}"; do
        echo "INSERT INTO entities SELECT id FROM \"$table\";"
    done
    while read -r table column; do
        cat << SQL
SELECT '$table.$column: ' || COUNT(*) || ' vorläufige IDs, z. B. ' || MIN("$column")
FROM "$table" WHERE "$column" GLOB 'discere:*_*:*' HAVING COUNT(*) > 0;
SQL
    done < <(reference_columns "$DB_PATH")
    for entry in "${REFERENCE_COLUMNS_WITHOUT_FK[@]}"; do
        table="${entry% *}"
        column="${entry#* }"
        cat << SQL
SELECT '$table.$column: ' || COUNT(*) || ' IDs ohne Entität, z. B. ' || MIN("$column")
FROM "$table"
WHERE "$column" GLOB 'discere:*' AND "$column" NOT IN (SELECT id FROM entities)
HAVING COUNT(*) > 0;
SQL
    done
    cat << 'SQL'
SELECT 'Fremdschlüssel: ' || COUNT(*) || ' Verweise lösen nicht auf, z. B. '
       || (SELECT "table" || ' → ' || parent FROM pragma_foreign_key_check(NULL, 'main') LIMIT 1)
FROM pragma_foreign_key_check(NULL, 'main')
HAVING COUNT(*) > 0;
SQL
}

# Erst das SQL erzeugen, dann prüfen: checks_sql liest selbst das Schema, und
# zwei gleichzeitig öffnende Verbindungen können sich im WAL-Modus sperren.
sql="$(checks_sql)"
problems="$(sqlite3 -bail "$DB_PATH" <<< "$sql")" || plugin_fail "Prüfung der Verweise fehlgeschlagen."
if [[ -n "$problems" ]]; then
    echo "$problems"
    exit 1
fi
plugin_log "Verweise auf Entitäten OK."
