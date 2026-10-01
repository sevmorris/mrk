#!/usr/bin/env bash
# update-verdict.sh — prove that make update ends by saying what topgrade's
# exit status means: which steps failed and that the others ran, or that the
# run stopped short, and never the first when the second is true.
#
# Until 2026-09-30 a run in which one cask failed to download ended, after
# every other step and clean-up command had completed, on
# "make: *** [update] Error 1" and nothing else.
#
# topgrade is a stub first on PATH that prints the transcript TRANSCRIPT names
# and exits RC; nothing is upgraded. The real Makefile's update recipe runs it,
# under a throwaway HOME: through tee, as it does with no terminal, and on
# macOS inside a pseudo-terminal too, where it records the run with script(1).
# The transcripts are in the forms real runs of topgrade 17.12.2 were recorded
# in, with no terminal and through script. Three more hold a byte that is not
# UTF-8, and run in a UTF-8 locale, where macOS's sed stops on one.
# A run interrupted with no terminal must leave no recording, and the verdict
# must be on stderr alone when bin/lib/common.sh is sourced too.
# The update shell function is run in a zsh that reads no startup file.
# The last cases run one clean-up command of assets/topgrade.toml, pip cache
# purge, against a stub pip3: an empty cache must be said to be normal, and
# nothing else must.
# ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

command -v python3 >/dev/null || { fail "python3 not found"; exit 1; }

W=$(mrk_mktemp_d) || exit 1
W=$(cd "$W" && pwd -P)
trap 'rm -rf "$W"' EXIT
S="$W/stubs" T="$W/transcripts" TMP="$W/tmp"
mkdir -p "$S" "$T" "$TMP" "$W/home" "$W/nobrew"
: > "$W/brew-calls"

cat > "$S/topgrade" <<'EOF'
#!/bin/sh
cat "$TRANSCRIPT"
[ $# -gt 0 ] && echo "topgrade args: $*"
# HOLD: a run still under way, for the cases that interrupt it.
[ -n "${HOLD:-}" ] && { echo "holding"; sleep 30; }
exit "$RC"
EOF
cat > "$W/nobrew/brew" <<EOF
#!/bin/sh
echo "\$1" >> "$W/brew-calls"
EOF
chmod +x "$S/topgrade" "$W/nobrew/brew"

# The transcripts: a run's last step, topgrade's Summary, and the clean-up
# commands that follow it, in each of the three ways topgrade 17 draws a step's
# header, taken from recordings of real runs:
#   plain   no terminal: "―― 20:04:24 - Summary ――", in U+2015
#   wide    a terminal, as script(1) records it: the window title on a line of
#           its own, then "── 20:04:24 - Summary ────", in U+2500, CRLF
#   narrow  a terminal that reports no width: the title and a U+2015 header on
#           one line, CRLF
# Until 2026-10-01 these were all written here in a form made up from a pasted
# terminal, and the verdict read no other: with no terminal it said topgrade
# had stopped before its summary.
header() { # FORM TITLE
  case "$1" in
    plain)  printf '―― 20:04:24 - %s ――\n' "$2" ;;
    wide)   printf '\033]0;Topgrade - %s\a\r\n── 20:04:24 - %s ──────────────────────────\r\n' "$2" "$2" ;;
    narrow) printf '\033]0;Topgrade - %s\a―― 20:04:24 - %s ――\r\n' "$2" "$2" ;;
  esac
}
text() { # FORM LINE...
  local form=$1 eol=$'\n'
  shift
  [[ "$form" == plain ]] || eol=$'\r\n'
  printf "%s$eol" "$@"
}
summary() { # FORM STATUS-OF-TLDR STATUS-OF-CASK
  header "$1" 'npm global update'; text "$1" 'changed 12 packages in 3s'
  header "$1" Summary
  text "$1" 'oh-my-zsh: OK' 'pipx: OK' "TLDR: $2" 'yarn: OK' 'gcloud: OK' 'GitHub CLI Extensions: OK' \
    'Git Repositories: OK' 'Brew (ARM): OK' "Brew Cask (ARM): $3" 'npm global update: OK'
  header "$1" 'pipx upgrade-all'; text "$1" 'No packages upgraded'
  header "$1" 'pip cache purge'; text "$1" 'ERROR: No matching packages' '(the pip cache was already empty; this is normal)'
  header "$1" 'Homebrew cache scrub'; header "$1" 'npm cache verify'; header "$1" 'pyenv rehash'
  header "$1" 'go clean test cache'; header "$1" 'Refresh zsh completions'
}
summary plain OK FAILED > "$T/one-failed"
summary wide OK $'\033[31mFAILED\033[0m' > "$T/one-failed-wide"
summary narrow OK FAILED > "$T/one-failed-narrow"
summary plain FAILED FAILED > "$T/two-failed"
summary plain OK OK > "$T/all-ok"
printf '%s\n' 'Error: Configuration error' 'unknown field nope, expected one of ...' > "$T/no-summary"
# The same runs with one byte that is not UTF-8 above the Summary: a file name
# in Latin-1, as a package manager can print one.
{ printf 'Downloading caf\xe9.dmg\n'; cat "$T/one-failed"; } > "$T/one-failed-latin1"
{ printf 'Downloading caf\xe9.dmg\r\n'; cat "$T/one-failed-wide"; } > "$T/one-failed-wide-latin1"
{ printf 'Downloading caf\xe9.dmg\n'; cat "$T/all-ok"; } > "$T/all-ok-latin1"

