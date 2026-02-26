#!/usr/bin/env bash
set -euo pipefail

# mrk defaults - apply macOS defaults and generate a rollback script
#
# Usage:
#   defaults.sh                 # apply all defaults (except trackpad)
#   defaults.sh --with-trackpad # also apply trackpad gesture settings

ROLL_DIR="$HOME/.mrk"
ROLLBACK="$ROLL_DIR/defaults-rollback.sh"

WITH_TRACKPAD=false
for arg in "$@"; do
  case "$arg" in
    --with-trackpad) WITH_TRACKPAD=true ;;
    *) echo "Unknown option: $arg" >&2; exit 1 ;;
  esac
done

# Create rollback directory and script with error checking
if ! mkdir -p "$ROLL_DIR"; then
  echo "Error: Failed to create rollback directory: $ROLL_DIR" >&2
  exit 1
fi

if ! printf '#!/usr/bin/env bash\n' > "$ROLLBACK" || ! chmod +x "$ROLLBACK"; then
  echo "Error: Failed to initialize rollback script: $ROLLBACK" >&2
  exit 1
fi

log(){ printf "[defaults] %s\n" "$*"; }
backup_line(){ echo "$1" >> "$ROLLBACK"; }

# Helper: capture current value (if any) and append the inverse to rollback
# Usage: write_default <domain> <key> <type> <value>
write_default(){
  local domain="$1" key="$2" type="$3" value="$4"
  local current
  if current=$(defaults read "$domain" "$key" 2>/dev/null); then
    case "$current" in
      true|false)    backup_line "defaults write $domain $key -bool $current" ;;
      ''|*[!0-9.]*|*.*.*) backup_line "defaults write $domain $key -string \"$current\"" ;;
      *.*)           backup_line "defaults write $domain $key -float $current" ;;
      *)             backup_line "defaults write $domain $key -int $current" ;;
    esac
  else
    backup_line "defaults delete $domain $key >/dev/null 2>&1 || true"
  fi
  case "$type" in
    bool)   defaults write "$domain" "$key" -bool "$value" || return 1 ;;
    int)    defaults write "$domain" "$key" -int "$value" || return 1 ;;
    float)  defaults write "$domain" "$key" -float "$value" || return 1 ;;
    string) defaults write "$domain" "$key" -string "$value" || return 1 ;;
    *) log "Unknown type: $type" >&2; return 1 ;;
  esac
}

log "Applying macOS defaults..."

# Track failures
failed=0

###############################################################################
# General UI / UX                                                             #
###############################################################################

# Dark mode
write_default NSGlobalDomain AppleInterfaceStyle string Dark || ((failed++))
# Always show scrollbars
write_default NSGlobalDomain AppleShowScrollBars string Always || ((failed++))
# Show all filename extensions
write_default NSGlobalDomain AppleShowAllExtensions bool true || ((failed++))
# Disable window open/close animations
write_default NSGlobalDomain NSAutomaticWindowAnimationsEnabled bool false || ((failed++))
# Near-instant window resize animation
write_default NSGlobalDomain NSWindowResizeTime float 0.001 || ((failed++))
# Don't restore windows on relaunch
write_default NSGlobalDomain NSQuitAlwaysKeepsWindows bool false || ((failed++))
# Expand save panel by default
write_default NSGlobalDomain NSNavPanelExpandedStateForSaveMode bool true || ((failed++))
write_default NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 bool true || ((failed++))
# Expand print dialog by default
write_default NSGlobalDomain PMPrintingExpandedStateForPrint bool true || ((failed++))
write_default NSGlobalDomain PMPrintingExpandedStateForPrint2 bool true || ((failed++))
# Save to disk (not iCloud) by default
write_default NSGlobalDomain NSDocumentSaveNewDocumentsToCloud bool false || ((failed++))
# Instant Quick Look animation
write_default NSGlobalDomain QLPanelAnimationDuration float 0 || ((failed++))

###############################################################################
# Sound                                                                       #
###############################################################################

# Mute system alert sound
write_default NSGlobalDomain com.apple.sound.beep.volume float 0 || ((failed++))
# Disable UI sound effects
write_default NSGlobalDomain com.apple.sound.uiaudio.enabled bool false || ((failed++))

