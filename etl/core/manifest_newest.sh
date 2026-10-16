#!/usr/bin/env bash
# =============================================================================
# manifest_newest.sh — Das neueste Release eines Referenz-DB-Manifests
#
# Usage:
#   ./core/manifest_newest.sh --manifest <manifest.json>
#
# Ausgabe (stdout): das Release mit der höchsten version, als flaches JSON in
# der Form der obersten Ebene ({version, schemaVersion, url, sha256, …}).
#
# Das Manifest nennt unter "schemas" je Schemaversion deren neuestes Release
# (Schlüssel: die Schemaversion) und auf der obersten Ebene das neueste mit
# Schemaversion 1, für Apps, die "schemas" nicht kennen. Kandidaten sind die
# oberste Ebene und alle Einträge unter "schemas"; version zählt über alle
# Schemas hinweg. Bei gleicher version gewinnt die höhere Schemaversion.
#
# Das neueste Release ist der Vorgänger des nächsten Builds
# (core/previous_release.sh) und das, wogegen core/check_publishable.sh einen
# Build prüft. Die oberste Ebene allein reicht dafür nicht: Nach einem
# Release mit Schemaversion 2 nennt sie weiter das ältere mit 1.
#
# Bricht ab bei einem Schlüssel unter "schemas", der keine ganze Zahl ist,
# bei einem Release ohne ganzzahlige version, ohne url oder ohne sha256 und
# bei einem Manifest ganz ohne Release.
# =============================================================================

set -Eeuo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./plugin_api.sh
source "$CORE_DIR/plugin_api.sh"
PLUGIN_SOURCE="manifest_newest"

MANIFEST=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --manifest) MANIFEST="$2"; shift ;;
        --help|-h)
            plugin_print_help_from_header "$0" 2 25
            exit 0
            ;;
        *) plugin_fail "Unbekanntes Argument: $1" ;;
    esac
    shift
done

plugin_require_command jq
[[ -f "$MANIFEST" ]] || plugin_fail "Manifest nicht gefunden: '$MANIFEST' (--manifest)."

# Fehler als Text auf stdout, damit jq mit Code 0 endet und die Meldung
# hier ankommt; ein gültiges Release ist ein Objekt.
newest="$(jq -c '
    def release_or_error($where):
        if (.version | type) != "number" or (.version | floor) != .version then
            "\($where): version fehlt oder ist keine ganze Zahl"
        elif (.url | type) != "string" then "\($where): url fehlt"
        elif (.sha256 | type) != "string" then "\($where): sha256 fehlt"
        else . end;
    [
        (if has("version") then del(.schemas) | release_or_error("oberste Ebene") else empty end),
        (.schemas // {} | to_entries[]
            | if (.key | test("^[0-9]+$")) | not then
                  "Schlüssel \"\(.key)\" unter schemas ist keine ganze Zahl"
              elif (.value | type) != "object" then
                  "schemas[\"\(.key)\"] ist kein Objekt"
              else
                  .key as $key
                  | .value + {schemaVersion: ($key | tonumber)}
                  | release_or_error("schemas[\"\($key)\"]")
              end)
    ]
    | (map(select(type == "string")) | first) // (
        map(select(type == "object"))
        | if length == 0 then "kein Release" else max_by([.version, .schemaVersion]) end)
' "$MANIFEST")" || plugin_fail "Manifest ist kein lesbares JSON: $MANIFEST"

[[ "$newest" == \{* ]] || plugin_fail "Manifest $MANIFEST: $(jq -r . <<< "$newest")"
echo "$newest"
