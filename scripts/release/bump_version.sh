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
#   ./scripts/release/bump_version.sh --patch --commit  # bump + branch + commit, prints the PR command
#   ./scripts/release/bump_version.sh --patch --pr      # bump + branch + commit + push + open the PR
#   ./scripts/release/bump_version.sh --dry-run --minor
#
# --commit must be run from main (clean working tree): main is a protected
# branch, so the bump can't be pushed directly — it needs its own branch and
# a PR, same as submersion's promote.yml does this.
#
# --pr implies --commit and additionally pushes the branch and opens the PR
# via `gh` — the only remaining manual step is tagging the merge commit once
# the PR is actually merged (that can't happen until a human approves it).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"
PUBSPEC="$PROJECT_DIR/pubspec.yaml"

# --- Parse arguments ---
BUMP_TYPE=""
SET_VERSION=""
DRY_RUN=false
AUTO_COMMIT=false
AUTO_PR=false

for arg in "$@"; do
  case "$arg" in
    --major)   BUMP_TYPE="major" ;;
    --minor)   BUMP_TYPE="minor" ;;
    --patch)   BUMP_TYPE="patch" ;;
    --set)     BUMP_TYPE="set" ;;
    --commit)  AUTO_COMMIT=true ;;
    --pr)      AUTO_COMMIT=true; AUTO_PR=true ;;
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
        echo "Usage: $0 [--major|--minor|--patch|--set X.Y.Z] [--commit] [--pr] [--dry-run]"
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
  CURRENT_BRANCH=$(git -C "$PROJECT_DIR" rev-parse --abbrev-ref HEAD)
  if [ "$CURRENT_BRANCH" != "main" ]; then
    echo "Error: --commit must be run from main (currently on '$CURRENT_BRANCH')."
    echo "main is protected — the bump needs its own branch, branched from main."
    exit 1
  fi

  BUMP_BRANCH="chore/bump-${NEW_SEMVER}"
  git -C "$PROJECT_DIR" checkout -b "$BUMP_BRANCH"
  git -C "$PROJECT_DIR" add "$PUBSPEC"
  git -C "$PROJECT_DIR" commit -m "chore: bump version to $NEW_SEMVER"

  echo ""
  echo "Reminder: update distribution/whatsnew/*/whatsnew with this release's"
  echo "user-facing notes (max 500 chars, no markdown), commit that on"
  echo "$BUMP_BRANCH, and push before merging the PR — otherwise the Play"
  echo "Store release ships with the previous release's notes."

  if [ "$AUTO_PR" = true ]; then
    echo ""
    echo "Pushing $BUMP_BRANCH and opening the PR..."
    git -C "$PROJECT_DIR" push -u origin "$BUMP_BRANCH"
    if PR_URL=$(gh pr create --repo discere-app/discere \
      --title "chore: bump version to $NEW_SEMVER" \
      --body "Version bump, no functional changes." \
      --base main --head "$BUMP_BRANCH"); then
      echo "$PR_URL"
      echo ""
      echo "After the PR is merged, tag the merge commit on main:"
      echo "  git checkout main && git pull"
      echo "  git tag $NEW_SEMVER && git push --tags"
    else
      echo ""
      echo "Push succeeded but 'gh pr create' failed — open it manually:"
      echo "  gh pr create --title \"chore: bump version to $NEW_SEMVER\" --body \"Version bump, no functional changes.\" --base main"
      exit 1
    fi
  else
    echo ""
    echo "Next step — push and open the PR:"
    echo "  git push -u origin $BUMP_BRANCH"
    echo "  gh pr create --title \"chore: bump version to $NEW_SEMVER\" --body \"Version bump, no functional changes.\" --base main"
    echo ""
    echo "After the PR is merged, tag the merge commit on main:"
    echo "  git checkout main && git pull"
    echo "  git tag $NEW_SEMVER && git push --tags"
  fi
else
  echo ""
  echo "Reminder: update distribution/whatsnew/*/whatsnew with this release's"
  echo "user-facing notes (max 500 chars, no markdown) before merging the PR —"
  echo "otherwise the Play Store release ships with the previous release's"
  echo "notes."
  echo ""
  echo "Next steps (main is protected — bump needs its own branch):"
  echo "  git checkout -b chore/bump-$NEW_SEMVER"
  echo "  git add pubspec.yaml && git commit -m 'chore: bump version to $NEW_SEMVER'"
  echo "  git push -u origin chore/bump-$NEW_SEMVER"
  echo "  gh pr create --title \"chore: bump version to $NEW_SEMVER\" --body \"Version bump, no functional changes.\" --base main"
  echo ""
  echo "After the PR is merged, tag the merge commit on main:"
  echo "  git checkout main && git pull"
  echo "  git tag $NEW_SEMVER && git push --tags"
  echo ""
  echo "Tip: rerun with --pr instead of --commit to do the commit/push/PR steps automatically."
fi
