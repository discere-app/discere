#!/usr/bin/env bash
# =============================================================================
# import.sh — Plugin für kuratierte Ergänzungen
#
# Importiert von Hand gepflegte Daten zu Entitäten anderer Quellen. Die Quelle
# legt keine Entitäten an: Jede Zeile adressiert eine vorhandene Entität über
# den Quellenschlüssel (taxon_source) und die external_id, die diese Quelle ihr
# gegeben hat.
#
# Usage:
#   ./import.sh --db /path/to/discere.db
#
# Flags:
#   --db <path>    Ziel-Datenbank (Pflichtfeld)
#   Alle anderen Flags von build.sh werden mit Warnung ignoriert.
#
# Daten:
#   data/class_common_names.csv — Volksnamen für Klassen, je Zeile
#     taxon_source, external_id, class (wissenschaftlicher Name), language,
#     name und source_url als Beleg.
#
# Plugin-Konventionen:
#   - Kein CREATE TABLE — Schema ist Aufgabe von core/create_db.sh
#   - Logs auf stderr, nichts auf stdout
#   - Idempotent: alle Zeilen mit source = 'curated' werden ersetzt
# =============================================================================

set -Eeuo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../core/plugin_api.sh
source "$PLUGIN_DIR/../../core/plugin_api.sh"
plugin_init "$PLUGIN_DIR"

DB_PATH="${DB_PATH:-}"
CLASS_NAMES_CSV="$PLUGIN_DIR/data/class_common_names.csv"
CSV_COLUMNS=(taxon_source external_id class language name source_url)

# ---------------------------------------------------------------------------
# Argumente
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --db) DB_PATH="$2"; shift ;;
        --help|-h)
            plugin_print_help_from_header "$0" 2 25
            exit 0
            ;;
        *) plugin_warn "Unbekanntes Argument: $1" ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# Validierung
# ---------------------------------------------------------------------------
check_deps() {
    plugin_require_db_path "$DB_PATH"
    plugin_require_command sqlite3
    [[ -f "$CLASS_NAMES_CSV" ]] || plugin_fail "Datei fehlt: $CLASS_NAMES_CSV"
}

# Eine vertauschte Spalte würde sonst still in die falsche Spalte geladen.
check_csv_header() {
    local expected actual
    expected="$(IFS=,; echo "${CSV_COLUMNS[*]}")"
    actual="$(head -n 1 "$CLASS_NAMES_CSV")"
    [[ "$actual" == "$expected" ]] \
        || plugin_fail "Kopfzeile von $(basename "$CLASS_NAMES_CSV") ist '$actual', erwartet '$expected'."
}

# ---------------------------------------------------------------------------
# ETL
# ---------------------------------------------------------------------------

# SQL, das die CSV in tmp_class_names lädt. rowid + 1 ist die Zeilennummer in
# der Datei. .import liest eine leere Zelle als '' und eine fehlende als NULL;
# die Prüfungen behandeln beides als leer.
staging_sql() {
    local column_definitions
    column_definitions="$(printf '%s TEXT, ' "${CSV_COLUMNS[@]}")"
    cat << EOF
.bail on
CREATE TEMP TABLE tmp_class_names (${column_definitions%, });
.import --csv --skip 1 "$CLASS_NAMES_CSV" tmp_class_names
EOF
}

# Je leerer Zelle eine Meldung. Ohne diese Zeilen bliebe eine leere Zelle
# stumm: jeder Vergleich und jedes || mit NULL ergibt NULL.
empty_cell_problems_sql() {
    local column
    for column in "${CSV_COLUMNS[@]}"; do
        [[ "$column" == "${CSV_COLUMNS[0]}" ]] || echo "UNION ALL"
        echo "SELECT line, 'Spalte $column ist leer' FROM numbered WHERE NULLIF(TRIM($column), '') IS NULL"
    done
}

# Die Taxonquellen, die eine Zeile adressieren darf: genau die aus
# depends_on_sources, denn nur deren Daten liegen sicher schon in der DB.
taxon_sources_sql() {
    local taxon_sources taxon_source
    taxon_sources="$(plugin_manifest_list "$PLUGIN_MANIFEST_PATH" "depends_on_sources")"
    echo "CREATE TEMP TABLE tmp_taxon_sources (source TEXT);"
    for taxon_source in $taxon_sources; do
        echo "INSERT INTO tmp_taxon_sources VALUES ('$taxon_source');"
    done
}

