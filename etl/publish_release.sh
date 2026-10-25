#!/usr/bin/env bash
# =============================================================================
# publish_release.sh — Maintainer-only: publish a reference-DB release
#
# Compresses a locally built discere_reference.db, uploads it as a GitHub
# Release asset on the discere-data repo, and updates/pushes
# data/reference-db/manifest.json there — the small file the app polls to
# decide whether a newer reference DB is available (see
# lib/shared/persistence/reference_database_provisioner.dart and
# https://github.com/discere-app/discere/issues/54).
#
# The manifest names, under "schemas", the newest release of every schema
# version, keyed by that version; its top level is always the newest
# schema-1 release, for app builds that predate "schemas". Every app takes
# the newest release it can read, so a schema change needs no particular
# order of app and release rollout. This script sets the entry of the
# release's schema and, for schema 1 only, the top level as well
# (core/manifest_update.sh).
#
# Run manually after ./etl/build.sh has produced a fresh
# assets/database/discere_reference.db. Only a complete, validated build
# against the release that is published right now, under a higher version
# than that release, is accepted (core/check_publishable.sh): a partial
# build, a --no-enrich or --initial build, one against an older predecessor,
# or a --version not above the published one is refused. "Published" means
# the newest release of any schema (core/manifest_newest.sh). Every image
# host with usable pictures must also serve a sample of them to the app's
# User-Agent (core/check_image_hosts.sh, needs network access): a host that
# blocks the app looks fine in the DB and in a browser. Not part of CI — reference-DB
# updates are infrequent and this mirrors discere-data's existing manual
# publish pattern (scripts/generate-index.sh).
#
# Usage:
#   ./etl/publish_release.sh --version 3
#   ./etl/publish_release.sh --version 3 \
#     --source /path/to/discere_reference.db --data-repo ../discere-data
#
# Flags:
#   --version <int>         New release "version" (data content version),
#                            one counter across all schemas. Bump whenever
#                            the DB content changes; must be greater than
#                            the newest published version.
#                            The release's schema version is not a flag:
#                            core/schema_version.sh derives it from the DB
#                            (2 for IDs without source plus register and
#                            aliases, 1 for IDs with source). A wrong value
#                            would let an app install a DB it cannot read.
#   --source <path>         Built reference DB
#                            (default: assets/database/discere_reference.db)
#   --data-repo <path>      Local discere-data checkout
#                            (default: ../discere-data, sibling checkout)
#   --tag <name>             Release tag (default: refdb-v<version>)
#
# Requires: gh (authenticated — run `gh auth login` once), jq, sha256sum (or
# shasum on macOS), gzip, git, curl. The discere-data checkout needs a "github"
# git remote pointing at github.com/discere-app/discere-data.
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=./core/plugin_api.sh
source "$SCRIPT_DIR/core/plugin_api.sh"

REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

SOURCE_DB="$REPO_ROOT/assets/database/discere_reference.db"
DATA_REPO="$REPO_ROOT/../discere-data"
GITHUB_REPO="discere-app/discere-data"
VERSION=""
SCHEMA_VERSION=""
TAG=""

log()  { echo "[$(date '+%H:%M:%S')] [publish_release] $*" >&2; }
fail() { echo "[ERROR] [publish_release] $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) plugin_require_value "$@"; VERSION="$2"; shift ;;
        --schema-version)
            fail "--schema-version gibt es nicht mehr: Die Schemaversion wird aus der DB abgeleitet (core/schema_version.sh)." ;;
        --source) plugin_require_value "$@"; SOURCE_DB="$2"; shift ;;
        --data-repo) plugin_require_value "$@"; DATA_REPO="$2"; shift ;;
        --tag) plugin_require_value "$@"; TAG="$2"; shift ;;
        --help|-h)
            plugin_print_help "$0"
            exit 0
            ;;
        *) plugin_fail_unknown_argument "$1" ;;
    esac
    shift
done

[[ -n "$VERSION" ]] || fail "--version ist erforderlich"
command -v gh >/dev/null 2>&1 || fail "gh CLI nicht gefunden (brew install gh)"
gh auth status >/dev/null 2>&1 || fail "gh ist nicht eingeloggt (gh auth login)"
[[ -f "$SOURCE_DB" ]] || fail "Quelle nicht gefunden: $SOURCE_DB"
[[ -d "$DATA_REPO" ]] || fail "discere-data Checkout nicht gefunden: $DATA_REPO"

TAG="${TAG:-refdb-v$VERSION}"
DATA_REPO="$(cd "$DATA_REPO" && pwd)"

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | cut -d' ' -f1
    else
        shasum -a 256 "$1" | cut -d' ' -f1
    fi
}

