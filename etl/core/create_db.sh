#!/usr/bin/env bash
# =============================================================================
      # create_db.sh — Erstellt eine leere Discere-Datenbank mit Schema
#
# Usage:
#   ./core/create_db.sh --output /path/to/discere.db
#   ./core/create_db.sh --force
#
# Flags:
#   --output <path>   Ziel-Pfad für die SQLite-Datenbank
#   --force           Bestehende Datenbank überschreiben
#
# Umgebungsvariablen:
#   OUTPUT_DB         Entspricht --output
#
# Ausgabe (stdout): Pfad zur erstellten Datenbank — wird vom Orchestrator
#                   (build.sh) als DB_PATH weiterverwendet.
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DB="${OUTPUT_DB:-}"
FORCE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) OUTPUT_DB="$2"; shift ;;
        --force)  FORCE=true ;;
        --help|-h)
            sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "[WARN] [create_db] Unbekanntes Argument: $1" >&2 ;;
    esac
    shift
done

OUTPUT_DB="${OUTPUT_DB:-../assets/database/discere_reference.db}"

log()  { echo "[$(date '+%H:%M:%S')] [create_db] $*" >&2; }
fail() { echo "[ERROR] [create_db] $*" >&2; exit 1; }

command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 nicht gefunden."

if [[ -f "$OUTPUT_DB" ]]; then
    [[ "$FORCE" == true ]] || fail "DB existiert bereits: $OUTPUT_DB — verwende --force."
    rm -f "$OUTPUT_DB"
    log "Bestehende Datenbank entfernt."
fi

mkdir -p "$(dirname "$OUTPUT_DB")"
log "Erstelle Datenbank: $OUTPUT_DB"
sqlite3 "$OUTPUT_DB" < "$SCRIPT_DIR/sql/schema.sql" || fail "Schema-Erstellung fehlgeschlagen."

# WAL-Modus separat setzen — nicht in schema.sql weil sqlite3 "wal" auf stdout
# schreibt und damit den DB-Pfad des Orchestrators korrumpiert.
sqlite3 "$OUTPUT_DB" "PRAGMA journal_mode = WAL;" > /dev/null

log "Schema erfolgreich erstellt."

echo "$OUTPUT_DB"
