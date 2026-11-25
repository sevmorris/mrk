#!/usr/bin/env bash
set -euo pipefail

# Audio Opener — ask before an audio file opens in Music
#
# Applied by mrk post-install. A double-click on an audio file in Finder,
# often a slow click meant to rename it, opened the file in Music and added it
# to the library. Audio Opener is a small AppleScript app that asks first:
# Cancel (the default), QuickTime Player or Music.
#
# The script:
# 1. builds ~/Applications/Audio Opener.app from AudioOpener.applescript, with
#    set-default.swift compiled into its Resources, when the app is missing or
#    was built from different sources. The SHA-256 of the two sources is kept
#    in the app's Info.plist as MrkSourceSHA. A build needs swiftc, from the
#    Command Line Tools that Homebrew installs in Phase 2.
# 2. runs set-default, which makes the app the default for each type in TYPES
#    while Music opens that type, or no app does. A type you have given to
#    another app stays with it. macOS asks you to confirm each change, so an
#    unattended run skips this step.
#
# It records no undo. To give a type back to Music: Get Info on a file of that
# type, Open with: Music, Change All.

_self="${BASH_SOURCE[0]}"
while [[ -L "$_self" ]]; do
  _dir="$(cd "$(dirname "$_self")" && pwd)"
  _self="$(readlink "$_self")"
  [[ "$_self" != /* ]] && _self="$_dir/$_self"
done
HERE="$(cd "$(dirname "$_self")" && pwd)"
SCRIPT_DIR="$(cd "$HERE/../.." && pwd)/scripts"
source "$SCRIPT_DIR/lib.sh"

SRC="$HERE/AudioOpener.applescript"
HELPER_SRC="$HERE/set-default.swift"
APP_DIR="$HOME/Applications"
APP="$APP_DIR/Audio Opener.app"
HELPER="$APP/Contents/Resources/set-default"
BUNDLE_ID="local.mrk.audio-opener"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# The types Music opens on a Mac with no other audio app set: MP3, MPEG-4 audio
# (.m4a, and protected .m4p from the iTunes Store), WAV, AIFF, AIFC and MP2.
TYPES=(
  public.mp3
  public.mpeg-4-audio
  com.apple.m4a-audio
  com.apple.protected-mpeg-4-audio
  com.microsoft.waveform-audio
  public.aiff-audio
  public.aifc-audio
  public.mp2
)

failed=0

###############################################################################
# 1. The app                                                                  #
###############################################################################

sha=$(cat "$SRC" "$HELPER_SRC" | shasum -a 256 | cut -d' ' -f1)
built=$(/usr/libexec/PlistBuddy -c "Print :MrkSourceSHA" "$APP/Contents/Info.plist" 2>/dev/null || true)

build_app(){
  local tmp bundle plist out
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/audio-opener.XXXXXX")
  bundle="$tmp/Audio Opener.app"
  plist="$bundle/Contents/Info.plist"
  # osacompile signs the droplet and says "replacing existing signature" on
  # every build, so its output, and swiftc's, is shown only on a failure. The
  # droplet has no bundle identifier, and its Info.plist accepts every file.
  # Replace that with audio only, so the app is offered for audio in Open With
  # and nowhere else. LSUIElement keeps it out of the Dock while the dialog is
  # up. The bundle is signed again, ad hoc, after these changes.
  if ! out=$(osacompile -o "$bundle" "$SRC" 2>&1); then
    printf '%s\n' "$out" >&2
    rm -rf "$tmp"
    return 1
  fi
  if ! out=$(swiftc -O -o "$bundle/Contents/Resources/set-default" "$HELPER_SRC" 2>&1); then
    printf '%s\n' "$out" >&2
    rm -rf "$tmp"
    return 1
  fi
  if /usr/libexec/PlistBuddy \
          -c "Add :CFBundleIdentifier string $BUNDLE_ID" \
          -c "Delete :CFBundleDocumentTypes" \
          -c "Add :CFBundleDocumentTypes array" \
          -c "Add :CFBundleDocumentTypes:0 dict" \
          -c "Add :CFBundleDocumentTypes:0:CFBundleTypeName string Audio" \
          -c "Add :CFBundleDocumentTypes:0:CFBundleTypeRole string Viewer" \
          -c "Add :CFBundleDocumentTypes:0:LSHandlerRank string Alternate" \
          -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes array" \
          -c "Add :CFBundleDocumentTypes:0:LSItemContentTypes:0 string public.audio" \
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

if [[ -n "$built" && "$built" == "$sha" && -x "$HELPER" ]]; then
  logskip "Audio Opener app" "built from these sources"
elif ! command -v swiftc >/dev/null 2>&1; then
  warn "Audio Opener needs swiftc to build: xcode-select --install"
  exit 1
elif build_app; then
  ok "Built $APP"
else
  warn "Could not build $APP"
  exit 1
fi

###############################################################################
# 2. The default app for each type                                            #
###############################################################################

# macOS asks you to confirm each change, so this step needs someone at the
# Mac. An unattended run (post-install --yes) leaves the types as they are and
# says how to finish. A type you keep for Music is asked about again on the
# next run, while Music still opens it; it is not counted as a failure.
if [[ "${NONINTERACTIVE:-0}" == 1 ]]; then
  logskip "Audio Opener default" "macOS asks to confirm each type; run $HERE/install.sh at the Mac"
  exit 0
fi

set_n=0 already_n=0 asked=0
while IFS=$'\t' read -r type result; do
  [[ -n "$type" ]] || continue
  case "$result" in
    asking)
      if (( asked == 0 )); then
        info "macOS asks you to confirm each audio type that moves to Audio Opener."
        info "Read the buttons before you click: their order is not always the same."
      fi
      asked=1 ;;
    set)        set_n=$(( set_n + 1 )) ;;
    already)    already_n=$(( already_n + 1 )) ;;
    kept\ *)    logskip "$type" "opens in ${result#kept }" ;;
    declined\ *) logskip "$type" "kept for Music in the macOS dialog" ;;
    *)          warn "$type: $result"; failed=$(( failed + 1 )) ;;
  esac
done < <("$HELPER" "$APP" "${TYPES[@]}" 2>&1)

if (( set_n > 0 )); then ok "Audio Opener now opens $set_n audio type(s)"; fi
if (( already_n > 0 )); then logskip "Audio Opener default" "$already_n type(s) already set"; fi

if (( failed > 0 )); then exit 1; fi
