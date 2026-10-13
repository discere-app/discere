#!/usr/bin/env bash
# =============================================================================
# plugin_order.sh — Bestimmt, welche Plugins in welcher Reihenfolge laufen
#
# Usage:
#   ./core/plugin_order.sh --plugins-dir <dir> [--no-enrich] [<quelle>...]
#
# Ohne <quelle> gelten alle Plugins unter <dir> (Verzeichnisse mit import.sh,
# ohne führendes _), sonst die genannten samt ihren Abhängigkeiten aus
# depends_on_sources, transitiv. Jedes Plugin wird mit validate_plugin.sh
# geprüft, bevor sein Manifest gelesen wird.
#
# Reihenfolge: topologisch nach depends_on_sources. Unter den jeweils
# lauffähigen Quellen kommt die alphabetisch kleinste zuerst, damit jeder
# Build dieselbe Reihenfolge hat.
#
# --no-enrich: Quellen mit optional: true entfallen, ebenso jede Quelle, die
# von einer entfallenen abhängt.
#
# Abbruch bei unbekanntem Plugin, unbekannter Abhängigkeit, einem Zyklus und
# zwei ausgewählten Quellen mit derselben placement_priority.
#
# Ausgabe (stdout): die auszuführenden Plugins, eines pro Zeile.
# =============================================================================

set -Eeuo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./plugin_api.sh
source "$CORE_DIR/plugin_api.sh"

PLUGINS_DIR=""
SKIP_OPTIONAL=false
REQUESTED=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --plugins-dir) PLUGINS_DIR="$2"; shift ;;
        --no-enrich)   SKIP_OPTIONAL=true ;;
        --help|-h)
            plugin_print_help_from_header "$0" 2 23
            exit 0
            ;;
        *) REQUESTED+=("$1") ;;
    esac
    shift
done

log()  { echo "[$(date '+%H:%M:%S')] [plugin_order] $*" >&2; }
fail() { echo "[ERROR] [plugin_order] $*" >&2; exit 1; }

[[ -d "$PLUGINS_DIR" ]] || fail "Plugin-Verzeichnis nicht gefunden: '$PLUGINS_DIR' (--plugins-dir)."

# Geladene Plugins, über den Index verbunden (Bash 3.2 kennt keine
# assoziativen Arrays). DEPENDENCIES hält je Plugin seine Quellenschlüssel,
# durch Leerzeichen getrennt — validate_plugin.sh hat ihre Form geprüft.
NAMES=()
DEPENDENCIES=()
OPTIONAL=()
PRIORITIES=()

contains() {
    local needle="$1"
    shift
    local item
    for item in "$@"; do
        if [[ "$item" == "$needle" ]]; then
            return 0
        fi
    done
    return 1
}

