#!/usr/bin/env bash
# defaults-watch.sh — prove that defaults-watch names the key a setting change
# writes, says what config/defaults.tsv does about it, and changes nothing.
#
# defaults-watch is new on 2026-09-30. Until then a change made in System
# Settings was the one change nothing in mrk recorded, and finding its key
# meant guessing a domain for `defaults read`.
#
# defaults is a stub first on PATH. Its first `domains` call serves the
# "before" fixtures and its second the "after" ones, so the two snapshots see
# one change of each kind defaults-watch tells apart: a key config/defaults.tsv
# sets, at its value and at another, a key with spaces in it, a key of the
# trackpad's second domain, a path in the home directory, a key the file lacks,
# a nested dictionary, a deleted key, a new domain, a -currentHost key, a key
# for all users, and window frames, dates and the other keys that change on
# their own.
# The real config/defaults.tsv is read. uname says Darwin.
# Nothing reaches the real HOME or any preferences.
# It runs under /bin/bash and under the bash running this file. ci-check runs it.


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

command -v python3 >/dev/null || { fail "python3 not found"; exit 1; }

W=$(mrk_mktemp_d) || exit 1
W=$(cd "$W" && pwd -P)
trap 'rm -rf "$W"' EXIT
S="$W/stubs" FIX="$W/fix" SYS="$W/system-prefs" TMP="$W/tmp"
mkdir -p "$S" "$FIX" "$SYS" "$TMP" "$W/home"
: > "$W/calls"

