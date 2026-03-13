#!/usr/bin/env zsh
# release.sh — Build, verify, package, and publish a Barkeep release.
#
# Usage: ./release.sh <version>
#   e.g. ./release.sh 1.0.0
#
# Requires: xcodegen, xcodebuild, hdiutil, gh (GitHub CLI), git

set -euo pipefail

REPO="sevmorris/mrk"
APP_NAME="Barkeep"
TAG_PREFIX="barkeep"

# ── Args ──────────────────────────────────────────────────────────────────────
if [[ $# -ne 1 ]]; then
    echo "Usage: $0 <version>"
    echo "  e.g. $0 1.0.0"
    exit 1
fi

VERSION="$1"
TAG="${TAG_PREFIX}-v${VERSION}"
SCRIPT_DIR="${0:A:h}"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
PROJECT="$PROJECT_DIR/Barkeep.xcodeproj"
SCHEME="Barkeep"
DERIVED_DATA="/tmp/barkeep_build_${VERSION}"
APP_PATH="$DERIVED_DATA/Build/Products/Release/Barkeep.app"
STAGING="/tmp/barkeep_dmg_${VERSION}"
DMG="/tmp/Barkeep-v${VERSION}.dmg"
MOUNT="/tmp/barkeep_verify_${VERSION}"

# ── Helpers ───────────────────────────────────────────────────────────────────
step()  { echo "\n▶ $*"; }
ok()    { echo "  ✓ $*"; }
fail()  { echo "\n  ✗ $*" >&2; exit 1; }

cleanup() {
    rm -rf "$STAGING" "$MOUNT" "$DERIVED_DATA"
    rm -f "$DMG"
}

# ── Preflight ─────────────────────────────────────────────────────────────────
step "Preflight checks"
for cmd in xcodegen xcodebuild hdiutil gh git; do
    command -v $cmd &>/dev/null || fail "'$cmd' not found in PATH"
done
ok "Tools present"

cd "$REPO_ROOT"

if [[ -n "$(git status --porcelain)" ]]; then
    fail "Working tree is dirty — commit or stash changes before releasing"
fi
ok "Working tree clean"

if git tag | grep -q "^${TAG}$"; then
    fail "Tag $TAG already exists — has this version been released?"
fi
ok "Tag $TAG is available"

# ── Version bump ──────────────────────────────────────────────────────────────
step "Bumping version to $VERSION"
CURRENT=$(grep 'CFBundleShortVersionString' "$PROJECT_DIR/project.yml" | grep -o '"[0-9][0-9.]*"' | tr -d '"')
if [[ "$CURRENT" == "$VERSION" ]]; then
    ok "Already at $VERSION — skipping bump"
else
    sed -i '' "s/CFBundleShortVersionString: \"${CURRENT}\"/CFBundleShortVersionString: \"${VERSION}\"/" \
        "$PROJECT_DIR/project.yml"
    ok "Bumped $CURRENT → $VERSION"
    git add "$PROJECT_DIR/project.yml"
    git commit -m "barkeep: bump version to $VERSION"
    ok "Committed version bump"
fi

# ── Generate xcodeproj ────────────────────────────────────────────────────────
step "Generating Xcode project"
cd "$PROJECT_DIR"
xcodegen generate --quiet
ok "xcodeproj generated"

# ── Build ─────────────────────────────────────────────────────────────────────
step "Building (clean, Release)"
rm -rf "$DERIVED_DATA"
xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED_DATA" \
    -quiet
ok "Build complete"

# ── Verify app version ────────────────────────────────────────────────────────
step "Verifying built app version"
BUILT_VERSION=$(defaults read "$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)
[[ "$BUILT_VERSION" == "$VERSION" ]] || \
    fail "App version mismatch: expected $VERSION, got $BUILT_VERSION"
ok "App reports $BUILT_VERSION"

# ── Stage DMG contents ────────────────────────────────────────────────────────
step "Staging DMG contents"
rm -rf "$STAGING"
mkdir "$STAGING"
cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
ok "App and Applications alias staged"

# ── Create DMG ────────────────────────────────────────────────────────────────
step "Creating DMG"
rm -f "$DMG"
hdiutil create \
    -volname "Barkeep v${VERSION}" \
    -srcfolder "$STAGING" \
    -ov \
    -format UDZO \
    -o "$DMG" \
    -quiet
ok "Created $(du -sh $DMG | cut -f1) DMG"

# ── Verify DMG ────────────────────────────────────────────────────────────────
step "Verifying DMG"
rm -rf "$MOUNT"
mkdir "$MOUNT"
hdiutil attach "$DMG" -mountpoint "$MOUNT" -quiet -nobrowse
DMG_VERSION=$(defaults read "$MOUNT/Barkeep.app/Contents/Info.plist" CFBundleShortVersionString)
hdiutil detach "$MOUNT" -quiet
[[ "$DMG_VERSION" == "$VERSION" ]] || \
    fail "DMG version mismatch: expected $VERSION, got $DMG_VERSION"
ok "DMG contains $DMG_VERSION"

# ── Tag and push ──────────────────────────────────────────────────────────────
step "Tagging and pushing"
cd "$REPO_ROOT"
git tag "$TAG"
git push
git push origin "$TAG"
ok "Pushed $TAG"

# ── GitHub release ────────────────────────────────────────────────────────────
step "Creating GitHub release"
PREV_TAG=$(git tag --sort=-creatordate | grep "^${TAG_PREFIX}-v" | grep -v "^${TAG}$" | head -1 || true)
if [[ -n "$PREV_TAG" ]]; then
    CHANGES=$(git log "${PREV_TAG}..HEAD" --pretty=format:"- %s" \
        | grep -v "^- barkeep: bump version" || true)
else
    CHANGES=$(git log --pretty=format:"- %s" \
        | grep -v "^- barkeep: bump version" || true)
fi
RELEASE_NOTES="### Changes
${CHANGES}"
gh release create "$TAG" "$DMG" \
    --repo "$REPO" \
    --title "Barkeep v${VERSION}" \
    --notes "$RELEASE_NOTES"
ok "Release published"

# ── Remove old Barkeep releases ───────────────────────────────────────────────
step "Removing old releases"
OLD_TAGS=$(gh release list --repo "$REPO" --limit 100 --json tagName \
    --jq '.[].tagName' | grep "^${TAG_PREFIX}-v" | grep -v "^${TAG}$" || true)
if [[ -z "$OLD_TAGS" ]]; then
    ok "No old releases to remove"
else
    while IFS= read -r old_tag; do
        gh release delete "$old_tag" --repo "$REPO" --yes --cleanup-tag 2>/dev/null || true
        git tag -d "$old_tag" 2>/dev/null || true
        ok "Removed $old_tag"
    done <<< "$OLD_TAGS"
fi

# ── Clean up temp files ───────────────────────────────────────────────────────
step "Cleaning up"
rm -rf "$STAGING" "$MOUNT" "$DERIVED_DATA"
rm -f "$DMG"
ok "Temp files removed"

# ── Done ──────────────────────────────────────────────────────────────────────
RELEASE_URL="https://github.com/${REPO}/releases/tag/${TAG}"
echo "\n✓ Barkeep v${VERSION} released successfully."
echo "  $RELEASE_URL"
open "$RELEASE_URL"
