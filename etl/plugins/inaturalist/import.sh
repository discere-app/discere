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
# aktiver Arten samt Synonymen, höhere Taxa über ihre Rangtabelle. Vorher
# fallen iNaturalist-Taxa heraus, die nicht zur eigenen Kette jeder Entität
# ihres Namens passen (sql/export.sql). Höhere Taxa werden unter ihrem
# Namensschlüssel abgelegt (genus:barbus), den die App abfragt, Arten unter
# ihrer ID. Was nicht eindeutig zuzuordnen ist oder abgelehnt wird, steht im
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
            plugin_print_help_from_header "$0" 2 32
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

# Alle Namen, die der Abgleich treffen kann, mit jeder Entität, die sie
# trägt, und ihrer Kette (sql/reference_names.sql). export.sql
# grenzt die iNaturalist-Taxa damit auf die ein, die überhaupt in Frage
# kommen, und prüft sie gegen die Kette jeder dieser Entitäten.
export_reference_names() {
    plugin_log "Exportiere Namen der Referenz-DB..."
    {
        printf 'rank\tnormalized_name\tentity_id\tchain_phylum\tchain_class\tchain_order\tchain_family\n'
        sqlite3 -separator $'\t' "$DB_PATH" < "$PLUGIN_SQL_DIR/reference_names.sql"
    } > "$WORK_DIR/reference_names.tsv" || plugin_fail "Export der Namen fehlgeschlagen."
}

export_records() {
    plugin_log "Lese iNaturalist-Taxa..."
    local sql
    sql=$(sed \
        -e "s|\${TAXA_FILE}|${TAXA_FILE}|g" \
        -e "s|\${REFERENCE_NAMES}|${WORK_DIR}/reference_names.tsv|g" \
        -e "s|\${PHYLUM_EQUIVALENTS}|${PLUGIN_DIR}/data/phylum_equivalents.csv|g" \
        -e "s|\${CLASS_EQUIVALENTS}|${PLUGIN_DIR}/data/class_equivalents.csv|g" \
        -e "s|\${PLACEHOLDER_PATTERNS}|${PLUGIN_CORE_DIR}/data/placeholder_patterns.csv|g" \
        -e "s|\${EXPORT_DIR}|${WORK_DIR}|g" \
        "$PLUGIN_SQL_DIR/export.sql")
    duckdb "$WORK_DIR/tmp.duckdb" -c "$sql" > /dev/null || plugin_fail "DuckDB-Export fehlgeschlagen."
    plugin_report < "$WORK_DIR/report.tsv"
    plugin_log "$(( $(wc -l < "$WORK_DIR/match_input.tsv") - 1 )) Taxa zum Abgleich. Abgelehnt:" \
        "$(cut -f1 "$WORK_DIR/report.tsv" | sort | uniq -c | awk '{ printf "%s %s, ", $2, $1 }')"
}

# Ersetzt alle iNaturalist-Zuordnungen in einer Transaktion. entity_type und
# die Namensschlüssel höherer Taxa sind die, die die App abfragt.
#
# Arten werden nur bei matched zugeordnet, über ein Synonym nur, wenn die
# Familie des iNaturalist-Taxons gleich der eigenen ist und das Epitheton
# des Synonyms in den ersten vier Buchstaben dem der Art gleicht (ohne
# Leerzeichen am Rand, klein geschrieben; so gehen Genusangleichungen wie
# pulcher/pulchra und Schreibvarianten wie leeorum/leei durch): SeaLifeBase
# führt Synonyme, die anderen Arten gehören — auch aus anderen Familien (der
# Kappensäger trägt den Namen einer Möwe), auch aus derselben (Mactra mera
# das Synonym Mactra antiquata). Abgelehnte stehen als synonym_family bzw.
# synonym_epithet im Build-Bericht.
#
# Höhere Taxa adressiert die App über den Namensschlüssel, den alle
# gleichnamigen Zeilen einer Rangtabelle teilen (FishBase führt etwa Gobio
# viermal, drei davon ohne Arten). Auch ambiguous wegen mehrerer
# gleichnamiger Zeilen ergibt deshalb eine Zuordnung: Ein Taxon kommt nur in
# den Abgleich, wenn es zu jeder dieser Zeilen passt (export.sql). Andere
# Gründe für ambiguous gibt es bei höheren Taxa nicht, weil Homonyme auf
# iNaturalist-Seite schon vor dem Abgleich herausfallen. Der Build-Bericht
# führt die gleichnamigen Zeilen trotzdem auf.
#
# metadata_json hält fest, wogegen geprüft wurde: Stamm, Klasse, Ordnung und
# Familie des iNaturalist-Taxons, ob es über ein Synonym zugeordnet wurde und
# ob sein Name bei iNaturalist mehrere Taxa trägt. validate() prüft damit
# jede Zuordnung erneut, unabhängig von export.sql.
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
CREATE TEMP TABLE tmp_lineage (
    record_key TEXT PRIMARY KEY, phylum TEXT, class TEXT, "order" TEXT, family TEXT, homonym INTEGER
);
.import --skip 1 "$WORK_DIR/lineage.tsv" tmp_lineage
CREATE TEMP TABLE tmp_accepted AS
SELECT r.*, NULLIF(l.phylum, '') AS phylum, NULLIF(l.class, '') AS class,
       NULLIF(l."order", '') AS "order", NULLIF(l.family, '') AS family, l.homonym,
       (SELECT f.name FROM species s
        JOIN genera g ON g.id = s.genus
        JOIN families f ON f.id = g.family
        WHERE s.id = r.entity_id) AS own_family,
       (SELECT LOWER(TRIM(s.name)) FROM species s WHERE s.id = r.entity_id) AS own_epithet,
       LOWER(TRIM(substr(TRIM(r.name), instr(TRIM(r.name), ' ') + 1))) AS name_rest