ENV=(env -i HOME="$W/home" PATH="$S:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$TMP" TERM=dumb)
RC_SEEN=0
# update TRANSCRIPT RC [LOCALE] — make update with no terminal, in the C locale
# env -i leaves, or in LOCALE. Output in $W/out.
update() {
  "${ENV[@]}" ${3:+LC_ALL="$3"} TRANSCRIPT="$T/$1" RC="$2" make --no-print-directory -C "$REPO_ROOT" update < /dev/null > "$W/out" 2>&1
  RC_SEEN=$?
}
has() { grep -qF -- "$1" "$W/out"; }
show() { sed 's/^/    /' "$W/out"; }
tidy() { [[ -z "$(find "$TMP" -mindepth 1 -maxdepth 1)" ]]; }

# ── 1. One step failed ───────────────────────────────────────────────────────

update one-failed 1
verdict=$(grep -n 'Update finished' "$W/out" | cut -d: -f1)
last_step=$(grep -n 'Refresh zsh completions' "$W/out" | cut -d: -f1)
make_err=$(grep -n '\*\*\* \[update\] Error' "$W/out" | head -1 | cut -d: -f1)
if (( RC_SEEN != 0 )) && has "Update finished: every step ran. 1 of 10 failed: Brew Cask (ARM)." \
   && has "Nothing was interrupted: the other 9 succeeded, and the 7 clean-up commands after them ran." \
   && has 'which make reports next as "Error 1".' \
   && (( last_step < verdict && verdict < make_err )) && tidy; then
  pass "one failed step: named, the rest said to have run, between topgrade's last line and make's error"
else
  fail "one failed step: exit $RC_SEEN, lines $last_step/$verdict/$make_err"; show
fi

# ── 1b. The other two ways topgrade draws its headers ───────────────────────

for form in wide narrow; do
  update "one-failed-$form" 1
  if has "Update finished: every step ran. 1 of 10 failed: Brew Cask (ARM)." \
     && has "the other 9 succeeded, and the 7 clean-up commands after them ran."; then
    pass "the $form header form is read the same"
  else
    fail "the $form header form:"; show
  fi
done

# ── 1c. A byte that is not UTF-8 in the recording, in a UTF-8 locale ────────

# Every case above runs in the C locale, which env -i leaves, and a shell at a
# terminal runs in a UTF-8 one. There macOS's sed stops at the first byte that
# is not UTF-8, and until 2026-10-01 the verdict then never saw the Summary: it
# said topgrade had stopped before it, or with exit 0 said nothing (audit 20,
# X-2). Where sed does not stop on such a byte, the cases still run, and cannot
# fail for this reason; the note says so.
UTF8=en_US.UTF-8
if printf 'caf\xe9\n' | "${ENV[@]}" LC_ALL="$UTF8" sed 's/x/y/' >/dev/null 2>&1; then
  logskip "a byte that is not UTF-8" "this sed reads it in $UTF8, so the next three checks cannot fail here"
fi
for t in one-failed-latin1 one-failed-wide-latin1; do
  update "$t" 1 "$UTF8"
  if has "Update finished: every step ran. 1 of 10 failed: Brew Cask (ARM)." && ! has "stopped before its summary"; then
    pass "a byte that is not UTF-8 above the Summary ($t): the Summary is still read"
  else
    fail "a byte that is not UTF-8 above the Summary ($t):"; show
  fi
done
update all-ok-latin1 0 "$UTF8"
if (( RC_SEEN == 0 )) && has "Update finished: all 10 steps succeeded."; then
  pass "the same with nothing failed: still says all 10 succeeded"
else
  fail "a byte that is not UTF-8, nothing failed: exit $RC_SEEN"; show
