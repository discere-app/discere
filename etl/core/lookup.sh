#!/usr/bin/env bash
# =============================================================================
# lookup.sh — Materialisiert species_name_lookup
#
# Usage:
#   ./core/lookup.sh --db <db>
#
# Läuft in Stage 03 von build.sh, nach allen Quellen. Die Regel steht in
# core/sql/rebuild_lookup.sql: Ein Name bekommt nur einen Eintrag, wenn er
# genau eine aktive Art meint.
#
# Build-Bericht (Quelle „lookup“, core/sql/lookup_report.sql): ambiguous —
# ein Name ohne Eintrag, weil er mehrere Arten meint, mit allen Arten;
# misapplied — ein Name, den aktive Arten nur als falsch angewandten führen.
# =============================================================================

set -Eeuo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./plugin_api.sh
source "$CORE_DIR/plugin_api.sh"
PLUGIN_SOURCE="lookup"

DB_PATH=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --db) plugin_require_value "$@"; DB_PATH="$2"; shift ;;
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

report="$(sqlite3 -bail "$DB_PATH" \
    ".read '$CORE_DIR/sql/rebuild_lookup.sql'" \
    ".read '$CORE_DIR/sql/lookup_report.sql'")" \
    || plugin_fail "species_name_lookup fehlgeschlagen."
plugin_report <<< "$report"
plugin_log "species_name_lookup: $(sqlite3 "$DB_PATH" 'SELECT COUNT(*) FROM species_name_lookup;') Namen," \
    "ohne Eintrag: $(grep -c $'^ambiguous\t' <<< "$report" || true) mehrdeutig," \
    "$(grep -c $'^misapplied\t' <<< "$report" || true) nur falsch angewandt"