###############################################################################
# Keyboard & input                                                            #
###############################################################################

# Key repeat speed (lower is faster)
write_default NSGlobalDomain KeyRepeat int 2 || ((failed++))
write_default NSGlobalDomain InitialKeyRepeat int 15 || ((failed++))
# Key repeat instead of accent character picker
write_default NSGlobalDomain ApplePressAndHoldEnabled bool false || ((failed++))
# Full keyboard access (Tab through all UI controls)
write_default NSGlobalDomain AppleKeyboardUIMode int 2 || ((failed++))
# Disable auto-capitalization
write_default NSGlobalDomain NSAutomaticCapitalizationEnabled bool false || ((failed++))
# Disable smart dashes
write_default NSGlobalDomain NSAutomaticDashSubstitutionEnabled bool false || ((failed++))
# Disable double-space period shortcut
write_default NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled bool false || ((failed++))
# Disable smart quotes
write_default NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled bool false || ((failed++))
# Disable autocorrect
write_default NSGlobalDomain NSAutomaticSpellingCorrectionEnabled bool false || ((failed++))

###############################################################################
# Dock                                                                        #
###############################################################################

# Dock on left side
write_default com.apple.dock orientation string left || ((failed++))
# Icon size 36 pixels
write_default com.apple.dock tilesize int 36 || ((failed++))
# Scale effect for minimize
write_default com.apple.dock mineffect string scale || ((failed++))
# Minimize windows into application icon
write_default com.apple.dock minimize-to-application bool true || ((failed++))
# Disable dock icon bouncing
write_default com.apple.dock no-bouncing bool true || ((failed++))
# Don't show recent applications
write_default com.apple.dock show-recents bool false || ((failed++))
# No delay before dock shows (if autohide enabled)
write_default com.apple.dock autohide-delay float 0 || ((failed++))

###############################################################################
# Finder                                                                      #
###############################################################################

# Disable all Finder animations
write_default com.apple.finder DisableAllAnimations bool true || ((failed++))

###############################################################################
# Screenshots                                                                 #
###############################################################################

# Disable window shadow in screenshots
write_default com.apple.screencapture disable-shadow bool true || ((failed++))
# Don't show floating thumbnail after capture
write_default com.apple.screencapture show-thumbnail bool false || ((failed++))
# Don't include date in screenshot filename
write_default com.apple.screencapture include-date bool false || ((failed++))
# Save screenshots to ~/Desktop
write_default com.apple.screencapture location string "$HOME/Desktop" || ((failed++))

###############################################################################
# Desktop Services                                                            #
###############################################################################

# Don't create .DS_Store files on network volumes
write_default com.apple.desktopservices DSDontWriteNetworkStores bool true || ((failed++))
# Don't create .DS_Store files on USB volumes
write_default com.apple.desktopservices DSDontWriteUSBStores bool true || ((failed++))

###############################################################################
# Disk images                                                                 #
###############################################################################

# Skip DMG verification
write_default com.apple.frameworks.diskimages skip-verify bool true || ((failed++))
write_default com.apple.frameworks.diskimages skip-verify-locked bool true || ((failed++))
write_default com.apple.frameworks.diskimages skip-verify-remote bool true || ((failed++))

###############################################################################
# Time Machine                                                                #
###############################################################################

# Don't prompt to use new disks for backup
write_default com.apple.TimeMachine DoNotOfferNewDisksForBackup bool true || ((failed++))

###############################################################################
# Software Update & App Store                                                 #
###############################################################################

# Auto-check for updates
write_default com.apple.SoftwareUpdate AutomaticCheckEnabled bool true || ((failed++))
# Auto-download updates
write_default com.apple.SoftwareUpdate AutomaticDownload bool true || ((failed++))
# Install system data files automatically
write_default com.apple.SoftwareUpdate ConfigDataInstall bool true || ((failed++))
# Install security updates automatically
write_default com.apple.SoftwareUpdate CriticalUpdateInstall bool true || ((failed++))
# Auto-update App Store apps
write_default com.apple.commerce AutoUpdate bool true || ((failed++))

###############################################################################
# Activity Monitor                                                            #
###############################################################################