fi

# ── 2. Two failed ────────────────────────────────────────────────────────────

update two-failed 1
if has "every step ran. 2 of 10 failed: TLDR, Brew Cask (ARM)." && has "the other 8 succeeded"; then
  pass "two failed steps: both named, in topgrade's order"
else
  fail "two failed steps:"; show
fi

# ── 3. Nothing failed ────────────────────────────────────────────────────────

update all-ok 0
if (( RC_SEEN == 0 )) && has "Update finished: all 10 steps succeeded." && ! has "failed"; then
  pass "nothing failed: says all 10 succeeded, and exits 0"
else
  fail "nothing failed: exit $RC_SEEN"; show
fi

# ── 4. topgrade stopped before its summary: never "every step ran" ───────────

update no-summary 1
if (( RC_SEEN != 0 )) && has "topgrade stopped before its summary (exit 1): not every step ran." && ! has "Update finished"; then
  pass "no summary: says the run stopped short, and does not say every step ran"
else
  fail "no summary: exit $RC_SEEN"; show
fi

# ── 5. Every step OK, and still a failure status ─────────────────────────────

update all-ok 3
if (( RC_SEEN != 0 )) && has "topgrade exited 3, though its summary shows no failed step" && ! has "all 10 steps succeeded"; then
  pass "a failure after the summary: reported as that, not as success"
else
  fail "a failure after the summary: exit $RC_SEEN"; show
fi

# ── 6. No topgrade: brew update and upgrade, and no verdict ──────────────────

env -i HOME="$W/home" PATH="$W/nobrew:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$TMP" TERM=dumb \
  make --no-print-directory -C "$REPO_ROOT" update < /dev/null > "$W/out" 2>&1; rc=$?
if (( rc == 0 )) && [[ "$(tr '\n' ' ' < "$W/brew-calls")" == "update upgrade " ]] && ! has "Update finished"; then
  pass "without topgrade: brew update, then brew upgrade"
else
  fail "without topgrade: exit $rc, brew calls: $(tr '\n' ' ' < "$W/brew-calls")"; show
fi

# ── 7. At a terminal: recorded through script(1), the status kept ────────────

if [[ "$(uname -s)" == Darwin ]]; then
  cat > "$W/at-a-terminal.py" <<'PY'
import os, pty, sys
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[1], sys.argv[1:])
out = b""
while True:
    try:
        chunk = os.read(fd, 4096)
    except OSError:
        break
    if not chunk:
        break
    out += chunk
_, status = os.waitpid(pid, 0)
sys.stdout.write(out.decode("utf-8", "replace").replace("\r", ""))
sys.exit(os.WEXITSTATUS(status) if os.WIFEXITED(status) else 1)
PY
  "${ENV[@]}" TRANSCRIPT="$T/one-failed-wide" RC=1 python3 "$W/at-a-terminal.py" \
    make --no-print-directory -C "$REPO_ROOT" update > "$W/out" 2>&1; rc=$?
  if (( rc != 0 )) && has "Update finished: every step ran. 1 of 10 failed: Brew Cask (ARM)." && tidy; then
    pass "at a terminal: the run is recorded through script, read, and its recording removed"
  else
    fail "at a terminal: exit $rc, TMPDIR: $(find "$TMP" -mindepth 1 | tr '\n' ' ')"; show
  fi
fi

# ── 7b. Interrupted away from a terminal: the recording is removed ───────────

# The command in a session of its own, with no terminal. When the stub says
# "holding", the whole process group gets the signal, as Ctrl-C or a closed
# window sends it. Until 2026-10-01 only run_topgrade's last line removed the
# recording, and such a run left it in TMPDIR (audit 20, X-4).
cat > "$W/interrupt.py" <<'PY'
import os, signal, subprocess, sys
sig, argv = getattr(signal, "SIG" + sys.argv[1]), sys.argv[2:]
p = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                     stderr=subprocess.STDOUT, start_new_session=True)
out = b""
for line in iter(p.stdout.readline, b""):
    out += line
    if b"holding" in line:
        os.killpg(p.pid, sig)
        break
