#!/usr/bin/env bash
set -euo pipefail

# mrk hardening — opt-in security tweaks with rollback (inspired by Strap)

ROLL_DIR="$HOME/.mrk"
ROLL="$ROLL_DIR/hardening-rollback.sh"

# Create rollback directory and script with error checking
if ! mkdir -p "$ROLL_DIR"; then
  echo "Error: Failed to create rollback directory: $ROLL_DIR" >&2
  exit 1
fi

if ! printf '#!/usr/bin/env bash\n' > "$ROLL" || ! chmod +x "$ROLL"; then
  echo "Error: Failed to initialize rollback script: $ROLL" >&2
  exit 1
fi

log(){ printf "[hardening] %s\n" "$*"; }
warn(){ printf "[hardening] warning: %s\n" "$*" >&2; }
rollback(){ echo "$*" >> "$ROLL"; }

have_sudo=false
if command -v sudo >/dev/null 2>&1; then
  # Check if sudo is available (may require password)
  have_sudo=true
fi

# 1) Touch ID for sudo (pam_tid)
if $have_sudo; then
  if ! grep -q 'pam_tid.so' /etc/pam.d/sudo 2>/dev/null; then
    log "Enabling Touch ID for sudo"
    if sudo cp /etc/pam.d/sudo /etc/pam.d/sudo.backup.mrk 2>/dev/null; then
      rollback "sudo mv /etc/pam.d/sudo.backup.mrk /etc/pam.d/sudo"
      tmpfile="$(mktemp)"
      { echo 'auth       sufficient     pam_tid.so'; cat /etc/pam.d/sudo; } > "$tmpfile"
      if sudo cp "$tmpfile" /etc/pam.d/sudo 2>/dev/null; then
        log "Touch ID for sudo enabled"
      else
        warn "Failed to write new sudo PAM config (may require password)"
        # Restore backup
        sudo mv /etc/pam.d/sudo.backup.mrk /etc/pam.d/sudo 2>/dev/null || true
      fi
      rm -f "$tmpfile"
    else
      warn "Failed to backup sudo PAM config (may require password)"
    fi
  else
    log "Touch ID for sudo already enabled"
  fi
else
  log "Skipping Touch ID (sudo unavailable)"
fi

# 2) Require password immediately after sleep/screensaver
log "Requiring password immediately on wake"
prev1=$(defaults read com.apple.screensaver askForPassword 2>/dev/null || echo "0")
prev2=$(defaults read com.apple.screensaver askForPasswordDelay 2>/dev/null || echo "0")
rollback "defaults write com.apple.screensaver askForPassword -int ${prev1:-0}"
rollback "defaults write com.apple.screensaver askForPasswordDelay -int ${prev2:-0}"
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0

# 3) Enable firewall (global + stealth)
if $have_sudo; then
  log "Enabling macOS firewall (global on, stealth on)"
  prev=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | awk '{print $3}' || echo "off")
  rollback "/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate ${prev:-off}"
  if sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on 2>/dev/null; then
    if sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on 2>/dev/null; then
      log "Firewall enabled with stealth mode"
    else
      warn "Failed to enable firewall stealth mode"
    fi
  else
    warn "Failed to enable firewall (may require password)"
  fi
else
  log "Skipping firewall changes (sudo unavailable)"
fi

log "Hardening done. Rollback: $ROLL"
