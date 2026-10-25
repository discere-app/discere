#!/usr/bin/env bash
# =============================================================================
# placeholders.sh — Markiert die Rang-Platzhalter der Quellen
#
# Usage:
#   ./core/placeholders.sh --db <db>
#
# Läuft in Stage 02d von build.sh, nach allen Quellen und der
# Identitäts-Stage: Die Regel gilt für jede Quelle gleich, auch für Taxa, die
# aus dem Vorgänger übernommen wurden, und der Bericht nennt die endgültigen
# IDs. Setzt is_placeholder in classes, orders, families und genera nach der
# Namensregel in core/sql/placeholders.sql (Muster in
# core/data/placeholder_patterns.csv).
#
# Build-Bericht (Quelle „placeholders“): je Platzhalter eine Zeile mit dem
# Rang als Kategorie, der ID als Schlüssel, dem Namen und als Detail Quelle
# und Anzahl aktiver Arten darunter.
# =============================================================================

set -Eeuo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./plugin_api.sh
source "$CORE_DIR/plugin_api.sh"
PLUGIN_SOURCE="placeholders"

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

report="$(sed -e "s|\${PLACEHOLDER_PATTERNS}|$CORE_DIR/data/placeholder_patterns.csv|g" \
              "$CORE_DIR/sql/placeholders.sql" | sqlite3 -bail "$DB_PATH")" \
    || plugin_fail "Markieren der Rang-Platzhalter fehlgeschlagen."
plugin_report <<< "$report"
plugin_log "Rang-Platzhalter markiert: $(grep -c . <<< "$report" || true)"
