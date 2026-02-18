#!/usr/bin/env bash
set -euo pipefail

# AlDente Pro battery management preferences
#
# Applied by mrk post-install.

log(){ printf "[aldente-defaults] %s\n" "$*"; }

failed=0

# Maximum charge level (%)
defaults write com.apphousekitchen.aldente-pro chargeVal -int 80 || ((failed++))

# Calibration backup percentage
defaults write com.apphousekitchen.aldente-pro calibrationBackupPercentage -int 80 || ((failed++))

# Enable sailing mode (maintain charge level without micro-charging)
defaults write com.apphousekitchen.aldente-pro sailingMode -bool true || ((failed++))

# Sailing level tolerance (%)
defaults write com.apphousekitchen.aldente-pro sailingLevel -int 5 || ((failed++))

# Enable automatic discharge when above charge limit
defaults write com.apphousekitchen.aldente-pro automaticDischarge -bool true || ((failed++))

# Don't allow discharge below limit
defaults write com.apphousekitchen.aldente-pro allowDischarge -bool false || ((failed++))

# Blink MagSafe LED during discharge
defaults write com.apphousekitchen.aldente-pro magsafeBlinkDischarge -bool true || ((failed++))

# Enable Sparkle auto-updates
defaults write com.apphousekitchen.aldente-pro SUAutomaticallyUpdate -bool true || ((failed++))
defaults write com.apphousekitchen.aldente-pro SUEnableAutomaticChecks -bool true || ((failed++))

if (( failed > 0 )); then
  log "Warning: $failed default(s) failed to apply"
else
  log "All defaults applied"
fi
