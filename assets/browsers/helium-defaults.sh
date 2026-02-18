#!/usr/bin/env bash
set -euo pipefail
_Y="\033[33m" _D="\033[2m" _R="\033[0m"
# Helium defaults — automatic updates via Sparkle framework
#
# Applied by mrk post-install. Helium is a minimal floating browser
# with no extension support.

log(){ printf "${_D}[helium-defaults]${_R} %s\n" "$*"; }
warn(){ printf "${_Y}[helium-defaults] ⚠${_R} %s\n" "$*"; }
failed=0

# Enable automatic update checks (Sparkle)
defaults write net.imput.helium SUEnableAutomaticChecks -bool true || ((failed++))

# Automatically download and install updates
defaults write net.imput.helium SUAutomaticallyUpdate -bool true || ((failed++))

if (( failed > 0 )); then
  warn "Warning: $failed default(s) failed to apply"
else
  log "All defaults applied"
fi
