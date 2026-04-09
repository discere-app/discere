#!/usr/bin/env bash
# =============================================================================
# validate_plugin.sh — Prüft Plugin-Struktur vor der Ausführung
#
# Wird von build.sh vor jedem Plugin-Aufruf aufgerufen.
# Stellt sicher dass alle Pflicht-Dateien eines Plugins vorhanden sind.
#
# Usage:
#   ./core/validate_plugin.sh <plugin-dir>
#
# Exit-Code:
#   0 — Plugin-Struktur ist gültig
#   1 — Plugin-Struktur ist ungültig (Details auf stderr)
# =============================================================================

set -Eeuo pipefail

PLUGIN_DIR="${1:-}"
CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./plugin_api.sh
source "$CORE_DIR/plugin_api.sh"

log()  { echo "[$(date '+%H:%M:%S')] [validate_plugin] $*" >&2; }
fail() { echo "[ERROR] [validate_plugin] $*" >&2; exit 1; }

[[ -n "$PLUGIN_DIR" ]] || fail "Kein Plugin-Verzeichnis angegeben. Usage: $0 <plugin-dir>"
[[ -d "$PLUGIN_DIR" ]] || fail "Plugin-Verzeichnis nicht gefunden: $PLUGIN_DIR"

PLUGIN_NAME="$(basename "$PLUGIN_DIR")"
ERRORS=()

# Pflicht-Dateien
[[ -f "$PLUGIN_DIR/plugin.yaml" ]] || ERRORS+=("plugin.yaml fehlt")
[[ -f "$PLUGIN_DIR/import.sh"   ]] || ERRORS+=("import.sh fehlt")
[[ -d "$PLUGIN_DIR/sql"         ]] || ERRORS+=("sql/ Verzeichnis fehlt")
[[ -f "$PLUGIN_DIR/sql/export.sql" ]] || ERRORS+=("sql/export.sql fehlt")
[[ -f "$PLUGIN_DIR/sql/source.sql" ]] || ERRORS+=("sql/source.sql fehlt")

# import.sh muss ausführbar sein
if [[ -f "$PLUGIN_DIR/import.sh" ]] && [[ ! -x "$PLUGIN_DIR/import.sh" ]]; then
    ERRORS+=("import.sh ist nicht ausführbar (chmod +x)")
fi

if [[ -f "$PLUGIN_DIR/plugin.yaml" ]]; then
    plugin_name="$(plugin_manifest_get "$PLUGIN_DIR/plugin.yaml" "name")"
    plugin_source="$(plugin_manifest_get "$PLUGIN_DIR/plugin.yaml" "source")"
    plugin_version="$(plugin_manifest_get "$PLUGIN_DIR/plugin.yaml" "version")"

    [[ -n "$plugin_name" ]] || ERRORS+=("plugin.yaml: Pflichtfeld 'name' fehlt")
    [[ -n "$plugin_source" ]] || ERRORS+=("plugin.yaml: Pflichtfeld 'source' fehlt")
    [[ -n "$plugin_version" ]] || ERRORS+=("plugin.yaml: Pflichtfeld 'version' fehlt")

    if [[ -n "$plugin_source" ]] && [[ ! "$plugin_source" =~ ^[a-z0-9][a-z0-9_-]*$ ]]; then
        ERRORS+=("plugin.yaml: 'source' muss dem Muster [a-z0-9][a-z0-9_-]* entsprechen")
    fi
fi

if [[ ${#ERRORS[@]} -gt 0 ]]; then
    log "Plugin '$PLUGIN_NAME' ist ungültig:"
    for err in "${ERRORS[@]}"; do
        log "  ✗ $err"
    done
    fail "Plugin-Validierung fehlgeschlagen: $PLUGIN_NAME"
fi

log "Plugin '$PLUGIN_NAME' — Struktur OK"
