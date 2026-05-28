#!/usr/bin/env bash
set -euo pipefail

# mrk hardening — opt-in security tweaks with rollback (inspired by Strap)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

for _arg in "$@"; do
  case "$_arg" in
    --yes|-y) NONINTERACTIVE=1 ;;
  esac
done

ROLL_DIR="$HOME/.mrk"
ROLL="$ROLL_DIR/hardening-rollback.sh"

# Create rollback directory and script with error checking
if ! mkdir -p "$ROLL_DIR"; then
  echo "Error: Failed to create rollback directory: $ROLL_DIR" >&2
  exit 1
fi

if [[ -f "$ROLL" ]] && grep -q '^#!/usr/bin/env bash$' "$ROLL" 2>/dev/null; then
  # Rollback file already exists and has a valid shebang — preserve prior entries
  chmod +x "$ROLL" 2>/dev/null || true
else
  if ! printf '#!/usr/bin/env bash\n' > "$ROLL" || ! chmod +x "$ROLL"; then
    echo "Error: Failed to initialize rollback script: $ROLL" >&2
    exit 1
  fi
fi

log(){ printf "[hardening] %s\n" "$*"; }
warn(){ printf "[hardening] warning: %s\n" "$*" >&2; }
rollback(){ grep -qFx "$*" "$ROLL" 2>/dev/null && return 0; echo "$*" >> "$ROLL"; }

have_sudo=false
if command -v sudo >/dev/null 2>&1; then
  have_sudo=true
  # Refresh credentials once when interactive (avoids mid-script password prompts)
  if [[ -t 0 ]] && (( ! NONINTERACTIVE )) && ! sudo -n true 2>/dev/null; then
    log "Hardening requires administrator privileges"
    sudo -v || have_sudo=false
  fi
fi

# 1) Touch ID for sudo (pam_tid)
if $have_sudo; then
  if ! grep -q 'pam_tid.so' /etc/pam.d/sudo 2>/dev/null; then
    log "Touch ID for sudo will modify /etc/pam.d/sudo"
    if confirm; then
      log "Enabling Touch ID for sudo"
      if sudo cp /etc/pam.d/sudo /etc/pam.d/sudo.backup.mrk 2>/dev/null; then
        rollback "sudo mv /etc/pam.d/sudo.backup.mrk /etc/pam.d/sudo"
        tmpfile="$(mktemp -t mrk)"
        { echo 'auth       sufficient     pam_tid.so'; cat /etc/pam.d/sudo; } > "$tmpfile"
        if [[ ! -s "$tmpfile" ]] || ! grep -q 'pam_tid\.so' "$tmpfile" || \
           ! grep -qE 'pam_smartcard\.so|pam_opendirectory\.so' "$tmpfile"; then
          warn "Generated PAM config appears invalid — aborting Touch ID setup"
          rm -f "$tmpfile"
          sudo mv /etc/pam.d/sudo.backup.mrk /etc/pam.d/sudo 2>/dev/null || true
        elif sudo cp "$tmpfile" /etc/pam.d/sudo 2>/dev/null; then
          log "Touch ID for sudo enabled"
        else
          warn "Failed to write new sudo PAM config (may require password)"
          sudo mv /etc/pam.d/sudo.backup.mrk /etc/pam.d/sudo 2>/dev/null || true
        fi
        rm -f "$tmpfile"
      else
        warn "Failed to backup sudo PAM config (may require password)"
      fi
    else
      log "Skipping Touch ID setup"
    fi
  else
    log "Touch ID for sudo already enabled"
  fi
else
  log "Skipping Touch ID (sudo unavailable)"
fi

# 2) Require password immediately after sleep/screensaver
log "Requiring password immediately on wake"
prev1_absent=0 prev2_absent=0
if prev1=$(defaults read com.apple.screensaver askForPassword 2>/dev/null); then
  :
else
  prev1_absent=1
  prev1="0"
fi
if prev2=$(defaults read com.apple.screensaver askForPasswordDelay 2>/dev/null); then
  :
else
  prev2_absent=1
  prev2="0"
fi
# Guard: only record if no entry for this key exists — first-run originals win on re-runs
if ! grep -qF "askForPassword -" "$ROLL" 2>/dev/null; then
  if (( prev1_absent )); then
    rollback 'defaults delete com.apple.screensaver askForPassword >/dev/null 2>&1 || true'
  else
    rollback "defaults write com.apple.screensaver askForPassword -int ${prev1}"
  fi
fi
if ! grep -qF "askForPasswordDelay -" "$ROLL" 2>/dev/null; then
  if (( prev2_absent )); then
    rollback 'defaults delete com.apple.screensaver askForPasswordDelay >/dev/null 2>&1 || true'
  else
    rollback "defaults write com.apple.screensaver askForPasswordDelay -int ${prev2}"
  fi
fi
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0

# 3) Enable firewall (global + stealth)
if $have_sudo; then
  prev="off"
  /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null | \
    grep -qi "enabled" && prev="on" || true
  prev_stealth="off"
  /usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>/dev/null | \
    grep -qi " is on" && prev_stealth="on" || true

  need_firewall=0
  if [[ "$prev" != "on" || "$prev_stealth" != "on" ]]; then
    need_firewall=1
    log "Firewall changes require sudo (global: ${prev}, stealth: ${prev_stealth})"
  fi

  if (( need_firewall )); then
    if ! confirm; then
      log "Skipping firewall changes"
    else
      grep -qF "setglobalstate" "$ROLL" 2>/dev/null || \
        rollback "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate $prev"

      if [[ "$prev" != "on" ]]; then
        log "Enabling macOS firewall (global on)"
        if sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on 2>/dev/null; then
          log "Firewall enabled"
        else
          warn "Failed to enable firewall (may require password)"
        fi
      else
        log "Firewall already enabled"
      fi

      if [[ "$prev_stealth" != "on" ]]; then
        grep -qF "setstealthmode" "$ROLL" 2>/dev/null || \
          rollback "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode $prev_stealth"
        log "Enabling firewall stealth mode"
        if sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on 2>/dev/null; then
          log "Stealth mode enabled"
        else
          warn "Failed to enable firewall stealth mode"
        fi
      else
        log "Firewall stealth mode already enabled"
      fi
    fi
  fi
else
  log "Skipping firewall changes (sudo unavailable)"
fi

log "Hardening done. Rollback: $ROLL"
