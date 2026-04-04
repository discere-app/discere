#!/usr/bin/env bash
# =============================================================================
# build.sh — Orchestrator
#
# Koordiniert create_db.sh und alle Plugin-Scripts in expliziten Stages.
# Neue Datenquellen: Plugin-Script in plugins/<n>/import.sh ablegen,
# dann mit --plugin <n> einbinden.
#
# Usage:
#   ./build.sh                                   # alle Plugins auto-discover, download + cleanup
#   ./build.sh --plugin fishbase --download      # nur fishbase, explizit
#   ./build.sh --plugin fishbase --keep          # parquets behalten
#   ./build.sh --output /tmp/discere.db        # eigener Output-Pfad
#
# Wird build.sh ohne --plugin aufgerufen, werden alle plugins/<n>/import.sh
# automatisch gefunden und ausgeführt. Ohne weitere Flags gilt für jedes
# Plugin der Default: Daten herunterladen und nach dem Import wieder löschen.
#
# Flags:
#   --output <path>          Ziel-Datenbank
#   --force                  Bestehende DB überschreiben
#   --plugin <n>             Plugin explizit angeben (wiederholbar)
#                            Ohne diesen Flag: alle Plugins in plugins/ werden verwendet
#   --download               An alle Plugins weitergegeben
#   --keep                   Heruntergeladene Dateien behalten (an alle Plugins)
#   --version <v25.04>       An alle Plugins weitergegeben
#   --fishbase-dir <path>    An fishbase-Plugin weitergegeben
#   --no-download            Download deaktivieren (lokale Dateien verwenden)
#   --no-enrich              Enrichment-Stage überspringen
#
# Umgebungsvariablen:
#   OUTPUT_DB, FISHBASE_VERSION, FISHBASE_DIR
#
# Pipeline-Stages:
#   01 — Datenbank erstellen (create_db.sh)
#   02 — Plugins validieren + ausführen (validate_plugin.sh + plugins/<n>/import.sh)
#   03 — Enrichment          (enrichment/*/enrich.sh)
#   04 — FTS rebuild         (core/sql/rebuild_fts.sql)
#   05 — Validierung         (core/sql/validate.sql)
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$SCRIPT_DIR/core"
PLUGINS_DIR="$SCRIPT_DIR/plugins"
ENRICHMENT_DIR="$SCRIPT_DIR/enrichment"

OUTPUT_DB="${OUTPUT_DB:-../assets/database/discere_reference.db}"
FORCE=false
PLUGINS=()
PLUGIN_FLAGS=()
EXPLICIT_DOWNLOAD=false   # wurde --download oder --no-download explizit gesetzt?
NO_DOWNLOAD=false
SKIP_ENRICHMENT=false

# ---------------------------------------------------------------------------
# Argumente
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)        OUTPUT_DB="$2"; shift ;;
        --force)         FORCE=true ;;
        --plugin)        PLUGINS+=("$2"); shift ;;
        --download)      PLUGIN_FLAGS+=("--download"); EXPLICIT_DOWNLOAD=true ;;
        --no-download)   NO_DOWNLOAD=true; EXPLICIT_DOWNLOAD=true ;;
        --no-enrich)     SKIP_ENRICHMENT=true ;;
        --keep)          PLUGIN_FLAGS+=("--keep") ;;
        --version)       PLUGIN_FLAGS+=("--version" "$2"); shift ;;
        --fishbase-dir)  PLUGIN_FLAGS+=("--fishbase-dir" "$2"); shift ;;
        --help|-h)
            sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "[WARN] [build] Unbekanntes Argument: $1" >&2 ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[$(date '+%H:%M:%S')] [build] $*" >&2; }
