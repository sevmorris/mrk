#!/usr/bin/env bash
# maintain.sh — prove that maintain's build check says, for each Go tool,
# whether it is up to date, older than its source, or not installed, and that
# a dry run calls neither gh, git nor make.
#
# Step 4 reads tool_freshness in scripts/lib.sh, the check the Upkeep panel of
# mrk-status reads too. Until 2026-09-30 it was maintain's own loop, and until
# 2026-10-01 no test ran maintain at all (audit 20, X-11).
#
# maintain runs with --dry-run under a throwaway HOME, whose ~/bin holds one
# binary dated far ahead of every source, one dated 2000, and lacks the third.
# The sources are this checkout's own, read and never written. gh, git and make
# are stubs first on PATH that record any call.
# maintain needs bash 4, and hands itself to Homebrew's when it is run under an
# older one. ci-check runs it.

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
S="$W/stubs" H="$W/home"
mkdir -p "$S" "$H/bin"
: > "$W/calls"

for cmd in gh git make; do
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s/calls"\n' "$cmd" "$W" > "$S/$cmd"
done
chmod +x "$S"/*
ln -s "$BASH" "$S/bash"

# mrk-picker newer than any source can be, mrk-status older than every one,
# and no mrk-menu.
printf '#!/bin/sh\n' > "$H/bin/mrk-picker"
printf '#!/bin/sh\n' > "$H/bin/mrk-status"
touch -t 209901010000 "$H/bin/mrk-picker"
touch -t 200001010000 "$H/bin/mrk-status"

ENV=(env -i HOME="$H" PATH="$S:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="${TMPDIR:-/tmp}" TERM=dumb)
RC=0
maintain() {
  "${ENV[@]}" "$REPO_ROOT/bin/maintain" "$@" < /dev/null > "$W/out" 2>&1
  RC=$?
}
has() { grep -qF -- "$1" "$W/out"; }
show() { sed 's/^/    /' "$W/out"; }

# ── 1. The build check: one line for each tool, by its state ─────────────────

maintain --dry-run
if (( RC == 0 )) && has "mrk-picker: up to date" \
   && has "mrk-status: source newer than binary — run make build-tools" \
   && has "mrk-menu: not installed — run make build-tools" && has "Maintenance complete."; then
  pass "the build check: up to date, older than its source, and not installed, each named"
else
  fail "the build check: exit $RC"; show
fi

# ── 2. A dry run previews steps 1 to 3, and calls nothing ────────────────────

# shellcheck disable=SC2016  # the dry run prints $REPO_ROOT as written
if has "DRY RUN" && has "Would prune GitHub Pages deployments beyond the 10 most recent." \
   && has 'Would run: git -C "$REPO_ROOT" fetch --prune' && has 'Would run: make -C "$REPO_ROOT" check' \
   && [[ ! -s "$W/calls" ]]; then
  pass "--dry-run: the three steps are previewed, and gh, git and make are never called"
else
  fail "--dry-run: calls: $(tr '\n' ';' < "$W/calls")"; show
fi

# ── 3. A wrong command line: exit 2, and nothing runs ────────────────────────

maintain --keep=0; rc_keep=$RC
maintain --bogus
if (( rc_keep == 2 && RC == 2 )) && has "Unknown option: --bogus" && [[ ! -s "$W/calls" ]]; then
  pass "--keep=0 and an unknown option exit 2, and call nothing"
else
  fail "the refusals: --keep=0 exit $rc_keep, --bogus exit $RC"; show
fi

if (( fails )); then
  err "$fails maintain check(s) failed"
  exit 1
fi
ok "maintain checks passed"
