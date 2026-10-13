#!/usr/bin/env bash
# =============================================================================
# match.sh — Abgleich mit vorhandenen Entitäten für Plugins
#
# Wird von Plugins nach core/plugin_api.sh gesourced:
#
#   source "$PLUGIN_CORE_DIR/match.sh"
#   match_records "$DB_PATH" "$input_tsv" "$result_tsv"
#
# Die Regeln stehen in core/sql/match.sql. Ein Plugin, das ohnehin eine
# sqlite3-Sitzung gegen die DB hält, kann match.sql auch direkt per .read
# einbinden; match_records ist der Weg für Datensätze aus einer Datei, etwa
# aus DuckDB.
# =============================================================================

MATCH_SQL="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sql/match.sql"

# match_records <db> <eingabe.tsv> <ergebnis.tsv>
#
# Eingabe: TSV mit Kopfzeile record_key, rank, name.
# Ergebnis: TSV mit Kopfzeile record_key, rank, name, entity_id, status,
# matched_by, detail (Bedeutung siehe match.sql).
#
# Was nicht matched ist (none, ambiguous), geht mit Detail in den
# Build-Bericht (plugin_report).
match_records() {
    local db_path="$1"
    local input="$2"
    local output="$3"
    local report_rows

    report_rows="$(mktemp)"
    if ! sqlite3 "$db_path" << SQL
.bail on
.mode tabs
CREATE TEMP TABLE match_input (record_key TEXT, rank TEXT, name TEXT);
.import --skip 1 "$input" match_input
.read "$MATCH_SQL"
.headers on
.once "$output"
SELECT record_key, rank, name, entity_id, status, matched_by, detail
FROM match_result ORDER BY rank, record_key;
.headers off
.once "$report_rows"
SELECT status, record_key, name, detail
FROM match_result WHERE status != 'matched' ORDER BY status, rank, name, record_key;
SQL
    then
        rm -f "$report_rows"
        plugin_fail "Abgleich fehlgeschlagen: $input"
    fi
    plugin_report < "$report_rows"
    rm -f "$report_rows"
}
