#!/usr/bin/env bash
set -euo pipefail

# Safari power-user defaults
#
# Applied by mrk post-install. No rollback — re-run mrk defaults
# or reset Safari preferences manually to revert.

_self="${BASH_SOURCE[0]}"
while [[ -L "$_self" ]]; do
  _dir="$(cd "$(dirname "$_self")" && pwd)"
  _self="$(readlink "$_self")"
  [[ "$_self" != /* ]] && _self="$_dir/$_self"
done
SCRIPT_DIR="$(cd "$(dirname "$_self")/../.." && pwd)/scripts"
source "$SCRIPT_DIR/lib.sh"

failed=0

###############################################################################
# General                                                                     #
###############################################################################

# Show full URL in Smart Search Field
# Why: partial URL display hides the actual domain, making phishing and spoofed links harder to spot
defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true || failed=$(( failed + 1 ))

# Show favorites bar
defaults write com.apple.Safari ShowFavoritesBar-v2 -bool true || failed=$(( failed + 1 ))

# Show status bar
defaults write com.apple.Safari ShowOverlayStatusBar -bool true || failed=$(( failed + 1 ))

###############################################################################
# Privacy & Security                                                          #
###############################################################################

# Send Do Not Track header
defaults write com.apple.Safari SendDoNotTrackHTTPHeader -bool true || failed=$(( failed + 1 ))

# Prevent cross-site tracking
defaults write com.apple.Safari BlockStoragePolicy -int 2 || failed=$(( failed + 1 ))

# Don't auto-open "safe" downloads
# Why: file type alone doesn't determine safety; auto-opening can execute malicious content without prompting
defaults write com.apple.Safari AutoOpenSafeDownloads -bool false || failed=$(( failed + 1 ))

# Disable AutoFill for credit cards
# Why: reduces exposure if the browser is accessed without authorization or on a shared machine
defaults write com.apple.Safari AutoFillCreditCardData -bool false || failed=$(( failed + 1 ))

###############################################################################
# Developer                                                                   #
###############################################################################

# Enable Develop menu
defaults write com.apple.Safari IncludeDevelopMenu -bool true || failed=$(( failed + 1 ))

# Enable developer extras (Web Inspector in contextual menu)
defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true || failed=$(( failed + 1 ))
defaults write com.apple.Safari "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" -bool true || failed=$(( failed + 1 ))

###############################################################################
# Extensions                                                                  #
###############################################################################

# Enable extensions
defaults write com.apple.Safari ExtensionsEnabled -bool true || failed=$(( failed + 1 ))

# Auto-update extensions
defaults write com.apple.Safari InstallExtensionUpdatesAutomatically -bool true || failed=$(( failed + 1 ))

###############################################################################
# Summary                                                                     #
###############################################################################

if (( failed > 0 )); then
  warn "$failed default(s) failed to apply"
else
  ok "All defaults applied"
fi

log "Restart Safari for changes to take effect"

# Exit 1 when any write failed, after every write has been tried and counted, so
# post-install's apply_defaults reports this script as failed rather than
# printing "Applied" under the warning above. Until 2026-09-11 each failure was
# counted with ((failed++)), which returns 1 from zero: under set -e that ended
# the script at the first failed write under bash 5, and never under bash 3.2.
if (( failed > 0 )); then exit 1; fi
