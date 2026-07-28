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
# Run manually after ./etl/build.sh has produced a fresh
# assets/database/discere_reference.db. Not part of CI — reference-DB
# updates are infrequent and this mirrors discere-data's existing manual
# publish pattern (scripts/generate-index.sh).
#
# Usage:
#   ./etl/publish_release.sh --version 3 --schema-version 1
#   ./etl/publish_release.sh --version 3 --schema-version 1 \
#     --source /path/to/discere_reference.db --data-repo ../discere-data
#
# Flags:
#   --version <int>         New manifest "version" (data content version).
#                            Bump whenever the DB content changes.
#   --schema-version <int>  Manifest "schemaVersion". Only bump when
#                            etl/core/sql/schema.sql changes in a way that
#                            requires a matching app release — the app is
#                            expected to refuse/ignore a manifest whose
#                            schemaVersion it doesn't understand.
#   --source <path>         Built reference DB
#                            (default: assets/database/discere_reference.db)
#   --data-repo <path>      Local discere-data checkout
#                            (default: ../discere-data, sibling checkout)
#   --tag <name>             Release tag (default: refdb-v<version>)
#
# Requires: gh (authenticated — run `gh auth login` once), jq, sha256sum (or
# shasum on macOS), gzip, git. The discere-data checkout needs a "github"
# git remote pointing at github.com/discere-app/discere-data.
# =============================================================================

set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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
        --version) VERSION="$2"; shift ;;
        --schema-version) SCHEMA_VERSION="$2"; shift ;;
        --source) SOURCE_DB="$2"; shift ;;
        --data-repo) DATA_REPO="$2"; shift ;;
        --tag) TAG="$2"; shift ;;
        --help|-h)
            sed -n '2,35p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *) fail "Unbekanntes Argument: $1" ;;
    esac
    shift
done

[[ -n "$VERSION" ]] || fail "--version ist erforderlich"
[[ -n "$SCHEMA_VERSION" ]] || fail "--schema-version ist erforderlich"
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

WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT
ASSET_NAME="discere_reference.db.gz"
COMPRESSED="$WORK_DIR/$ASSET_NAME"

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
mkdir -p "$MANIFEST_DIR"

PUBLISHED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -n \
    --argjson version "$VERSION" \
    --argjson schemaVersion "$SCHEMA_VERSION" \
    --arg url "$ASSET_URL" \
    --arg sha256 "$CHECKSUM" \
    --argjson compressedSizeBytes "$SIZE_BYTES" \
    --arg publishedAt "$PUBLISHED_AT" \
    '{version: $version, schemaVersion: $schemaVersion, url: $url, sha256: $sha256, compressedSizeBytes: $compressedSizeBytes, publishedAt: $publishedAt}' \
    > "$MANIFEST_FILE"

log "Geschrieben: $MANIFEST_FILE"

if [[ -z "$(git -C "$DATA_REPO" status --porcelain -- "$MANIFEST_DIR")" ]]; then
    log "Manifest unverändert, nichts zu committen."
    exit 0
fi

git -C "$DATA_REPO" add "$MANIFEST_DIR"
git -C "$DATA_REPO" commit -m "chore: publish reference-db v$VERSION"

log "Pushe discere-data github/main..."
git -C "$DATA_REPO" push github main

log "Fertig: reference-db v$VERSION veröffentlicht ($TAG)."
