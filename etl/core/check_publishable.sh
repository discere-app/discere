#!/usr/bin/env bash
# =============================================================================
# check_publishable.sh — Darf diese Referenz-DB als Release erscheinen?
#
# Usage:
#   ./core/check_publishable.sh --db <db> --manifest <manifest.json> --version <int>
#
# --manifest ist das veröffentlichte Manifest (publish_release.sh:
# data/reference-db/manifest.json im discere-data-Checkout, frisch gepullt).
# Maßgeblich ist sein neuestes Release über alle Schemaversionen
# (core/manifest_newest.sh), nicht die oberste Ebene: Die nennt nach einem
# Release mit Schemaversion 2 weiter das ältere mit 1. --version ist die
# Version, unter der die DB erscheinen soll; sie muss größer sein als die des
# neuesten Releases, denn version zählt über alle Schemas, und die App lädt
# nur eine höhere Version als die installierte.
#
# Ein Release entsteht nur aus einem vollständigen Build gegen genau dieses
# neueste Release (docs/datenquellen.md, Lebenszyklus). build.sh vermerkt
# dazu in metadata:
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
VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db)       plugin_require_value "$@"; DB_PATH="$2"; shift ;;
        --manifest) plugin_require_value "$@"; MANIFEST="$2"; shift ;;
        --version)  plugin_require_value "$@"; VERSION="$2"; shift ;;
        --help|-h)
            plugin_print_help "$0"
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
[[ "$VERSION" =~ ^[0-9]+$ ]] || plugin_fail "--version muss eine ganze Zahl sein, erhalten: '$VERSION'."

metadata() {
    sqlite3 "file:$DB_PATH?mode=ro" "SELECT value FROM metadata WHERE key = '$1';" 2> /dev/null || true
}

scope="$(metadata build_scope)"
[[ -n "$scope" ]] || plugin_fail "$DB_PATH trägt keinen Build-Vermerk (build_scope) — nicht mit build.sh gebaut."
[[ "$scope" == complete ]] || plugin_fail "Kein vollständiger Build: $scope"
[[ "$(metadata build_validated)" == true ]] || plugin_fail "Der Build hat die Validierung nicht bestanden."

newest="$("$CORE_DIR/manifest_newest.sh" --manifest "$MANIFEST")" \
    || plugin_fail "Kein Release im Manifest: $MANIFEST"
published_version="$(jq -r '.version' <<< "$newest")"
published_sha256="$(jq -r '.sha256' <<< "$newest")"
previous_version="$(metadata build_previous_version)"
previous_sha256="$(metadata build_previous_sha256)"
[[ "$previous_version" == "$published_version" && "$previous_sha256" == "$published_sha256" ]] \
    || plugin_fail "Gebaut gegen Vorgänger v$previous_version ($previous_sha256), das neueste veröffentlichte ist v$published_version ($published_sha256). Neu bauen."
(( 10#$VERSION > published_version )) \
    || plugin_fail "Version v$VERSION ist nicht größer als die des neuesten veröffentlichten Releases v$published_version. Die App lädt nur eine höhere Version; --version erhöhen."

plugin_log "Vollständiger Build gegen das neueste veröffentlichte Release v$published_version — darf als v$VERSION veröffentlicht werden."
