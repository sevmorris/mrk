#!/usr/bin/env bash
# update-full.sh — prove that update-full runs its eight steps in order, with
# the two that changed on 2026-09-30 as they are documented: step 1 pulls with
# PULL_BUILD=0, and step 4 runs topgrade through run_topgrade, so the run says
# which of topgrade's steps failed and then goes on.
#
# Until 2026-10-01 no test ran update-full. tests/macos-updates.sh read it for
# one line, and a copy that ran plain topgrade again, or pulled without
# PULL_BUILD=0, passed every test in the repository (audit 20, X-11).
#
# update-full quits every running application and can restart the Mac, so
# nothing here is real. Every command it reaches is a stub first on PATH that
# records its call: make, osascript, softwareupdate, sw_vers, topgrade,
# clean-ds, brew, sudo and sleep. osascript lists no process, so there is
# nothing to quit; the test checks that the stubs are the commands found before
# it runs update-full at all, and that no quit and no sudo was ever asked for.
# MRK_ROOT names a scratch folder, and HOME a throwaway one. bin/macos-updates
# is the real script, run against the softwareupdate stub.
# update-full needs bash 4, and hands itself to Homebrew's when it is run under
# an older one. ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

W=$(mrk_mktemp_d) || exit 1
W=$(cd "$W" && pwd -P)
trap 'rm -rf "$W"' EXIT
S="$W/stubs" TMP="$W/tmp" ROOT="$W/mrk"
mkdir -p "$S" "$TMP" "$W/home" "$ROOT/.git"

# ── Stubs ────────────────────────────────────────────────────────────────────

