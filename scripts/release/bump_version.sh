#!/usr/bin/env bash
# Bump the semantic version in pubspec.yaml.
#
# The build number is not stored here — release.yml computes it at build
# time as the commit count on the release commit (`git rev-list --count`)
# and passes it to `flutter build` via --build-number. This script only
# manages the marketing version (X.Y.Z).
#
# Usage:
#   ./scripts/release/bump_version.sh --patch       # X.Y.Z -> X.Y.(Z+1)
#   ./scripts/release/bump_version.sh --minor       # X.Y.Z -> X.(Y+1).0
#   ./scripts/release/bump_version.sh --major       # X.Y.Z -> (X+1).0.0
#   ./scripts/release/bump_version.sh --set 2.0.0   # X.Y.Z -> 2.0.0
#   ./scripts/release/bump_version.sh --patch --commit  # bump + git commit
#   ./scripts/release/bump_version.sh --dry-run --minor

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
PUBSPEC="$PROJECT_DIR/pubspec.yaml"

# --- Parse arguments ---
BUMP_TYPE=""
SET_VERSION=""
DRY_RUN=false
AUTO_COMMIT=false

for arg in "$@"; do
  case "$arg" in
    --major)   BUMP_TYPE="major" ;;
    --minor)   BUMP_TYPE="minor" ;;
    --patch)   BUMP_TYPE="patch" ;;
    --set)     BUMP_TYPE="set" ;;
    --commit)  AUTO_COMMIT=true ;;
    --dry-run) DRY_RUN=true ;;
    --help|-h)
      sed -nE '2,/^$/s/^# ?//p' "$0"
      exit 0
      ;;
    *)
      if [ "$BUMP_TYPE" = "set" ] && [ -z "$SET_VERSION" ]; then
        SET_VERSION="$arg"
      else
        echo "Unknown argument: $arg"
        echo "Usage: $0 [--major|--minor|--patch|--set X.Y.Z] [--commit] [--dry-run]"
        exit 1
      fi
      ;;
  esac
done

if [ -z "$BUMP_TYPE" ]; then
  echo "Error: No bump type specified."
  echo "Usage: $0 [--major|--minor|--patch|--set X.Y.Z] [--commit] [--dry-run]"
  exit 1
fi

if [ "$BUMP_TYPE" = "set" ] && [ -z "$SET_VERSION" ]; then
  echo "Error: --set requires a version argument (e.g., --set 2.0.0)"
  exit 1
fi

# --- Read current version ---
VERSION_LINE=$(grep '^version:' "$PUBSPEC")
if [ -z "$VERSION_LINE" ]; then
  echo "Error: Could not find 'version:' in $PUBSPEC"
  exit 1
fi

# Strip any leftover +N build suffix from older pubspec.yaml revisions.
SEMVER=$(echo "$VERSION_LINE" | sed 's/version: *//' | cut -d'+' -f1)

MAJOR=$(echo "$SEMVER" | cut -d'.' -f1)
MINOR=$(echo "$SEMVER" | cut -d'.' -f2)
PATCH=$(echo "$SEMVER" | cut -d'.' -f3)

if [ -z "$MAJOR" ] || [ -z "$MINOR" ] || [ -z "$PATCH" ]; then
  echo "Error: Could not parse version '$SEMVER' (expected format: X.Y.Z)"
  exit 1
fi

# --- Calculate new version ---
case "$BUMP_TYPE" in
  major)
    NEW_SEMVER="$((MAJOR + 1)).0.0"
    ;;
  minor)
    NEW_SEMVER="${MAJOR}.$((MINOR + 1)).0"
    ;;
  patch)
    NEW_SEMVER="${MAJOR}.${MINOR}.$((PATCH + 1))"
    ;;
  set)
    if ! echo "$SET_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$'; then
      echo "Error: Invalid version format '$SET_VERSION' (expected X.Y.Z)"
      exit 1
    fi
    NEW_SEMVER="$SET_VERSION"
    ;;
esac

echo "=== Version Bump ==="
echo "Current: $SEMVER"
echo "New:     $NEW_SEMVER"
echo ""

if [ "$DRY_RUN" = true ]; then
  echo "[Dry run] Would update $PUBSPEC"
  exit 0
fi

# --- Update pubspec.yaml ---
# perl, not sed -i: BSD sed (macOS) requires `-i ''` while GNU sed (Linux CI
# runners) reads that '' as the script and fails with "can't read s/...: No
# such file or directory". perl -pi is portable across both.
perl -pi -e "s/^version: .*/version: ${NEW_SEMVER}/" "$PUBSPEC"

# Verify the change
UPDATED=$(grep '^version:' "$PUBSPEC" | sed 's/version: *//')
if [ "$UPDATED" != "$NEW_SEMVER" ]; then
  echo "Error: Verification failed. Expected '$NEW_SEMVER' but found '$UPDATED'"
  exit 1
fi

echo "Updated $PUBSPEC"

if [ "$AUTO_COMMIT" = true ]; then
  git -C "$PROJECT_DIR" add "$PUBSPEC"
  git -C "$PROJECT_DIR" commit -m "chore: bump version to $NEW_SEMVER"
  echo ""
  echo "Next step:"
  echo "  git push && git tag $NEW_SEMVER && git push --tags"
else
  echo ""
  echo "Next steps:"
  echo "  git add pubspec.yaml && git commit -m 'chore: bump version to $NEW_SEMVER'"
  echo "  git push && git tag $NEW_SEMVER && git push --tags"
fi
