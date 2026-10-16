#!/usr/bin/env bash
# =============================================================================
# previous_release.sh — Stellt das zuletzt veröffentlichte Release bereit
#
# Usage:
#   ./core/previous_release.sh                 # Release aus dem Manifest
#   ./core/previous_release.sh --path <db>     # lokale Referenz-DB
#
# Ausgabe (stdout): Pfad zur Referenz-DB des Vorgängers. Die Identitäts-Stage
# (core/identity.sh) übernimmt daraus Register und Aliase. Neben einer
# heruntergeladenen DB liegt manifest.json: ihr Eintrag aus dem Manifest,
# flach in der Form der obersten Ebene (version, schemaVersion, url, sha256).
#
# Ohne --path nimmt das Skript das neueste Release des Manifests, über alle
# Schemaversionen (core/manifest_newest.sh), lädt dessen .gz, prüft die
# Prüfsumme und entpackt sie nach
# <cache-dir>/v<version>/discere_reference.db. Ein Eintrag im Cache wird
# wiederverwendet, solange das Manifest dieselbe Prüfsumme nennt und die
# entpackte DB die beim Entpacken gemerkte Prüfsumme hat.
#
# Flags:
#   --path <db>           Lokale Referenz-DB statt Download (etwa für Tests)
#   --cache-dir <dir>     Cache (Default: etl/cache/releases, gitignored)
#   --manifest-url <url>  Manifest (Default: discere-data, main)
#
# Umgebungsvariablen:
#   DISCERE_RELEASE_MANIFEST_URL  Entspricht --manifest-url
#
# Bricht ab, wenn kein gültiges Release bereitsteht: ohne lesbares Manifest
# oder ohne Release darin, bei falscher Prüfsumme oder wenn die DB keine
# Referenz-DB ist.
# =============================================================================

set -Eeuo pipefail

CORE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ETL_DIR="$(cd "$CORE_DIR/.." && pwd)"

# shellcheck source=./plugin_api.sh
source "$CORE_DIR/plugin_api.sh"
PLUGIN_SOURCE="previous_release"

LOCAL_PATH=""
CACHE_DIR="$ETL_DIR/cache/releases"
MANIFEST_URL="${DISCERE_RELEASE_MANIFEST_URL:-https://raw.githubusercontent.com/discere-app/discere-data/main/data/reference-db/manifest.json}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --path)         LOCAL_PATH="$2"; shift ;;
        --cache-dir)    CACHE_DIR="$2"; shift ;;
        --manifest-url) MANIFEST_URL="$2"; shift ;;
        --help|-h)
            plugin_print_help_from_header "$0" 2 30
            exit 0
            ;;
        *) plugin_fail "Unbekanntes Argument: $1" ;;
    esac
    shift
done

plugin_require_command sqlite3

sha256_of() {
    if command -v sha256sum > /dev/null 2>&1; then
        sha256sum "$1" | cut -d ' ' -f 1
    else
        shasum -a 256 "$1" | cut -d ' ' -f 1
    fi
}

# Eine Referenz-DB hat mindestens die fünf Entitätstabellen.
require_reference_db() {
    local db="$1" tables
    tables="$(sqlite3 "file:$db?mode=ro" "
        SELECT COUNT(*) FROM sqlite_schema WHERE type = 'table'
          AND name IN ('species', 'genera', 'families', 'orders', 'classes');" 2> /dev/null || true)"
    [[ "$tables" == 5 ]] || plugin_fail "Keine lesbare Referenz-DB: $db"
}

if [[ -n "$LOCAL_PATH" ]]; then
    [[ -f "$LOCAL_PATH" ]] || plugin_fail "Vorgänger nicht gefunden: $LOCAL_PATH"
    require_reference_db "$LOCAL_PATH"
    echo "$LOCAL_PATH"
    exit 0
fi

plugin_require_command curl jq gunzip

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

curl --silent --show-error --location --fail --output "$WORK_DIR/manifest.json" "$MANIFEST_URL" \
    || plugin_fail "Manifest nicht lesbar: $MANIFEST_URL"
# Der Vorgänger ist das neueste Release überhaupt, nicht die oberste Ebene:
# Die nennt nach einem Release mit Schemaversion 2 weiter das ältere mit 1,
# und ein Build dagegen ließe die Aliase des neueren aus.
"$CORE_DIR/manifest_newest.sh" --manifest "$WORK_DIR/manifest.json" > "$WORK_DIR/release.json" \
    || plugin_fail "Kein Release im Manifest: $MANIFEST_URL"
version="$(jq -r '.version' "$WORK_DIR/release.json")"
url="$(jq -r '.url' "$WORK_DIR/release.json")"
sha256="$(jq -r '.sha256' "$WORK_DIR/release.json")"

release_dir="$CACHE_DIR/v$version"
release_db="$release_dir/discere_reference.db"

# Ein Cache-Eintrag gilt nur, wenn er zum Manifest passt und die entpackte
# DB seitdem unverändert ist: Eine lokal veränderte DB würde sonst Vorgänger
# eines vollständigen Builds.
cache_is_valid() {
    [[ -f "$release_db" ]] \
        && [[ "$(cat "$release_dir/sha256" 2> /dev/null || true)" == "$sha256" ]] \
        && [[ "$(cat "$release_dir/db_sha256" 2> /dev/null || true)" == "$(sha256_of "$release_db")" ]]
}

if cache_is_valid; then
    plugin_log "Vorgänger v$version aus dem Cache: $release_db"
else
    if [[ -f "$release_db" ]]; then
        plugin_warn "Cache von v$version passt nicht zum Manifest oder wurde verändert — lade neu."
    fi
    plugin_log "Lade Vorgänger v$version: $url"
    curl --silent --show-error --location --fail --output "$WORK_DIR/release.db.gz" "$url" \
        || plugin_fail "Download fehlgeschlagen: $url"
    actual="$(sha256_of "$WORK_DIR/release.db.gz")"
    [[ "$actual" == "$sha256" ]] \
        || plugin_fail "Prüfsumme falsch: $url hat $actual, das Manifest nennt $sha256."
    gunzip --stdout "$WORK_DIR/release.db.gz" > "$WORK_DIR/discere_reference.db" \
        || plugin_fail "Entpacken fehlgeschlagen: $url"
    # Ein Release kann im WAL-Modus vorliegen; im Rollback-Modus bleibt der
    # Cache beim Lesen frei von -wal/-shm-Dateien.
    sqlite3 "$WORK_DIR/discere_reference.db" "PRAGMA journal_mode = DELETE;" > /dev/null \
        || plugin_fail "Keine lesbare Referenz-DB: $url"
    mkdir -p "$release_dir"
    mv "$WORK_DIR/discere_reference.db" "$release_db"
    echo "$sha256" > "$release_dir/sha256"
    sha256_of "$release_db" > "$release_dir/db_sha256"
    plugin_log "Vorgänger v$version zwischengespeichert: $release_db"
fi

# Der Eintrag neben der DB nennt Version und Prüfsumme des Vorgängers;
# build.sh vermerkt beides in der neuen DB, core/check_publishable.sh
# vergleicht es mit dem dann neuesten veröffentlichten Release.
cp "$WORK_DIR/release.json" "$release_dir/manifest.json"

require_reference_db "$release_db"
echo "$release_db"
