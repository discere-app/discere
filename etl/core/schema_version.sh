#!/usr/bin/env bash
# =============================================================================
# schema_version.sh — Schemaversion einer Referenz-DB, aus ihrem Inhalt
#
# Usage:
#   ./core/schema_version.sh --db <db>
#
# Ausgabe (stdout): die Schemaversion, die das Manifest für diese DB nennen
# muss. publish_release.sh schreibt sie ins Manifest; ein Argument dafür gibt
# es nicht, denn eine falsche Version ließe eine App eine DB installieren,
# die sie nicht lesen kann.
#
#   1 — IDs tragen ihre Quelle (discere:<quelle>_<typ>:<nr>), kein Register.
#   2 — IDs ohne Quelle (discere:<typ>:<nr>) mit Register (entity_source_keys)
#       und Aliasen (entity_aliases). Eine App, die nur Version 1 kennt, fände
#       ihre gespeicherten IDs darin nicht mehr und verlöre Lernstände.
#
# Jede andere Form — etwa ein Register neben IDs mit Quelle — bricht ab. Eine
# künftige Schemaversion braucht hier ihre eigene Erkennung.
# =============================================================================

set -Eeuo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./plugin_api.sh
source "$CORE_DIR/plugin_api.sh"
PLUGIN_SOURCE="schema_version"

DB_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db) plugin_require_value "$@"; DB_PATH="$2"; shift ;;
        --help|-h)
            plugin_print_help "$0"
            exit 0
            ;;
        *) plugin_fail_unknown_argument "$1" ;;
    esac
    shift
done

plugin_require_command sqlite3
[[ -f "$DB_PATH" ]] || plugin_fail "Referenz-DB nicht gefunden: '$DB_PATH' (--db)."

query() {
    sqlite3 "file:$DB_PATH?mode=ro" "$1" 2> /dev/null \
        || plugin_fail "Keine lesbare Referenz-DB: $DB_PATH"
}

tables="$(query "SELECT COUNT(*) FROM sqlite_schema WHERE type = 'table'
                 AND name IN ('entity_source_keys', 'entity_aliases');")"
species="$(query "SELECT COUNT(*) FROM species;")"
[[ "$species" -gt 0 ]] || plugin_fail "$DB_PATH enthält keine Arten."
final_ids="$(query "SELECT COUNT(*) FROM species
                    WHERE id GLOB 'discere:species:[1-9]*'
                      AND substr(id, 17) NOT GLOB '*[^0-9]*';")"
source_ids="$(query "SELECT COUNT(*) FROM species WHERE id GLOB 'discere:*_species:*';")"

if [[ "$tables" -eq 2 && "$final_ids" -eq "$species" \
      && "$(query "SELECT COUNT(*) FROM entity_source_keys;")" -gt 0 ]]; then
    echo 2
elif [[ "$tables" -eq 0 && "$source_ids" -eq "$species" ]]; then
    echo 1
else
    plugin_fail "$DB_PATH hat keine bekannte Schemaform: Register/Aliase $tables von 2, $final_ids IDs ohne Quelle, $source_ids mit Quelle, $species Arten."
fi
