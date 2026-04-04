#!/usr/bin/env bash
# =============================================================================
# enrich.sh — iNaturalist Taxon ID Mapping
#
# Lädt taxa.csv von iNaturalist AWS Open Data, matched auf bestehende
# Species (via wissenschaftlichem Namen) und schreibt das taxon_id-Mapping
# in inat_taxon_ids.
#
# Wird von build.sh nach allen Plugins aufgerufen (Stage 03).
# Kein CREATE TABLE — Schema ist Aufgabe von core/create_db.sh.
#
# Usage:
#   ./enrichment/inaturalist/enrich.sh --db /path/to/discere.db
#   ./enrichment/inaturalist/enrich.sh --db /path/to/discere.db --no-download
#
# Flags:
#   --db <path>        Ziel-Datenbank (Pflichtfeld)
#   --download         taxa.csv von AWS S3 herunterladen (Default)
#   --no-download      Lokale Datei verwenden
#   --keep             taxa.csv nach dem Enrichment behalten
#   --taxa-file <path> Lokale taxa.csv.gz (überschreibt Download)
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SQL_DIR="$SCRIPT_DIR/sql"
WORK_DIR="$(mktemp -d)"

DB_PATH="${DB_PATH:-}"
DOWNLOAD=true
KEEP_FILES=false
TAXA_FILE="${TAXA_FILE:-}"

TAXA_URL="https://inaturalist-open-data.s3.amazonaws.com/taxa.csv.gz"
TAXA_LOCAL="${TAXA_FILE:-${SCRIPT_DIR}/cache/taxa.csv.gz}"

# ---------------------------------------------------------------------------
# Argumente
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)           DB_PATH="$2"; shift ;;
        --download)     DOWNLOAD=true ;;
        --no-download)  DOWNLOAD=false ;;
        --keep)         KEEP_FILES=true ;;
        --taxa-file)    TAXA_LOCAL="$2"; DOWNLOAD=false; shift ;;
        --help|-h)
            sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "[WARN] [inat-enrich] Unbekanntes Argument: $1" >&2 ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[$(date '+%H:%M:%S')] [inat-enrich] $*" >&2; }
fail() { echo "[ERROR] [inat-enrich] $*" >&2; exit 1; }