FROM tmp_match_result r
JOIN tmp_lineage l ON l.record_key = r.record_key
WHERE r.status = 'matched'
   OR (r.rank != 'species' AND r.status = 'ambiguous');
CREATE TEMP TABLE tmp_rejected AS
SELECT record_key, name, entity_id,
       CASE
           WHEN family IS NULL OR own_family IS NULL OR LOWER(TRIM(own_family)) != LOWER(family)
           THEN 'synonym_family'
           ELSE 'synonym_epithet'
       END AS category,
       CASE
           WHEN family IS NULL OR own_family IS NULL OR LOWER(TRIM(own_family)) != LOWER(family)
           THEN 'iNaturalist-Familie: ' || COALESCE(family, '-') || '; Familie von ' || entity_id
                || ': ' || COALESCE(own_family, '-')
           ELSE 'Epitheton von ' || entity_id || ': ' || COALESCE(own_epithet, '-')
       END AS detail
FROM tmp_accepted
WHERE matched_by = 'synonym'
  AND (family IS NULL OR own_family IS NULL OR LOWER(TRIM(own_family)) != LOWER(family)
       OR own_epithet IS NULL
       OR substr(CASE WHEN instr(name_rest, ' ') > 0
                      THEN substr(name_rest, 1, instr(name_rest, ' ') - 1)
                      ELSE name_rest END, 1, 4) != substr(own_epithet, 1, 4));
.mode tabs
.once "$WORK_DIR/synonym_report.tsv"
SELECT category, record_key, name, detail FROM tmp_rejected ORDER BY category, name, record_key;
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
    '${PLUGIN_SOURCE}', record_key, '${synced_at}',
    json_object('phylum', phylum, 'class', class, 'order', "order", 'family', family,
                'matched_by', NULLIF(matched_by, ''), 'homonym', homonym)
FROM tmp_accepted
WHERE record_key NOT IN (SELECT record_key FROM tmp_rejected);
COMMIT;
EOF
    plugin_report < "$WORK_DIR/synonym_report.tsv"
    plugin_log "Synonym-Treffer abgelehnt, andere Familie: $(grep -c '^synonym_family' "$WORK_DIR/synonym_report.tsv" || true)," \
        "anderes Epitheton: $(grep -c '^synonym_epithet' "$WORK_DIR/synonym_report.tsv" || true)"
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

# Prüft jede Zuordnung erneut gegen die Kette, mit eigener SQL
# (sql/validate_mappings.sql), die die iNaturalist-Kette selbst aus
# taxa.csv ableitet statt export.sql zu vertrauen: Ein Fehler in der Prüfung
# oder der Ableitung des Exports ließe sonst falsche Zuordnungen still durch.
validate() {
    plugin_validate_min_count \
        "$DB_PATH" \
        "entity_external_ids" \
        "provider='${PLUGIN_SOURCE}'" \
        1 \
        "iNaturalist-Zuordnungen"
    plugin_validate_source_entry_exists "$DB_PATH"
    local violations
    gunzip -c "$TAXA_FILE" > "$WORK_DIR/taxa.tsv" || plugin_fail "taxa.csv.gz nicht lesbar."
    violations="$(sed \
        -e "s|\${TAXA_TSV}|${WORK_DIR}/taxa.tsv|g" \
        -e "s|\${PHYLUM_EQUIVALENTS}|${PLUGIN_DIR}/data/phylum_equivalents.csv|g" \
        -e "s|\${CLASS_EQUIVALENTS}|${PLUGIN_DIR}/data/class_equivalents.csv|g" \
        -e "s|\${PLACEHOLDER_PATTERNS}|${PLUGIN_CORE_DIR}/data/placeholder_patterns.csv|g" \
        "$PLUGIN_SQL_DIR/validate_mappings.sql" | sqlite3 -bail "$DB_PATH")" \
        || plugin_fail "Prüfung der Zuordnungen fehlgeschlagen."
    if [[ -n "$violations" ]]; then
        plugin_fail "Zuordnungen passen nicht zur Kette ($(printf '%s\n' "$violations" | wc -l | tr -d ' ')):"$'\n'"$(printf '%s\n' "$violations" | head -20)"
    fi
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
