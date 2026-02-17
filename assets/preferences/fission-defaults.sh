#!/usr/bin/env bash
set -euo pipefail

# Fission audio editor preferences
#
# Applied by mrk2 post-install.
# Sets custom format defaults for audio export/conversion.
# Does NOT include license info — enter that manually.

log(){ printf "[fission-defaults] %s\n" "$*"; }

failed=0

# Dark theme
defaults write com.rogueamoeba.Fission applicationTheme -int 2 || ((failed++))

# Custom WAV format: 24-bit mono 44.1kHz with dither
defaults write com.rogueamoeba.Fission CustomFormatWAV -dict \
  BitRate -int 0 \
  ChannelCount -int 1 \
  Dithering -int 1 \
  SampleSize -int 24 \
  SamplingRate -int 44100 \
  Type -int 5 \
  TypeExtra -int 0 \
  UseSDM -int 0 \
  UseVBR -int 1 || ((failed++))

# Custom MP3 format: 160kbps stereo 44.1kHz VBR
defaults write com.rogueamoeba.Fission CustomFormatMP3 -dict \
  BitRate -int 160000 \
  ChannelCount -int 2 \
  Dithering -int 0 \
  SampleSize -int 16 \
  SamplingRate -int 44100 \
  Type -int 3 \
  TypeExtra -int 0 \
  UseSDM -int 0 \
  UseVBR -int 1 || ((failed++))

# Custom AAC format: 160kbps stereo 44.1kHz VBR
defaults write com.rogueamoeba.Fission CustomFormatAAC -dict \
  BitRate -int 160000 \
  ChannelCount -int 2 \
  Dithering -int 0 \
  SampleSize -int 16 \
  SamplingRate -int 44100 \
  Type -int 2 \
  TypeExtra -int 0 \
  UseSDM -int 0 \
  UseVBR -int 1 || ((failed++))

# Default export format: WAV (type 5, preset index 3)
defaults write com.rogueamoeba.Fission exportFormatType -int 5 || ((failed++))

# Don't show start window
defaults write com.rogueamoeba.Fission showStartWindow -bool false || ((failed++))

if (( failed > 0 )); then
  log "Warning: $failed default(s) failed to apply"
else
  log "All defaults applied"
fi
