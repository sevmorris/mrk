#!/usr/bin/env bash
set -euo pipefail

# Audio Hijack preferences
#
# Applied by mrk post-install.
# Sets theme, preferred audio editor, and buffer size.

_self="${BASH_SOURCE[0]}"
while [[ -L "$_self" ]]; do
  _dir="$(cd "$(dirname "$_self")" && pwd)"
  _self="$(readlink "$_self")"
  [[ "$_self" != /* ]] && _self="$_dir/$_self"
done
SCRIPT_DIR="$(cd "$(dirname "$_self")/../.." && pwd)/scripts"
source "$SCRIPT_DIR/lib.sh"

failed=0

# Dark theme (0=light, 1=auto, 2=dark)
defaults write com.rogueamoeba.audiohijack applicationTheme -int 2 || failed=$(( failed + 1 ))

# Preferred external audio editor — iZotope RX, the newest one installed.
#
# RX's bundle ID changes with its version. This line used to write
# com.izotope.RXPro, and on 2026-09-17 the RX on this Mac was the standalone
# "iZotope RX 12 Audio Editor", com.izotope.RX12, so Audio Hijack's editor
# pointed at an app that was not there. The ID is now read from the app. With no
# RX installed, the setting is left alone.
rx_app=""
rx_best=-1
for app in "/Applications/iZotope RX "*" Audio Editor.app"; do
  [[ -d "$app" ]] || continue
  rx_ver=${app#/Applications/iZotope RX }
  rx_ver=${rx_ver%% *}
  if [[ "$rx_ver" =~ ^[0-9]+$ ]] && (( rx_ver > rx_best )); then
    rx_best=$rx_ver
    rx_app=$app
  fi
done
if [[ -n "$rx_app" ]] && rx_id=$(defaults read "$rx_app/Contents/Info" CFBundleIdentifier 2>/dev/null); then
  defaults write com.rogueamoeba.audiohijack audioEditorBundleID -string "$rx_id" || failed=$(( failed + 1 ))
else
  logskip "Audio Hijack external editor" "no iZotope RX Audio Editor in /Applications"
fi

# Audio buffer size (frames)
defaults write com.rogueamoeba.audiohijack bufferFrames -int 512 || failed=$(( failed + 1 ))

# Disable external command execution (security)
defaults write com.rogueamoeba.audiohijack allowExternalCommands -int 0 || failed=$(( failed + 1 ))

if (( failed > 0 )); then
  warn "$failed default(s) failed to apply"
else
  ok "All defaults applied"
fi

# Exit 1 when any write failed, after every write has been tried and counted, so
# post-install's apply_defaults reports this script as failed rather than
# printing "Applied" under the warning above. Until 2026-09-11 each failure was
# counted with ((failed++)), which returns 1 from zero: under set -e that ended
# the script at the first failed write under bash 5, and never under bash 3.2.
if (( failed > 0 )); then exit 1; fi
