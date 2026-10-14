#!/usr/bin/env bash
# =============================================================================
# check_publishable.sh — Darf diese Referenz-DB als Release erscheinen?
#
# Usage:
#   ./core/check_publishable.sh --db <db> --manifest <manifest.json>
#
# --manifest ist das Manifest des zurzeit veröffentlichten Releases
# (publish_release.sh: data/reference-db/manifest.json im discere-data-
# Checkout, frisch gepullt).
#
# Ein Release entsteht nur aus einem vollständigen Build gegen genau dieses
# Release (docs/datenquellen.md, Lebenszyklus). build.sh vermerkt dazu in
# metadata:
#   build_scope              — complete, oder incomplete: <Gründe> (Teilbuild,
#                              --no-enrich, --initial, lokaler Vorgänger)
#   build_previous_version,
#   build_previous_sha256    — Version und Prüfsumme des Vorgängers laut
#                              dem Manifest, gegen das gebaut wurde
#   build_validated          — true, sobald die Validierung bestanden ist
#
# Ein Teilbuild übernimmt die Arten der übrigen Quellen als deprecated (und
# macht sie, wo ein Name passt, zu Aliasen), ein Build mit --initial vergibt
# alle IDs ohne Aliase neu, und ein Build gegen ein älteres Release ließe
# die Aliase des dazwischen veröffentlichten aus. Jedes davon schriebe in
# der App Lernstände falsch um.
#
# Exit-Code 0, wenn die DB veröffentlicht werden darf; sonst 1 mit Grund.
# =============================================================================

set -Eeuo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./plugin_api.sh
source "$CORE_DIR/plugin_api.sh"
PLUGIN_SOURCE="check_publishable"

DB_PATH=""
MANIFEST=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)       DB_PATH="$2"; shift ;;
        --manifest) MANIFEST="$2"; shift ;;
        --help|-h)
            plugin_print_help_from_header "$0" 2 28
            exit 0
            ;;
        *) plugin_fail "Unbekanntes Argument: $1" ;;
    esac
    shift
done

plugin_require_command sqlite3 jq
[[ -f "$DB_PATH" ]] || plugin_fail "Referenz-DB nicht gefunden: '$DB_PATH' (--db)."
[[ -f "$MANIFEST" ]] \
    || plugin_fail "Kein veröffentlichtes Manifest: '$MANIFEST' (--manifest). Ohne Vorgänger gibt es kein Release."

metadata() {
    sqlite3 "file:$DB_PATH?mode=ro" "SELECT value FROM metadata WHERE key = '$1';" 2> /dev/null || true
}

scope="$(metadata build_scope)"
[[ -n "$scope" ]] || plugin_fail "$DB_PATH trägt keinen Build-Vermerk (build_scope) — nicht mit build.sh gebaut."
[[ "$scope" == complete ]] || plugin_fail "Kein vollständiger Build: $scope"
[[ "$(metadata build_validated)" == true ]] || plugin_fail "Der Build hat die Validierung nicht bestanden."

published_version="$(jq -er '.version' "$MANIFEST")" || plugin_fail "Manifest ohne version: $MANIFEST"
published_sha256="$(jq -er '.sha256' "$MANIFEST")" || plugin_fail "Manifest ohne sha256: $MANIFEST"
previous_version="$(metadata build_previous_version)"
previous_sha256="$(metadata build_previous_sha256)"
[[ "$previous_version" == "$published_version" && "$previous_sha256" == "$published_sha256" ]] \
    || plugin_fail "Gebaut gegen Vorgänger v$previous_version ($previous_sha256), veröffentlicht ist v$published_version ($published_sha256). Neu bauen."

plugin_log "Vollständiger Build gegen das veröffentlichte Release v$published_version — darf veröffentlicht werden."
