#!/usr/bin/env bash
set -euo pipefail

# Audio Hijack preferences
#
# Applied by mrk post-install.
# Sets theme, preferred audio editor, and buffer size.

log(){ printf "[audio-hijack-defaults] %s\n" "$*"; }

failed=0

# Dark theme (0=light, 1=auto, 2=dark)
defaults write com.rogueamoeba.AudioHijack applicationTheme -int 2 || ((failed++))

# Preferred external audio editor — iZotope RX
defaults write com.rogueamoeba.AudioHijack audioEditorBundleID -string "com.izotope.RXPro" || ((failed++))

# Audio buffer size (frames)
defaults write com.rogueamoeba.AudioHijack bufferFrames -int 512 || ((failed++))

# Disable external command execution (security)
defaults write com.rogueamoeba.AudioHijack allowExternalCommands -int 0 || ((failed++))

if (( failed > 0 )); then
  log "Warning: $failed default(s) failed to apply"
else
  log "All defaults applied"
fi