fail() { echo "[ERROR] [build] $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Validierung via SQL
# Liest Zeilenzahlen aus validate.sql und prüft Mindestwerte.
# ---------------------------------------------------------------------------
run_validation() {
    local db="$1"
    log "Prüfe Zeilenzahlen und UUID-Format..."

    local failed=false
    while IFS='|' read -r tbl n min; do
        tbl=$(echo "$tbl" | tr -d ' ')
        n=$(echo "$n"   | tr -d ' ')
        min=$(echo "$min" | tr -d ' ')
        if [[ "$n" -lt "$min" ]]; then
            log "  FEHLER: $tbl — $n (erwartet >= $min)"
            failed=true
        else
            log "  $(printf '%-22s' "$tbl") $n"
        fi
    done < <(sqlite3 "$db" < "$CORE_DIR/sql/validate.sql")

    [[ "$failed" == false ]] || fail "Validierung fehlgeschlagen — DB wird nicht verwendet."
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
# Auto-discover: wenn kein --plugin angegeben, alle plugins/<n>/import.sh verwenden
if [[ ${#PLUGINS[@]} -eq 0 ]]; then
    while IFS= read -r -d '' plugin_dir; do
        plugin_name="$(basename "$plugin_dir")"
        # _template überspringen
        [[ "$plugin_name" == _* ]] && continue
        [[ -f "$plugin_dir/import.sh" ]] && PLUGINS+=("$plugin_name")
    done < <(find "$PLUGINS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
    [[ ${#PLUGINS[@]} -gt 0 ]] || fail "Keine Plugins in $PLUGINS_DIR gefunden."
fi

# Default: --download wenn weder --download noch --no-download explizit gesetzt
if [[ "$EXPLICIT_DOWNLOAD" == false ]]; then
    PLUGIN_FLAGS+=("--download")
    log "Kein --download/--no-download angegeben — Default: --download (cleanup nach Import)"
fi

log "=== Discere Build ==="
log "Output  : $OUTPUT_DB"
log "Plugins : ${PLUGINS[*]}"
[[ ${#PLUGIN_FLAGS[@]} -gt 0 ]] && log "Flags   : ${PLUGIN_FLAGS[*]}"

# ---------------------------------------------------------------------------
# Stage 01 — Datenbank erstellen
# ---------------------------------------------------------------------------
log "--- Stage 01: Datenbank erstellen ---"
FORCE_FLAG=()
[[ "$FORCE" == true ]] && FORCE_FLAG=("--force")

DB_PATH=$(OUTPUT_DB="$OUTPUT_DB" "$CORE_DIR/create_db.sh" \
    --output "$OUTPUT_DB" "${FORCE_FLAG[@]+"${FORCE_FLAG[@]}"}")
log "Datenbank bereit: $DB_PATH"

# ---------------------------------------------------------------------------
# Stage 02 — Plugins validieren + ausführen
# ---------------------------------------------------------------------------
log "--- Stage 02: Plugins ---"
for plugin in "${PLUGINS[@]}"; do
    log "Plugin: $plugin"
    plugin_dir="$PLUGINS_DIR/$plugin"
    plugin_script="$plugin_dir/import.sh"

    # Struktur-Validierung vor Ausführung
    "$CORE_DIR/validate_plugin.sh" "$plugin_dir" \
        || fail "Plugin '$plugin' hat ungültige Struktur — Build abgebrochen."

    "$plugin_script" --db "$DB_PATH" "${PLUGIN_FLAGS[@]+"${PLUGIN_FLAGS[@]}"}"
done

# ---------------------------------------------------------------------------
# Stage 03 — Enrichment (nach allen Plugins, vor FTS rebuild)
# ---------------------------------------------------------------------------
log "--- Stage 03: Enrichment ---"
if [[ "$SKIP_ENRICHMENT" == true ]]; then
    log "Enrichment übersprungen (--no-enrich)."
elif [[ -d "$ENRICHMENT_DIR" ]]; then
    while IFS= read -r -d '' enrich_script; do
        enrich_name="$(basename "$(dirname "$enrich_script")")"
        log "Enrichment: $enrich_name"
        "$enrich_script" --db "$DB_PATH" \
            "${PLUGIN_FLAGS[@]+"${PLUGIN_FLAGS[@]}"}"
    done < <(find "$ENRICHMENT_DIR" -name "enrich.sh" -print0 | sort -z)
else
    log "Kein enrichment/ Verzeichnis gefunden — übersprungen."
fi

# ---------------------------------------------------------------------------
# Stage 04 — FTS rebuild (nach Plugins + Enrichment)
# ---------------------------------------------------------------------------
log "--- Stage 04: FTS rebuild ---"
sqlite3 "$DB_PATH" < "$CORE_DIR/sql/rebuild_fts.sql" || fail "FTS rebuild fehlgeschlagen."

# ---------------------------------------------------------------------------
# Stage 05 — Validierung
# ---------------------------------------------------------------------------
log "--- Stage 05: Validierung ---"
run_validation "$DB_PATH"

log "=== Build abgeschlossen: $DB_PATH ==="