# Each records "NAME ARGS" in $W/calls. make fails when $W/make-fails names the
# target it is given; topgrade prints the transcript TRANSCRIPT names and exits
# RC; softwareupdate and sw_vers answer macos-updates.
for cmd in osascript clean-ds brew sudo sleep; do
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s/calls"\n' "$cmd" "$W" > "$S/$cmd"
done
cat > "$S/make" <<EOF
#!/bin/sh
printf 'make %s\n' "\$*" >> "$W/calls"
[ -f "$W/make-fails" ] && case " \$* " in *" \$(cat "$W/make-fails") "*) exit 2 ;; esac
exit 0
EOF
cat > "$S/topgrade" <<EOF
#!/bin/sh
printf 'topgrade %s\n' "\$*" >> "$W/calls"
cat "\$TRANSCRIPT"
exit "\$RC"
EOF
cat > "$S/softwareupdate" <<EOF
#!/bin/sh
printf 'softwareupdate %s\n' "\$*" >> "$W/calls"
echo "Software Update Tool"
echo "No new software available."
EOF
printf '#!/bin/sh\necho 26.7.1\n' > "$S/sw_vers"
chmod +x "$S"/*
ln -s "$BASH" "$S/bash"

# The transcripts, in the form topgrade draws with no terminal.
printf '%s\n' '―― 20:04:21 - Brew Cask (ARM) ――' 'Error: Download failed' \
  '―― 20:04:24 - Summary ――' 'Brew (ARM): OK' 'Brew Cask (ARM): FAILED' \
  '―― 20:04:25 - pyenv rehash ――' > "$W/one-failed"
printf '%s\n' '―― 20:04:24 - Summary ――' 'Brew (ARM): OK' 'Brew Cask (ARM): OK' > "$W/all-ok"

ENV=(env -i HOME="$W/home" MRK_ROOT="$ROOT" PATH="$S:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$TMP" TERM=dumb)
RC_SEEN=0
# full TRANSCRIPT RC [ARGS...] — update-full with no terminal. Output in
# $W/out, the stub calls of this run in $W/calls.
full() {
  local transcript=$1 rc=$2
  shift 2
  : > "$W/calls"
  "${ENV[@]}" TRANSCRIPT="$W/$transcript" RC="$rc" "$REPO_ROOT/bin/update-full" "$@" < /dev/null > "$W/out" 2>&1
  RC_SEEN=$?
}
has() { grep -qF -- "$1" "$W/out"; }
show() { sed 's/^/    /' "$W/out"; printf '    calls: %s\n' "$(tr '\n' ';' < "$W/calls")"; }
# order — the stub calls, first word and target only, on one line
order() { awk '{ printf "%s%s ", $1, ($1 == "make" ? ":" $4 : "") }' "$W/calls"; }
line_no() { grep -nF -- "$1" "$W/out" | head -1 | cut -d: -f1; }

# ── 0. The stubs are what update-full would find ─────────────────────────────

# Before anything runs: were osascript, sudo or make the real ones, this test
# would quit applications or pull ~/mrk.
real=""
for cmd in osascript sudo make topgrade softwareupdate brew clean-ds sleep; do
  # shellcheck disable=SC2016  # expanded by the inner sh
  found=$("${ENV[@]}" /bin/sh -c 'command -v "$1"' sh "$cmd")
  [[ "$found" == "$S/$cmd" ]] || real+="$cmd "
done
if [[ -n "$real" ]]; then
  fail "not stubbed, so update-full is not run: $real"
  exit 1
fi
pass "every command update-full reaches is a stub"

# ── 1. One topgrade step failed: every step of update-full, in order ─────────

full one-failed 1 --yes --no-reboot
if (( RC_SEEN == 0 )) && [[ "$(order)" == "make:pull osascript sleep softwareupdate topgrade make:build-tools clean-ds brew " ]] \
   && has "Update complete. Reboot skipped (--no-reboot)."; then
  pass "the steps run in order: pull, quit, macOS updates, topgrade, build-tools, clean-ds, brew doctor"
else
  fail "the steps: exit $RC_SEEN, order: $(order)"; show
fi

# Step 1 leaves the Go tools to step 5, which comes after topgrade can have
# brought a new Go.
if grep -qxF "make -C $ROOT pull PULL_BUILD=0" "$W/calls" && grep -qxF "make -C $ROOT build-tools" "$W/calls"; then
  pass "step 1 pulls with PULL_BUILD=0, and step 5 builds the tools"
else
  fail "step 1 or step 5: the make calls were: $(grep '^make' "$W/calls" | tr '\n' ';')"
fi

# Step 4 is run_topgrade: the verdict, then update-full's own line, then on.
verdict=$(line_no "Update finished: every step ran. 1 of 2 failed: Brew Cask (ARM).")
going=$(line_no "Continuing with the rest of update-full.")
if [[ -n "$verdict" && -n "$going" ]] && (( verdict < going )) \
   && has "Nothing was interrupted: the other 1 succeeded, and the clean-up command after them ran." \
   && [[ -z "$(find "$TMP" -mindepth 1 -maxdepth 1)" ]]; then
  pass "step 4 names the topgrade step that failed, says the rest ran, and goes on; no recording is left"
else
  fail "step 4: verdict at line ${verdict:-none}, 'Continuing' at line ${going:-none}"; show
fi

if ! grep -q '^sudo' "$W/calls" && ! grep -qi 'quit' "$W/calls"; then
  pass "no application was asked to quit, and sudo was never called"
else
  fail "a quit or a sudo call:"; show
fi

# ── 2. Nothing failed: says so, and no "Continuing" ──────────────────────────

full all-ok 0 --yes --no-reboot
if (( RC_SEEN == 0 )) && has "Update finished: all 2 steps succeeded." && ! has "Continuing with the rest" \
   && grep -qxF "make -C $ROOT build-tools" "$W/calls"; then
  pass "nothing failed: the verdict says all succeeded, and the run goes on without a warning"
else
  fail "nothing failed: exit $RC_SEEN"; show
fi

# ── 3. A pull that fails: said, and the run goes on ──────────────────────────

echo pull > "$W/make-fails"
full all-ok 0 --yes --no-reboot
rm -f "$W/make-fails"
if (( RC_SEEN == 0 )) && has "mrk pull failed" && [[ "$(order)" == "make:pull osascript sleep softwareupdate topgrade make:build-tools clean-ds brew " ]]; then
  pass "a pull that fails: update-full says so and runs the other steps"
else
  fail "a pull that fails: exit $RC_SEEN, order: $(order)"; show
fi

# ── 4. No terminal and no --yes, and an unknown option: nothing runs ─────────

full all-ok 0
rc_plain=$RC_SEEN; calls_plain=$(wc -l < "$W/calls" | tr -d ' ')
refused=0; has "Refusing to run non-interactively without --yes." && refused=1
full all-ok 0 --bogus
if (( rc_plain == 1 && refused == 1 && calls_plain == 0 && RC_SEEN == 2 )) && [[ ! -s "$W/calls" ]] && has "Unknown option: --bogus"; then
  pass "without --yes and with no terminal it exits 1, an unknown option exits 2, and neither runs a step"
else
  fail "the refusals: no --yes exit $rc_plain with $calls_plain call(s); --bogus exit $RC_SEEN"; show
fi

if (( fails )); then
  err "$fails update-full check(s) failed"
  exit 1
fi
ok "update-full checks passed"
