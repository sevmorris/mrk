#!/usr/bin/env bash
set -euo pipefail

# mrk defaults - apply macOS defaults and generate a rollback script
#
# Usage:
#   defaults.sh                 # apply all defaults (except trackpad)
#   defaults.sh --with-trackpad # also apply trackpad gesture settings

ROLL_DIR="$HOME/.mrk"
ROLLBACK="${ROLLBACK:-$HOME/.mrk/defaults-rollback.sh}"

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

if [[ -f "$ROLLBACK" ]] && grep -q '^#!/usr/bin/env bash$' "$ROLLBACK" 2>/dev/null; then
  # Rollback file already exists and has a valid shebang — preserve prior entries
  chmod +x "$ROLLBACK" 2>/dev/null || true
else
  if ! printf '#!/usr/bin/env bash\n' > "$ROLLBACK"; then
    echo "Error: Failed to initialize rollback script: $ROLLBACK" >&2
    exit 1
  fi
  if ! chmod +x "$ROLLBACK"; then
    echo "Error: Failed to set executable on rollback script: $ROLLBACK" >&2
    exit 1
  fi
fi

_self="${BASH_SOURCE[0]}"
while [[ -L "$_self" ]]; do
  _dir="$(cd "$(dirname "$_self")" && pwd)"
  _self="$(readlink "$_self")"
  [[ "$_self" != /* ]] && _self="$_dir/$_self"
done
SCRIPT_DIR="$(cd "$(dirname "$_self")" && pwd)"
source "$SCRIPT_DIR/lib.sh"
backup_line(){ grep -qFx "$1" "$ROLLBACK" 2>/dev/null && return 0; echo "$1" >> "$ROLLBACK"; }

# Helper: capture current value (if any) and append the inverse to rollback.
# Skips the write if the current value already matches the target (idempotent).
# Uses `defaults read-type` for authoritative type detection.
# Usage: write_default <domain> <key> <type> <value>
write_default(){
  local domain="$1" key="$2" type="$3" value="$4"
  local current current_type

  # Shell-escape with printf %q so values containing ", \, $, newlines, or
  # shell metacharacters survive re-evaluation in the rollback script intact.
  local esc_domain esc_key
  esc_domain=$(printf '%q' "$domain")
  esc_key=$(printf '%q' "$key")

  if current=$(defaults read "$domain" "$key" 2>/dev/null); then
    # Authoritative type detection
    current_type=$(defaults read-type "$domain" "$key" 2>/dev/null | awk '{print $NF}' || echo "string")

    local esc_current
    esc_current=$(printf '%q' "$current")

    # Save rollback BEFORE idempotency check so re-runs preserve first-run originals.
    # Guard skips append when an entry for this domain+key already exists in the file,
    # in either form backup_line writes (trailing space stops prefix collisions).
    if ! grep -qF "defaults write $esc_domain $esc_key " "$ROLLBACK" 2>/dev/null && \
       ! grep -qF "defaults delete $esc_domain $esc_key " "$ROLLBACK" 2>/dev/null; then
      case "$current_type" in
        boolean)
          local bool_val
          [[ "$current" == "1" ]] && bool_val="true" || bool_val="false"
          backup_line "defaults write $esc_domain $esc_key -bool $bool_val"
          ;;
        integer) backup_line "defaults write $esc_domain $esc_key -int $current" ;;
        float)   backup_line "defaults write $esc_domain $esc_key -float $current" ;;
        *)       backup_line "defaults write $esc_domain $esc_key -string $esc_current" ;;
      esac
    fi

    # Idempotency: skip write if already at target value and type
    local already_set=0
    case "$type" in
      bool)
        local norm_val norm_cur
        [[ "$value" == "true" ]] && norm_val="1" || norm_val="0"
        # defaults read returns 1/0 for booleans
        [[ "$current" == "1" ]] && norm_cur="1" || norm_cur="0"
        [[ "$norm_val" == "$norm_cur" && "$current_type" == "boolean" ]] && already_set=1
        ;;
      int)
        [[ "$current" == "$value" && "$current_type" == "integer" ]] && already_set=1
        ;;
      float)
        if [[ "$current_type" == "float" ]]; then
          local eq; eq=$(awk "BEGIN{print ($current == $value) ? 1 : 0}" 2>/dev/null || echo "0")
          [[ "$eq" == "1" ]] && already_set=1
        fi
        ;;
      string)
        [[ "$current" == "$value" && "$current_type" == "string" ]] && already_set=1
        ;;
    esac

    if (( already_set )); then
      return 0
    fi
  else
    backup_line "defaults delete $esc_domain $esc_key >/dev/null 2>&1 || true"
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
write_default NSGlobalDomain AppleInterfaceStyle string Dark || failed=$(( failed + 1 ))
# Always show scrollbars
# Why: overlay scrollbars appear/disappear and shift layout; always-visible scrollbars provide a consistent click target
write_default NSGlobalDomain AppleShowScrollBars string Always || failed=$(( failed + 1 ))
# Show all filename extensions
# Why: hidden extensions can make malicious files appear harmless (e.g. "invoice.pdf.app" shows as "invoice.pdf")
write_default NSGlobalDomain AppleShowAllExtensions bool true || failed=$(( failed + 1 ))
# Disable window open/close animations
# Why: eliminates visual delay when rapidly switching or tiling windows
write_default NSGlobalDomain NSAutomaticWindowAnimationsEnabled bool false || failed=$(( failed + 1 ))
# Near-instant window resize animation
# Why: eliminates the perceivable lag when resizing windows
write_default NSGlobalDomain NSWindowResizeTime float 0.001 || failed=$(( failed + 1 ))
# Don't restore windows on relaunch
# Why: stale windows from a previous session can cause confusion after crashes or updates
write_default NSGlobalDomain NSQuitAlwaysKeepsWindows bool false || failed=$(( failed + 1 ))
# Expand save panel by default
# Why: collapsed panel hides the destination path, making accidental misplacement easy
write_default NSGlobalDomain NSNavPanelExpandedStateForSaveMode bool true || failed=$(( failed + 1 ))
write_default NSGlobalDomain NSNavPanelExpandedStateForSaveMode2 bool true || failed=$(( failed + 1 ))
# Expand print dialog by default
write_default NSGlobalDomain PMPrintingExpandedStateForPrint bool true || failed=$(( failed + 1 ))
write_default NSGlobalDomain PMPrintingExpandedStateForPrint2 bool true || failed=$(( failed + 1 ))
# Save to disk (not iCloud) by default
# Why: avoids accidental sync of sensitive files to iCloud without explicit intent
write_default NSGlobalDomain NSDocumentSaveNewDocumentsToCloud bool false || failed=$(( failed + 1 ))
# Instant Quick Look animation
write_default NSGlobalDomain QLPanelAnimationDuration float 0 || failed=$(( failed + 1 ))

# Double-clicking a window title bar minimises it
# Why: zoom is reachable from the green button; minimise is the more common intent
write_default NSGlobalDomain AppleActionOnDoubleClick string Minimize || failed=$(( failed + 1 ))
# Selection highlight colour
write_default NSGlobalDomain AppleHighlightColor string "0.764700 0.976500 0.568600" || failed=$(( failed + 1 ))
# Small sidebar icons (1 small, 2 medium, 3 large)
write_default NSGlobalDomain NSTableViewDefaultSizeMode int 1 || failed=$(( failed + 1 ))
# Disable two-finger swipe to navigate back/forward
# Why: an accidental horizontal scroll loses form input in a browser
write_default NSGlobalDomain AppleEnableSwipeNavigateWithScrolls bool false || failed=$(( failed + 1 ))
# Disable Force Click and haptic feedback
write_default NSGlobalDomain com.apple.trackpad.forceClick bool false || failed=$(( failed + 1 ))
# Double-click speed, in seconds between clicks
write_default NSGlobalDomain com.apple.mouse.doubleClickThreshold float 0.8 || failed=$(( failed + 1 ))

###############################################################################
# Sound                                                                       #
###############################################################################

# Mute system alert sound
write_default NSGlobalDomain com.apple.sound.beep.volume float 0 || failed=$(( failed + 1 ))
# Disable UI sound effects
write_default NSGlobalDomain com.apple.sound.uiaudio.enabled bool false || failed=$(( failed + 1 ))

# Alert sound
write_default NSGlobalDomain com.apple.sound.beep.sound string "/System/Library/Sounds/Tink.aiff" || failed=$(( failed + 1 ))

###############################################################################
# Keyboard & input                                                            #
###############################################################################

# Key repeat speed (lower is faster)
write_default NSGlobalDomain KeyRepeat int 2 || failed=$(( failed + 1 ))
write_default NSGlobalDomain InitialKeyRepeat int 15 || failed=$(( failed + 1 ))
# Key repeat instead of accent character picker
# Why: the accent picker interrupts keyboard-driven navigation and editing in code and terminal
write_default NSGlobalDomain ApplePressAndHoldEnabled bool false || failed=$(( failed + 1 ))
# Full keyboard access (Tab through all UI controls)
# Why: allows Tab to cycle through buttons, radio buttons, etc. without reaching for the mouse
write_default NSGlobalDomain AppleKeyboardUIMode int 2 || failed=$(( failed + 1 ))
# Disable auto-capitalization
# Why: breaks commands, code, and domain names entered in text fields outside terminals
write_default NSGlobalDomain NSAutomaticCapitalizationEnabled bool false || failed=$(( failed + 1 ))
# Disable smart dashes
# Why: converts "--" to an em dash, breaking markdown, CLI flags, and code
write_default NSGlobalDomain NSAutomaticDashSubstitutionEnabled bool false || failed=$(( failed + 1 ))
# Disable double-space period shortcut
# Why: interferes with intentional spacing in code, prose, and command entry
write_default NSGlobalDomain NSAutomaticPeriodSubstitutionEnabled bool false || failed=$(( failed + 1 ))
# Disable smart quotes
# Why: curly quotes break shell scripts, JSON, code snippets, and command-line arguments
write_default NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled bool false || failed=$(( failed + 1 ))
# Disable autocorrect
# Why: mangles technical terms, hostnames, variable names, and other domain-specific vocabulary
write_default NSGlobalDomain NSAutomaticSpellingCorrectionEnabled bool false || failed=$(( failed + 1 ))

# Disable autocorrect inside WebKit text fields
# Why: the WebKit mirror of NSAutomaticSpellingCorrectionEnabled above; set separately or Safari still autocorrects
write_default NSGlobalDomain WebAutomaticSpellingCorrectionEnabled bool false || failed=$(( failed + 1 ))

###############################################################################
# Dock                                                                        #
###############################################################################

# Dock on left side
write_default com.apple.dock orientation string left || failed=$(( failed + 1 ))
# Icon size 36 pixels
write_default com.apple.dock tilesize int 36 || failed=$(( failed + 1 ))
# Scale effect for minimize
write_default com.apple.dock mineffect string scale || failed=$(( failed + 1 ))
# Minimize windows into application icon
# Why: minimized windows don't clutter the Dock's strip; they're reachable via the app's icon
write_default com.apple.dock minimize-to-application bool true || failed=$(( failed + 1 ))
# Disable dock icon bouncing
# Why: eliminates attention-hijacking animations during focused work
write_default com.apple.dock no-bouncing bool true || failed=$(( failed + 1 ))
# Don't show recent applications
write_default com.apple.dock show-recents bool false || failed=$(( failed + 1 ))
# No delay before dock shows (if autohide enabled)
write_default com.apple.dock autohide-delay float 0 || failed=$(( failed + 1 ))

###############################################################################
# Finder                                                                      #
###############################################################################

# Disable all Finder animations
# Why: makes file operations feel instant; each animation adds visible latency per action
write_default com.apple.finder DisableAllAnimations bool true || failed=$(( failed + 1 ))

# Show the path bar
write_default com.apple.finder ShowPathbar bool true || failed=$(( failed + 1 ))
# Show the status bar (item count and free space)
write_default com.apple.finder ShowStatusBar bool true || failed=$(( failed + 1 ))
# Show the full POSIX path in the window title
write_default com.apple.finder _FXShowPosixPathInTitle bool true || failed=$(( failed + 1 ))
# Keep folders on top when sorting by name
write_default com.apple.finder _FXSortFoldersFirst bool true || failed=$(( failed + 1 ))
# Use list view for new windows (Nlsv list, icnv icon, clmv column, glyv gallery)
write_default com.apple.finder FXPreferredViewStyle string Nlsv || failed=$(( failed + 1 ))
# Search the current folder by default, not the whole Mac
write_default com.apple.finder FXDefaultSearchScope string SCcf || failed=$(( failed + 1 ))
# No warning when changing a file extension
# Why: the warning fires constantly when renaming files and teaches you to dismiss it
write_default com.apple.finder FXEnableExtensionChangeWarning bool false || failed=$(( failed + 1 ))
# No warning when emptying the Trash
write_default com.apple.finder WarnOnEmptyTrash bool false || failed=$(( failed + 1 ))
# New Finder windows open the Desktop (PfDe desktop, PfHm home, PfAF recents)
write_default com.apple.finder NewWindowTarget string PfDe || failed=$(( failed + 1 ))
# Show hard disks on the Desktop
write_default com.apple.finder ShowHardDrivesOnDesktop bool true || failed=$(( failed + 1 ))
# Do not show connected servers on the Desktop
write_default com.apple.finder ShowMountedServersOnDesktop bool false || failed=$(( failed + 1 ))
# Allow Cmd-Q to quit Finder
write_default com.apple.finder QuitMenuItem bool true || failed=$(( failed + 1 ))
# Open folders in new windows, not tabs
write_default com.apple.finder FinderSpawnTab bool false || failed=$(( failed + 1 ))

###############################################################################
# Screenshots                                                                 #
###############################################################################

# Disable window shadow in screenshots
# Why: shadows add padding and visual noise to documentation screenshots
write_default com.apple.screencapture disable-shadow bool true || failed=$(( failed + 1 ))
# Don't show floating thumbnail after capture
# Why: the thumbnail overlays the screen for several seconds and delays access to the file path
write_default com.apple.screencapture show-thumbnail bool false || failed=$(( failed + 1 ))
# Don't include date in screenshot filename
# Why: predictable, date-free filenames are easier to reference in scripts and automation
write_default com.apple.screencapture include-date bool false || failed=$(( failed + 1 ))
# Save screenshots to ~/Desktop
write_default com.apple.screencapture location string "$HOME/Desktop" || failed=$(( failed + 1 ))

# Show mouse clicks in screen recordings
write_default com.apple.screencapture showsClicks bool true || failed=$(( failed + 1 ))

###############################################################################
# Desktop Services                                                            #
###############################################################################

# Don't create .DS_Store files on network volumes
# Why: DS_Store files expose directory metadata and appear as clutter to non-macOS users on shared volumes
write_default com.apple.desktopservices DSDontWriteNetworkStores bool true || failed=$(( failed + 1 ))
# Don't create .DS_Store files on USB volumes
# Why: portable drives are often shared across OSes where DS_Store files are visible noise
write_default com.apple.desktopservices DSDontWriteUSBStores bool true || failed=$(( failed + 1 ))

###############################################################################
# Disk images                                                                 #
###############################################################################

# Skip DMG verification
# Why: verification is redundant when the source is trusted; skips multi-second delays on large installers
write_default com.apple.frameworks.diskimages skip-verify bool true || failed=$(( failed + 1 ))
write_default com.apple.frameworks.diskimages skip-verify-locked bool true || failed=$(( failed + 1 ))
write_default com.apple.frameworks.diskimages skip-verify-remote bool true || failed=$(( failed + 1 ))

###############################################################################
# Time Machine                                                                #
###############################################################################

# Don't prompt to use new disks for backup
# Why: prevents Time Machine dialogs from interrupting when external drives are connected for other purposes
write_default com.apple.TimeMachine DoNotOfferNewDisksForBackup bool true || failed=$(( failed + 1 ))

###############################################################################
# Software Update & App Store                                                 #
###############################################################################

# Auto-check for updates
# Why: security patches are applied automatically without waiting for manual intervention
write_default com.apple.SoftwareUpdate AutomaticCheckEnabled bool true || failed=$(( failed + 1 ))
# Auto-download updates
write_default com.apple.SoftwareUpdate AutomaticDownload bool true || failed=$(( failed + 1 ))
# Install system data files automatically
write_default com.apple.SoftwareUpdate ConfigDataInstall bool true || failed=$(( failed + 1 ))
# Install security updates automatically
write_default com.apple.SoftwareUpdate CriticalUpdateInstall bool true || failed=$(( failed + 1 ))
# Auto-update App Store apps
write_default com.apple.commerce AutoUpdate bool true || failed=$(( failed + 1 ))

# Check for updates every day
write_default com.apple.SoftwareUpdate ScheduleFrequency int 1 || failed=$(( failed + 1 ))

###############################################################################
# Activity Monitor                                                            #
###############################################################################

# Show CPU usage in dock icon
# Why: makes CPU pressure visible at a glance without switching windows
write_default com.apple.ActivityMonitor IconType int 2 || failed=$(( failed + 1 ))
# Show all processes
# Why: the default "My Processes" view hides background processes that may be consuming resources
write_default com.apple.ActivityMonitor ShowCategory int 100 || failed=$(( failed + 1 ))
# Sort by CPU usage
# Why: surfaces the highest-load process immediately on open
write_default com.apple.ActivityMonitor SortColumn string CPUUsage || failed=$(( failed + 1 ))
# Sort descending
write_default com.apple.ActivityMonitor SortDirection int 0 || failed=$(( failed + 1 ))
# Update every 1 second
# Why: the 5s default misses short-lived spikes; 1s catches transient load
write_default com.apple.ActivityMonitor UpdatePeriod int 1 || failed=$(( failed + 1 ))

###############################################################################
# TextEdit                                                                    #
###############################################################################

# Default to plain text
# Why: RTF creates binary files that can't be read by other editors, diffed in git, or inspected as plain text
write_default com.apple.TextEdit RichText int 0 || failed=$(( failed + 1 ))

###############################################################################
# Terminal.app                                                                #
###############################################################################

# Default profile: Pro
write_default com.apple.Terminal "Default Window Settings" string Pro || failed=$(( failed + 1 ))
write_default com.apple.Terminal "Startup Window Settings" string Pro || failed=$(( failed + 1 ))
# Focus follows mouse
# Why: avoids needing to click to focus a terminal window, reducing hand movement across panes
write_default com.apple.Terminal FocusFollowsMouse bool true || failed=$(( failed + 1 ))
# Secure keyboard entry
# Why: prevents other processes from intercepting keystrokes, protecting passwords and private keys
write_default com.apple.Terminal SecureKeyboardEntry bool true || failed=$(( failed + 1 ))
# Don't show line marks
write_default com.apple.Terminal ShowLineMarks bool false || failed=$(( failed + 1 ))

###############################################################################
# Menu bar clock                                                              #
###############################################################################

# Digital clock
write_default com.apple.menuextra.clock IsAnalog bool false || failed=$(( failed + 1 ))
# Show AM/PM
write_default com.apple.menuextra.clock ShowAMPM bool true || failed=$(( failed + 1 ))
# Show day of week
write_default com.apple.menuextra.clock ShowDayOfWeek bool true || failed=$(( failed + 1 ))
# Don't show date
write_default com.apple.menuextra.clock ShowDate int 0 || failed=$(( failed + 1 ))

# Flash the time separators once a second
write_default com.apple.menuextra.clock FlashDateSeparators bool true || failed=$(( failed + 1 ))

###############################################################################
# Trackpad (opt-in: --with-trackpad)                                          #
###############################################################################

if $WITH_TRACKPAD; then
  log "Applying trackpad defaults..."

  for domain in com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad; do
    # Disable tap-to-click
    write_default "$domain" Clicking bool false || failed=$(( failed + 1 ))
    # Suppress Force Touch
    write_default "$domain" ForceSuppressed bool true || failed=$(( failed + 1 ))
    # Silent clicking (no haptic detent on click)
    write_default "$domain" ActuateDetents int 0 || failed=$(( failed + 1 ))
    # Bottom-right corner secondary click
    write_default "$domain" TrackpadCornerSecondaryClick int 2 || failed=$(( failed + 1 ))
    # Disable all multi-finger gestures
    write_default "$domain" TrackpadFiveFingerPinchGesture int 0 || failed=$(( failed + 1 ))
    write_default "$domain" TrackpadFourFingerHorizSwipeGesture int 0 || failed=$(( failed + 1 ))
    write_default "$domain" TrackpadFourFingerPinchGesture int 0 || failed=$(( failed + 1 ))
    write_default "$domain" TrackpadFourFingerVertSwipeGesture int 0 || failed=$(( failed + 1 ))
    write_default "$domain" TrackpadPinch bool false || failed=$(( failed + 1 ))
    write_default "$domain" TrackpadRightClick bool false || failed=$(( failed + 1 ))
    write_default "$domain" TrackpadRotate bool false || failed=$(( failed + 1 ))
    write_default "$domain" TrackpadThreeFingerDrag bool false || failed=$(( failed + 1 ))
    write_default "$domain" TrackpadThreeFingerHorizSwipeGesture int 0 || failed=$(( failed + 1 ))
    write_default "$domain" TrackpadThreeFingerTapGesture int 0 || failed=$(( failed + 1 ))
    write_default "$domain" TrackpadThreeFingerVertSwipeGesture int 0 || failed=$(( failed + 1 ))
    write_default "$domain" TrackpadTwoFingerDoubleTapGesture int 0 || failed=$(( failed + 1 ))
    write_default "$domain" TrackpadTwoFingerFromRightEdgeSwipeGesture int 0 || failed=$(( failed + 1 ))
  done
fi

###############################################################################
# Privacy & diagnostics                                                       #
###############################################################################

# Turn off Apple personalised advertising
write_default com.apple.AdLib allowApplePersonalizedAdvertising bool false || failed=$(( failed + 1 ))
# Limit ad tracking, so the advertising identifier is not used
write_default com.apple.AdLib forceLimitAdTracking bool true || failed=$(( failed + 1 ))
# Do not show the crash reporter dialog
# Why: a crashed background process should not interrupt with a dialog nobody submits
write_default com.apple.CrashReporter DialogType string none || failed=$(( failed + 1 ))

###############################################################################
# Windows & Stage Manager                                                     #
###############################################################################

# Do not reveal the Desktop when clicking the wallpaper
# Why: a stray click on the wallpaper otherwise hides every window
write_default com.apple.WindowManager EnableStandardClickToShowDesktop bool false || failed=$(( failed + 1 ))
# Group Stage Manager windows one at a time, not by application
write_default com.apple.WindowManager AppWindowGroupingBehavior int 1 || failed=$(( failed + 1 ))

###############################################################################
# Xcode                                                                       #
###############################################################################

# Do not create a git repository for a new project
# Why: the repo layout here is decided per project, not by the new-project sheet
write_default com.apple.dt.Xcode IDEDisableGitSupportForNewProjects bool true || failed=$(( failed + 1 ))
# Do not confirm before cleaning the build folder
write_default com.apple.dt.Xcode IDEWorkspaceSuppressCleanBuildPrompt bool true || failed=$(( failed + 1 ))

###############################################################################
# Finish up                                                                   #
###############################################################################

if (( failed > 0 )); then
  warn "$failed default(s) failed to apply"
fi

log "Writing rollback helper to $ROLLBACK"
backup_line "killall Finder >/dev/null 2>&1 || true"
backup_line "killall Dock >/dev/null 2>&1 || true"
backup_line "killall SystemUIServer >/dev/null 2>&1 || true"

# Apply immediate effects
killall Finder >/dev/null 2>&1 || true
killall Dock >/dev/null 2>&1 || true
killall SystemUIServer >/dev/null 2>&1 || true

ok "Defaults applied. Revert with: $ROLLBACK"
