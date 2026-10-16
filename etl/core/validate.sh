#!/usr/bin/env bash
# =============================================================================
# validate.sh — Mindest-Zeilenzahlen und Invarianten am Ende des Builds
#
# Usage:
#   ./core/validate.sh --db <db> --plugins-dir <dir> [--ran <plugin|enrich>]...
#
# Läuft in Stage 05 von build.sh. Führt core/sql/validate.sql aus; jede Zeile
# ist tbl | n | min | requires und schlägt fehl, wenn n < min. requires sagt,
# was im Build gelaufen sein muss, damit die Zeile gilt:
#   always                Invariante, wird immer geprüft
#   enrich                Stage 01b (core/seed_locale_place_mappings.sh)
#   <plugin>[,<plugin>]   alle genannten Plugins
# --ran nennt, was gelaufen ist (wiederholbar): jedes ausgeführte Plugin und
# enrich, wenn Stage 01b lief. Eine Mindestzahl, deren Voraussetzung fehlt,
# wird mit Grund als übersprungen geloggt; ein vollständiger Build prüft
# jede.
#
# Abbruch, wenn eine Zeile keine vier Spalten hat, requires leer ist oder
# etwas nennt, das weder always, enrich noch ein Plugin unter <dir> ist —
# eine Prüfung wird nie still übersprungen. Ebenso bei einem Fehler im SQL.
#
# Gibt je Zeile eine Logzeile aus und endet mit Exit-Code 1, sobald eine
# geprüfte Zeile n < min hat.
# =============================================================================

set -Eeuo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./plugin_api.sh
source "$CORE_DIR/plugin_api.sh"
PLUGIN_SOURCE="validate"

DB_PATH=""
PLUGINS_DIR=""
RAN=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)          DB_PATH="$2"; shift ;;
        --plugins-dir) PLUGINS_DIR="$2"; shift ;;
        --ran)         RAN+=("$2"); shift ;;
        --help|-h)
            plugin_print_help_from_header "$0" 2 24
            exit 0
            ;;
        *) plugin_fail "Unbekanntes Argument: $1" ;;
    esac
    shift
done
[[ -n "$DB_PATH" ]] || plugin_fail "--db fehlt."
[[ -n "$PLUGINS_DIR" ]] || plugin_fail "--plugins-dir fehlt."

KNOWN_PLUGINS=" $("$CORE_DIR/plugin_order.sh" --plugins-dir "$PLUGINS_DIR" 2> /dev/null | tr '\n' ' ') " \
    || plugin_fail "Plugins unter $PLUGINS_DIR nicht lesbar."
RAN_LIST=" ${RAN[*]-} "

is_known() {
    [[ "$1" == enrich || "$KNOWN_PLUGINS" == *" $1 "* ]]
}

for ran in ${RAN[@]+"${RAN[@]}"}; do
    is_known "$ran" || plugin_fail "--ran $ran: weder enrich noch ein Plugin unter $PLUGINS_DIR."
done

# Gibt den Grund aus, warum eine Zeile mit dieser Voraussetzung nicht geprüft
# wird, leer, wenn sie gilt. Bricht bei einer ungültigen Voraussetzung ab.
skip_reason() {
    local tbl="$1" requires="$2" token missing=()
    [[ "$requires" == always ]] && return 0
    [[ -n "$requires" ]] || plugin_fail "$tbl: keine Voraussetzung (requires) — Validierung abgebrochen."
    for token in ${requires//,/ }; do
        is_known "$token" \
            || plugin_fail "$tbl: unbekannte Voraussetzung '$token' — Validierung abgebrochen."
        [[ "$RAN_LIST" == *" $token "* ]] && continue
        if [[ "$token" == enrich ]]; then
            missing+=("Stage 01b")
        else
            missing+=("Plugin $token")
        fi
    done
    [[ ${#missing[@]} -eq 0 ]] || (IFS=,; echo "${missing[*]} nicht gelaufen" | sed 's/,/, /g')
}

ROWS="$(sqlite3 -bail "$DB_PATH" < "$CORE_DIR/sql/validate.sql")" \
    || plugin_fail "core/sql/validate.sql fehlgeschlagen — Validierung abgebrochen."

plugin_log "Prüfe Zeilenzahlen und Invarianten..."
failed=false
rows_read=0
while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    rows_read=$((rows_read + 1))
    IFS='|' read -r tbl n min requires extra <<< "$row"
    [[ -z "${extra:-}" && "$row" == *'|'*'|'*'|'* ]] \
        || plugin_fail "Zeile ohne die Spalten tbl | n | min | requires: $row — Validierung abgebrochen."
    [[ "$n" =~ ^[0-9]+$ && "$min" =~ ^[0-9]+$ ]] \
        || plugin_fail "$tbl: n und min müssen Zahlen sein: $row — Validierung abgebrochen."
    reason="$(skip_reason "$tbl" "$requires")" || exit 1
    if [[ -n "$reason" ]]; then
        plugin_log "  $(printf '%-34s' "$tbl") übersprungen: $reason"
    elif [[ "$n" -lt "$min" ]]; then
        plugin_log "  FEHLER: $tbl — $n (erwartet >= $min)"
        failed=true
    else
        plugin_log "  $(printf '%-34s' "$tbl") $n"
    fi
done <<< "$ROWS"

[[ $rows_read -gt 0 ]] || plugin_fail "core/sql/validate.sql liefert keine Zeilen — Validierung abgebrochen."

[[ "$failed" == false ]] || plugin_fail "Validierung fehlgeschlagen."
plugin_log "Validierung OK."
