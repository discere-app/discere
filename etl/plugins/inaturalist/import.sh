#!/usr/bin/env bash
# =============================================================================
# import.sh — iNaturalist Plugin
#
# Ordnet Arten und höheren Taxa der Referenz-DB ihre iNaturalist-Taxon-ID zu
# und schreibt sie nach entity_external_ids (provider 'inaturalist'). Damit
# fragt die App iNaturalist direkt per ID statt per Namenssuche.
#
# Usage:
#   ./import.sh --db /path/to/discere.db
#   ./import.sh --db /path/to/discere.db --taxa-file /path/to/taxa.csv.gz
#
# Flags:
#   --db <path>          Ziel-Datenbank (Pflichtfeld)
#   --download           taxa.csv.gz von iNaturalist Open Data laden (Default)
#   --no-download        taxa.csv.gz aus ./cache verwenden
#   --keep               Heruntergeladene taxa.csv.gz behalten
#   --taxa-file <path>   Vorhandene taxa.csv.gz verwenden (ohne Download)
#   Alle anderen Flags von build.sh werden mit Warnung ignoriert.
#
# Zuordnung über core/match.sh: Arten über alle wissenschaftlichen Namen
# aktiver Arten samt Synonymen, höhere Taxa über ihre Rangtabelle. Höhere
# Taxa werden unter ihrem Namensschlüssel abgelegt (genus:barbus), den die App
# abfragt, Arten unter ihrer ID. Was nicht eindeutig zuzuordnen ist, steht im
# Build-Bericht statt in der DB.
#
# Plugin-Konventionen:
#   - Kein CREATE TABLE — Schema ist Aufgabe von core/create_db.sh
#   - Logs auf stderr, nichts auf stdout
#   - Idempotent: alle iNaturalist-Zuordnungen werden ersetzt
# =============================================================================

set -Eeuo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=../../core/plugin_api.sh
source "$PLUGIN_DIR/../../core/plugin_api.sh"
plugin_init "$PLUGIN_DIR"
# shellcheck source=../../core/match.sh
source "$PLUGIN_CORE_DIR/match.sh"

WORK_DIR="$(mktemp -d)"

DB_PATH="${DB_PATH:-}"
DOWNLOAD=true
KEEP_FILES=false
TAXA_FILE="$PLUGIN_DIR/cache/taxa.csv.gz"
TAXA_URL="https://inaturalist-open-data.s3.amazonaws.com/taxa.csv.gz"

# ---------------------------------------------------------------------------
# Argumente
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)          DB_PATH="$2"; shift ;;
        --download)    DOWNLOAD=true ;;
        --no-download) DOWNLOAD=false ;;
        --keep)        KEEP_FILES=true ;;
        --taxa-file)   TAXA_FILE="$2"; DOWNLOAD=false; shift ;;
        --help|-h)
            plugin_print_help_from_header "$0" 2 30
            exit 0
            ;;
        *) plugin_warn "Unbekanntes Argument: $1" ;;
    esac
    shift
done