# Show CPU usage in dock icon
write_default com.apple.ActivityMonitor IconType int 2 || ((failed++))
# Show all processes
write_default com.apple.ActivityMonitor ShowCategory int 100 || ((failed++))
# Sort by CPU usage
write_default com.apple.ActivityMonitor SortColumn string CPUUsage || ((failed++))
# Sort descending
write_default com.apple.ActivityMonitor SortDirection int 0 || ((failed++))
# Update every 1 second
write_default com.apple.ActivityMonitor UpdatePeriod int 1 || ((failed++))

###############################################################################
# TextEdit                                                                    #
###############################################################################

# Default to plain text
write_default com.apple.TextEdit RichText int 0 || ((failed++))

###############################################################################
# Terminal.app                                                                #
###############################################################################

# Default profile: Pro
write_default com.apple.Terminal "Default Window Settings" string Pro || ((failed++))
write_default com.apple.Terminal "Startup Window Settings" string Pro || ((failed++))
# Focus follows mouse
write_default com.apple.Terminal FocusFollowsMouse bool true || ((failed++))
# Secure keyboard entry
write_default com.apple.Terminal SecureKeyboardEntry bool true || ((failed++))
# Don't show line marks
write_default com.apple.Terminal ShowLineMarks bool false || ((failed++))

###############################################################################
# Menu bar clock                                                              #
###############################################################################

# Digital clock
write_default com.apple.menuextra.clock IsAnalog bool false || ((failed++))
# Show AM/PM
write_default com.apple.menuextra.clock ShowAMPM bool true || ((failed++))
# Show day of week
write_default com.apple.menuextra.clock ShowDayOfWeek bool true || ((failed++))
# Don't show date
write_default com.apple.menuextra.clock ShowDate int 0 || ((failed++))

###############################################################################
# Trackpad (opt-in: --with-trackpad)                                          #
###############################################################################

if $WITH_TRACKPAD; then
  log "Applying trackpad defaults..."

  for domain in com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad; do
    # Disable tap-to-click
    write_default "$domain" Clicking bool false || ((failed++))
    # Suppress Force Touch
    write_default "$domain" ForceSuppressed bool true || ((failed++))
    # Bottom-right corner secondary click
    write_default "$domain" TrackpadCornerSecondaryClick int 2 || ((failed++))
    # Disable all multi-finger gestures
    write_default "$domain" TrackpadFiveFingerPinchGesture int 0 || ((failed++))
    write_default "$domain" TrackpadFourFingerHorizSwipeGesture int 0 || ((failed++))
    write_default "$domain" TrackpadFourFingerPinchGesture int 0 || ((failed++))
    write_default "$domain" TrackpadFourFingerVertSwipeGesture int 0 || ((failed++))
    write_default "$domain" TrackpadPinch bool false || ((failed++))
    write_default "$domain" TrackpadRightClick bool false || ((failed++))
    write_default "$domain" TrackpadRotate bool false || ((failed++))
    write_default "$domain" TrackpadThreeFingerDrag bool false || ((failed++))
    write_default "$domain" TrackpadThreeFingerHorizSwipeGesture int 0 || ((failed++))
    write_default "$domain" TrackpadThreeFingerTapGesture int 0 || ((failed++))
    write_default "$domain" TrackpadThreeFingerVertSwipeGesture int 0 || ((failed++))
    write_default "$domain" TrackpadTwoFingerDoubleTapGesture int 0 || ((failed++))
    write_default "$domain" TrackpadTwoFingerFromRightEdgeSwipeGesture int 0 || ((failed++))
  done
fi

###############################################################################
# Finish up                                                                   #
###############################################################################

if (( failed > 0 )); then
  log "Warning: $failed default(s) failed to apply"
fi

log "Writing rollback helper to $ROLLBACK"
backup_line "killall Finder >/dev/null 2>&1 || true"
backup_line "killall Dock >/dev/null 2>&1 || true"
backup_line "killall SystemUIServer >/dev/null 2>&1 || true"

# Apply immediate effects
killall Finder >/dev/null 2>&1 || true
killall Dock >/dev/null 2>&1 || true
killall SystemUIServer >/dev/null 2>&1 || true

log "Defaults applied. You can revert with: $ROLLBACK"