index_of() {
    local i
    for ((i = 0; i < ${#NAMES[@]}; i++)); do
        if [[ "${NAMES[$i]}" == "$1" ]]; then
            echo "$i"
            return 0
        fi
    done
    return 1
}

dependencies_of() {
    local index
    index="$(index_of "$1")"
    echo "${DEPENDENCIES[$index]}"
}

# Gibt 1 zurück, wenn es kein Plugin dieses Namens gibt; die Meldung kennt
# nur der Aufrufer (unbekanntes Plugin oder unbekannte Abhängigkeit).
load_plugin() {
    local name="$1"
    local plugin_dir="$PLUGINS_DIR/$name"
    local manifest="$plugin_dir/plugin.yaml"
    local dependencies

    [[ -f "$manifest" ]] || return 1
    "$CORE_DIR/validate_plugin.sh" "$plugin_dir" \
        || fail "Plugin '$name' hat ungültige Struktur — Build abgebrochen."

    dependencies="$(plugin_manifest_list "$manifest" "depends_on_sources")"
    NAMES+=("$name")
    DEPENDENCIES+=("$(echo $dependencies)")
    OPTIONAL+=("$(plugin_manifest_get "$manifest" "optional")")
    PRIORITIES+=("$(plugin_manifest_get "$manifest" "placement_priority")")
}

discover_plugins() {
    local plugin_dir plugin_name
    while IFS= read -r -d '' plugin_dir; do
        plugin_name="$(basename "$plugin_dir")"
        [[ "$plugin_name" == _* ]] && continue
        [[ -f "$plugin_dir/import.sh" ]] && REQUESTED+=("$plugin_name")
    done < <(find "$PLUGINS_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
    [[ ${#REQUESTED[@]} -gt 0 ]] || fail "Keine Plugins in $PLUGINS_DIR gefunden."
}

load_selection() {
    local name dependency i

    for name in "${REQUESTED[@]}"; do
        contains "$name" ${NAMES[@]+"${NAMES[@]}"} && continue
        load_plugin "$name" || fail "Unbekanntes Plugin '$name': $PLUGINS_DIR/$name/plugin.yaml fehlt."
    done

    # NAMES wächst während der Schleife; so kommen Abhängigkeiten von
    # Abhängigkeiten mit.
    for ((i = 0; i < ${#NAMES[@]}; i++)); do
        for dependency in ${DEPENDENCIES[$i]}; do
            contains "$dependency" "${NAMES[@]}" && continue
            load_plugin "$dependency" \
                || fail "Unbekannte Abhängigkeit: '${NAMES[$i]}' hängt von '$dependency' ab, dafür gibt es kein Plugin unter $PLUGINS_DIR."
            log "Abhängigkeit hinzugenommen: '$dependency' (für '${NAMES[$i]}')."
        done
    done
}

# placement_priority entscheidet, wessen Einordnung gilt, sobald mehr als eine
# Quelle Einordnungen liefert (siehe docs/datenquellen.md). Solange das nicht
# gebaut ist, wird der Wert nur hier geprüft: Gleichstand hätte dann keine
# Rangfolge und bricht deshalb schon jetzt ab.
check_placement_priorities() {
    local i duplicates
    duplicates="$(
        for ((i = 0; i < ${#NAMES[@]}; i++)); do
            if [[ -n "${PRIORITIES[$i]}" ]]; then
                echo "${PRIORITIES[$i]} ${NAMES[$i]}"
            fi
        done | LC_ALL=C sort | awk '
            { names[$1] = ($1 in names) ? names[$1] ", " $2 : $2; count[$1]++ }
            END { for (p in count) if (count[p] > 1) print "placement_priority " p ": " names[p] }
        ' | LC_ALL=C sort
    )"
    [[ -z "$duplicates" ]] || fail "Doppelte placement_priority — $duplicates"
}

ready_plugins() {
    local name dependency ready
    for name in "$@"; do
        ready=true
        for dependency in $(dependencies_of "$name"); do
            if ! contains "$dependency" ${ORDERED[@]+"${ORDERED[@]}"}; then
                ready=false
                break
            fi
        done
        if [[ "$ready" == true ]]; then
            echo "$name"
        fi
    done
}

# Aus den Plugins, die nicht mehr einzuordnen sind, fallen so lange die weg,
# von denen keines der übrigen abhängt. Was bleibt, liegt auf einem Zyklus.
cycle_members() {
    local members=("$@")
    local changed=true
    local name other kept
    while [[ "$changed" == true ]]; do
        changed=false
        kept=()
        for name in "${members[@]}"; do
            for other in "${members[@]}"; do
                if contains "$name" $(dependencies_of "$other"); then
                    kept+=("$name")
                    break
                fi
            done
        done
        if [[ ${#kept[@]} -lt ${#members[@]} ]]; then
            changed=true
        fi
        members=(${kept[@]+"${kept[@]}"})
    done
    printf '%s\n' "${members[@]}" | LC_ALL=C sort | paste -sd ' ' -
}

order_plugins() {
    local remaining=("${NAMES[@]}")
    local next name rest
    ORDERED=()
    while [[ ${#remaining[@]} -gt 0 ]]; do
        next="$(ready_plugins "${remaining[@]}" | LC_ALL=C sort | sed -n '1p')"
        [[ -n "$next" ]] \
            || fail "Zyklus in depends_on_sources zwischen: $(cycle_members "${remaining[@]}")"
        ORDERED+=("$next")
        rest=()
        for name in "${remaining[@]}"; do
            [[ "$name" == "$next" ]] || rest+=("$name")
        done
        remaining=(${rest[@]+"${rest[@]}"})
    done
}

skip_optional_plugins() {
    local name index dependency skipped=()
    RUNNABLE=()
    for name in "${ORDERED[@]}"; do
        index="$(index_of "$name")"
        if [[ "${OPTIONAL[$index]}" == true ]]; then
            log "Übersprungen (--no-enrich): '$name' ist optional."
            skipped+=("$name")
            continue
        fi
        for dependency in ${DEPENDENCIES[$index]}; do
            if contains "$dependency" ${skipped[@]+"${skipped[@]}"}; then
                log "Übersprungen (--no-enrich): '$name' hängt vom übersprungenen '$dependency' ab."
                skipped+=("$name")
                continue 2
            fi
        done
        RUNNABLE+=("$name")
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
[[ ${#REQUESTED[@]} -gt 0 ]] || discover_plugins
load_selection
check_placement_priorities
order_plugins

if [[ "$SKIP_OPTIONAL" == true ]]; then
    skip_optional_plugins
else
    RUNNABLE=("${ORDERED[@]}")
fi

[[ ${#RUNNABLE[@]} -eq 0 ]] || printf '%s\n' "${RUNNABLE[@]}"
