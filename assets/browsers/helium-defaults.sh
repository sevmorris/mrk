#!/usr/bin/env bash
set -euo pipefail

# Helium defaults — automatic updates via Sparkle framework
#
# Applied by mrk post-install. Helium is a minimal floating browser
# with no extension support.

_self="${BASH_SOURCE[0]}"
while [[ -L "$_self" ]]; do
  _dir="$(cd "$(dirname "$_self")" && pwd)"
  _self="$(readlink "$_self")"
  [[ "$_self" != /* ]] && _self="$_dir/$_self"
done
SCRIPT_DIR="$(cd "$(dirname "$_self")/../.." && pwd)/scripts"
source "$SCRIPT_DIR/lib.sh"

failed=0

# Enable automatic update checks (Sparkle)
defaults write net.imput.helium SUEnableAutomaticChecks -bool true || failed=$(( failed + 1 ))

# Automatically download and install updates
defaults write net.imput.helium SUAutomaticallyUpdate -bool true || failed=$(( failed + 1 ))

if (( failed > 0 )); then
  warn "$failed default(s) failed to apply"
else
  ok "All defaults applied"
fi

# Exit 1 when any write failed, after every write has been tried and counted, so
# post-install's apply_defaults reports this script as failed rather than
# printing "Applied" under the warning above. Until 2026-09-11 each failure was
# counted with ((failed++)), which returns 1 from zero: under set -e that ended
# the script at the first failed write under bash 5, and never under bash 3.2.
if (( failed > 0 )); then exit 1; fi
