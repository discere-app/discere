#!/usr/bin/env bash
# =============================================================================
# build.sh — Orchestrator
#
# Koordiniert create_db.sh und alle Plugin-Scripts in expliziten Stages.
# Neue Datenquellen: Plugin-Script in plugins/<n>/import.sh ablegen,
# dann mit --plugin <n> einbinden. Welche Plugins in welcher Reihenfolge
# laufen, bestimmt core/plugin_order.sh aus depends_on_sources.
#
# Usage:
#   ./build.sh                                   # alle Plugins auto-discover, download + cleanup
#   ./build.sh --plugin fishbase --download      # nur fishbase, explizit
#   ./build.sh --plugin fishbase --keep          # parquets behalten
#   ./build.sh --output /tmp/discere.db        # eigener Output-Pfad
#
# Wird build.sh ohne --plugin aufgerufen, werden alle plugins/<n>/import.sh
# automatisch gefunden und ausgeführt; mit --plugin laufen die genannten samt
# ihren Abhängigkeiten. Ohne weitere Flags gilt für jedes Plugin der Default:
# Daten herunterladen und nach dem Import wieder löschen.
#
# Flags:
#   --output <path>          Ziel-Datenbank
#   --force                  Bestehende DB überschreiben
#   --plugin <n>             Plugin explizit angeben (wiederholbar), Abhängigkeiten
#                            kommen mit. Ohne diesen Flag: alle Plugins in plugins/
#   --download               An alle Plugins weitergegeben
#   --keep                   Heruntergeladene Dateien behalten (an alle Plugins)
#   --version <v26.06>       An alle Plugins weitergegeben
#   --fishbase-dir <path>    An fishbase-Plugin weitergegeben
#   --no-download            Download deaktivieren (lokale Dateien verwenden)
#   --no-enrich              Stage 01b und optionale Plugins (samt Abhängigen)
#                            überspringen, etwa inaturalist
#   --previous-release <db>  Lokale Referenz-DB als Vorgänger statt des
#                            veröffentlichten Releases
#   --initial                Ohne Vorgänger bauen, alle IDs neu vergeben —
#                            nur für Tests und einen allerersten Build
#   --accept-species-loss <quelle>
#                            Einbruch der Arten einer Quelle hinnehmen
#                            (core/identity.sh, wiederholbar) — nur zum
#                            Testen, der Build ist dann nicht veröffentlichbar
#
# Umgebungsvariablen:
#   OUTPUT_DB, FISHBASE_VERSION, FISHBASE_DIR
#   DISCERE_RELEASE_MANIFEST_URL  Manifest des Vorgängers (core/previous_release.sh)
#
# Pipeline-Stages:
#   00 — Plugins validieren + ordnen (core/plugin_order.sh)
#   00b — Vorgänger-Release bereitstellen (core/previous_release.sh)
#   01 — Datenbank erstellen (create_db.sh)
#   01b — Locale Place Mappings (core/seed_locale_place_mappings.sh)
#   02 — Quellen mit Entitäten (placement_priority) ausführen (plugins/<n>/import.sh)
#   02b — Identität: endgültige IDs, Register, Aliase (core/identity.sh)
#   02c — Ergänzende Quellen ausführen (plugins/<n>/import.sh)
#   02d — Rang-Platzhalter markieren (core/placeholders.sh)
#   03 — Species Name Lookup (core/sql/rebuild_lookup.sql)
#   04 — FTS rebuild         (core/sql/rebuild_fts.sql)
#   05 — Validierung         (core/check_references.sh, core/validate.sh)
#
# Build-Bericht: <output ohne Endung>.build-report/ — je Quelle eine TSV mit
# dem, was sie nicht zuordnen konnte (plugin_report in core/plugin_api.sh),
# dazu die Rang-Platzhalter aus Stage 02d (placeholders.tsv).
# Die Zusammenfassung steht im Log vor Stage 05.
#
# Build-Vermerk in metadata: build_scope (complete, oder incomplete: <Gründe>),
# build_previous_version/build_previous_sha256 (Vorgänger laut Manifest) und
# build_validated. Vollständig ist ein Build mit allen Plugins, ohne
# --no-enrich, --initial und --accept-species-loss, gegen das veröffentlichte
# Release (nicht --previous-release). Nur ein solcher, validierter Build lässt sich mit
# publish_release.sh veröffentlichen (core/check_publishable.sh). Die Validierung
# prüft Mindestzahlen nur für die Plugins und Stages, die der Build ausgeführt
# hat, Invarianten immer — validiert ist deshalb auch ein Teilbuild.
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORE_DIR="$SCRIPT_DIR/core"
PLUGINS_DIR="$SCRIPT_DIR/plugins"

