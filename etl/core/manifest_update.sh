#!/usr/bin/env bash
# =============================================================================
# manifest_update.sh — Trägt ein neues Release ins Referenz-DB-Manifest ein
#
# Usage:
#   ./core/manifest_update.sh --manifest <manifest.json> --schema <int> \
#     --version <int> --url <url> --sha256 <hex> --size <bytes> \
#     --published-at <ISO-8601>
#
# Schreibt das Manifest an Ort und Stelle fort; publish_release.sh ruft es
# für data/reference-db/manifest.json im discere-data-Checkout auf.
#
# Das Manifest nennt unter "schemas" je Schemaversion deren neuestes Release,
# mit der Schemaversion als Schlüssel und ohne eigenes Feld schemaVersion:
#
#   {
#     "version": 2, "schemaVersion": 1, "url": …, "sha256": …,
#     "compressedSizeBytes": …, "publishedAt": …,
#     "schemas": {
#       "1": { "version": 2, "url": …, "sha256": …, "compressedSizeBytes": …, "publishedAt": … },
#       "2": { "version": 3, … }
#     }
#   }
#
# Die oberste Ebene ist immer das neueste Release mit Schemaversion 1, für
# Apps, die "schemas" nicht kennen. Jede App nimmt das neueste Release, das
# sie lesen kann; deshalb braucht ein Schemawechsel keine Reihenfolge von
# App- und Release-Auslieferung.
#
# Das Skript setzt schemas["<--schema>"] auf das neue Release und nur bei
# Schemaversion 1 zusätzlich die oberste Ebene. Alle anderen Einträge bleiben.
# Fehlt "schemas" (ein Manifest mit nur der obersten Ebene), legt es sie an
# und übernimmt die bisherige oberste Ebene als schemas["1"], damit beide
# Darstellungen übereinstimmen. Hat diese oberste Ebene eine andere
# Schemaversion als 1, bricht es ab.
#
# Ob das Release veröffentlicht werden darf (Version, Vorgänger), prüft
# core/check_publishable.sh vorher; dieses Skript schreibt nur.
# =============================================================================

set -Eeuo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./plugin_api.sh
source "$CORE_DIR/plugin_api.sh"
PLUGIN_SOURCE="manifest_update"

MANIFEST=""
SCHEMA=""
VERSION=""
URL=""
SHA256=""
SIZE=""
PUBLISHED_AT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --manifest)     plugin_require_value "$@"; MANIFEST="$2"; shift ;;
        --schema)       plugin_require_value "$@"; SCHEMA="$2"; shift ;;
        --version)      plugin_require_value "$@"; VERSION="$2"; shift ;;
        --url)          plugin_require_value "$@"; URL="$2"; shift ;;
        --sha256)       plugin_require_value "$@"; SHA256="$2"; shift ;;
        --size)         plugin_require_value "$@"; SIZE="$2"; shift ;;
        --published-at) plugin_require_value "$@"; PUBLISHED_AT="$2"; shift ;;
        --help|-h)
            plugin_print_help "$0"
            exit 0
            ;;
        *) plugin_fail_unknown_argument "$1" ;;
    esac
    shift
done

plugin_require_command jq
[[ -f "$MANIFEST" ]] || plugin_fail "Manifest nicht gefunden: '$MANIFEST' (--manifest)."
for pair in "--schema:$SCHEMA" "--version:$VERSION" "--size:$SIZE"; do
    [[ "${pair#*:}" =~ ^[0-9]+$ ]] \
        || plugin_fail "${pair%%:*} muss eine ganze Zahl sein, erhalten: '${pair#*:}'."
done
[[ -n "$URL" ]] || plugin_fail "--url ist erforderlich."
[[ -n "$SHA256" ]] || plugin_fail "--sha256 ist erforderlich."
[[ -n "$PUBLISHED_AT" ]] || plugin_fail "--published-at ist erforderlich."

# Ohne "schemas" wird die oberste Ebene schemas["<ihre Schemaversion>"] und
# bleibt oben stehen. Dort darf nur ein Release mit Schemaversion 1 stehen:
# Ältere Apps lesen allein sie und lehnen jede andere ab.
if ! jq -e 'has("schemas")' "$MANIFEST" > /dev/null; then
    top_schema="$(jq -r '.schemaVersion' "$MANIFEST")" \
        || plugin_fail "Manifest ist kein lesbares JSON: $MANIFEST"
    [[ "$top_schema" == 1 ]] \
        || plugin_fail "Die oberste Ebene von $MANIFEST hat Schemaversion $top_schema, erlaubt ist nur 1 (für Apps, die \"schemas\" nicht kennen). Manifest von Hand richtigstellen."
fi

updated="$(mktemp "$MANIFEST.XXXXXX")"
trap 'rm -f "$updated"' EXIT

jq \
    --argjson schema "$((10#$SCHEMA))" \
    --argjson version "$((10#$VERSION))" \
    --arg url "$URL" \
    --arg sha256 "$SHA256" \
    --argjson size "$((10#$SIZE))" \
    --arg publishedAt "$PUBLISHED_AT" '
    {version: $version, url: $url, sha256: $sha256,
     compressedSizeBytes: $size, publishedAt: $publishedAt} as $release
    | if has("schemas") then . else .schemas = {"1": del(.schemaVersion)} end
    | .schemas[$schema | tostring] = $release
    | .schemas |= (to_entries | sort_by(.key | tonumber) | from_entries)
    | if $schema == 1 then . + $release + {schemaVersion: 1} else . end
' "$MANIFEST" > "$updated" || plugin_fail "Manifest nicht fortschreibbar: $MANIFEST"

# Überschrieben statt ersetzt: Die Datei behält ihre Rechte.
cat "$updated" > "$MANIFEST"
where="schemas[\"$((10#$SCHEMA))\"]"
(( 10#$SCHEMA == 1 )) && where="$where und auf der obersten Ebene"
plugin_log "Manifest $MANIFEST: v$((10#$VERSION)) unter $where."
