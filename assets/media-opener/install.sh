#!/usr/bin/env bash
set -euo pipefail

# Media Opener — ask before an audio or video file opens
#
# Applied by mrk post-install. A double-click on an audio file in Finder,
# often a slow click meant to rename it, opened the file in Music and added it
# to the library. Apps that install themselves as editors or taggers, such as
# MusicBrainz Picard and Fission, also take over video and audio types. Media
# Opener is a small AppleScript app that asks first: Cancel (the default),
# QuickTime Player, and Music or VLC.
#
# This script builds ~/Applications/Media Opener.app from
# MediaOpener.applescript, when the app is missing or was built from different
# sources. The SHA-256 of the AppleScript and of this script is kept in the
# app's Info.plist as MrkSourceSHA. It deletes Audio Opener.app, the audio-only
# app that came before it.
#
# It does not choose the file types that the app opens. config/default-apps.tsv
# lists them, and scripts/default-apps sets them; post-install runs it next.

_self="${BASH_SOURCE[0]}"
while [[ -L "$_self" ]]; do
  _dir="$(cd "$(dirname "$_self")" && pwd)"
  _self="$(readlink "$_self")"
  [[ "$_self" != /* ]] && _self="$_dir/$_self"
done
HERE="$(cd "$(dirname "$_self")" && pwd)"
SCRIPT_DIR="$(cd "$HERE/../.." && pwd)/scripts"
source "$SCRIPT_DIR/lib.sh"

SRC="$HERE/MediaOpener.applescript"
APP_DIR="$HOME/Applications"
APP="$APP_DIR/Media Opener.app"
OLD_APP="$APP_DIR/Audio Opener.app"
BUNDLE_ID="local.mrk.media-opener"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

sha=$(cat "$SRC" "$HERE/install.sh" | shasum -a 256 | cut -d' ' -f1)
built=$(/usr/libexec/PlistBuddy -c "Print :MrkSourceSHA" "$APP/Contents/Info.plist" 2>/dev/null || true)

build_app(){
  local tmp bundle plist out
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/media-opener.XXXXXX")
  bundle="$tmp/Media Opener.app"
  plist="$bundle/Contents/Info.plist"
  # osacompile signs the droplet and says "replacing existing signature" on
  # every build, so its output is shown only on a failure. The droplet has no
  # bundle identifier, and its Info.plist accepts every file. Replace that with
  # audio and video only, so the app is offered for them in Open With and
  # nowhere else. LSUIElement keeps it out of the Dock while the dialog is up.
  # The bundle is signed again, ad hoc, after these changes.
  if ! out=$(osacompile -o "$bundle" "$SRC" 2>&1); then
    printf '%s\n' "$out" >&2
    rm -rf "$tmp"
    return 1
  fi
  if /usr/libexec/PlistBuddy \
          -c "Add :CFBundleIdentifier string $BUNDLE_ID" \
          -c "Delete :CFBundleDocumentTypes" \
          -c "Add :CFBundleDocumentTypes array" \
          -c "Add :CFBundleDocumentTypes:0 dict" \
          -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string Media" \
          -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Viewer" \
          -c "Add :CFBundleDocumentTypes:0:LSHandlerRank string Alternate" \
          -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes array" \
          -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string public.audio" \
          -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:1 string public.movie" \
          -c "Add :LSUIElement bool true" \
          -c "Add :MrkSourceSHA string $sha" \
          "$plist" >/dev/null \
     && codesign --force --deep -s - "$bundle" 2>/dev/null \
     && mkdir -p "$APP_DIR" \
     && rm -rf "$APP" \
     && mv "$bundle" "$APP" \
     && "$LSREGISTER" -f "$APP"; then
    rm -rf "$tmp"
    return 0
  fi
  rm -rf "$tmp"
  return 1
}

if [[ -n "$built" && "$built" == "$sha" ]]; then
  logskip "Media Opener app" "built from these sources"
elif build_app; then
  ok "Built $APP"
else
  warn "Could not build $APP"
  exit 1
fi

# Audio Opener was the audio-only app before Media Opener. Its types go to
# Media Opener when default-apps runs next.
if [[ -d "$OLD_APP" ]]; then
  "$LSREGISTER" -u "$OLD_APP" 2>/dev/null || true
  rm -rf "$OLD_APP"
  ok "Deleted $OLD_APP, which Media Opener replaces"
fi
