#!/usr/bin/env bash
# undo-files.sh — prove that mrk's undo scripts survive, are offered, and undo
# only what they are asked to. Audit 19, W-3, W-8, W-9 and W-13.
#
# Until 2026-09-27:
# - W-3: trim-services (and hardening.sh, which tests/hardening-rollback.sh
#   covers) kept a copy of the old rollback check, and emptied an undo file
#   whose first line was any shebang but `#!/usr/bin/env bash`.
# - W-8: services-rollback.sh was offered by neither uninstall nor nuke-mrk,
#   and nuke-mrk put it in the Trash with ~/.mrk while launchd kept the
#   disables. It did so on this Mac on 2026-09-24.
# - W-13: "Run macOS defaults rollback now?" also ran the whole-domain deletes
#   post-install writes for each plist it imports. On this Mac, 33 apps'
#   preferences, and every setting made in them since.
# - W-9: setup's MRK_LOGIN_MSG appended an undo line on every run, so after two
#   runs the undo ended by writing mrk's own message back.
#
# Each script runs from a copy of the repository, under a throwaway HOME, with
# `env -i` and PATH cut to stubs and the system directories. defaults,
# launchctl, killall, sudo, make and brew are stubs. The undo files the cases
# plant run through them, so each line they run is recorded and nothing reaches
# the real preferences or launchd. For the login message, `defaults` keeps
# /Library/Preferences in a scratch folder and `sudo` runs its command there.
# nuke-mrk's /Applications and JDK paths point into the sandbox. uninstall needs
# a terminal, so it runs in a pseudo-terminal that answers each [y/N] as it
# appears: script(1) sends end-of-file the moment its input runs out, before
# the first prompt has read anything. Each case runs under /bin/bash and under
# the bash running this file. ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" != --inner ]]; then
  run_under() {
    # shellcheck disable=SC2016  # expanded by the inner bash, not this one
    printf '  under bash %s\n' "$("$1" -c 'echo "${BASH_VERSION%%(*}"')"
    "$1" "${BASH_SOURCE[0]}" --inner "$1"
  }
  rc=0
  run_under /bin/bash || rc=1
  if [[ ! "$BASH" -ef /bin/bash ]]; then run_under "$BASH" || rc=1; fi
  exit "$rc"
fi
BASH_UNDER_TEST="$2"

# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

command -v python3 >/dev/null 2>&1 || { fail "python3 not found"; exit 1; }

W=$(mrk_mktemp_d) || exit 1
W=$(cd "$W" && pwd -P)
trap 'rm -rf "$W"' EXIT
R="$W/repo"; H="$W/home"; S="$W/stubs"
mkdir -p "$R" "$S" "$W/tmp" "$W/Applications"

# ── The repository copy ──────────────────────────────────────────────────────

while IFS= read -r -d '' f; do
  [[ -f "$REPO_ROOT/$f" ]] || continue
  mkdir -p "$R/$(dirname "$f")"
  cp -p "$REPO_ROOT/$f" "$R/$f"
done < <(git -C "$REPO_ROOT" ls-files -z scripts bin)
printf '#!/usr/bin/env bash\nexit 0\n' > "$R/scripts/defaults.sh"   # setup's macOS defaults: not under test
sed -e "s#/Applications/#$W/Applications/#g" \
    -e "s#/Library/Java/JavaVirtualMachines/#$W/jvm/#g" "$R/bin/nuke-mrk" > "$W/rewrite" \
  && cat "$W/rewrite" > "$R/bin/nuke-mrk"
if grep -nE '"/Applications/|/Library/Java/' "$R/bin/nuke-mrk" | grep -v "$W"; then
  fail "a real path survived the rewrite of nuke-mrk — refusing to run"
  exit 1
fi

# ── Stubs ────────────────────────────────────────────────────────────────────

# Each records its command line in $SANDBOX/calls.
cat > "$S/record" <<'EOF'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >> "$SANDBOX/calls"
EOF
chmod +x "$S/record"
for cmd in killall brew make osascript open; do cp -p "$S/record" "$S/$cmd"; done
# sudo runs its command only when SUDO_RUNS=1, and never with a real sudo
cat > "$S/sudo" <<'EOF'
#!/bin/bash
printf 'sudo %s\n' "$*" >> "$SANDBOX/calls"
[[ "${SUDO_RUNS:-0}" == 1 ]] || exit 0
while [[ "${1:-}" == -* ]]; do case "$1" in -v) exit 0 ;; *) shift ;; esac; done
[[ $# -eq 0 ]] && exit 0
exec "$@"
EOF
# defaults records; with DEFAULTS_STORE set it keeps /Library/Preferences in
# that folder instead, and refuses every other domain.
cat > "$S/defaults" <<'EOF'
#!/bin/bash
printf 'defaults %s\n' "$*" >> "$SANDBOX/calls"
[[ -n "${DEFAULTS_STORE:-}" ]] || exit 0
verb="$1"; dom="${2:-}"
case "$dom" in
  /Library/Preferences/*) ;;
  *) echo "defaults stub: refused $*" >> "$SANDBOX/calls"; exit 2 ;;
esac
mkdir -p "$DEFAULTS_STORE$(dirname "$dom")"
shift 2
exec /usr/bin/defaults "$verb" "$DEFAULTS_STORE$dom" "$@"
EOF
# launchctl: print-disabled lists $SANDBOX/disabled, print succeeds for a
# label in $SANDBOX/loaded, disable adds to the list; everything is recorded.
cat > "$S/launchctl" <<'EOF'
#!/bin/bash
printf 'launchctl %s\n' "$*" >> "$SANDBOX/calls"
case "$1" in
  print-disabled) cat "$SANDBOX/disabled" 2>/dev/null ;;
  print)          grep -qxF "${2##*/}" "$SANDBOX/loaded" 2>/dev/null ;;
  disable)        printf '\t"%s" => disabled\n' "${2##*/}" >> "$SANDBOX/disabled" ;;