cat > "$S/defaults" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$W/calls"
host=user
[ "\$1" = -currentHost ] && { host=host; shift; }
case "\$1" in
  domains)
    [ "\$CASE" = broken ] && { echo "defaults: cannot list" >&2; exit 1; }
    if [ \$host = user ]; then
      n=\$(cat "$W/phase" 2>/dev/null || echo 0); n=\$((n + 1)); echo \$n > "$W/phase"
      # The all-users files change with the snapshot, as cfprefsd writes them.
      rm -f "$SYS"/*.plist; cp "$FIX/\$CASE/phase\$n/system/"*.plist "$SYS/" 2>/dev/null
    fi
    ls "$FIX/\$CASE/phase\$(cat "$W/phase")/\$host" | sed 's/\.plist\$//' | grep -vx NSGlobalDomain | paste -sd, - | sed 's/,/, /g' ;;
  export)
    src="$FIX/\$CASE/phase\$(cat "$W/phase")/\$host/\$2.plist"
    [ -f "\$src" ] && cp "\$src" "\$3" ;;
  *) exit 1 ;;
esac
EOF
printf '#!/bin/sh\necho Darwin\n' > "$S/uname"
chmod +x "$S/defaults" "$S/uname"
ln -s "$BASH_UNDER_TEST" "$S/bash"

# Fixtures: CASE/phaseN/{user,host,system}/DOMAIN.plist
python3 - "$FIX" "$W/home" <<'PY'
import datetime, os, plistlib, sys
root, home = sys.argv[1:3]
def put(case, phase, kind, domain, d):
    p = os.path.join(root, case, f"phase{phase}", kind)
    os.makedirs(p, exist_ok=True)
    with open(os.path.join(p, domain + ".plist"), "wb") as f:
        plistlib.dump(d, f)
t0, t1 = datetime.datetime(2026, 9, 30, 8), datetime.datetime(2026, 9, 30, 9)
for phase, on in ((1, False), (2, True)):
    put("changes", phase, "user", "NSGlobalDomain", {
        "AppleShowScrollBars": "Always" if on else "Automatic",   # the file sets Always
        "AppleShowAllExtensions": not on,                         # the file sets true
    })
    # The file sets ~/Desktop, which is home + /Desktop.
    put("changes", phase, "user", "com.apple.screencapture", {"location": f"{home}/{'Desktop' if on else 'Pictures'}"})
    put("changes", phase, "user", "com.apple.Terminal", {"Default Window Settings": "Basic" if on else "Pro"})
    put("changes", phase, "user", "com.apple.driver.AppleBluetoothMultitouch.trackpad", {"Clicking": not on})
    put("changes", phase, "user", "com.example.watch", {"Answer": 42 if on else 41, "Folder": f"{home}/Work" if on else "",
                                                        **({} if on else {"Gone": "soon"})})
    put("changes", phase, "user", "com.apple.symbolichotkeys", {"AppleSymbolicHotKeys": {"64": {"enabled": not on, "value": {"type": "standard"}}}})
    put("changes", phase, "user", "com.apple.systempreferences", {"NSWindow Frame Main Window": f"{phase} 0 800 600", "LastSeen": t1 if on else t0})
    # versionLastLaunched and SUUpdateGroupIdentifier are in lib.sh's list of
    # keys that change on their own, which snapshot-prefs reads too; the toolbar
    # layout is defaults-watch's own addition to it.
    put("changes", phase, "user", "com.example.noisy", {"versionLastLaunched": f"4.{phase}", "SUUpdateGroupIdentifier": phase,
                                                        "NSToolbar Configuration Main": f"layout {phase}"})
    if on:
        put("changes", phase, "user", "com.example.fresh", {"Fresh": True})
    put("changes", phase, "host", "com.apple.screensaver", {"idleTime": 600 if on else 0})
    put("changes", phase, "system", "com.apple.alf", {"globalstate": 1 if on else 0})
    put("quiet", phase, "user", "NSGlobalDomain", {"AppleShowScrollBars": "Always"})
    put("quiet", phase, "host", "com.apple.screensaver", {"idleTime": 0})
PY

ENV=(env -i HOME="$W/home" PATH="$S:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$TMP" TERM=dumb
     DEFAULTS_WATCH_SYSTEM_DIR="$SYS")
DW="$REPO_ROOT/scripts/defaults-watch"
RC=0
watch() { # CASE ARGS... — output in $W/out, exit status in RC
  local case=$1; shift
  rm -f "$W/phase"
  "${ENV[@]}" CASE="$case" "$DW" "$@" < /dev/null > "$W/out" 2> "$W/err"
  RC=$?
}
show() { sed 's/^/    /' "$W/out" "$W/err"; }
has() { grep -qF -- "$1" "$W/out"; }
line_of() { grep -n -- "$1" "$REPO_ROOT/config/defaults.tsv" | head -1 | cut -d: -f1; }

# ── 1. One change of each kind ───────────────────────────────────────────────

watch changes --seconds 0
scroll=$(line_of $'^NSGlobalDomain\tAppleShowScrollBars\t')
ext=$(line_of $'^NSGlobalDomain\tAppleShowAllExtensions\t')
term=$(line_of $'^com.apple.Terminal\tDefault Window Settings\t')
click=$(line_of $'^com.apple.driver.AppleBluetoothMultitouch.trackpad\tClicking\t')
shots=$(line_of $'^com.apple.screencapture\tlocation\t')

if (( RC == 0 )) && has "NSGlobalDomain  AppleShowScrollBars" && has '"Automatic" → "Always"' \
   && has "config/defaults.tsv line $scroll sets \"Always\": this is the value mrk sets."; then
  pass "a key config/defaults.tsv sets, changed to its value: said to be the value mrk sets"
else
  fail "a key at config/defaults.tsv's value (line $scroll):"; show
fi
if has "config/defaults.tsv line $ext sets bool true, so make defaults would put that back." \
   && has $'      NSGlobalDomain\tAppleShowAllExtensions\tbool\tfalse\talways\tGeneral UI / UX' \
   && has "      mrk-defaults --skip NSGlobalDomain AppleShowAllExtensions"; then
  pass "a key config/defaults.tsv sets, changed to another value: the line to change it to, its section kept, or the skip"
else
  fail "a key at another value than config/defaults.tsv's (line $ext):"; show
fi
if has "config/defaults.tsv line $term sets string Pro" \
   && has $'      com.apple.Terminal\tDefault Window Settings\tstring\tBasic\talways\tTerminal.app' \
   && has "      mrk-defaults --skip com.apple.Terminal 'Default Window Settings'"; then
  pass "a key with spaces in it: found in config/defaults.tsv, and its line given with the spaces as they are"
else
  fail "a key with spaces (line $term):"; show
fi
if has "com.apple.driver.AppleBluetoothMultitouch.trackpad  Clicking" && has "config/defaults.tsv line $click sets false: this is the value mrk sets."; then
  pass "a key of the trackpad's second domain: found on its own line"
else
  fail "the trackpad's second domain (line $click):"; show
fi
if has "com.apple.screencapture  location" && has "config/defaults.tsv line $shots sets \"$W/home/Desktop\": this is the value mrk sets."; then
  pass "a path the file writes as ~/: compared as a path in the home directory"
else
  fail "a ~/ path (line $shots):"; show
fi
if has "com.example.watch  Answer" && has "41 → 42" && has $'      com.example.watch\tAnswer\tint\t42\talways\tApplications' \
   && has "and add its description to docs/defaults/descriptions.tsv, which check-defaults-desc requires."; then
  pass "a key config/defaults.tsv lacks: the line to add, and the description it will need"
else
  fail "a key config/defaults.tsv lacks:"; show
fi
if has $'      com.example.watch\tFolder\tstring\t~/Work\talways\tApplications'; then
  pass "a new path in the home directory: its line has ~/, so it suits another Mac"
else
  fail "a new path in the home directory:"; show
fi
if has "com.example.fresh  Fresh" && has "(absent) → true" && has $'      com.example.fresh\tFresh\tbool\ttrue\talways\tApplications'; then
  pass "a domain that did not exist before: its key reported as added"
else
  fail "a new domain:"; show
fi
if has "com.example.watch  Gone" && has '"soon" → (absent)' && has "defaults delete com.example.watch Gone"; then
  pass "a deleted key: the defaults delete that would remove it"
else
  fail "a deleted key:"; show
fi
if has "AppleSymbolicHotKeys/64/enabled: true → false" && has "config/defaults.tsv holds bool, int, float and string only"; then
  pass "a change inside a dictionary: the path to it, and why config/defaults.tsv cannot hold it"
else
  fail "a nested change:"; show
fi
if has "com.apple.screensaver  idleTime  (this Mac only: -currentHost)" && has "defaults -currentHost write com.apple.screensaver idleTime -int 600"; then
  pass "a -currentHost key: marked, with the defaults -currentHost line"
else
  fail "a -currentHost key:"; show
fi
if has "com.apple.alf  globalstate  (all users: $SYS)" && has "sudo defaults write $SYS/com.apple.alf globalstate -int 1"; then
  pass "a key for all users: marked, with the sudo defaults line"
else
  fail "a key for all users:"; show
fi
noise=$(sed -n '/^Also changed, and probably not the setting:/,$p' "$W/out")
if grep -q 'com.apple.systempreferences  NSWindow Frame Main Window' <<<"$noise" && grep -q 'com.apple.systempreferences  LastSeen' <<<"$noise" \
   && ! grep -q '^com.apple.systempreferences' "$W/out"; then
  pass "a window frame and a date: listed apart, as probably not the setting"
else
  fail "the noise:"; show
fi

# The list of such keys is lib.sh's, the one snapshot-prefs leaves out of a
# commit, and the toolbar layout besides. Until 2026-10-01 defaults-watch kept
# a list of its own, which lacked versionLastLaunched and
# SUUpdateGroupIdentifier and showed each as a setting (audit 20, X-9).
if grep -q 'com.example.noisy  versionLastLaunched' <<<"$noise" && grep -q 'com.example.noisy  SUUpdateGroupIdentifier' <<<"$noise" \
   && grep -q 'com.example.noisy  NSToolbar Configuration Main' <<<"$noise" && ! grep -q '^com.example.noisy' "$W/out"; then
  pass "keys from lib.sh's list, and a toolbar layout: listed apart too"
else
  fail "the shared list of keys that change on their own:"; show
fi

# A key that config/defaults-skip.tsv skips: make defaults leaves it, so
# there is nothing to put back and nothing to change. On a copy of the
# repository, whose skip list names it.
R="$W/repo"; mkdir -p "$R/scripts" "$R/config"
cp "$REPO_ROOT/scripts/defaults-watch" "$REPO_ROOT/scripts/lib.sh" "$R/scripts/"
cp "$REPO_ROOT/config/defaults.tsv" "$R/config/"
{ cat "$REPO_ROOT/config/defaults-skip.tsv"; printf 'NSGlobalDomain\tAppleShowAllExtensions\n'; } > "$R/config/defaults-skip.tsv"
DW_REAL=$DW DW="$R/scripts/defaults-watch"
watch changes --seconds 0
DW=$DW_REAL
if (( RC == 0 )) && has "config/defaults.tsv line $ext sets bool true, but config/defaults-skip.tsv skips the key," \
   && has "so make defaults leaves it as it is." && ! has $'      NSGlobalDomain\tAppleShowAllExtensions\tbool\tfalse' \
   && ! has "mrk-defaults --skip NSGlobalDomain AppleShowAllExtensions"; then
  pass "a skipped key at another value: make defaults leaves it, so no line to change and no skip to give"
else
  fail "a skipped key (line $ext):"; show
fi

# ── 2. Nothing changed ───────────────────────────────────────────────────────

watch quiet --seconds 0
if (( RC == 0 )) && has "No preference changed."; then
  pass "nothing changed: says so, and what is not stored as a preference"
else
  fail "nothing changed: rc $RC"; show
fi

# ── 3. defaults failing: an error, not "nothing changed" ──────────────────────

watch broken --seconds 0
if (( RC == 1 )) && grep -q "defaults domains failed" "$W/err" && ! has "No preference changed"; then
  pass "defaults domains failing: exit 1 and says so, never \"no preference changed\""
else
  fail "defaults domains failing: rc $RC"; show
fi

# ── 4. Refusals ──────────────────────────────────────────────────────────────

n_calls=$(wc -l < "$W/calls")
watch quiet
r1=$RC; grep -q 'No terminal to wait at for Return' "$W/err"; g1=$?
watch quiet --seconds soon
r2=$RC
watch quiet --bogus
r3=$RC
if (( r1 == 2 && g1 == 0 && r2 == 2 && r3 == 2 )) && [[ "$(wc -l < "$W/calls")" == "$n_calls" ]]; then
  pass "no terminal and no --seconds, a bad --seconds, an unknown argument: exit 2, before any snapshot"
else
  fail "refusals: rc $r1 $r2 $r3, or defaults was called"; show
fi

# ── 5. Read only, and nothing left behind ─────────────────────────────────────

if grep -vE '^(-currentHost )?(domains|export [^ ]+ [^ ]+)$' "$W/calls" | grep -q .; then
  fail "defaults was asked for more than domains and export:"; sed 's/^/    /' "$W/calls"
else
  pass "defaults was asked for domains and export, nothing else"
fi
if [[ -z "$(ls -A "$TMP")" ]]; then
  pass "the scratch directory is removed"
else
  fail "left in TMPDIR: $(find "$TMP" -mindepth 1 -maxdepth 1 | tr '\n' ' ')"
fi

if (( fails )); then
  err "$fails defaults-watch check(s) failed"
  exit 1
fi
ok "defaults-watch checks passed"
