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
# in, with no terminal and through script.
# The update shell function is run in a zsh that reads no startup file.
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
  header "$1" 'pip cache purge'; text "$1" 'ERROR: No matching packages'
  header "$1" 'Homebrew cache scrub'; header "$1" 'npm cache verify'; header "$1" 'pyenv rehash'
  header "$1" 'go clean test cache'; header "$1" 'Refresh zsh completions'
}
summary plain OK FAILED > "$T/one-failed"
summary wide OK $'\033[31mFAILED\033[0m' > "$T/one-failed-wide"
summary narrow OK FAILED > "$T/one-failed-narrow"
summary plain FAILED FAILED > "$T/two-failed"
summary plain OK OK > "$T/all-ok"
printf '%s\n' 'Error: Configuration error' 'unknown field nope, expected one of ...' > "$T/no-summary"

ENV=(env -i HOME="$W/home" PATH="$S:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$TMP" TERM=dumb)
RC_SEEN=0
# update TRANSCRIPT RC — make update with no terminal. Output in $W/out.
update() {
  "${ENV[@]}" TRANSCRIPT="$T/$1" RC="$2" make --no-print-directory -C "$REPO_ROOT" update < /dev/null > "$W/out" 2>&1
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

if (( fails )); then
  err "$fails update verdict check(s) failed"
  exit 1
fi
ok "update verdict checks passed"
