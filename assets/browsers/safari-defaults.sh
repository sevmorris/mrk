#!/usr/bin/env bash
set -euo pipefail

# Safari power-user defaults
#
# Applied by mrk2 post-install. No rollback — re-run mrk1 defaults
# or reset Safari preferences manually to revert.

log(){ printf "[safari-defaults] %s\n" "$*"; }

failed=0

###############################################################################
# General                                                                     #
###############################################################################

# Show full URL in Smart Search Field
defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true || ((failed++))

# Show favorites bar
defaults write com.apple.Safari ShowFavoritesBar-v2 -bool true || ((failed++))

# Show status bar
defaults write com.apple.Safari ShowOverlayStatusBar -bool true || ((failed++))

###############################################################################
# Privacy & Security                                                          #
###############################################################################

# Send Do Not Track header
defaults write com.apple.Safari SendDoNotTrackHTTPHeader -bool true || ((failed++))

# Prevent cross-site tracking
defaults write com.apple.Safari BlockStoragePolicy -int 2 || ((failed++))

# Don't auto-open "safe" downloads
defaults write com.apple.Safari AutoOpenSafeDownloads -bool false || ((failed++))

# Disable AutoFill for credit cards
defaults write com.apple.Safari AutoFillCreditCardData -bool false || ((failed++))

###############################################################################
# Developer                                                                   #
###############################################################################

# Enable Develop menu
defaults write com.apple.Safari IncludeDevelopMenu -bool true || ((failed++))

# Enable developer extras (Web Inspector in contextual menu)
defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true || ((failed++))
defaults write com.apple.Safari "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" -bool true || ((failed++))

###############################################################################
# Extensions                                                                  #
###############################################################################

# Enable extensions
defaults write com.apple.Safari ExtensionsEnabled -bool true || ((failed++))

# Auto-update extensions
defaults write com.apple.Safari InstallExtensionUpdatesAutomatically -bool true || ((failed++))

###############################################################################
# Summary                                                                     #
###############################################################################

if (( failed > 0 )); then
  log "Warning: $failed default(s) failed to apply"
else
  log "All defaults applied"
fi

log "Restart Safari for changes to take effect"
