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
  cat <<'EOF'
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
    *)         echo "harden: unknown option: $_arg" >&2; usage >&2; exit 2 ;;
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
#
# macOS 14 and later include /etc/pam.d/sudo_local from /etc/pam.d/sudo, and
# Apple's sudo_local.template calls it the "local config file which survives
# system update". Until 2026-09-11 this edited /etc/pam.d/sudo itself — the
# file Apple does not say survives — and overwrote it in place, so a write
# that failed part-way left sudo's own PAM file truncated. Now the line goes
# in sudo_local wherever sudo includes it; /etc/pam.d/sudo is edited only on a
# macOS too old to have sudo_local; and every file is written beside its
# target and renamed over it. "Already enabled" means an uncommented line, not
# any mention of pam_tid — the template itself carries a commented one.
PAM_SUDO=/etc/pam.d/sudo
PAM_LOCAL=/etc/pam.d/sudo_local
TID_LINE='auth       sufficient     pam_tid.so'
tid_on(){ grep -qE '^[[:space:]]*auth[[:space:]]+sufficient[[:space:]]+pam_tid\.so' "$1" 2>/dev/null; }
# pam_write TARGET CONTENT — copy CONTENT beside TARGET and rename it over TARGET.
pam_write(){
  sudo cp "$2" "$1.mrk-new" 2>/dev/null && sudo chmod 444 "$1.mrk-new" 2>/dev/null \
    && sudo mv "$1.mrk-new" "$1" 2>/dev/null
}
if $have_sudo; then
  if tid_on "$PAM_SUDO" || tid_on "$PAM_LOCAL"; then
    log "Touch ID for sudo already enabled"
  else
    pam_target=$PAM_SUDO
    if grep -qE '^[[:space:]]*auth[[:space:]]+include[[:space:]]+sudo_local' "$PAM_SUDO" 2>/dev/null; then
      pam_target=$PAM_LOCAL
    fi
    log "Touch ID for sudo will modify $pam_target"
    if confirm; then
      tmpfile="$(mrk_mktemp)"
      pam_ready=1
      if [[ -e "$pam_target" ]]; then
        # Someone's file — sudo_local may already hold other lines. Prepend,
        # keep the rest, and keep the original to put back.
        { echo "$TID_LINE"; cat "$pam_target"; } > "$tmpfile"
        if sudo cp "$pam_target" "$pam_target.backup.mrk" 2>/dev/null; then
          rollback "sudo mv $pam_target.backup.mrk $pam_target"
        else
          warn "Failed to back up $pam_target (may require password) — leaving Touch ID alone"
          pam_ready=0
        fi
      else
        echo "$TID_LINE" > "$tmpfile"
        rollback "sudo rm -f $pam_target"
      fi
      if (( pam_ready )) && [[ "$pam_target" == "$PAM_SUDO" ]] && \
         ! grep -qE 'pam_smartcard\.so|pam_opendirectory\.so' "$tmpfile"; then
        warn "Generated PAM config appears invalid — aborting Touch ID setup"
        pam_ready=0
      fi
      if (( pam_ready )); then
        if pam_write "$pam_target" "$tmpfile"; then
          log "Touch ID for sudo enabled ($pam_target)"
        else
          sudo rm -f "$pam_target.mrk-new" 2>/dev/null || true
          warn "Failed to write $pam_target (may require password) — it is unchanged"
        fi
      fi
      rm -f "$tmpfile"
    else
      log "Skipping Touch ID setup"
    fi
  fi
else
  log "Skipping Touch ID (sudo unavailable)"
fi

# recorded [-currentHost] DOMAIN KEY — true when the rollback script already
# holds a line for KEY, in either form such a line takes: write, which puts a
# value back, or delete, for a key that was absent. First-run originals win on
# re-runs only if both forms are checked. The Analytics and Handoff guards
# below used to check the write form alone, so a key absent on the first run
# got a delete line then, and on the second run a write line recording mrk's
# own value — the rollback ran both, and ended on mrk's value. (A trailing
# space stops one key being taken for a longer key it prefixes.)
recorded(){
  local host=""
  if [[ "$1" == -currentHost ]]; then host="-currentHost "; shift; fi
  grep -qF "defaults ${host}write $1 $2 " "$ROLL" 2>/dev/null ||
    grep -qF "defaults ${host}delete $1 $2 " "$ROLL" 2>/dev/null
}

# 2) Require password immediately after sleep/screensaver
#
# Through sysadminctl, the interface macOS reads. This used to write the
# com.apple.screensaver keys askForPassword and askForPasswordDelay, which
# current macOS ignores: on the machine this was found on (2026-09-11, macOS
# 15.7.4) they read 1 and 0 — "immediately" — while `sysadminctl -screenLock
# status` reported the delay macOS was enforcing, 3600 seconds. The step said
# "Requiring password immediately on wake" and changed nothing.
#
# Setting it needs the login password, which sysadminctl asks for itself, so
# it runs only at a terminal; otherwise this prints the command to run.
lock_prev=""
lock_status=$(sysadminctl -screenLock status 2>&1) || true
if [[ "$lock_status" =~ delay\ is\ ([0-9]+)\ seconds ]]; then
  lock_prev=${BASH_REMATCH[1]}
  (( lock_prev == 0 )) && lock_prev=immediate