# Gibt je Problem eine Zeile „Zeile <n>: <Grund>“ aus. Zeilen mit leeren
# Zellen bekommen nur diese Meldung, die übrigen Prüfungen laufen auf den
# vollständigen Zeilen.
#
# Zwei Namen derselben Sprache an einer Klasse hätten keine Rangfolge (rank
# ist NULL). Deshalb darf weder die CSV zwei Zeilen für dieselbe Klasse und
# Sprache haben noch die Taxonquelle selbst schon einen Namen in dieser
# Sprache führen.
find_problems() {
    {
        staging_sql
        taxon_sources_sql
        cat << EOF
WITH numbered AS (
    SELECT rowid + 1 AS line, * FROM tmp_class_names
),
empty_cells (line, problem) AS (
$(empty_cell_problems_sql)
),
complete AS (
    SELECT * FROM numbered WHERE line NOT IN (SELECT line FROM empty_cells)
),
problems (line, problem) AS (
    SELECT line, problem FROM empty_cells
    UNION ALL
    SELECT line, format('Taxonquelle ''%s'' steht nicht in depends_on_sources', taxon_source)
    FROM complete
    WHERE taxon_source NOT IN (SELECT source FROM tmp_taxon_sources)
    UNION ALL
    SELECT n.line, format('keine Klasse mit external_source ''%s'', external_id ''%s'' und Namen ''%s''',
                          n.taxon_source, n.external_id, n.class)
    FROM complete n
    WHERE n.taxon_source IN (SELECT source FROM tmp_taxon_sources)
      AND NOT EXISTS (
          SELECT 1 FROM classes c
          WHERE c.external_source = n.taxon_source
            AND c.external_id     = n.external_id
            AND c.name            = n.class
      )
    UNION ALL
    SELECT line, format('Sprache ''%s'' ist nicht en, de, fr oder es', language)
    FROM complete
    WHERE language NOT IN ('en', 'de', 'fr', 'es')
    UNION ALL
    SELECT a.line, format('Zeile %d nennt dieselbe Klasse in derselben Sprache', b.line)
    FROM complete a
    JOIN complete b
      ON b.taxon_source = a.taxon_source
     AND b.external_id  = a.external_id
     AND b.language     = a.language
     AND b.line        != a.line
    UNION ALL
    SELECT n.line, format('%s führt für diese Klasse schon einen Namen in ''%s'': %s',
                          n.taxon_source, n.language, cn.name)
    FROM complete n
    JOIN classes c
      ON c.external_source = n.taxon_source
     AND c.external_id     = n.external_id
    JOIN common_names cn
      ON cn.entity_id = c.id
     AND cn.language  = n.language
     AND cn.source    = n.taxon_source
)
SELECT format('Zeile %d: %s', line, problem) FROM problems ORDER BY line, problem;
EOF
    } | sqlite3 "$DB_PATH"
}

validate_class_names() {
    local problems
    plugin_log "Prüfe $(basename "$CLASS_NAMES_CSV")..."
    problems="$(find_problems)" || plugin_fail "Prüfung von $(basename "$CLASS_NAMES_CSV") fehlgeschlagen."
    [[ -z "$problems" ]] \
        || plugin_fail "Ungültige Zeilen in $(basename "$CLASS_NAMES_CSV"):"$'\n'"$problems"
}

# Ersetzt alle Zeilen dieser Quelle in einer Transaktion. entity_id ist die
# id der gefundenen Klasse, nicht aus einem ID-Format abgeleitet.
import_class_names() {
    plugin_log "Importiere Klassennamen in: $DB_PATH"
    {
        staging_sql
        cat << EOF
BEGIN;
DELETE FROM common_names WHERE source = '${PLUGIN_SOURCE}';
INSERT INTO common_names (
    entity_id, entity_type, language, country, name,
    source, rank, is_preferred, name_type
) SELECT
    c.id, 'class', n.language, NULL, TRIM(n.name),
    '${PLUGIN_SOURCE}', NULL, 1, NULL
FROM tmp_class_names n
JOIN classes c
  ON c.external_source = n.taxon_source
 AND c.external_id     = n.external_id
 AND c.name            = n.class;
COMMIT;
EOF
    } | sqlite3 "$DB_PATH" || plugin_fail "SQLite-Import fehlgeschlagen."
}

# ---------------------------------------------------------------------------
# Source-Metadaten schreiben
#
# Die Daten haben keine Releases. Als Version dient eine Prüfsumme der CSV,
# damit metadata zeigt, welcher Stand gebaut wurde.
# ---------------------------------------------------------------------------
write_source_metadata() {
    local data_version
    data_version="$(cksum < "$CLASS_NAMES_CSV" | awk '{ print $1 }')"
    plugin_write_source_metadata "$DB_PATH" "$PLUGIN_SQL_DIR/source.sql" "$data_version"
}

# Jede Zeile der CSV muss in der DB angekommen sein.
validate() {
    local expected actual
    expected="$(tail -n +2 "$CLASS_NAMES_CSV" | grep -c . || true)"
    actual="$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM common_names WHERE source = '${PLUGIN_SOURCE}';")"
    [[ "$actual" -eq "$expected" ]] \
        || plugin_fail "Klassennamen: $actual in der DB, $expected in $(basename "$CLASS_NAMES_CSV")."
    plugin_validate_source_entry_exists "$DB_PATH"
    plugin_log "Kuratierte Daten OK: $actual Klassennamen."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
plugin_log "=== ${PLUGIN_NAME} Import ==="
plugin_log "DB: $DB_PATH"

check_deps
check_csv_header
validate_class_names
import_class_names
write_source_metadata
validate

plugin_log "=== ${PLUGIN_NAME} Import abgeschlossen ==="
