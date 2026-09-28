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
disabled=0

# bundle id|app name in /Applications.
#
# Only an installed app gets the keys, as in every other app-defaults script.
# This one used to write all six domains whether or not the app was there, and
# post-install imports a saved plist only into an empty domain: an app installed
# after the first run of post-install found its domain already holding these
# two keys, and its saved preferences were never imported.
apps=(
  "com.rogueamoeba.audiohijack|Audio Hijack"
  "com.rogueamoeba.Fission|Fission"
  "com.rogueamoeba.Loopback|Loopback"
  "com.rogueamoeba.Piezo|Piezo"
  "com.rogueamoeba.soundsource|SoundSource"
  "com.rogueamoeba.farrago|Farrago"
)

for entry in "${apps[@]}"; do
  bundle_id="${entry%%|*}"
  app_name="${entry#*|}"
  if [[ ! -d "/Applications/$app_name.app" ]]; then
    logskip "$app_name auto-update" "not installed"
    continue
  fi
  defaults write "$bundle_id" SUAllowsAutomaticUpdates -bool false || failed=$(( failed + 1 ))
  defaults write "$bundle_id" SUAutomaticallyUpdate -bool false || failed=$(( failed + 1 ))
  log "Disabled auto-update: $app_name"
  disabled=$(( disabled + 1 ))
done

if (( failed > 0 )); then
  warn "$failed default(s) failed to apply"
else
  ok "Auto-updates disabled for $disabled installed Rogue Amoeba app(s)"
fi

# Exit 1 when any write failed, after every write has been tried and counted, so
# post-install's apply_defaults reports this script as failed rather than
# printing "Applied" under the warning above. Until 2026-09-11 each failure was
# counted with ((failed++)), which returns 1 from zero: under set -e that ended
# the script at the first failed write under bash 5, and never under bash 3.2.
if (( failed > 0 )); then exit 1; fi
