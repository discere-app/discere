#!/usr/bin/env bash
# =============================================================================
# seed_locale_place_mappings.sh — Befüllt locale_place_mappings in der Reference-DB
#
# Liest locale_iso_codes.csv (locale, language_code, ISO Alpha-2, ISO Numeric,
# Länder-Name auf Englisch), löst pro Land die iNaturalist-Place-ID über die
# iNat-API auf und schreibt alle Zeilen in die DB.
#
# Länder die im CSV mehrfach vorkommen (z.B. CH für de-CH und fr-CH) werden
# nur einmal gegen die API abgefragt; das Ergebnis wird im laufenden Script
# zwischengespeichert.
#
# Usage:
#   ./core/seed_locale_place_mappings.sh --db /path/to/discere.db
#
# Abhängigkeiten: curl, jq, sqlite3
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CSV_FILE="$SCRIPT_DIR/data/locale_iso_codes.csv"
INAT_API="https://api.inaturalist.org/v1"
API_SLEEP=0.4
DB_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --db) DB_PATH="$2"; shift ;;
        --help|-h)
            sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) echo "[WARN] [seed_locale_place_mappings] Unbekanntes Argument: $1" >&2 ;;
    esac
    shift
done

log()  { echo "[$(date '+%H:%M:%S')] [seed_locale_place_mappings] $*" >&2; }
fail() { echo "[ERROR] [seed_locale_place_mappings] $*" >&2; exit 1; }

[[ -n "$DB_PATH" ]]  || fail "--db fehlt."
[[ -f "$DB_PATH" ]]  || fail "DB nicht gefunden: $DB_PATH"
[[ -f "$CSV_FILE" ]] || fail "CSV nicht gefunden: $CSV_FILE"

for cmd in curl jq sqlite3; do
    command -v "$cmd" >/dev/null 2>&1 || fail "'$cmd' nicht gefunden."
done

# ---------------------------------------------------------------------------
# SQL-Injection-Schutz: escapt einfache Anführungszeichen für SQLite-Strings
# ('' ist der Standard-Escape in SQL)
# ---------------------------------------------------------------------------
sql_esc() { printf '%s' "${1//\'/\'\'}"; }

# ---------------------------------------------------------------------------
# iNat-Lookup: findet die Place-ID für einen Ländernamen (place_type=12 = Country)
#
# Strategie:
#   1. Exakter Name-Match (display_name case-insensitive) — verhindert Fehl-
#      treffer bei mehrdeutigen Namen wie "Guinea" (≠ Papua New Guinea).
#   2. Fallback: erster Treffer mit place_type == 12.
#
# Ergebnis wird in CACHE_FILE zwischengespeichert (Format: "Name=ID" pro Zeile).
# ---------------------------------------------------------------------------
CACHE_FILE=$(mktemp /tmp/locale_place_cache.XXXXXX)
trap 'rm -f "$CACHE_FILE"' EXIT

resolve_inat_place_id() {
    local country_name="$1"

    # Cache-Lookup
    local cached
    cached=$(grep -F "${country_name}=" "$CACHE_FILE" 2>/dev/null | head -1 || true)
    if [[ -n "$cached" ]]; then
        echo "${cached#*=}"
        return
    fi

    local response
    response=$(curl -sf -G \
        --data-urlencode "q=$country_name" \
        --data-urlencode "per_page=10" \
        -H "Accept: application/json" \
        "$INAT_API/places/autocomplete" 2>/dev/null || echo "")

    sleep "$API_SLEEP"

    if [[ -z "$response" ]]; then
        echo "${country_name}=" >> "$CACHE_FILE"
        echo ""
        return
    fi

    local place_id
    place_id=$(echo "$response" | jq -r --arg name "$country_name" '
        [ .results[] | select(
            .place_type == 12 and
            (.display_name | ascii_downcase) == ($name | ascii_downcase)
          )
        ] |
        if length > 0 then .[0].id | tostring
        else
          [ .results[] | select(.place_type == 12) ] |
          if length > 0 then .[0].id | tostring else "" end
        end
    ')

    echo "${country_name}=${place_id}" >> "$CACHE_FILE"
    echo "$place_id"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
log "CSV:  $CSV_FILE"
log "DB:   $DB_PATH"

total=0
inserted=0
failed=0

while IFS=, read -r locale language_code country_code_alpha2 country_code_numeric country_name_en inat_place_id_csv; do
    [[ "$locale" == "locale" ]] && continue  # Header
    [[ -z "$locale" ]]          && continue  # Leerzeile

    total=$((total + 1))

    # Statische ID aus CSV verwenden wenn vorhanden — überspringt den API-Call.
    # Leere Spalte → API-Lookup (für neue oder noch nicht aufgelöste Einträge).
    if [[ -n "${inat_place_id_csv:-}" ]]; then
        place_id="$inat_place_id_csv"
        log "  STATIC $locale ($country_name_en) → inat_place_id=$place_id"
    else
        place_id=$(resolve_inat_place_id "$country_name_en")
    fi

    if [[ -z "$place_id" || "$place_id" == "null" ]]; then
        log "  WARN  $locale ($country_name_en) — kein iNat-Place gefunden, übersprungen"
        failed=$((failed + 1))
        continue
    fi

    sqlite3 "$DB_PATH" \
        "INSERT OR REPLACE INTO locale_place_mappings
             (locale, language_code, country_code_alpha2, country_code_numeric,
              inat_place_id, country_name_en)
         VALUES
             ('$(sql_esc "$locale")', '$(sql_esc "$language_code")',
              '$(sql_esc "$country_code_alpha2")', '$(sql_esc "$country_code_numeric")',
              $place_id, '$(sql_esc "$country_name_en")');"

    log "  OK    $locale ($country_name_en) → inat_place_id=$place_id (api)"
    inserted=$((inserted + 1))

done < "$CSV_FILE"

log "Fertig: $inserted/$total eingefügt, $failed nicht auflösbar."
[[ $failed -eq 0 ]] || \
    log "WARN: $failed Einträge ohne iNat-Place-ID — prüfe country_name_en im CSV."
