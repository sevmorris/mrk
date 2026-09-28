#!/usr/bin/env bash
# docs-drift.sh — hold the places that list mrk's commands, Make targets and
# tests to what the repository actually has. Audit 19, W-26, W-27 and W-28.
#
# Each of these lists is written by hand and read by nobody who would notice it
# going stale, and module 19 found all three stale at once:
# - W-26: the manual's "~/Makefile" tables listed make mrk-status, make
#   mrk-menu and make build-tools, which dotfiles/Makefile did not have. From ~
#   each failed with "No rule to make target".
# - W-27: make check's help and the manual's make check row named fewer tests
#   than ci-check runs, and fell further behind with every test added.
# - W-28: BIN-1 said it had 39 command entries. It had 41.
#
# Checked here:
# 1. every file in tests/ is run by ci-check, named in its --help, and described
#    in BIN-1's ci-check entry
# 2. every make target the manual lists under "~/Makefile" is one dotfiles/Makefile
#    defines
# 3. BIN-1's count of its command entries is the number it has
# 4. every command mrk puts on the PATH has a BIN-1 entry. The names come from
#    setup itself, in a dry run of its tools phase on a copy of the repository
#    under a throwaway HOME, and from the Makefile's link-home-bin calls, so
#    this test does not keep a second copy of setup's naming rules.
# 5. BIN-1's tables of the two shared libraries, scripts/lib.sh and
#    bin/lib/common.sh, name every function each defines, and no function it
#    no longer defines. Until 2026-09-28 the lib.sh table lacked seven, and the
#    common.sh one still listed is_running, which nothing called.
#
# Read-only, apart from that dry run, which a scratch HOME keeps to itself.
# ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

BIN1="$REPO_ROOT/docs/bin/mrk-usage.html"
CI="$REPO_ROOT/scripts/ci-check"
MANUAL="$REPO_ROOT/docs/manual.md"

# ── 1. Every test is run, listed and described ───────────────────────────────

usage=$(sed -n '/^usage() {/,/^EOF$/p' "$CI")
entry=$(awk '/<div class="proc" id="ci-check">/ { p = 1; print; next }
             p && /<div class="proc" id=/ { exit }
             p' "$BIN1")
[[ -n "$usage" && -n "$entry" ]] || { fail "could not find ci-check's usage or its BIN-1 entry"; exit 1; }
not_run="" not_listed="" not_described="" n_tests=0
for f in "$REPO_ROOT"/tests/*; do
  [[ -f "$f" ]] || continue
  name=${f##*/}; stem=${name%.*}
  n_tests=$((n_tests + 1))
  grep -qF "tests/$name" "$CI" || not_run="$not_run $name"
  grep -qF "$stem" <<<"$usage" || not_listed="$not_listed $stem"
  grep -qF "tests/$name" <<<"$entry" || not_described="$not_described $name"
done
if (( n_tests >= 10 )) && [[ -z "$not_run$not_listed$not_described" ]]; then
  pass "all $n_tests tests in tests/ are run by ci-check, named in its --help, and described in BIN-1"
else
  fail "tests/ ($n_tests files): not run by ci-check:${not_run:- none}; not in its --help:${not_listed:- none}; not in BIN-1:${not_described:- none}"
fi

# ── 2. The manual's ~/Makefile targets exist ─────────────────────────────────

section=$(awk '/^## Commands you can run from anywhere/ { p = 1; next } p && /^## / { exit } p' "$MANUAL")
missing="" n_targets=0
while IFS= read -r t; do
  [[ -n "$t" ]] || continue
  n_targets=$((n_targets + 1))
  grep -qE "^$t:" "$REPO_ROOT/dotfiles/Makefile" || missing="$missing $t"
done < <(grep -oE '^\| `make [a-z][a-z-]*' <<<"$section" | awk '{ print $3 }')
if (( n_targets >= 5 )) && [[ -z "$missing" ]]; then
  pass "the $n_targets make targets the manual lists under ~/Makefile all exist there"
else
  fail "the manual lists under ~/Makefile ($n_targets targets) what dotfiles/Makefile lacks:${missing:- none}"
fi

# ── 3. BIN-1's count of its own entries ──────────────────────────────────────