branch="$(git -C "$DATA_REPO" rev-parse --abbrev-ref HEAD)"
[[ "$branch" == "main" ]] || fail "discere-data ist auf '$branch', erwartet 'main'"
git -C "$DATA_REPO" diff --quiet && git -C "$DATA_REPO" diff --cached --quiet \
    || fail "discere-data hat uncommittete Änderungen"
git -C "$DATA_REPO" remote get-url github >/dev/null 2>&1 \
    || fail "kein 'github' Remote in discere-data konfiguriert"

log "Pulle discere-data github/main..."
git -C "$DATA_REPO" pull --ff-only github main

# Nur ein vollständiger, validierter Build gegen genau das jetzt
# veröffentlichte Release darf es ablösen (Teilbuild, --initial oder ein
# veralteter Vorgänger schrieben in der App Lernstände falsch um), und nur
# unter einer höheren Version (sonst lädt die App es nie).
"$SCRIPT_DIR/core/check_publishable.sh" --db "$SOURCE_DB" \
    --manifest "$DATA_REPO/data/reference-db/manifest.json" --version "$VERSION" \
    || fail "$SOURCE_DB darf nicht veröffentlicht werden."
# Ein Host, der die App aussperrt, fällt weder in der DB noch im Browser auf;
# seine Bilder blieben in der App leer.
"$SCRIPT_DIR/core/check_image_hosts.sh" --db "$SOURCE_DB" \
    || fail "Bild-Hosts von $SOURCE_DB liefern der App keine Bilder."
SCHEMA_VERSION="$("$SCRIPT_DIR/core/schema_version.sh" --db "$SOURCE_DB")" \
    || fail "Schemaversion von $SOURCE_DB nicht bestimmbar."
log "Schemaversion laut DB: $SCHEMA_VERSION"

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
ASSET_NAME="discere_reference.db.gz"
COMPRESSED="$WORK_DIR/$ASSET_NAME"

# Der Build legt die DB im WAL-Modus an. Veröffentlicht wird sie im
# Rollback-Modus: Das schreibt ein noch nicht übernommenes -wal in die Datei
# selbst (gzip nimmt nur sie mit), und die App legt beim Öffnen keine
# -wal/-shm daneben an.
log "Stelle $SOURCE_DB auf journal_mode = DELETE"
mode="$(sqlite3 "$SOURCE_DB" "PRAGMA journal_mode = DELETE;")" \
    || fail "journal_mode ließ sich nicht umstellen: $SOURCE_DB"
[[ "$mode" == "delete" ]] || fail "journal_mode ist '$mode', erwartet 'delete': $SOURCE_DB"
[[ ! -e "$SOURCE_DB-wal" ]] \
    || fail "$SOURCE_DB-wal liegt noch daneben – öffnet ein anderer Prozess die DB?"

log "Komprimiere $SOURCE_DB"
gzip --keep --stdout "$SOURCE_DB" > "$COMPRESSED"

CHECKSUM="$(sha256_of "$COMPRESSED")"
SIZE_BYTES="$(wc -c < "$COMPRESSED" | tr -d ' ')"
log "Fertig: $ASSET_NAME ($SIZE_BYTES bytes, sha256=$CHECKSUM)"

log "Erstelle Release $TAG auf $GITHUB_REPO"
gh release create "$TAG" "$COMPRESSED" \
    --repo "$GITHUB_REPO" \
    --title "$TAG" \
    --notes "Reference database v$VERSION (schema v$SCHEMA_VERSION)"

ASSET_URL="https://github.com/$GITHUB_REPO/releases/download/$TAG/$ASSET_NAME"
log "Hochgeladen: $ASSET_URL"

MANIFEST_DIR="$DATA_REPO/data/reference-db"
MANIFEST_FILE="$MANIFEST_DIR/manifest.json"

PUBLISHED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
"$SCRIPT_DIR/core/manifest_update.sh" --manifest "$MANIFEST_FILE" \
    --schema "$SCHEMA_VERSION" --version "$VERSION" --url "$ASSET_URL" \
    --sha256 "$CHECKSUM" --size "$SIZE_BYTES" --published-at "$PUBLISHED_AT" \
    || fail "Manifest nicht fortschreibbar: $MANIFEST_FILE"

log "Geschrieben: $MANIFEST_FILE"

if [[ -z "$(git -C "$DATA_REPO" status --porcelain -- "$MANIFEST_DIR")" ]]; then
    log "Manifest unverändert, nichts zu committen."
    exit 0
fi

git -C "$DATA_REPO" add "$MANIFEST_DIR"
git -C "$DATA_REPO" commit -m "chore: publish reference-db v$VERSION (schema $SCHEMA_VERSION)"

log "Pushe discere-data github/main..."
git -C "$DATA_REPO" push github main

log "Fertig: reference-db v$VERSION veröffentlicht ($TAG)."
