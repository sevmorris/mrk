#!/usr/bin/env bash
set -euo pipefail

# mrk hardening — opt-in security tweaks with rollback (inspired by Strap)

_self="${BASH_SOURCE[0]}"
while [[ -L "$_self" ]]; do
  _dir="$(cd "$(dirname "$_self")" && pwd)"
  _self="$(readlink "$_self")"
  [[ "$_self" != /* ]] && _self="$_dir/$_self"
done
SCRIPT_DIR="$(cd "$(dirname "$_self")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

usage() {
  cat >&2 <<'EOF'
Usage: harden [--yes | -y] [--help | -h]

Apply the macOS security settings, with a rollback script.

  -y, --yes    Skip every confirmation prompt
  -h, --help   Show this help

Undo with: bash ~/.mrk/hardening-rollback.sh
EOF
}

# An unknown argument used to fall through this loop and the script ran anyway.
# `harden --help` therefore APPLIED the settings instead of printing help, which
# is a poor thing for a script that edits /etc/pam.d/sudo to do.
for _arg in "$@"; do
  case "$_arg" in
    --yes|-y)  NONINTERACTIVE=1 ;;
    --help|-h) usage; exit 0 ;;
    *)         echo "harden: unknown option: $_arg" >&2; usage; exit 1 ;;
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
  if [[ -t 0 ]] && (( ! ${NONINTERACTIVE:-0} )) && ! sudo -n true 2>/dev/null; then
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
        tmpfile="$(mrk_mktemp)"
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
# Guard: only record if no entry for this key exists — first-run originals win on re-runs.
# Match both forms the rollback lines take (trailing space stops prefix collisions).
if ! grep -qF "defaults write com.apple.screensaver askForPassword " "$ROLL" 2>/dev/null && \
   ! grep -qF "defaults delete com.apple.screensaver askForPassword " "$ROLL" 2>/dev/null; then
  if (( prev1_absent )); then
    rollback 'defaults delete com.apple.screensaver askForPassword >/dev/null 2>&1 || true'
  else
    rollback "defaults write com.apple.screensaver askForPassword -int ${prev1}"
  fi
fi
if ! grep -qF "defaults write com.apple.screensaver askForPasswordDelay " "$ROLL" 2>/dev/null && \
   ! grep -qF "defaults delete com.apple.screensaver askForPasswordDelay " "$ROLL" 2>/dev/null; then
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
  # Capture command output before grep to avoid SIGPIPE/pipefail race
  # (grep -q closes stdin early, which can make the pipeline return non-zero
  # under `set -o pipefail` even when the pattern matches).
  prev="off"
  fw_state=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null || true)
  if grep -qi "enabled" <<< "$fw_state"; then prev="on"; fi
  prev_stealth="off"
  fw_stealth=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>/dev/null || true)
  if grep -qi " is on" <<< "$fw_stealth"; then prev_stealth="on"; fi

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

# 4) Quarantine prompt for downloaded applications
#
# This is the one step here that LOWERS the security floor rather than raising
# it, and it is deliberate. LSQuarantine=false suppresses the "X is an app
# downloaded from the Internet. Are you sure you want to open it?" dialog that
# LaunchServices shows the first time you open a quarantined app.
#
# It does NOT disable Gatekeeper: signature and notarization checks still run,
# an unsigned app is still refused, and `spctl` is untouched. What it removes is
# the extra confirmation on an app that has already passed those checks.
#
# It lives in this script rather than in defaults.sh because it is a security
# decision, and because `make harden` writes a rollback — `make defaults` would
# too, but grouping it with the firewall and the sleep password keeps the whole
# security posture in one file and one rollback.
log "Suppressing the quarantine prompt for downloaded apps"
warn "this LOWERS the security floor — see the note in scripts/hardening.sh"
lsq_absent=0
if lsq_prev=$(defaults read com.apple.LaunchServices LSQuarantine 2>/dev/null); then
  :
else
  lsq_absent=1
  lsq_prev="1"
fi
# Same first-run-wins guard as the keys above.
if ! grep -qF "defaults write com.apple.LaunchServices LSQuarantine " "$ROLL" 2>/dev/null && \
   ! grep -qF "defaults delete com.apple.LaunchServices LSQuarantine " "$ROLL" 2>/dev/null; then
  if (( lsq_absent )); then
    rollback 'defaults delete com.apple.LaunchServices LSQuarantine >/dev/null 2>&1 || true'
  else
    lsq_bool=false
    [[ "$lsq_prev" == "1" ]] && lsq_bool=true
    rollback "defaults write com.apple.LaunchServices LSQuarantine -bool ${lsq_bool}"
  fi
fi
defaults write com.apple.LaunchServices LSQuarantine -bool false

# 5) Stop sending Mac Analytics to Apple
#
# This lives in a system plist, so it needs sudo, which is why it is here and
# not in defaults.sh. It is the last of the three telemetry channels: Siri data
# sharing and personalised advertising are already off in defaults.sh, and this
# is the usage-and-crash one.
if $have_sudo; then
  log "Turning off Mac Analytics submission"
  DIAG="/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist"
  # Read plainly first, then with sudo, and treat the key as absent only when
  # BOTH fail. Neither read alone is enough:
  #
  #   A plain read works on a stock Mac, where the plist is world-readable, and
  #   stops a missing sudo credential being misread as a missing key — which
  #   recorded a rollback that DELETES AutoSubmit instead of restoring it.
  #
  #   But `sudo defaults write` rewrites the file as root, mode 600. So from the
  #   second run of this script onward the plain read fails on permissions, and
  #   the plain read alone would reintroduce exactly the same bug.
  #
  # Only the write needs privilege; the reads are belt and braces.
  if prev_auto=$(defaults read "$DIAG" AutoSubmit 2>/dev/null) \
     || prev_auto=$(sudo -n defaults read "$DIAG" AutoSubmit 2>/dev/null) \
     || prev_auto=$(sudo defaults read "$DIAG" AutoSubmit 2>/dev/null); then
    if ! grep -qF "defaults write \"$DIAG\" AutoSubmit " "$ROLL" 2>/dev/null; then
      auto_bool=false
      [[ "$prev_auto" == "1" ]] && auto_bool=true
      rollback "sudo defaults write \"$DIAG\" AutoSubmit -bool ${auto_bool}"
    fi
  else
    rollback "sudo defaults delete \"$DIAG\" AutoSubmit >/dev/null 2>&1 || true"
  fi
  sudo defaults write "$DIAG" AutoSubmit -bool false 2>/dev/null \
    || warn "Failed to write AutoSubmit (may require Full Disk Access for the terminal)"
  sudo defaults write "$DIAG" ThirdPartyDataSubmit -bool false 2>/dev/null || true
else
  log "Skipping Mac Analytics (sudo unavailable)"
fi

# 6) Turn off Handoff
#
# ByHost, so it needs `defaults -currentHost` — write_default in defaults.sh
# issues a plain `defaults write` and would put the keys in the wrong plist.
# Handoff advertises what you are doing to nearby Apple devices. iPhone call
# relay and iPhone widgets are already off; this is the rest of that story.
log "Turning off Handoff"
for hk in ActivityAdvertisingAllowed ActivityReceivingAllowed; do
  if prev_h=$(defaults -currentHost read com.apple.coreservices.useractivityd "$hk" 2>/dev/null); then
    if ! grep -qF "defaults -currentHost write com.apple.coreservices.useractivityd $hk " "$ROLL" 2>/dev/null; then
      h_bool=false
      [[ "$prev_h" == "1" ]] && h_bool=true
      rollback "defaults -currentHost write com.apple.coreservices.useractivityd $hk -bool ${h_bool}"
    fi
  else
    rollback "defaults -currentHost delete com.apple.coreservices.useractivityd $hk >/dev/null 2>&1 || true"
  fi
  defaults -currentHost write com.apple.coreservices.useractivityd "$hk" -bool false
done

log "Hardening done. Rollback: $ROLL"