cleanup() {
    plugin_cleanup_dir "$WORK_DIR"
    if [[ "$DOWNLOAD" == true && "$KEEP_FILES" == false && -f "$TAXA_FILE" ]]; then
        plugin_log "Lösche taxa.csv.gz: $TAXA_FILE"
        rm -f "$TAXA_FILE"
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Validierung
# ---------------------------------------------------------------------------
check_deps() {
    plugin_require_db_path "$DB_PATH"
    plugin_require_command duckdb sqlite3
    if [[ "$DOWNLOAD" == true ]]; then
        plugin_require_command curl
    fi
}

check_taxa_file() {
    [[ -f "$TAXA_FILE" ]] || plugin_fail "taxa.csv.gz nicht gefunden: $TAXA_FILE — verwende --download oder --taxa-file"
}

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
# --remote-time übernimmt das Datum der Datei auf dem Server; es dient als
# Version der Quelle.
download_taxa() {
    if [[ -f "$TAXA_FILE" ]]; then
        plugin_log "taxa.csv.gz bereits vorhanden: $TAXA_FILE"
        return 0
    fi
    mkdir -p "$(dirname "$TAXA_FILE")"
    plugin_log "Lade taxa.csv.gz (~40 MB): $TAXA_URL"
    curl --location --fail --silent --show-error --remote-time \
         --output "$TAXA_FILE" "$TAXA_URL" \
    || plugin_fail "Download von taxa.csv.gz fehlgeschlagen."
    plugin_log "Download abgeschlossen."
}

# ---------------------------------------------------------------------------
# ETL
# ---------------------------------------------------------------------------

# Alle Namen, die der Abgleich treffen kann, normalisiert wie
# species_scientific_names.normalized_name. export.sql grenzt die
# iNaturalist-Taxa damit auf die ein, die überhaupt in Frage kommen. Namen
# mit Tab oder Zeilenumbruch (Tippfehler in den Quelldaten) passen in keine
# TSV-Zeile und auf keinen iNaturalist-Namen; sie fallen hier weg.
export_reference_names() {
    plugin_log "Exportiere Namen der Referenz-DB..."
    {
        printf 'rank\tnormalized_name\n'
        sqlite3 -separator $'\t' "$DB_PATH" "
            SELECT rank, normalized_name FROM (
                SELECT 'species' AS rank, normalized_name FROM species_scientific_names
                UNION SELECT 'genus',  LOWER(TRIM(name)) FROM genera
                UNION SELECT 'family', LOWER(TRIM(name)) FROM families
                UNION SELECT 'order',  LOWER(TRIM(name)) FROM orders
                UNION SELECT 'class',  LOWER(TRIM(name)) FROM classes
            )
            WHERE instr(normalized_name, char(9))  = 0
              AND instr(normalized_name, char(10)) = 0
              AND instr(normalized_name, char(13)) = 0;"
    } > "$WORK_DIR/reference_names.tsv" || plugin_fail "Export der Namen fehlgeschlagen."
}

export_records() {
    plugin_log "Lese iNaturalist-Taxa..."
    local sql
    sql=$(sed \
        -e "s|\${TAXA_FILE}|${TAXA_FILE}|g" \
        -e "s|\${REFERENCE_NAMES}|${WORK_DIR}/reference_names.tsv|g" \
        -e "s|\${EXPORT_DIR}|${WORK_DIR}|g" \
        "$PLUGIN_SQL_DIR/export.sql")
    duckdb "$WORK_DIR/tmp.duckdb" -c "$sql" > /dev/null || plugin_fail "DuckDB-Export fehlgeschlagen."
    plugin_report < "$WORK_DIR/homonyms.tsv"
    plugin_log "$(( $(wc -l < "$WORK_DIR/match_input.tsv") - 1 )) Taxa zum Abgleich, $(wc -l < "$WORK_DIR/homonyms.tsv" | tr -d ' ') Homonyme im Build-Bericht."
}

# Ersetzt alle iNaturalist-Zuordnungen in einer Transaktion. entity_type und
# die Namensschlüssel höherer Taxa sind die, die die App abfragt.
#
# Arten werden nur bei matched zugeordnet. Höhere Taxa adressiert die App über
# den Namensschlüssel, den alle gleichnamigen Zeilen einer Rangtabelle teilen
# (FishBase führt etwa Gobio viermal, drei davon ohne Arten). Für den
# Schlüssel zählt deshalb nur, ob der Name auf dem Rang vorkommt: Auch
# ambiguous wegen mehrerer gleichnamiger Zeilen ergibt eine Zuordnung. Andere
# Gründe für ambiguous gibt es bei höheren Taxa nicht, weil Homonyme auf
# iNaturalist-Seite schon vor dem Abgleich herausfallen. Der Build-Bericht
# führt die gleichnamigen Zeilen trotzdem auf.
import_mappings() {
    local synced_at
    synced_at="$(date -u +%Y-%m-%d)"
    plugin_log "Importiere Zuordnungen in entity_external_ids..."
    sqlite3 "$DB_PATH" << EOF || plugin_fail "SQLite-Import fehlgeschlagen."
.bail on
.mode ascii
.separator "\t" "\n"
CREATE TEMP TABLE tmp_match_result (
    record_key TEXT, rank TEXT, name TEXT, entity_id TEXT,
    status TEXT, matched_by TEXT, detail TEXT
);
.import --skip 1 "$WORK_DIR/match_result.tsv" tmp_match_result
BEGIN;
DELETE FROM entity_external_ids WHERE provider = '${PLUGIN_SOURCE}';
INSERT INTO entity_external_ids (
    entity_id, entity_type, provider, external_id, last_synced_at, metadata_json
) SELECT
    CASE rank WHEN 'species' THEN entity_id ELSE rank || ':' || LOWER(TRIM(name)) END,
    CASE rank
        WHEN 'species' THEN 'species'
        WHEN 'genus'   THEN 'genera'
        WHEN 'family'  THEN 'families'
        WHEN 'order'   THEN 'orders'
        WHEN 'class'   THEN 'classes'
    END,
    '${PLUGIN_SOURCE}', record_key, '${synced_at}', NULL
FROM tmp_match_result
WHERE status = 'matched'
   OR (rank != 'species' AND status = 'ambiguous');
COMMIT;
EOF
}

# ---------------------------------------------------------------------------
# Source-Metadaten schreiben
#
# Version ist das Datum der taxa.csv.gz (beim Download das des Servers).
# ---------------------------------------------------------------------------
write_source_metadata() {
    local data_version
    data_version="$(date -u -r "$TAXA_FILE" +%Y-%m-%d)"
    plugin_write_source_metadata "$DB_PATH" "$PLUGIN_SQL_DIR/source.sql" "$data_version"
}

validate() {
    plugin_validate_min_count \
        "$DB_PATH" \
        "entity_external_ids" \
        "provider='${PLUGIN_SOURCE}'" \
        1 \
        "iNaturalist-Zuordnungen"
    plugin_validate_source_entry_exists "$DB_PATH"
    plugin_log "iNaturalist-Zuordnungen OK: $(sqlite3 "$DB_PATH" \
        "SELECT COUNT(*) FROM entity_external_ids WHERE provider='${PLUGIN_SOURCE}';")"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
plugin_log "=== ${PLUGIN_NAME} Import ==="
plugin_log "Taxa: $TAXA_FILE"
plugin_log "DB  : $DB_PATH"

check_deps
if [[ "$DOWNLOAD" == true ]]; then
    download_taxa
fi
check_taxa_file
export_reference_names
export_records
match_records "$DB_PATH" "$WORK_DIR/match_input.tsv" "$WORK_DIR/match_result.tsv"
import_mappings
write_source_metadata
validate

plugin_log "=== ${PLUGIN_NAME} Import abgeschlossen ==="