OUTPUT_DB="${OUTPUT_DB:-$SCRIPT_DIR/../assets/database/discere_reference.db}"
FORCE=false
SELECTED_PLUGINS=()
PLUGINS=()
ENTITY_PLUGINS=()
CONTRIBUTING_PLUGINS=()
PLUGIN_FLAGS=()
EXPLICIT_DOWNLOAD=false   # wurde --download oder --no-download explizit gesetzt?
NO_DOWNLOAD=false
SKIP_ENRICHMENT=false
PREVIOUS_RELEASE=""
INITIAL=false
ACCEPTED_LOSS=()

# ---------------------------------------------------------------------------
# Argumente
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --output)        OUTPUT_DB="$2"; shift ;;
        --force)         FORCE=true ;;
        --plugin)        SELECTED_PLUGINS+=("$2"); shift ;;
        --download)      PLUGIN_FLAGS+=("--download"); EXPLICIT_DOWNLOAD=true ;;
        --no-download)   NO_DOWNLOAD=true; EXPLICIT_DOWNLOAD=true ;;
        --no-enrich)     SKIP_ENRICHMENT=true ;;
        --keep)          PLUGIN_FLAGS+=("--keep") ;;
        --version)       PLUGIN_FLAGS+=("--version" "$2"); shift ;;
        --fishbase-dir)  PLUGIN_FLAGS+=("--fishbase-dir" "$2"); shift ;;
        --previous-release) PREVIOUS_RELEASE="$2"; shift ;;
        --initial)       INITIAL=true ;;
        --accept-species-loss) ACCEPTED_LOSS+=("$2"); shift ;;
        --help|-h)
            sed -n '2,72p' "$0" | sed 's/^# \{0,1\}//'
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

# shellcheck source=./core/plugin_api.sh
source "$CORE_DIR/plugin_api.sh"

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
# ---------------------------------------------------------------------------
# Stage 00 — Plugins validieren + ordnen
# Vor Stage 01, damit ein ungültiges Plugin oder ein Zyklus keine bestehende
# DB löscht (--force).
# ---------------------------------------------------------------------------
log "--- Stage 00: Plugins validieren + ordnen ---"
( PLUGIN_SOURCE=build; plugin_require_sqlite_version ) || fail "Build abgebrochen."
ORDER_FLAGS=()
[[ "$SKIP_ENRICHMENT" == true ]] && ORDER_FLAGS=("--no-enrich")

PLUGIN_ORDER="$("$CORE_DIR/plugin_order.sh" --plugins-dir "$PLUGINS_DIR" --groups \
    "${ORDER_FLAGS[@]+"${ORDER_FLAGS[@]}"}" \
    "${SELECTED_PLUGINS[@]+"${SELECTED_PLUGINS[@]}"}")" \
    || fail "Plugins konnten nicht geordnet werden — Build abgebrochen."
while read -r group plugin; do
    case "$group" in
        existence)    ENTITY_PLUGINS+=("$plugin") ;;
        contribution) CONTRIBUTING_PLUGINS+=("$plugin") ;;
        *) continue ;;
    esac
    PLUGINS+=("$plugin")