elif [[ "$lock_status" == *immediate* ]]; then
  lock_prev=immediate
elif [[ "$lock_status" =~ [Oo]ff|disabled ]]; then
  lock_prev=off
fi
case "$lock_prev" in
  off) lock_desc="never" ;;
  *)   lock_desc="$lock_prev seconds after sleep" ;;
esac
if [[ "$lock_prev" == immediate ]]; then
  log "A password is already required immediately on wake"
elif [[ -z "$lock_prev" ]]; then
  warn "Could not read the screen-lock delay — leaving it alone (sysadminctl: ${lock_status##*] })"
elif [[ ! -t 0 ]] || (( ${NONINTERACTIVE:-0} )); then
  warn "A password is required $lock_desc, not immediately. Setting it needs your login password:"
  warn "  sysadminctl -screenLock immediate -password -"
else
  log "A password is required $lock_desc; requiring it immediately (sysadminctl asks for your login password)"
  if confirm; then
    # Recorded first, like every other step: if the change then fails, the
    # line merely puts back the value that is still there.
    grep -qF "sysadminctl -screenLock " "$ROLL" 2>/dev/null || \
      rollback "sysadminctl -screenLock $lock_prev -password -"
    if sysadminctl -screenLock immediate -password -; then
      log "A password is now required immediately on wake"
    else
      warn "sysadminctl did not change the screen-lock delay"
    fi
  else
    log "Skipping the screen-lock delay"
  fi
fi

# 3) Enable firewall (global + stealth)
if $have_sudo; then
  # Capture command output before grep to avoid SIGPIPE/pipefail race
  # (grep -q closes stdin early, which can make the pipeline return non-zero
  # under `set -o pipefail` even when the pattern matches).
  # `|| true` used to fold a FAILED read into the same "off" a successful read of
  # a disabled firewall produces. The rollback line then said --setglobalstate
  # off, so running the rollback would have DISABLED a firewall that was on and
  # had merely failed to report itself. Track the two apart, the way the
  # screensaver keys above already do with prev1_absent/prev2_absent.
  prev="off" prev_absent=0
  if fw_state=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null); then
    if grep -qi "enabled" <<< "$fw_state"; then prev="on"; fi
  else
    prev_absent=1
  fi
  prev_stealth="off" prev_stealth_absent=0
  if fw_stealth=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>/dev/null); then
    if grep -qi " is on" <<< "$fw_stealth"; then prev_stealth="on"; fi
  else
    prev_stealth_absent=1
  fi

  need_firewall=0
  if [[ "$prev" != "on" || "$prev_stealth" != "on" ]]; then
    need_firewall=1
    log "Firewall changes require sudo (global: ${prev}, stealth: ${prev_stealth})"
  fi

  if (( need_firewall )); then
    if ! confirm; then
      log "Skipping firewall changes"
    else
      # Only record a rollback for a state actually read. Enabling still goes ahead
      # when the read failed — a firewall left on is not a harm, whereas a rollback
      # line inventing "it was off" is.
      if (( prev_absent )); then
        warn "Could not read the firewall state — enabling it, but recording no rollback line"
      else
        grep -qF "setglobalstate" "$ROLL" 2>/dev/null || \
          rollback "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate $prev"
      fi

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
        if (( prev_stealth_absent )); then
          warn "Could not read stealth mode — enabling it, but recording no rollback line"
        else
          grep -qF "setstealthmode" "$ROLL" 2>/dev/null || \
            rollback "sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode $prev_stealth"
        fi
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
  # Both keys, and each recorded before it changes: ThirdPartyDataSubmit was
  # written with no rollback line at all until 2026-09-11, so undoing hardening
  # left it off.
  for dk in AutoSubmit ThirdPartyDataSubmit; do
    recorded "\"$DIAG\"" "$dk" && continue
    if prev_d=$(defaults read "$DIAG" "$dk" 2>/dev/null) \
       || prev_d=$(sudo -n defaults read "$DIAG" "$dk" 2>/dev/null) \
       || prev_d=$(sudo defaults read "$DIAG" "$dk" 2>/dev/null); then
      d_bool=false
      [[ "$prev_d" == "1" ]] && d_bool=true
      rollback "sudo defaults write \"$DIAG\" $dk -bool ${d_bool}"
    else
      rollback "sudo defaults delete \"$DIAG\" $dk >/dev/null 2>&1 || true"
    fi
  done
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
  if ! recorded -currentHost com.apple.coreservices.useractivityd "$hk"; then
    if prev_h=$(defaults -currentHost read com.apple.coreservices.useractivityd "$hk" 2>/dev/null); then
      h_bool=false
      [[ "$prev_h" == "1" ]] && h_bool=true
      rollback "defaults -currentHost write com.apple.coreservices.useractivityd $hk -bool ${h_bool}"
    else
      rollback "defaults -currentHost delete com.apple.coreservices.useractivityd $hk >/dev/null 2>&1 || true"
    fi
  fi
  defaults -currentHost write com.apple.coreservices.useractivityd "$hk" -bool false
done

log "Hardening done. Rollback: $ROLL"
