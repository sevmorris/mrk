#!/usr/bin/env bash
set -euo pipefail

# AlDente Pro battery management preferences
#
# Applied by mrk post-install.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts"
source "$SCRIPT_DIR/lib.sh"

failed=0

# Maximum charge level (%)
# Why: lithium cells degrade fastest above ~80% SOC; capping charge extends long-term battery capacity
defaults write com.apphousekitchen.aldente-pro chargeVal -int 80 || ((failed++))

# Calibration backup percentage
defaults write com.apphousekitchen.aldente-pro calibrationBackupPercentage -int 80 || ((failed++))

# Enable sailing mode (maintain charge level without micro-charging)
# Why: prevents continuous micro-charging cycles at the charge limit, which cause incremental wear
defaults write com.apphousekitchen.aldente-pro sailingMode -bool true || ((failed++))

# Sailing level tolerance (%)
defaults write com.apphousekitchen.aldente-pro sailingLevel -int 5 || ((failed++))

# Enable automatic discharge when above charge limit
# Why: maintains charge at target level when plugged in for extended periods, not just on initial plug-in
defaults write com.apphousekitchen.aldente-pro automaticDischarge -bool true || ((failed++))

# Don't allow discharge below limit
defaults write com.apphousekitchen.aldente-pro allowDischarge -bool false || ((failed++))

# Blink MagSafe LED during discharge
# Why: provides visible confirmation that AlDente is actively discharging rather than just idle
defaults write com.apphousekitchen.aldente-pro magsafeBlinkDischarge -bool true || ((failed++))

# Enable Sparkle auto-updates
defaults write com.apphousekitchen.aldente-pro SUAutomaticallyUpdate -bool true || ((failed++))
defaults write com.apphousekitchen.aldente-pro SUEnableAutomaticChecks -bool true || ((failed++))

if (( failed > 0 )); then
  warn "$failed default(s) failed to apply"
else
  ok "All defaults applied"
fi