cleanup() {
    rm -rf "$WORK_DIR"
    if [[ "$KEEP_FILES" == false && -f "$TAXA_LOCAL" && "$DOWNLOAD" == true ]]; then
        log "Lösche taxa.csv.gz: $TAXA_LOCAL"
        rm -f "$TAXA_LOCAL"
    fi
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Deps
# ---------------------------------------------------------------------------
check_deps() {
    [[ -n "$DB_PATH" ]] || fail "--db ist ein Pflichtfeld."
    [[ -f "$DB_PATH" ]] || fail "Datenbank nicht gefunden: $DB_PATH"
    command -v duckdb  >/dev/null 2>&1 || fail "duckdb nicht gefunden."
    command -v sqlite3 >/dev/null 2>&1 || fail "sqlite3 nicht gefunden."
    [[ "$DOWNLOAD" == true ]] && { command -v curl >/dev/null 2>&1 || fail "curl nicht gefunden."; }
}

# ---------------------------------------------------------------------------
# Download
# ---------------------------------------------------------------------------
download_taxa() {
    if [[ -f "$TAXA_LOCAL" ]]; then
        log "taxa.csv.gz bereits vorhanden: $TAXA_LOCAL"
        return
    fi
    mkdir -p "$(dirname "$TAXA_LOCAL")"
    log "Lade taxa.csv.gz (~50MB) von AWS..."
    log "URL: $TAXA_URL"
    curl --location --fail --progress-bar \
         --output "$TAXA_LOCAL" \
         "$TAXA_URL" \
    || fail "Download von taxa.csv.gz fehlgeschlagen."
    log "Download abgeschlossen."
}

# ---------------------------------------------------------------------------
# Entpacken
# ---------------------------------------------------------------------------
extract_taxa() {
    log "Entpacke taxa.csv.gz..."
    local taxa_csv="${WORK_DIR}/taxa.csv"
    gunzip --keep --stdout "$TAXA_LOCAL" > "$taxa_csv" \
    || fail "Entpacken von taxa.csv.gz fehlgeschlagen."
    echo "$taxa_csv"
}

# ---------------------------------------------------------------------------
# Species-Namen aus DB exportieren
# ---------------------------------------------------------------------------
export_species_names() {
    log "Exportiere Species-Namen aus DB..."
    local species_csv="${WORK_DIR}/species.csv"
    sqlite3 -separator $'\t' "$DB_PATH" \
        "SELECT id AS species_id, name FROM species WHERE status = 'active';" \
    > "$species_csv" \
    || fail "Species-Export fehlgeschlagen."

    local tmp="${WORK_DIR}/species_header.csv"
    echo -e "species_id\tname" | cat - "$species_csv" > "$tmp"
    mv "$tmp" "$species_csv"

    local count
    count=$(wc -l < "$species_csv")
    log "$(( count - 1 )) aktive Species exportiert."
    echo "$species_csv"
}

# ---------------------------------------------------------------------------
# DuckDB: Taxon-ID-Mapping erstellen
# ---------------------------------------------------------------------------
run_duckdb() {
    local taxa_csv="$1"
    local species_csv="$2"
    log "Erstelle Taxon-ID-Mapping via DuckDB..."

    local sql
    sql=$(sed \
        -e "s|\${TAXA_CSV}|${taxa_csv}|g" \
        -e "s|\${SPECIES_CSV}|${species_csv}|g" \
        -e "s|\${EXPORT_DIR}|${WORK_DIR}|g" \
        "$SQL_DIR/enrich.sql")

    duckdb "${WORK_DIR}/tmp.duckdb" -c "$sql" \
    || fail "DuckDB-Enrichment fehlgeschlagen."

    [[ -f "${WORK_DIR}/inat_taxon_ids.csv" ]] \
    || fail "inat_taxon_ids.csv wurde nicht generiert."

    local count
    count=$(wc -l < "${WORK_DIR}/inat_taxon_ids.csv")
    log "$(( count - 1 )) Taxon-ID-Mappings extrahiert."
}

# ---------------------------------------------------------------------------
# SQLite Import
# ---------------------------------------------------------------------------
import_to_sqlite() {
    log "Importiere inat_taxon_ids in DB..."

    sqlite3 "$DB_PATH" \
        "DELETE FROM inat_taxon_ids;" \
    || fail "Löschen alter Taxon-IDs fehlgeschlagen."

    sqlite3 "$DB_PATH" << EOF
PRAGMA foreign_keys = OFF;
.mode csv
CREATE TEMP TABLE tmp_inat_taxon_ids (
    species_id TEXT,
    taxon_id   INTEGER
);
.import --skip 1 ${WORK_DIR}/inat_taxon_ids.csv tmp_inat_taxon_ids
INSERT OR IGNORE INTO inat_taxon_ids SELECT * FROM tmp_inat_taxon_ids;
PRAGMA foreign_keys = ON;
EOF

    local count
    count=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM inat_taxon_ids;")
    log "Importiert: $count inat_taxon_ids Einträge."
}

# ---------------------------------------------------------------------------
# Metadata
# ---------------------------------------------------------------------------
write_metadata() {
    local today
    today="$(date -u +%Y-%m-%d)"
    sqlite3 "$DB_PATH" \
        "INSERT INTO metadata (key, value) VALUES ('inaturalist_enrichment', '$today')
         ON CONFLICT (key) DO UPDATE SET value = excluded.value;" \
    || fail "metadata-Eintrag fehlgeschlagen."
    log "Metadata: inaturalist_enrichment = $today"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log "=== iNaturalist Taxon ID Mapping ==="
log "DB: $DB_PATH"

check_deps
[[ "$DOWNLOAD" == true ]] && download_taxa
taxa_csv=$(extract_taxa)
species_csv=$(export_species_names)
run_duckdb "$taxa_csv" "$species_csv"
import_to_sqlite
write_metadata

log "=== iNaturalist Enrichment abgeschlossen ==="