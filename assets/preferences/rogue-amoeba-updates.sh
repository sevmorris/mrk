#!/usr/bin/env bash
set -euo pipefail

# Rogue Amoeba — disable Sparkle auto-updates across the suite
#
# Applied by mrk post-install.
# Updates are managed via topgrade / brew upgrade instead.

_self="${BASH_SOURCE[0]}"
while [[ -L "$_self" ]]; do
  _dir="$(cd "$(dirname "$_self")" && pwd)"
  _self="$(readlink "$_self")"
  [[ "$_self" != /* ]] && _self="$_dir/$_self"
done
SCRIPT_DIR="$(cd "$(dirname "$_self")/../.." && pwd)/scripts"
source "$SCRIPT_DIR/lib.sh"

failed=0

apps=(
  "com.rogueamoeba.audiohijack"
  "com.rogueamoeba.Fission"
  "com.rogueamoeba.Loopback"
  "com.rogueamoeba.Piezo"
  "com.rogueamoeba.soundsource"
  "com.rogueamoeba.farrago"
)

for bundle_id in "${apps[@]}"; do
  app_name="${bundle_id##*.}"
  defaults write "$bundle_id" SUAllowsAutomaticUpdates -bool false || failed=$(( failed + 1 ))
  defaults write "$bundle_id" SUAutomaticallyUpdate -bool false || failed=$(( failed + 1 ))
  log "Disabled auto-update: $app_name"
done

if (( failed > 0 )); then
  warn "$failed default(s) failed to apply"
else
  ok "All Rogue Amoeba auto-updates disabled"
fi

# Exit 1 when any write failed, after every write has been tried and counted, so
# post-install's apply_defaults reports this script as failed rather than
# printing "Applied" under the warning above. Until 2026-09-11 each failure was
# counted with ((failed++)), which returns 1 from zero: under set -e that ended
# the script at the first failed write under bash 5, and never under bash 3.2.
if (( failed > 0 )); then exit 1; fi