n_entries=$(grep -c '<div class="proc" id=' "$BIN1")
said_has=$(grep -oE 'This manual has [0-9]+ command entries' "$BIN1" | grep -oE '[0-9]+')
said_of=$(grep -oE 'of the [0-9]+ answer <code>--help' "$BIN1" | grep -oE '[0-9]+')
if [[ "$said_has" == "$n_entries" && "$said_of" == "$n_entries" ]]; then
  pass "BIN-1 says it has $n_entries command entries, and it does"
else
  fail "BIN-1 has $n_entries command entries, and says ${said_has:-nothing} and ${said_of:-nothing}"
fi

# ── 4. Every command on the PATH has an entry ────────────────────────────────

W=$(mrk_mktemp_d) || exit 1
trap 'rm -rf "$W"' EXIT
while IFS= read -r -d '' f; do
  mkdir -p "$W/repo/$(dirname "$f")"
  cp -p "$REPO_ROOT/$f" "$W/repo/$f"
done < <(git -C "$REPO_ROOT" ls-files -z scripts bin)
mkdir -p "$W/home" "$W/tmp"
env -i HOME="$W/home" USER="${USER:-$(id -un)}" TMPDIR="$W/tmp" TERM=dumb \
  PATH=/usr/bin:/bin:/usr/sbin:/sbin MRK_ROOT="$W/repo" \
  /bin/bash "$W/repo/scripts/setup" --only tools --dry-run </dev/null > "$W/out" 2>&1
names=$(sed -nE "s#.*Would link: $W/home/bin/([^ ]+) -> .*#\1#p" "$W/out" | grep -vx lib)
names+=$'\n'$(grep -oE 'link-home-bin,[a-z-]+,[a-z -]+\)' "$REPO_ROOT/Makefile" \
               | sed -E 's/.*,([a-z -]+)\)/\1/' | tr ' ' '\n')
titles=$(grep -oE '<h3>[^<]+ <span' "$BIN1" | sed -E 's#<h3>##; s# <span##')
undocumented="" n_names=0
while IFS= read -r n; do
  [[ -n "$n" ]] || continue
  n_names=$((n_names + 1))
  # An entry's title, or the first word of a line in an entry's synopsis, as
  # mrk-status is in status's: two names for one binary.
  grep -qxF "$n" <<<"$titles" || grep -qE "^$n \[" "$BIN1" || undocumented="$undocumented $n"
done < <(sort -u <<<"$names")
if (( n_names >= 30 )) && [[ -z "$undocumented" ]]; then
  pass "all $n_names commands setup and the Makefile put on the PATH have a BIN-1 entry"
else
  fail "commands on the PATH ($n_names) with no BIN-1 entry:${undocumented:- none}"
  (( n_names >= 30 )) || sed 's/^/      /' "$W/out" | tail -5 >&2
fi

# ── 5. The shared libraries' tables ──────────────────────────────────────────

# lib_table CAPTION LIBRARY — check BIN-1's table captioned CAPTION against the
# functions LIBRARY defines, leaving out the _private ones.
lib_table() {
  local table defined listed n missing="" stale=""
  table=$(awk -v c="$1" 'index($0, c) { p = 1 } p && /<\/table>/ { exit } p' "$BIN1")
  defined=$(sed -nE 's/^([a-z][a-z0-9_]*)\(\) *\{.*/\1/p' "$2" | sort -u)
  # The first word of each code span in a row's first cell
  listed=$(grep -oE '<tr><td>.*</td><td>' <<<"$table" | sed -E 's#</td><td>.*##' \
             | grep -oE '<code>[a-z][a-z0-9_]*' | sed 's#<code>##' | sort -u)
  [[ -n "$table" && -n "$defined" ]] || { fail "could not read the table '$1' or $2"; return; }
  while IFS= read -r n; do
    grep -qE "(<code>|[ (])${n}[ ()<]" <<<"$table" || missing="$missing $n"
  done <<<"$defined"
  while IFS= read -r n; do
    grep -qxF "$n" <<<"$defined" || stale="$stale $n"
  done <<<"$listed"
  if [[ -z "$missing$stale" ]]; then
    pass "BIN-1's table of ${2##*/} names its $(wc -l <<<"$defined" | tr -d ' ') functions, and no others"
  else
    fail "BIN-1's table of ${2##*/}: missing${missing:- none}; names what it lacks:${stale:- none}"
  fi
}
lib_table "Table 3.1-1" "$REPO_ROOT/scripts/lib.sh"
lib_table "Table 3.1-2" "$REPO_ROOT/bin/lib/common.sh"

(( fails == 0 ))
