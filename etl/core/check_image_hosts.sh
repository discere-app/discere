#!/usr/bin/env bash
# =============================================================================
# check_image_hosts.sh — Liefern die Bild-Hosts einer Referenz-DB der App?
#
# Usage:
#   ./core/check_image_hosts.sh --db <db>
#
# Die App zeigt nur Bilder mit is_usable = 1 und lädt sie per GET mit ihrem
# eigenen User-Agent; sie nimmt nur Status 200. Ein Host, der Clients ohne
# Browser sperrt (etwa per Cloudflare-Challenge), sieht im Browser und in
# der DB unauffällig aus, liefert der App aber kein einziges Bild.
#
# Je Host — abgeleitet aus pictures.url, damit ein neues Plugin mit eigenem
# Bild-Host ohne Änderung mitgeprüft wird — lädt die Prüfung eine kleine
# Zufallsstichprobe nutzbarer Bilder so, wie die App es tut, und bewertet
# jede Antwort:
#
#   ok      — Status 200, Content-Type image/*, kein cf-mitigated-Header.
#   fehlt   — Status 404: Die Quelle nennt ein Bild, das es nicht gibt.
#   versagt — alles andere: Challenge (cf-mitigated, bei jedem Status),
#             anderer Status, falscher Content-Type, keine Antwort.
#
# Ein Host fällt durch, sobald eine Antwort versagt — eine Sperre trifft
# alle Bilder, auch wenn nur eine Anfrage sie zeigt —, oder wenn nicht die
# Mehrheit der Stichprobe ok ist: Einzelne fehlende Bilder kommen in den
# Quellen vor; fehlen die meisten, stimmt der Bildpfad nicht.
#
# Die URLs kommen unverändert aus der DB. Aus Host und Dateiname
# zusammengesetzte trafen ein anderes Bild: FishBase und SeaLifeBase
# vergeben gleiche Dateinamen für verschiedene Bilder.
#
# Exit-Code 0, wenn jeder Host seine Stichprobe liefert; sonst 1 mit Host,
# Beispiel-URL, Status und Grund.
# =============================================================================

set -Eeuo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./plugin_api.sh
source "$CORE_DIR/plugin_api.sh"
PLUGIN_SOURCE="check_image_hosts"

# User-Agent der App beim Laden von Bildern (AppConstants.userAgent in
# lib/shared/util/constants.dart). Ändert er sich dort, hier nachziehen:
# Sperren hängen oft am User-Agent.
APP_USER_AGENT="DiscereApp/1.1 (ch.feberle.discere; https://github.com/discere-app/discere)"

# Fünf Bilder je Host: genug, dass zwei fehlende Bilder einen Host noch
# nicht durchfallen lassen, und wenige Anfragen je Host.
SAMPLE_SIZE=5
# Pause zwischen zwei Anfragen in Sekunden, um die Hosts nicht zu belasten.
REQUEST_PAUSE=1

DB_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db) DB_PATH="$2"; shift ;;
        --help|-h)
            plugin_print_help "$0"
            exit 0
            ;;
        *) plugin_fail "Unbekanntes Argument: $1" ;;
    esac
    shift
done

plugin_require_command sqlite3 curl
[[ -f "$DB_PATH" ]] || plugin_fail "Referenz-DB nicht gefunden: '$DB_PATH' (--db)."

# Host und URL der Stichprobe, eine Zeile je Bild, nach Host sortiert.
sample="$(sqlite3 -separator $'\t' "file:$DB_PATH?mode=ro" "
    WITH usable AS (
        SELECT url, substr(url, instr(url, '://') + 3) AS rest
        FROM pictures
        WHERE is_usable = 1 AND url IS NOT NULL
    ), hosted AS (
        SELECT url,
               CASE WHEN instr(rest, '/') > 0 THEN substr(rest, 1, instr(rest, '/') - 1)
                    ELSE rest END AS host
        FROM usable
    ), ranked AS (
        SELECT host, url, ROW_NUMBER() OVER (PARTITION BY host ORDER BY random()) AS n
        FROM hosted
    )
    SELECT host, url FROM ranked WHERE n <= $SAMPLE_SIZE ORDER BY host, n;" 2> /dev/null)" \
    || plugin_fail "Keine lesbare Referenz-DB: $DB_PATH"

if [[ -z "$sample" ]]; then
    plugin_log "Keine nutzbaren Bilder — nichts zu prüfen."
    exit 0
fi

# probe <url> — lädt ein Bild wie die App und gibt den Befund aus:
# "ok", "fehlt" oder "versagt <status> <grund>".
probe() {
    local url="$1" headers curl_status=0 response status content_type mitigated
    headers="$(curl -sS -L --connect-timeout 10 --max-time 30 \
        -A "$APP_USER_AGENT" -o /dev/null -D - "$url" 2> /dev/null)" || curl_status=$?
    headers="$(tr -d '\r' <<< "$headers")"
    # Bei Weiterleitungen enthält headers jede Antwort; maßgeblich ist die letzte.
    response="$(awk '/^HTTP\// { block = "" } { block = block $0 "\n" } END { printf "%s", block }' <<< "$headers")"
    status="$(awk 'NR == 1 { print $2 }' <<< "$response")"
    content_type="$(awk -F ': *' 'tolower($1) == "content-type" { print $2 }' <<< "$response")"
    mitigated="$(awk -F ': *' 'tolower($1) == "cf-mitigated" { print $2 }' <<< "$headers")"

    if [[ $curl_status -ne 0 || -z "$status" ]]; then
        echo "versagt ${status:-–} keine Antwort (curl-Exit $curl_status)"
    elif [[ -n "$mitigated" ]]; then
        echo "versagt $status Cloudflare-Challenge (cf-mitigated: $mitigated)"
    elif [[ "$status" == 404 ]]; then
        echo fehlt
    elif [[ "$status" != 200 ]]; then
        echo "versagt $status erwartet 200"
    elif [[ "$content_type" != image/* ]]; then
        echo "versagt $status Content-Type '${content_type:-keiner}' statt image/*"
    else
        echo ok
    fi
}

failures=""
first_request=true

while IFS= read -r host; do
    total=0
    ok=0
    missing=""
    failed=""
    while IFS= read -r url; do
        $first_request || sleep "$REQUEST_PAUSE"
        first_request=false
        total=$((total + 1))
        read -r verdict status reason <<< "$(probe "$url")"
        case "$verdict" in
            ok)    ok=$((ok + 1)) ;;
            fehlt) missing="$missing $url" ;;
            *)     [[ -n "$failed" ]] || failed="$url → Status $status: $reason" ;;
        esac
    done <<< "$(awk -F '\t' -v host="$host" '$1 == host { print $2 }' <<< "$sample")"

    [[ -z "$missing" ]] || plugin_log "$host: Bild fehlt (404):$missing"
    if [[ -n "$failed" ]]; then
        failures="$failures"$'\n'"  $host: $failed"
    elif (( ok * 2 <= total )); then
        failures="$failures"$'\n'"  $host: nur $ok von $total Bildern geladen, die übrigen fehlen (404) — stimmt der Bildpfad?"
    else
        plugin_log "$host: $ok von $total Bildern geladen."
    fi
done <<< "$(cut -f1 <<< "$sample" | uniq)"

[[ -z "$failures" ]] || plugin_fail "Bild-Hosts liefern der App keine Bilder:$failures"
plugin_log "Alle Bild-Hosts liefern ihre Stichprobe."
