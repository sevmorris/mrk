#!/usr/bin/env bash
set -euo pipefail

# Helium defaults — automatic updates via Sparkle framework
#
# Applied by mrk post-install. Helium is a minimal floating browser
# with no extension support.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts"
source "$SCRIPT_DIR/lib.sh"

failed=0

# Enable automatic update checks (Sparkle)
defaults write net.imput.helium SUEnableAutomaticChecks -bool true || ((failed++))

# Automatically download and install updates
defaults write net.imput.helium SUAutomaticallyUpdate -bool true || ((failed++))

if (( failed > 0 )); then
  warn "$failed default(s) failed to apply"
else
  ok "All defaults applied"
fi
