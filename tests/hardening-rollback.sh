#!/usr/bin/env bash
# hardening-rollback.sh — run scripts/hardening.sh against a sandbox and prove
# that its undo script puts every setting back.
#
# harden edits PAM, the firewall and system preferences, and never runs here
# for real. A copy has every system path rewritten into a temporary directory
# — /etc/pam.d, the firewall tool, each preferences domain — and sudo,
# socketfilterfw and sysadminctl are stubs that keep their state in files. The
# copy refuses to run if any system reference survives the rewrite.
#
# What it guards, each found on 2026-09-11: a second run recorded mrk's own
# Analytics and Handoff values as the originals, so the undo left them
# changed; ThirdPartyDataSubmit had no undo line at all; the password-on-wake
# step wrote screensaver keys macOS ignores, and now goes through
# `sysadminctl -screenLock`; and Touch ID now goes into /etc/pam.d/sudo_local
# where sudo includes it, written beside its target and renamed over it.
#
# Runs under /bin/bash as well as the bash running it: harden has no bash-4
# guard, so on a new Mac it runs under 3.2. ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" != --inner ]]; then
  run_under() {
    # shellcheck disable=SC2016  # expanded by the inner bash, not this one
    printf '  under bash %s\n' "$("$1" -c 'echo "${BASH_VERSION%%(*}"')"
    "$1" "${BASH_SOURCE[0]}" --inner
  }
  rc=0
  run_under /bin/bash || rc=1
  if [[ ! "$BASH" -ef /bin/bash ]]; then run_under "$BASH" || rc=1; fi
  exit "$rc"
fi

# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"
ROOT=$(mrk_mktemp_d) || exit 1
trap 'rm -rf "$ROOT"' EXIT
BASH_UNDER_TEST=$BASH

STOCK='# sudo: auth account password session
auth       include        sudo_local
auth       sufficient     pam_smartcard.so
auth       required       pam_opendirectory.so
account    required       pam_permit.so
password   required       pam_deny.so
session    required       pam_permit.so'
TID='auth       sufficient     pam_tid.so'

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

# setup NAME PAM — a sandbox: stubs, a redirected copy of hardening.sh, and a
# Mac with the firewall off, a 3600 s screen-lock delay, and some keys absent.
setup() {
  SB=$ROOT/$1; P=$SB/prefs
  mkdir -p "$SB"/etc/pam.d "$P" "$SB"/bin "$SB"/home "$SB"/state "$SB"/tmp
  case $2 in
    stock15) printf '%s\n' "$STOCK" > "$SB/etc/pam.d/sudo" ;;
    old)     printf '%s\n' "$STOCK" | grep -v sudo_local > "$SB/etc/pam.d/sudo" ;;
    local)   printf '%s\n' "$STOCK" > "$SB/etc/pam.d/sudo"
             printf 'auth       optional       pam_reattach.so\n' > "$SB/etc/pam.d/sudo_local" ;;
    enabled) printf '%s\n%s\n' "$TID" "$STOCK" > "$SB/etc/pam.d/sudo" ;;
  esac
  chmod 644 "$SB"/etc/pam.d/*          # the stub sudo is not root
  echo off > "$SB/state/fw"; echo off > "$SB/state/stealth"; echo 3600 > "$SB/state/lock"
  cat > "$SB/bin/socketfilterfw" <<STUB
#!/bin/bash
S="$SB/state"
case "\$1" in
  --getglobalstate) [[ \$(cat "\$S/fw") == on ]] && echo "Firewall is enabled. (State = 1)" || echo "Firewall is disabled. (State = 0)" ;;
  --getstealthmode) [[ \$(cat "\$S/stealth") == on ]] && echo "Firewall stealth mode is on" || echo "Firewall stealth mode is off" ;;
  --setglobalstate) echo "\$2" > "\$S/fw" ;;
  --setstealthmode) echo "\$2" > "\$S/stealth" ;;
esac
STUB
  # The real one prints its answer on stderr, behind a timestamp.
  cat > "$SB/bin/sysadminctl" <<STUB
#!/bin/bash
S="$SB/state"; ts="2026-09-11 11:14:48.347 sysadminctl[1:2]"
[[ "\$1" == -screenLock ]] || exit 1
case "\$2" in
  status) echo "\$ts screenLock delay is \$(cat "\$S/lock") seconds" >&2 ;;
  immediate) echo 0 > "\$S/lock" ;;
  *) echo "\$2" > "\$S/lock" ;;
esac
STUB
  cat > "$SB/bin/sudo" <<'STUB'
#!/bin/bash
while [[ "${1:-}" == -* ]]; do case "$1" in -v) exit 0 ;; *) shift ;; esac; done
[[ $# -eq 0 ]] && exit 0
exec "$@"
STUB
  chmod +x "$SB"/bin/*
  sed -e "s|/usr/libexec/ApplicationFirewall/socketfilterfw|$SB/bin/socketfilterfw|g" \
      -e "s|/etc/pam.d|$SB/etc/pam.d|g" \
      -e "s|/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist|$P/DiagnosticMessagesHistory.plist|g" \
      -e "s|defaults -currentHost|defaults|g" -e "s|recorded -currentHost|recorded|g" \
      -e "s|com.apple.coreservices.useractivityd|$P/useractivityd|g" \
      -e "s|com.apple.LaunchServices|$P/LaunchServices|g" \
      -e "s|source \"\$SCRIPT_DIR/lib.sh\"|source \"$REPO_ROOT/scripts/lib.sh\"|" \
      "$REPO_ROOT/scripts/hardening.sh" > "$SB/harden.sh"
  local left
  # shellcheck disable=SC2016  # the pattern is the literal text of the helper's comparison
  left=$(grep -n -E '/etc/|/usr/libexec|/Library/|com\.apple\.|-currentHost' "$SB/harden.sh" \
    | grep -v -E '^[0-9]+:[[:space:]]*#' | grep -v -F "$SB" | grep -v -F '"$1" == -currentHost')
  if [[ -n "$left" ]]; then
    fail "the copy of hardening.sh still reaches the real system — not running it: $left"
    return 1
  fi
  defaults write "$P/DiagnosticMessagesHistory" ThirdPartyDataSubmit -bool true
  defaults write "$P/useractivityd" ActivityReceivingAllowed -bool true
}
snap() {
  local f dk v
  { for f in sudo sudo_local; do
      if [[ -e $SB/etc/pam.d/$f ]]; then echo "$f=$(shasum "$SB/etc/pam.d/$f" | cut -c1-12)"; else echo "$f=<none>"; fi
    done
    echo "fw=$(cat "$SB/state/fw") stealth=$(cat "$SB/state/stealth") lock=$(cat "$SB/state/lock")"
    for dk in LaunchServices:LSQuarantine DiagnosticMessagesHistory:AutoSubmit \
              DiagnosticMessagesHistory:ThirdPartyDataSubmit useractivityd:ActivityAdvertisingAllowed \
              useractivityd:ActivityReceivingAllowed; do
      v=$(defaults read "$P/${dk%%:*}" "${dk#*:}" 2>/dev/null) || v="<absent>"
      echo "$dk=$v"
    done; } > "$1"
}
harden() { HOME="$SB/home" TMPDIR="$SB/tmp" PATH="$SB/bin:$PATH" "$BASH_UNDER_TEST" "$SB/harden.sh" --yes >"$SB/run.log" 2>&1; }
undo()   { HOME="$SB/home" PATH="$SB/bin:$PATH" bash "$SB/home/.mrk/hardening-rollback.sh" >/dev/null 2>&1; }
restored() { diff -q "$SB/before" "$SB/after" >/dev/null; }

# A — a stock macOS 15, with no terminal: run twice, then undo.
if setup A stock15; then
  snap "$SB/before"; harden; l1=$(wc -l < "$SB/home/.mrk/hardening-rollback.sh")
  if [[ "$(cat "$SB/etc/pam.d/sudo_local" 2>/dev/null)" == "$TID" ]] \
     && [[ "$(cat "$SB/etc/pam.d/sudo")" == "$STOCK" ]]; then
    pass "Touch ID goes into a new sudo_local, and /etc/pam.d/sudo is left alone"
  else
    fail "Touch ID on a stock macOS 15 did not go into sudo_local alone"
  fi
  if grep -q 'A password is required 3600 seconds after sleep, not immediately' "$SB/run.log" \
     && [[ "$(cat "$SB/state/lock")" == 3600 ]]; then
    pass "with no terminal the screen-lock delay is reported, from sysadminctl, and left alone"
  else
    fail "the screen-lock step did not report the 3600 s delay and leave it: $(grep -i 'password is\|screen-lock' "$SB/run.log" | head -2)"
  fi
  harden
  if [[ "$(wc -l < "$SB/home/.mrk/hardening-rollback.sh")" == "$l1" ]]; then
    pass "a second run adds nothing to the undo script"
  else
    fail "a second run added: $(tail -n +$((l1 + 1)) "$SB/home/.mrk/hardening-rollback.sh" | tr '\n' ' ')"
  fi
  undo; snap "$SB/after"
  if restored; then pass "the undo puts every setting back"; else fail "the undo missed: $(diff "$SB/before" "$SB/after" | grep '^>' | tr '\n' ' ')"; fi
fi

# B — the same, at a terminal: the screen lock is changed, and put back.
if setup B stock15; then
  snap "$SB/before"
  HOME="$SB/home" TMPDIR="$SB/tmp" PATH="$SB/bin:$PATH" python3 - "$BASH_UNDER_TEST" "$SB/harden.sh" <<'PY'
import os, pty, select, sys, time
env = dict(os.environ); env.pop("NONINTERACTIVE", None)
pid, fd = pty.fork()
if pid == 0:
    os.execvpe(sys.argv[1], [sys.argv[1], sys.argv[2]], env)
out, t0, n = b"", time.time(), 0
while time.time() - t0 < 60:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try: chunk = os.read(fd, 4096)
        except OSError: chunk = b""
        if chunk:
            out += chunk
            while n < out.count(b"[Enter to continue"):
                os.write(fd, b"\r"); n += 1
            continue
    if os.waitpid(pid, os.WNOHANG)[0]: break
PY
  if [[ "$(cat "$SB/state/lock")" == 0 ]] && grep -qx 'sysadminctl -screenLock 3600 -password -' "$SB/home/.mrk/hardening-rollback.sh"; then
    pass "at a terminal the delay is set to immediate through sysadminctl, and the old one recorded"
  else
    fail "at a terminal: lock=$(cat "$SB/state/lock"), undo line: $(grep sysadminctl "$SB/home/.mrk/hardening-rollback.sh")"
  fi
  undo; snap "$SB/after"
  if restored; then pass "the undo puts the 3600 s delay back with the rest"; else fail "after undo at a terminal: $(diff "$SB/before" "$SB/after" | grep '^>' | tr '\n' ' ')"; fi
fi

# C, D — an older macOS with no sudo_local, and a sudo_local that already holds a line.
for case in "C old" "D local"; do
  read -r cname name <<<"$case"
  if setup "$cname" "$name"; then
    snap "$SB/before"; harden
    if [[ $name == old ]]; then f=sudo; else f=sudo_local; fi
    if [[ "$(head -1 "$SB/etc/pam.d/$f")" == "$TID" ]]; then
      pass "$([[ $name == old ]] && echo "with no sudo_local, Touch ID is prepended to sudo" || echo "an existing sudo_local keeps its lines, Touch ID prepended")"
    else
      fail "$f did not start with the Touch ID line"
    fi
    undo; snap "$SB/after"
    if restored; then pass "and the undo restores $f byte for byte"; else fail "undo after $f: $(diff "$SB/before" "$SB/after" | grep '^>' | tr '\n' ' ')"; fi
  fi
done

# E — Touch ID already enabled in sudo, as on the Mac this was found on.
if setup E enabled; then
  snap "$SB/before"; harden; snap "$SB/after2"
  if grep -q 'Touch ID for sudo already enabled' "$SB/run.log" && diff -q <(grep -E '^sudo' "$SB/before") <(grep -E '^sudo' "$SB/after2") >/dev/null; then
    pass "Touch ID already in sudo: no PAM file is touched"
  else
    fail "Touch ID already enabled, yet a PAM file changed"
  fi
fi

(( fails == 0 ))
