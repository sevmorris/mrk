#!/usr/bin/env bash
# home-makefile.sh — prove that ~/Makefile runs every one of ~/mrk's make
# targets from the home directory, with its ARGS.
#
# ~/Makefile is dotfiles/Makefile, linked into the home. Until 2026-09-30 it
# forwarded eleven targets by name and no others, so `make update` from ~ said
# "No rule to make target". ARGS was never the problem: make hands a variable
# given on the command line to the inner make by itself.
#
# Each case runs dotfiles/Makefile with MRK naming a stub Makefile that records
# the target and ARGS it was asked for, so nothing is run. One case hands it the
# real ~/mrk Makefile under make -n, which prints and runs nothing.
# ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

W=$(mrk_mktemp_d) || exit 1
trap 'rm -rf "$W"' EXIT
STUB="$W/mrk"
mkdir -p "$STUB" "$W/home"
: > "$W/log"

# The stub ~/mrk: every target records itself, help says who it is, and one
# target fails, as a target ~/mrk has no rule for does.
cat > "$STUB/Makefile" <<MK
help:
	@echo "stub help"
nope:
	@exit 3
.DEFAULT:
	@printf '%s ARGS=%s\n' "\$@" "\$(ARGS)" >> "$W/log"
MK

# home ARGS... — dotfiles/Makefile from the home, as make finds ~/Makefile
home() {
  : > "$W/log"
  (cd "$W/home" && make --no-print-directory -f "$REPO_ROOT/dotfiles/Makefile" MRK="$STUB" "$@") > "$W/out" 2>&1
}
logged() { [[ "$(cat "$W/log")" == "$1" ]]; }

home update
if logged "update ARGS="; then pass "make update: forwarded to ~/mrk"; else fail "make update: $(cat "$W/out" "$W/log")"; fi

home pull ARGS=--x
if logged "pull ARGS=--x"; then pass "a forwarded target keeps its ARGS"; else fail "make pull ARGS=--x: $(cat "$W/out" "$W/log")"; fi

home snapshot-prefs ARGS=-n
if logged "snapshot-prefs ARGS=-n"; then
  pass "make snapshot-prefs ARGS=-n: the -n reaches it"
else
  fail "make snapshot-prefs ARGS=-n: $(cat "$W/out" "$W/log")"
fi

home sync ARGS=-c
if logged "sync ARGS=-c"; then pass "a named rule keeps its ARGS too"; else fail "make sync ARGS=-c: $(cat "$W/out" "$W/log")"; fi

home
if grep -q 'From ~/' "$W/out" && grep -q 'stub help' "$W/out" && [[ ! -s "$W/log" ]]; then
  pass "make with no target: the help, ~/'s and ~/mrk's"
else
  fail "make with no target:"; sed 's/^/    /' "$W/out"
fi

home nope; rc=$?
if (( rc != 0 )); then pass "a target that fails in ~/mrk fails here too (exit $rc)"; else fail "make nope exited 0"; fi

# Every target of the real ~/mrk Makefile reaches ~/mrk.
missed=""
while IFS= read -r t; do
  [[ "$t" == help ]] && continue
  home "$t"
  logged "$t ARGS=" || missed="$missed $t"
done < <(sed -nE 's/^([a-zA-Z][a-zA-Z0-9_-]*):.*/\1/p' "$REPO_ROOT/Makefile" | sort -u)
if [[ -z "$missed" ]]; then
  pass "every target of ~/mrk's Makefile is forwarded from the home"
else
  fail "not forwarded:$missed"
fi
if grep -rq '^Makefile ' "$W/log"; then fail "make tried to rebuild ~/Makefile through ~/mrk"; fi

# The real ~/mrk Makefile, under make -n: the recipe it would run, run by none.
if (cd "$W/home" && make -n --no-print-directory -f "$REPO_ROOT/dotfiles/Makefile" MRK="$REPO_ROOT" update) 2>&1 | grep -q 'topgrade'; then
  pass "make -n update against the real ~/mrk: its recipe, printed and not run"
else
  fail "make -n update against the real ~/mrk did not reach its recipe"
fi

if (( fails )); then
  err "$fails home Makefile check(s) failed"
  exit 1
fi
ok "home Makefile checks passed"