out += p.stdout.read()
rc = p.wait()
sys.stdout.write(out.decode("utf-8", "replace"))
print("ended: %d" % rc)
PY
# await_tidy — the trap runs as the shell ends, which can be a moment after
# the command the driver waits for has gone
await_tidy() {
  local i
  for (( i = 0; i < 30; i++ )); do
    tidy && return 0
    sleep 0.1
  done
  return 1
}
for sig in INT TERM HUP; do
  "${ENV[@]}" HOLD=1 TRANSCRIPT="$T/one-failed" RC=1 python3 "$W/interrupt.py" "$sig" \
    make --no-print-directory -C "$REPO_ROOT" update > "$W/out" 2>&1
  if has "holding" && ! has "ended: 0" && ! has "Update finished" && await_tidy; then
    pass "SIG$sig with no terminal: the run ends, and its recording is removed"
  else
    fail "SIG$sig with no terminal: left in TMPDIR: $(find "$TMP" -mindepth 1 | tr '\n' ' ')"; show
    rm -f "$TMP"/*
  fi
done

# The caller's own traps: one set before run_topgrade still runs when the
# signal comes during it, and after a run that ends by itself the traps are as
# they were before it. Compared before and after, not with a fixed list: a
# signal ignored on entry, as INT is in a job started with &, is one bash 5
# lists and bash 3.2 does not.
# Under /bin/bash, which runs the Makefile's recipe, and the bash running this.
BASHES=(/bin/bash)
[[ "$BASH" -ef /bin/bash ]] || BASHES+=("$BASH")
for b in "${BASHES[@]}"; do
  # shellcheck disable=SC2016  # expanded by the bash under test
  "${ENV[@]}" HOLD=1 TRANSCRIPT="$T/all-ok" RC=0 python3 "$W/interrupt.py" TERM \
    "$b" -c '. "$1"; trap "echo the caller trap ran; exit 7" TERM; run_topgrade; echo not reached' bash "$REPO_ROOT/scripts/lib.sh" \
    > "$W/out" 2>&1
  # shellcheck disable=SC2016
  after=$("${ENV[@]}" TRANSCRIPT="$T/all-ok" RC=0 "$b" -c \
    '. "$1"; trap "echo mine" TERM; before=$(trap -p INT TERM HUP); run_topgrade >/dev/null 2>&1
     [[ "$(trap -p INT TERM HUP)" == "$before" ]] && trap -p TERM' bash "$REPO_ROOT/scripts/lib.sh" < /dev/null 2>&1)
  if has "the caller trap ran" && has "ended: 7" && ! has "not reached" && await_tidy \
     && [[ "$after" == "trap -- 'echo mine' SIGTERM" ]]; then
    # shellcheck disable=SC2016
    pass "the caller's trap ($("$b" -c 'echo "${BASH_VERSION%%(*}"')): it runs on a signal during the run, and the traps are as they were after one"
  else
    fail "the caller's trap under $b: after a run the traps had changed, or TERM's was: '$after'"; show
    rm -f "$TMP"/*
  fi
done

# ── 7c. From update-full, which sources both libraries: one stream ───────────

# bin/lib/common.sh's info is a line on stdout. Until 2026-10-01 the verdict
# printed through warn and info, so in update-full its first line went to
# stderr and its next two to stdout (audit 20, X-8).
# shellcheck disable=SC2016  # expanded by the inner bash
"$BASH" -c '. "$1/scripts/lib.sh"; . "$1/bin/lib/common.sh"; topgrade_verdict 1 "$2"' bash "$REPO_ROOT" "$T/one-failed" \
  > "$W/verdict-out" 2> "$W/out"
# shellcheck disable=SC2016
"$BASH" -c '. "$1/scripts/lib.sh"; topgrade_verdict 1 "$2"' bash "$REPO_ROOT" "$T/one-failed" > /dev/null 2> "$W/verdict-lib"
if [[ ! -s "$W/verdict-out" ]] && [[ "$(wc -l < "$W/out" | tr -d ' ')" == 3 ]] && cmp -s "$W/out" "$W/verdict-lib" \
   && has "  ⚠ Update finished: every step ran. 1 of 10 failed: Brew Cask (ARM)." \
   && has "    Nothing was interrupted: the other 9 succeeded" && has "    The exit status is 1 for the failed step alone."; then
  pass "with common.sh sourced too: the same three lines, all on stderr, none on stdout"
else
  fail "with common.sh sourced too: stdout holds: $(tr '\n' '|' < "$W/verdict-out")"; show
fi

# ── 8. The update shell function ─────────────────────────────────────────────

if command -v zsh >/dev/null 2>&1; then
  # shellcheck disable=SC2016  # expanded by the zsh, not here
  "${ENV[@]}" MRK_ROOT="$REPO_ROOT" TRANSCRIPT="$T/one-failed" RC=1 \
    zsh -f -i -c 'source "$1" 2>/dev/null; update --only brew; echo "update returned $?"' zsh "$REPO_ROOT/dotfiles/.aliases" \
    < /dev/null > "$W/out" 2>&1
  if has "topgrade args: --only brew" && has "every step ran. 1 of 10 failed: Brew Cask (ARM)." \
     && has "The exit status is 1 for the failed step alone." && ! has "make reports" && has "update returned 1"; then
    pass "the update function: its arguments reach topgrade, the verdict follows, and no word of make"
  else
    fail "the update function:"; show
  fi
fi

# ── 9. The pip cache purge step: an empty cache is said to be normal ─────────

# The step is taken from assets/topgrade.toml as written and run as topgrade
# runs a custom command, through a shell's -c. It starts `bash -lc`, a login
# shell, whose PATH puts /usr/bin, and the pip3 Xcode ships there, ahead of
# anything handed to it; the stub pip3 gets in front through the ~/.bash_profile
# a login shell reads, in a throwaway HOME. PIP_CASE picks what pip does:
#   old-empty  pip 21: "ERROR: No matching packages", exit 1
#   new-empty  pip 23 and later: a WARNING, "Files removed: 0", exit 0
#   purged     files removed, exit 0
#   broken     a real failure, exit 2
PH="$W/pip-home"
mkdir -p "$PH/stubs"
cat > "$PH/stubs/pip3" <<'EOF'
#!/bin/sh
[ "$1 $2" = "cache purge" ] || { echo "pip3 stub: unexpected: $*" >&2; exit 9; }
case "$PIP_CASE" in
  old-empty) echo "ERROR: No matching packages" >&2; exit 1 ;;
  new-empty) echo "WARNING: No matching packages" >&2; echo "Files removed: 0 (0 bytes)"; echo "Directories removed: 0"; exit 0 ;;
  purged)    echo "Files removed: 14 (2.1 MB)"; exit 0 ;;
  broken)    echo "ERROR: Exception:" >&2; echo "PermissionError: [Errno 13] Permission denied" >&2; exit 2 ;;
esac
EOF
chmod +x "$PH/stubs/pip3"
# shellcheck disable=SC2016  # $PATH is for the login shell to expand
printf 'export PATH="%s:$PATH"\n' "$PH/stubs" > "$PH/.bash_profile"
pip_step=$(grep -F '"pip cache purge" = ' "$REPO_ROOT/assets/topgrade.toml") || pip_step=""
pip_step=${pip_step#*= \"}
pip_step=$(printf '%s' "${pip_step%\"}" | sed 's/\\"/"/g')
NOTE="(the pip cache was already empty; this is normal)"
pip_run() { # PIP_CASE — output in $W/out, exit status in RC_SEEN
  env -i HOME="$PH" PATH=/usr/bin:/bin TERM=dumb PIP_CASE="$1" /bin/sh -c "$pip_step" < /dev/null > "$W/out" 2>&1
  RC_SEEN=$?
}

if [[ -z "$pip_step" ]]; then
  fail "\"pip cache purge\" is missing from assets/topgrade.toml"
else
  pip_run old-empty
  if (( RC_SEEN == 0 )) && [[ "$(cat "$W/out")" == "ERROR: No matching packages"$'\n'"$NOTE" ]]; then
    pass "pip 21 on an empty cache: pip's own line, then the note that this is normal"
  else
    fail "pip 21 on an empty cache: exit $RC_SEEN"; show
  fi
  pip_run new-empty
  if (( RC_SEEN == 0 )) && has "WARNING: No matching packages" && has "Files removed: 0 (0 bytes)" && [[ "$(tail -1 "$W/out")" == "$NOTE" ]]; then
    pass "a later pip on an empty cache: its warning and its counts, then the same note"
  else
    fail "a later pip on an empty cache: exit $RC_SEEN"; show
  fi
  pip_run purged
  if (( RC_SEEN == 0 )) && [[ "$(cat "$W/out")" == "Files removed: 14 (2.1 MB)" ]]; then
    pass "a cache with files in it: pip's output and nothing added"
  else
    fail "a cache with files in it: exit $RC_SEEN"; show
  fi
  # A real failure keeps pip's output, is never called normal, and is said to
  # have failed. The step still exits 0, as it did before the note existed.
  pip_run broken
  if (( RC_SEEN == 0 )) && has "PermissionError: [Errno 13] Permission denied" && ! has "this is normal" \
     && has "(pip cache purge failed, exit 2)"; then
    pass "a real pip failure: its output kept, not called normal, and said to have failed"
  else
    fail "a real pip failure: exit $RC_SEEN"; show
  fi
fi

if (( fails )); then
  err "$fails update verdict check(s) failed"
  exit 1
fi
ok "update verdict checks passed"
