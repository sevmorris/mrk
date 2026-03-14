#!/usr/bin/env bash
set -euo pipefail

# Rogue Amoeba — disable Sparkle auto-updates across the suite
#
# Applied by mrk post-install.
# Updates are managed via topgrade / brew upgrade instead.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts"
source "$SCRIPT_DIR/lib.sh"

failed=0

apps=(
  "com.rogueamoeba.AudioHijack"
  "com.rogueamoeba.Fission"
  "com.rogueamoeba.Loopback"
  "com.rogueamoeba.Piezo"
  "com.rogueamoeba.soundsource"
  "com.rogueamoeba.Farrago2"
)

for bundle_id in "${apps[@]}"; do
  app_name="${bundle_id##*.}"
  defaults write "$bundle_id" SUAllowsAutomaticUpdates -bool false || ((failed++))
  defaults write "$bundle_id" SUAutomaticallyUpdate -bool false || ((failed++))
  log "Disabled auto-update: $app_name"
done

if (( failed > 0 )); then
  warn "$failed default(s) failed to apply"
else
  ok "All Rogue Amoeba auto-updates disabled"
fi