esac
exit $?
EOF
chmod +x "$S"/*
ln -s "$BASH_UNDER_TEST" "$S/bash"

# ptyrun.py ANSWERS CMD... — CMD in a pseudo-terminal. Each time its output ends
# in a [y/N] or [Y/n] prompt, the next line of ANSWERS is typed, "n" once they
# run out. Prints what CMD printed, and exits with its status.
cat > "$W/ptyrun.py" <<'EOF'
import os, pty, re, select, sys
answers = sys.argv[1].splitlines()
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[2], sys.argv[2:])
out, pending = b"", b""
while True:
    try:
        ready, _, _ = select.select([fd], [], [], 30)
        if not ready:
            break
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    out += data
    pending += data
    if re.search(rb"\[[yYnN]/[yYnN]\]:?\s*$", pending):
        os.write(fd, ((answers.pop(0) if answers else "n") + "\n").encode())
        pending = b""
_, status = os.waitpid(pid, 0)
sys.stdout.buffer.write(out)
sys.exit(os.waitstatus_to_exitcode(status))
EOF

# ── Running ──────────────────────────────────────────────────────────────────

fresh_home() {
  rm -rf "$H" "$W/store"
  mkdir -p "$H/.Trash"
  : > "$W/calls"; : > "$W/disabled"; : > "$W/loaded"
}
# run [--tty] CMD ARGS... — CMD with a new Mac's environment; stdin is $ANSWERS,
# one answer to a line. Output in $W/out, exit status in RC.
RC=0
run() {
  local tty=0
  [[ "$1" == --tty ]] && { tty=1; shift; }
  local cmd=(env -i HOME="$H" USER="${USER:-$(id -un)}" LOGNAME="${USER:-$(id -un)}" TMPDIR="$W/tmp"
             TERM=dumb PATH="$S:/usr/bin:/bin:/usr/sbin:/sbin" SANDBOX="$W"
             SUDO_RUNS="${SUDO_RUNS:-0}" DEFAULTS_STORE="${DEFAULTS_STORE:-}"
             MRK_LOGIN_MSG="${MRK_LOGIN_MSG:-}" "$S/bash" "$@")
  if (( tty )); then
    python3 "$W/ptyrun.py" "${ANSWERS:-}" "${cmd[@]}" 2>&1 | tr -d '\r' > "$W/out"
    RC=${PIPESTATUS[0]}
  else
    printf '%s' "${ANSWERS:-}" | "${cmd[@]}" > "$W/out" 2>&1
    RC=${PIPESTATUS[1]}
  fi
}
answers() { printf '%s\n' "$@"; }
called() { grep -qF -- "$1" "$W/calls"; }
show() { sed 's/^/      /' "$W/out" | tail -"${1:-12}" >&2; }

# The undo files a Mac with everything applied holds. The defaults one has one
# line of each shape defaults.sh writes, and two whole-domain deletes of the
# shape post-install writes for an import.
plant_undo() {
  mkdir -p "$H/.mrk/plist-backups"
  cat > "$H/.mrk/defaults-rollback.sh" <<'EOF'
#!/usr/bin/env bash
defaults write com.apple.dock autohide -bool false
defaults delete NSGlobalDomain AppleShowAllExtensions >/dev/null 2>&1 || true
killall Dock >/dev/null 2>&1 || true
defaults delete com.googlecode.iterm2 >/dev/null 2>&1 || true
defaults delete io.github.sevmorris.UndoProbe >/dev/null 2>&1 || true
EOF
  printf '#!/usr/bin/env bash\nsudo mv /etc/pam.d/sudo_local.backup.mrk /etc/pam.d/sudo_local\n' > "$H/.mrk/hardening-rollback.sh"
  # shellcheck disable=SC2016  # $(id -u) is for the undo script to expand, as trim-services writes it
  printf '#!/usr/bin/env bash\nlaunchctl enable gui/$(id -u)/com.apple.photoanalysisd\n' > "$H/.mrk/services-rollback.sh"
  chmod +x "$H/.mrk"/*.sh
}
SETTINGS=("defaults write com.apple.dock autohide -bool false"
          "defaults delete NSGlobalDomain AppleShowAllExtensions" "killall Dock")
DOMAINS=("defaults delete com.googlecode.iterm2" "defaults delete io.github.sevmorris.UndoProbe")
ran_all()  { local c; for c in "$@"; do called "$c" || return 1; done; }
ran_none() { local c; for c in "$@"; do called "$c" && return 1; done; return 0; }

# ── W-13 and W-8: nuke-mrk ───────────────────────────────────────────────────

# nuke-mrk asks: continue, sync + snapshot, key archive, then the rollbacks.
# ~/mrk is a plain folder, so it has nothing unpushed to ask about.
nuke_mac() { fresh_home; mkdir -p "$H/mrk"; plant_undo; }

nuke_mac
ANSWERS="$(answers y n n n n n)" run "$R/bin/nuke-mrk"
kept=""
for f in defaults-rollback.sh hardening-rollback.sh services-rollback.sh plist-backups; do
  [[ -e "$H/.mrk/$f" ]] || kept="$kept $f"
done
if [[ $RC == 0 && -z "$kept" && ! -d "$H/mrk" ]] && ran_none "${SETTINGS[@]}" "${DOMAINS[@]}" "launchctl enable" "sudo mv"; then
  pass "nuke-mrk, rollbacks declined: all three undo scripts and plist-backups kept, none run"
else
  fail "nuke-mrk, declined (exit $RC): missing from ~/.mrk:${kept:- nothing}; calls: $(tr '\n' ';' < "$W/calls")"; show
fi

nuke_mac
ANSWERS="$(answers y n n y n n n n)" run "$R/bin/nuke-mrk"
if [[ $RC == 0 ]] && ran_all "${SETTINGS[@]}" "sudo mv" "launchctl enable" && ran_none "${DOMAINS[@]}" \
   && grep -qF "com.googlecode.iterm2" "$W/out" && grep -qF "io.github.sevmorris.UndoProbe" "$W/out"; then
  pass "nuke-mrk, rollbacks yes, apps no: settings, hardening and services undone, the two apps named and kept"
else
  fail "nuke-mrk, yes then no (exit $RC): calls: $(tr '\n' ';' < "$W/calls")"; show 20
fi

nuke_mac
ANSWERS="$(answers y n n y y n n n)" run "$R/bin/nuke-mrk"
if [[ $RC == 0 ]] && ran_all "${SETTINGS[@]}" "${DOMAINS[@]}" "sudo mv" "launchctl enable"; then
  pass "nuke-mrk, rollbacks yes, apps yes: the two apps' preferences deleted as well"
else
  fail "nuke-mrk, yes then yes (exit $RC): calls: $(tr '\n' ';' < "$W/calls")"; show 20
fi

# ── W-13 and W-8: uninstall ──────────────────────────────────────────────────

# uninstall asks: the macOS settings, then the apps, then hardening, then
# services.
fresh_home; plant_undo
ANSWERS="$(answers y n y y)" run --tty "$R/scripts/uninstall"
if [[ $RC == 0 ]] && ran_all "${SETTINGS[@]}" "sudo mv" "launchctl enable" && ran_none "${DOMAINS[@]}" \
   && grep -qF "com.googlecode.iterm2" "$W/out"; then
  pass "uninstall, settings yes, apps no: hardening and services offered and run, the apps named and kept"
else
  fail "uninstall, y n y y (exit $RC): calls: $(tr '\n' ';' < "$W/calls")"; show 20
fi

fresh_home; plant_undo
ANSWERS="$(answers y y n n)" run --tty "$R/scripts/uninstall"
if [[ $RC == 0 ]] && ran_all "${SETTINGS[@]}" "${DOMAINS[@]}" && ran_none "sudo mv" "launchctl enable"; then
  pass "uninstall, settings yes, apps yes: the apps' preferences deleted, hardening and services left"
else
  fail "uninstall, y y n n (exit $RC): calls: $(tr '\n' ';' < "$W/calls")"; show 20
fi

# The two copies of the pattern: lib.sh's, and nuke-mrk's, which sources nothing
lib_pat=$(sed -n "s/^MRK_WHOLE_DOMAIN_UNDO='\(.*\)'$/\1/p" "$REPO_ROOT/scripts/lib.sh")
nuke_pat=$(sed -n "s/^WHOLE_DOMAIN_UNDO='\(.*\)'$/\1/p" "$REPO_ROOT/bin/nuke-mrk")
if [[ -n "$lib_pat" && "$lib_pat" == "$nuke_pat" ]]; then
  pass "lib.sh and nuke-mrk carry the same whole-domain pattern"
else
  fail "the whole-domain pattern differs: lib.sh '$lib_pat', nuke-mrk '$nuke_pat'"
fi

# ── W-3 and W-8: trim-services keeps an existing undo file ───────────────────

fresh_home
mkdir -p "$H/.mrk"
printf '#!/bin/bash\nlaunchctl enable gui/501/com.example.kept\n' > "$H/.mrk/services-rollback.sh"
echo com.apple.photoanalysisd > "$W/loaded"
run "$R/scripts/trim-services"
if [[ $RC == 0 ]] && grep -qxF 'launchctl enable gui/501/com.example.kept' "$H/.mrk/services-rollback.sh" \
   && grep -qF 'com.apple.photoanalysisd' "$H/.mrk/services-rollback.sh"; then
  pass "trim-services keeps an undo file that begins #!/bin/bash, and adds to it"
else
  fail "trim-services (exit $RC) left: $(tr '\n' ';' < "$H/.mrk/services-rollback.sh")"; show
fi

fresh_home
echo com.apple.photoanalysisd > "$W/loaded"
run "$R/scripts/trim-services" --dry-run
if [[ $RC == 0 && ! -e "$H/.mrk" ]] && ! called "launchctl disable"; then
  pass "trim-services --dry-run makes no ~/.mrk and disables nothing"
else
  fail "trim-services --dry-run (exit $RC): ~/.mrk $([[ -e "$H/.mrk" ]] && echo made || echo absent)"; show
fi

# ── W-9: the login-window message's undo ─────────────────────────────────────

# login_case ORIGINAL — setup with MRK_LOGIN_MSG, twice, then the undo. The
# message must come back as ORIGINAL, or be absent when ORIGINAL is empty.
LW="/Library/Preferences/com.apple.loginwindow"
login_case() {
  local want="$1" got lines
  fresh_home
  mkdir -p "$W/store$(dirname "$LW")"
  [[ -n "$want" ]] && /usr/bin/defaults write "$W/store$LW" LoginwindowText -string "$want"
  SUDO_RUNS=1 DEFAULTS_STORE="$W/store" MRK_LOGIN_MSG="mrk says hi" run "$R/scripts/setup" --only defaults
  local rc1=$RC
  SUDO_RUNS=1 DEFAULTS_STORE="$W/store" MRK_LOGIN_MSG="mrk says hi" run "$R/scripts/setup" --only defaults
  local rc2=$RC
  lines=$(grep -c LoginwindowText "$H/.mrk/defaults-rollback.sh")
  SUDO_RUNS=1 DEFAULTS_STORE="$W/store" run "$H/.mrk/defaults-rollback.sh"
  got=$(/usr/bin/defaults read "$W/store$LW" LoginwindowText 2>/dev/null) || got=""
  if [[ $rc1$rc2 == 00 && "$lines" == 1 && "$got" == "$want" ]]; then
    pass "MRK_LOGIN_MSG twice, then the undo: one undo line, and the message back to '${want:-absent}'"
  else
    fail "MRK_LOGIN_MSG twice (exits $rc1 $rc2): $lines undo line(s); after the undo '${got:-absent}', want '${want:-absent}'"
    grep LoginwindowText "$H/.mrk/defaults-rollback.sh" | sed 's/^/      /' >&2
  fi
}
login_case ""
login_case "Welcome back"

(( fails == 0 ))
