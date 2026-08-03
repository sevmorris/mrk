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
defaults write com.rogueamoeba.audiohijack applicationTheme -int 2 || ((failed++))

# Preferred external audio editor — iZotope RX
defaults write com.rogueamoeba.audiohijack audioEditorBundleID -string "com.izotope.RXPro" || ((failed++))

# Audio buffer size (frames)
defaults write com.rogueamoeba.audiohijack bufferFrames -int 512 || ((failed++))

# Disable external command execution (security)
defaults write com.rogueamoeba.audiohijack allowExternalCommands -int 0 || ((failed++))

if (( failed > 0 )); then
  warn "$failed default(s) failed to apply"
else
  ok "All defaults applied"
fi