done <<< "$PLUGIN_ORDER"
[[ ${#PLUGINS[@]} -gt 0 ]] || fail "Keine Plugins auszuführen."

# Vollständig ist ein Build, der alle Plugins ausführt, gegen das
# veröffentlichte Release als Vorgänger. Nur aus einem solchen entsteht ein
# Release (core/check_publishable.sh); die Gründe dagegen landen in metadata.
INCOMPLETE_REASONS=()
ALL_PLUGINS="$("$CORE_DIR/plugin_order.sh" --plugins-dir "$PLUGINS_DIR" 2> /dev/null)" \
    || fail "Plugins konnten nicht geordnet werden — Build abgebrochen."
for plugin in $ALL_PLUGINS; do
    if [[ " ${PLUGINS[*]} " != *" $plugin "* ]]; then
        INCOMPLETE_REASONS+=("ohne Plugin $plugin")
    fi
done
[[ "$SKIP_ENRICHMENT" == true ]] && INCOMPLETE_REASONS+=("--no-enrich")
[[ "$INITIAL" == true ]] && INCOMPLETE_REASONS+=("--initial")
for source in ${ACCEPTED_LOSS[@]+"${ACCEPTED_LOSS[@]}"}; do
    INCOMPLETE_REASONS+=("--accept-species-loss $source")
done
# Eine Quelle mit Entitäten, die dieser Teilbuild nicht ausführt, fehlt
# absichtlich; die Identitäts-Stage soll das nicht als Einbruch werten.
SKIPPED_ENTITY_SOURCES=()
while read -r group plugin; do
    if [[ "$group" == existence && " ${PLUGINS[*]} " != *" $plugin "* ]]; then
        SKIPPED_ENTITY_SOURCES+=("$plugin")
    fi
done < <("$CORE_DIR/plugin_order.sh" --plugins-dir "$PLUGINS_DIR" --groups 2> /dev/null)
[[ -n "$PREVIOUS_RELEASE" ]] && INCOMPLETE_REASONS+=("lokaler Vorgänger (--previous-release)")

# ---------------------------------------------------------------------------
# Stage 00b — Vorgänger-Release
# Vor Stage 01: Ohne Vorgänger würden alle IDs neu vergeben und die Lernstände
# der Nutzer zeigten ins Leere. Der Build bricht dann ab, bevor er eine
# bestehende DB löscht — außer mit ausdrücklichem --initial.
# ---------------------------------------------------------------------------
log "--- Stage 00b: Vorgänger-Release ---"
IDENTITY_FLAGS=()
if [[ "$INITIAL" == true ]]; then
    [[ -z "$PREVIOUS_RELEASE" ]] || fail "--initial und --previous-release schließen sich aus."
    log "WARNUNG: --initial — ohne Vorgänger, alle IDs werden neu vergeben. Nur für Tests und einen allerersten Build."
    IDENTITY_FLAGS=("--initial")
else
    PREVIOUS_FLAGS=()
    [[ -n "$PREVIOUS_RELEASE" ]] && PREVIOUS_FLAGS=("--path" "$PREVIOUS_RELEASE")
    PREVIOUS_DB="$("$CORE_DIR/previous_release.sh" "${PREVIOUS_FLAGS[@]+"${PREVIOUS_FLAGS[@]}"}")" \
        || fail "Kein gültiges Vorgänger-Release — Build abgebrochen (--previous-release <db> oder ausdrücklich --initial)."
    log "Vorgänger: $PREVIOUS_DB"
    IDENTITY_FLAGS=("--previous-release" "$PREVIOUS_DB")
    for source in ${ACCEPTED_LOSS[@]+"${ACCEPTED_LOSS[@]}"} ${SKIPPED_ENTITY_SOURCES[@]+"${SKIPPED_ENTITY_SOURCES[@]}"}; do
        IDENTITY_FLAGS+=("--accept-species-loss" "$source")
    done
    if [[ ${#SKIPPED_ENTITY_SOURCES[@]} -gt 0 ]]; then
        log "Teilbuild: Rückgang angenommen für nicht ausgeführte Quellen: ${SKIPPED_ENTITY_SOURCES[*]}"
    fi
    PREVIOUS_MANIFEST="$(dirname "$PREVIOUS_DB")/manifest.json"
    if [[ -z "$PREVIOUS_RELEASE" ]]; then
        PREVIOUS_VERSION="$(jq -er '.version' "$PREVIOUS_MANIFEST")" \
            || fail "Manifest des Vorgängers ohne version: $PREVIOUS_MANIFEST"
        PREVIOUS_SHA256="$(jq -er '.sha256' "$PREVIOUS_MANIFEST")" \
            || fail "Manifest des Vorgängers ohne sha256: $PREVIOUS_MANIFEST"
    fi
fi

# Default: --download wenn weder --download noch --no-download explizit gesetzt
if [[ "$EXPLICIT_DOWNLOAD" == false ]]; then
    PLUGIN_FLAGS+=("--download")
    log "Kein --download/--no-download angegeben — Default: --download (cleanup nach Import)"
fi

log "=== Discere Build ==="
log "Output  : $OUTPUT_DB"
log "Plugins : ${ENTITY_PLUGINS[*]-} | Identität | ${CONTRIBUTING_PLUGINS[*]-} (in dieser Reihenfolge)"
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

# Schreibt einen Build-Vermerk in metadata (core/check_publishable.sh).
record_build() {
    local value=$2
    value=${value//\'/\'\'}
    sqlite3 "$DB_PATH" "INSERT OR REPLACE INTO metadata (key, value) VALUES ('$1', '$value');" \
        || fail "Build-Vermerk $1 fehlgeschlagen."
}
if [[ ${#INCOMPLETE_REASONS[@]} -eq 0 ]]; then
    record_build build_scope complete
else
    record_build build_scope "incomplete: $(IFS=,; echo "${INCOMPLETE_REASONS[*]}" | sed 's/,/, /g')"
    log "Kein vollständiger Build, nicht veröffentlichbar: ${INCOMPLETE_REASONS[*]}"
fi
if [[ -n "${PREVIOUS_VERSION:-}" ]]; then
    record_build build_previous_version "$PREVIOUS_VERSION"
    record_build build_previous_sha256 "$PREVIOUS_SHA256"
fi

# Der Build-Bericht gehört zu genau dieser DB und beginnt deshalb leer.
REPORT_DIR="${DB_PATH%.*}.build-report"
rm -rf "$REPORT_DIR"
mkdir -p "$REPORT_DIR"
export DISCERE_REPORT_DIR="$REPORT_DIR"
log "Build-Bericht: $REPORT_DIR"

# ---------------------------------------------------------------------------
# Stage 01b — Locale Place Mappings (iNat-API-Lookup, überspringbar mit --no-enrich)
# ---------------------------------------------------------------------------
log "--- Stage 01b: Locale Place Mappings ---"
if [[ "$SKIP_ENRICHMENT" == true ]]; then
    log "Übersprungen (--no-enrich)."
else
    "$CORE_DIR/seed_locale_place_mappings.sh" --db "$DB_PATH"
fi

run_plugins() {
    local plugin
    for plugin in "$@"; do
        log "Plugin: $plugin"
        "$PLUGINS_DIR/$plugin/import.sh" --db "$DB_PATH" "${PLUGIN_FLAGS[@]+"${PLUGIN_FLAGS[@]}"}"
    done
}

# ---------------------------------------------------------------------------
# Stage 02 — Quellen, die Entitäten liefern (placement_priority), mit
# vorläufigen IDs (validiert und geordnet in Stage 00)
# ---------------------------------------------------------------------------
log "--- Stage 02: Quellen mit Entitäten ---"
run_plugins ${ENTITY_PLUGINS[@]+"${ENTITY_PLUGINS[@]}"}

# ---------------------------------------------------------------------------
# Stage 02b — Identität: endgültige IDs, bevor ergänzende Quellen Beiträge
# daran hängen
# ---------------------------------------------------------------------------
log "--- Stage 02b: Identität ---"
"$CORE_DIR/identity.sh" --db "$DB_PATH" --plugins-dir "$PLUGINS_DIR" "${IDENTITY_FLAGS[@]}" \
    || fail "Identitäts-Stage fehlgeschlagen."

# ---------------------------------------------------------------------------
# Stage 02c — Ergänzende Quellen, auf den endgültigen IDs
# ---------------------------------------------------------------------------
log "--- Stage 02c: Ergänzende Quellen ---"
run_plugins ${CONTRIBUTING_PLUGINS[@]+"${CONTRIBUTING_PLUGINS[@]}"}

# ---------------------------------------------------------------------------
# Stage 02d — Rang-Platzhalter: eine Regel für alle Quellen, nach allen, die
# höhere Taxa liefern oder aus dem Vorgänger übernehmen
# ---------------------------------------------------------------------------
log "--- Stage 02d: Rang-Platzhalter ---"
"$CORE_DIR/placeholders.sh" --db "$DB_PATH" || fail "Rang-Platzhalter fehlgeschlagen."

# ---------------------------------------------------------------------------
# Stage 03 — Lookup-Tabelle materialisieren
# ---------------------------------------------------------------------------
log "--- Stage 03: Species Name Lookup ---"
sqlite3 "$DB_PATH" < "$CORE_DIR/sql/rebuild_lookup.sql" \
    || fail "Species Name Lookup rebuild fehlgeschlagen."

# ---------------------------------------------------------------------------
# Stage 04 — FTS rebuild (nach allen Plugins)
# ---------------------------------------------------------------------------
log "--- Stage 04: FTS rebuild ---"
sqlite3 "$DB_PATH" < "$CORE_DIR/sql/rebuild_fts.sql" || fail "FTS rebuild fehlgeschlagen."

# ---------------------------------------------------------------------------
# Build-Bericht — vor der Validierung, damit er auch bei Fehlschlag erscheint
# ---------------------------------------------------------------------------
log "--- Build-Bericht ---"
"$CORE_DIR/report_summary.sh" "$REPORT_DIR" | while IFS= read -r line; do log "  $line"; done
log "Details: $REPORT_DIR"

# ---------------------------------------------------------------------------
# Stage 05 — Validierung
# ---------------------------------------------------------------------------
log "--- Stage 05: Validierung ---"
"$CORE_DIR/check_references.sh" --db "$DB_PATH" \
    || fail "Verweise auf Entitäten ungültig — DB wird nicht verwendet."
# Mindestzahlen gelten nur für das, was dieser Build ausgeführt hat;
# Invarianten immer (core/validate.sh).
VALIDATE_FLAGS=()
for plugin in "${PLUGINS[@]}"; do
    VALIDATE_FLAGS+=("--ran" "$plugin")
done
[[ "$SKIP_ENRICHMENT" == false ]] && VALIDATE_FLAGS+=("--ran" "enrich")
"$CORE_DIR/validate.sh" --db "$DB_PATH" --plugins-dir "$PLUGINS_DIR" "${VALIDATE_FLAGS[@]}" \
    || fail "Validierung fehlgeschlagen — DB wird nicht verwendet."
record_build build_validated true

log "=== Build abgeschlossen: $DB_PATH ==="
