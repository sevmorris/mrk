#!/usr/bin/env bash
set -euo pipefail

# Helium defaults — automatic updates via Sparkle framework
#
# Applied by mrk2 post-install. Helium is a minimal floating browser
# with no extension support.

log(){ printf "[helium-defaults] %s\n" "$*"; }

failed=0

# Enable automatic update checks (Sparkle)
defaults write net.imput.helium SUEnableAutomaticChecks -bool true || ((failed++))

# Automatically download and install updates
defaults write net.imput.helium SUAutomaticallyUpdate -bool true || ((failed++))

if (( failed > 0 )); then
  log "Warning: $failed default(s) failed to apply"
else
  log "All defaults applied"
fi
