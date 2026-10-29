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
# 6. make tidy covers every Go module under tools/. Until 2026-09-28 its list
#    was written out and had missed tools/theme (audit 19, W-25). Read from
#    `make -n`, which prints the recipe and runs nothing.
# 7. README and the manual give the number of keys config/defaults.tsv lists,
#    and it is the number check-defaults-desc counts. On 2026-09-28 seven keys
#    left (audit 15, T-3) and both said 143 until they were edited by hand.
# 8. The manual's table of managed app preferences names the apps of
#    config/app-prefs.tsv, which snapshot-prefs and post-install read, by the
#    name the table gives each. Its third column is the manual's own: what
#    mrk writes into the app after the import.
# 9. Each command's options agree in three places: the case statement that
#    parses its arguments, its usage text, and its BIN-1 entry. All three are
#    read from the source, and nothing runs. -h and --help are left out:
#    BIN-1 says once, for every command, that each answers both. Audit 22, O-4.
# 10. BIN-1's entries of the five --check modes give the number of fields that
#    each line has, and name each fixed word, such as a state, that the script
#    can write. Both are read from the script's calls of mrk_check_line, and
#    from the words it gives the variables that it passes. The check-lines
#    callout lists the scripts that make such calls. Audit 22, O-4.
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

# ── 6. make tidy covers every Go module ──────────────────────────────────────

tidy_cmd=$(make --no-print-directory -n -C "$REPO_ROOT" tidy 2>/dev/null)
untidied="" n_mods=0
for gomod in "$REPO_ROOT"/tools/*/go.mod; do
  mod=$(basename "$(dirname "$gomod")")
  n_mods=$((n_mods + 1))
  grep -qE "for dir in .*\b$mod\b" <<<"$tidy_cmd" || untidied="$untidied $mod"
done
if (( n_mods >= 4 )) && [[ -z "$untidied" ]]; then
  pass "make tidy covers all $n_mods Go modules under tools/"
else
  fail "make tidy misses:${untidied:- none} ($n_mods modules)"
fi

# ── 7. The defaults key count ────────────────────────────────────────────────

n_keys=$("$REPO_ROOT/scripts/check-defaults-desc" 2>/dev/null | sed -nE 's/.*OK \(([0-9]+) keys.*/\1/p')
readme_keys=$(grep -oE 'config/defaults\.tsv.? \| [0-9]+ keys' "$REPO_ROOT/README.md" | grep -oE '[0-9]+ keys' | grep -oE '[0-9]+')
manual_keys=$(grep -oE 'The file lists [0-9]+ preference keys' "$MANUAL" | grep -oE '[0-9]+')
if [[ -n "$n_keys" && "$readme_keys" == "$n_keys" && "$manual_keys" == "$n_keys" ]]; then
  pass "README and the manual say config/defaults.tsv lists $n_keys keys, and it does"
else
  fail "config/defaults.tsv lists ${n_keys:-an uncounted number of} keys; README says ${readme_keys:-nothing}, the manual ${manual_keys:-nothing}"
fi

# ── 8. The manual's managed app preferences ──────────────────────────────────

table_apps=$(mrk_config_entries "$REPO_ROOT/config/app-prefs.tsv" | cut -f4 | LC_ALL=C sort)
manual_apps=$(awk '/^\*\*Managed app preferences:\*\*/ { p = 1; next } p && /^\| / { print; t = 1; next } p && t && !/^\|/ { exit }' "$MANUAL" \
  | awk -F' *\\| *' 'NR > 1 { print $2 }' | LC_ALL=C sort)
if [[ -n "$table_apps" && "$manual_apps" == "$table_apps" ]]; then
  pass "the manual's managed app preferences are the $(grep -c . <<<"$table_apps") apps of config/app-prefs.tsv"
else
  fail "the manual's managed app preferences differ from config/app-prefs.tsv (< table, > manual):"
  diff <(printf '%s\n' "$table_apps") <(printf '%s\n' "$manual_apps") | sed 's/^/    /' >&2
fi

# ── 9. The options: parser, usage text and BIN-1 ─────────────────────────────

# help_text FILE — the usage text that FILE shows for --help, read from its
# source: the body of usage(), the heredoc after a -h|--help) label, or a
# *_USAGE='…' string. For Go, the string that usage() writes.
help_text() {
  case "$1" in
    *.go) awk '/^func usage\(/ { p = 1; next } p && /^`\)/ { exit }
               p { sub(/.*fmt\.Fprint\(w, `/, ""); print }' "$1" ;;
    *) awk -v q="'" '
         /^usage\(\) *\{/ { u = 1 }
         u { print; if (/^\}/) exit; next }
         /^[ \t]*(-h *\| *--help|--help *\| *-h)\)/ { h = NR; next }
         h && tag == "" && NR - h <= 2 && match($0, /<<-?.?[A-Z_]+/) {
           tag = substr($0, RSTART, RLENGTH); gsub(/[^A-Z_]/, "", tag); next }
         tag != "" { if ($0 ~ "^[ \t]*" tag "$") exit; print; next }
         $0 ~ "^[A-Z_]*USAGE=" q { s = 1 }
         s { print; if (++k > 1 && $0 ~ q "$") exit }' "$1" ;;
  esac
}

# help_opts — the options that a usage text on stdin gives as the command's
# own: those in a line that starts with an option, and those in the synopsis
# lines after "Usage:", up to the run of spaces before a description. An
# option in a sentence, such as maintain's "git fetch --prune", can be another
# command's, so it does not count.
help_opts() {
  awk '{
    line = $0; sub(/^[ \t]+/, "", line)
    if (line ~ /^Usage:/) { syn = 1; sub(/^Usage:[ \t]*/, "", line) }
    else if (line == "") syn = 0
    if (!syn && line !~ /^-/) next
    i = index(line, "  "); if (i) line = substr(line, 1, i - 1)
    line = " " line
    while (match(line, /[^A-Za-z0-9-](--[a-z][a-z0-9-]*|-[A-Za-z])([^A-Za-z0-9-]|$)/)) {
      o = substr(line, RSTART + 1, RLENGTH - 1); sub(/[^A-Za-z0-9-]$/, "", o); print o
      line = substr(line, RSTART + RLENGTH - 1)
    }
  }' | grep -vxE -- '-h|--help' | sort -u
}

# parser_opts FILE — the options that FILE's parser takes: each label that
# starts with a dash, in a case statement that has a label for -h or --help.
parser_opts() {
  awk '
    /^[ \t]*case .* in([ \t]|$)/ { top++; nb++; blk[top] = nb; next }
    top && /^[ \t]*esac/ { top--; next }
    top && /^[ \t]*\(?-[-a-zA-Z0-9=*| "]*\)/ {
      l = $0; sub(/^[ \t]*\(?/, "", l); sub(/\).*/, "", l)
      n = split(l, a, "|")
      for (i = 1; i <= n; i++) {
        o = a[i]; gsub(/[ "]/, "", o); sub(/=.*/, "", o); sub(/\*$/, "", o)
        if (o == "-h" || o == "--help") help[blk[top]] = 1
        else if (o ~ /^-./ && o != "--") opts[blk[top]] = opts[blk[top]] " " o
      }
    }
    END { for (b in help) { n = split(opts[b], a, " "); for (i = 1; i <= n; i++) print a[i] } }' "$1" | sort -u
}

# go_flags DIR — the flags that the Go tool in DIR defines with the flag
# package. go_cases DIR — the options that its parseArgs takes.
go_flags() {
  cat "$1"/*.go | sed -nE 's/.*\.(Bool|String|Int|Duration)(Var)?\((&[^,]+, )?"([a-z][a-z0-9-]*)".*/--\4/p'
}
go_cases() {
  grep -hE '^[[:space:]]*case "-' "$1"/*.go | grep -oE '"-[^"]+"' | tr -d '"' | grep -vxE -- '-h|--help'
}

# entry_opts ID — the options that BIN-1's entry ID names as the command's
# own: those in its synopsis, and those at the head of an item that starts
# with an option, before the dash or after the first code span.
entry_opts() {
  awk -v id="$1" '
    index($0, "<div class=\"proc\" id=\"" id "\"") { p = 1; next }
    p && /<div class="proc" id=/ { exit }
    !p { next }
    /<pre>/ { pre = 1 }
    pre || /^[ \t]*<li><code>-/ {
      line = $0
      if (!pre) { i = index(line, " — "); if (!i) i = index(line, "</code>"); line = substr(line, 1, i) }
      line = " " line
      while (match(line, /[^A-Za-z0-9-](--[a-z][a-z0-9-]*|-[A-Za-z])([^A-Za-z0-9-]|$)/)) {
        o = substr(line, RSTART + 1, RLENGTH - 1); sub(/[^A-Za-z0-9-]$/, "", o); print o
        line = substr(line, RSTART + RLENGTH - 1)
      }
    }
    /<\/pre>/ { pre = 0 }' "$BIN1" | grep -vxE -- '-h|--help' | sort -u
}

# entry_of NAME — the id of the BIN-1 entry of the command NAME: NAME itself,
# mrk-NAME (scripts/setup is mrk-setup), or NAME less mrk- (mrk-status is
# status).
entry_of() {
  local c
  for c in "$1" "mrk-$1" "${1#mrk-}"; do
    grep -qF "<div class=\"proc\" id=\"$c\"" "$BIN1" && { echo "$c"; return; }
  done
}

# only_in A B — the lines of A that B does not have, on one line.
only_in() {
  comm -23 <(grep . <<<"$1" | sort -u) <(grep . <<<"$2" | sort -u) | tr '\n' ' ' | sed 's/ $//'
}

# Each command: its name and its source. A Go tool's source is its directory,
# from the Makefile's go-build calls.
commands=$(
  git -C "$REPO_ROOT" ls-files bin scripts | grep -E '^(bin|scripts)/[^/]+$' | grep -vx scripts/lib.sh \
    | awk '{ n = $0; sub(/.*\//, "", n); sub(/\.sh$/, "", n); print n "\t" $0 }'
  sed -nE 's/.*\$\(call go-build,([a-z-]+),([a-z-]+)\).*/\1 \2/p' "$REPO_ROOT/Makefile" \
    | awk '{ print $1 "\ttools/" $2 }'
)
opt_fails=$fails n_cmds=0 entries="" help_by_entry=""
while IFS=$'\t' read -r name src; do
  [[ -n "$name" ]] || continue
  n_cmds=$((n_cmds + 1))
  id=$(entry_of "$name")
  [[ -n "$id" ]] || { fail "$src has no BIN-1 entry to hold its options to"; continue; }
  if [[ "$src" == tools/* ]]; then
    flags=$(go_flags "$REPO_ROOT/$src")
    text=$(help_text "$REPO_ROOT/$src/main.go")
    help=$( { help_opts <<<"$text"; printf '%s\n' "$flags"; } | grep . | sort -u)
    parsed=$( { go_cases "$REPO_ROOT/$src"; printf '%s\n' "$flags"; } | grep . | sort -u)
    [[ -n "$text$flags" ]] || { fail "$src: could not read its usage text"; continue; }
  else
    text=$(help_text "$REPO_ROOT/$src")
    # decloud hands every argument to git, and has no usage text of its own.
    if [[ -z "$text" ]] && grep -q -- '--help' "$REPO_ROOT/$src"; then
      fail "$src: could not read its usage text"; continue
    fi
    help=$(help_opts <<<"$text")
    parsed=$(parser_opts "$REPO_ROOT/$src")
  fi
  x=$(only_in "$parsed" "$help")
  [[ -z "$x" ]] || fail "$src: its parser takes $x, which its usage text does not name"
  x=$(only_in "$help" "$parsed")
  [[ -z "$x" ]] || fail "$src: its usage text names $x, which its parser does not take"
  entries+=$'\n'$id
  help_by_entry+=$(awk -v id="$id" 'NF { print id "\t" $0 }' <<<"$help")$'\n'
done <<<"$commands"
n_opts=0
while IFS= read -r id; do
  [[ -n "$id" ]] || continue
  help=$(awk -F'\t' -v id="$id" '$1 == id { print $2 }' <<<"$help_by_entry")
  listed=$(entry_opts "$id")
  n_opts=$((n_opts + $(grep -c . <<<"$help")))
  x=$(only_in "$help" "$listed")
  [[ -z "$x" ]] || fail "BIN-1's $id entry does not name $x, which the usage text names"
  x=$(only_in "$listed" "$help")
  [[ -z "$x" ]] || fail "BIN-1's $id entry names $x, which the usage text does not"
done < <(sort -u <<<"$entries")
if (( fails == opt_fails && n_cmds >= 30 && n_opts >= 60 )); then
  pass "the $n_opts options of $n_cmds commands agree in each parser, each usage text and BIN-1"
elif (( fails == opt_fails )); then
  fail "read the options of only $n_cmds commands, $n_opts in all: the readers above no longer find them"
fi

# ── 10. The --check lines: fields and words ──────────────────────────────────

# check_calls FILE — for each call of mrk_check_line in FILE: "fields N", and
# "word POS WORD" or "var POS NAME" for each lowercase word or variable that
# the call gives as field POS. Comments and heredocs do not count.
check_calls() {
  awk '
    tag != "" { if ($0 ~ "^[ \t]*" tag "$") tag = ""; next }
    /^[ \t]*#/ || /mrk_check_line\(\)/ { next }
    {
      s = $0
      while ((i = index(s, "mrk_check_line ")) > 0) {
        s = substr(s, i + 15); n = 0; pos = 1
        while (1) {
          while (substr(s, pos, 1) == " ") pos++
          c = substr(s, pos, 1)
          if (c == "" || index(">;)|&#", c)) break
          tok = ""; dq = 0; br = 0; pa = 0
          while (pos <= length(s)) {
            c = substr(s, pos, 1)
            if (!dq && !br && !pa && (c == " " || index(">;)|&", c))) break
            if (c == "\"" && !br && !pa) dq = !dq
            else if (c == "{" && substr(s, pos - 1, 1) == "$") br++
            else if (c == "}" && br) br--
            else if (c == "(" && substr(s, pos - 1, 1) == "$") pa++
            else if (c == ")" && pa) pa--
            tok = tok c; pos++
          }
          n++; t = tok; gsub(/"/, "", t)
          if (t ~ /^[a-z]+$/) print "word", n, t
          else if (match(t, /^\$\{?[A-Za-z_][A-Za-z0-9_]*/)) { v = substr(t, RSTART, RLENGTH); sub(/^\$\{?/, "", v); print "var", n, v }
        }
        print "fields", n
        s = substr(s, pos)
      }
    }
    match($0, /<<-?.?[A-Z_]+/) { tag = substr($0, RSTART, RLENGTH); gsub(/[^A-Z_]/, "", tag) }' "$1"
}

# check_vars FILE NAMES — "NAME WORD" for each lowercase word that FILE gives
# one of the variables NAMES: NAME=word, NAME+=(word), or for NAME in word ….
# In a heredoc, only a Python line NAME = "word" if … else "word", which is
# how snapshot-prefs makes the change of each key.
check_vars() {
  awk -v vars="$2" '
    BEGIN { n = split(vars, v, " "); for (i = 1; i <= n; i++) want[v[i]] = 1 }
    tag != "" {
      if ($0 ~ "^[ \t]*" tag "$") { tag = ""; next }
      if (match($0, /^[ \t]*[A-Za-z_][A-Za-z0-9_]* = /)) {
        name = $0; sub(/^[ \t]*/, "", name); sub(/ .*/, "", name)
        if (name in want) { s = $0; while (match(s, /"[a-z]+"/)) { print name, substr(s, RSTART + 1, RLENGTH - 2); s = substr(s, RSTART + RLENGTH) } }
      }
      next
    }
    /^[ \t]*#/ { next }
    {
      s = " " $0
      while (match(s, /[ \t;(&|][A-Za-z_][A-Za-z0-9_]*\+?=\(?"?[a-z]+"?\)?([ \t;)|&]|$)/)) {
        m = substr(s, RSTART + 1, RLENGTH - 1); s = substr(s, RSTART + RLENGTH - 1)
        name = m; sub(/\+?=.*/, "", name)
        w = m; sub(/^[^=]*=\(?"?/, "", w); sub(/[^a-z].*/, "", w)
        if (name in want) print name, w
      }
      if (match($0, /for [A-Za-z_][A-Za-z0-9_]* in [a-z ]+;/)) {
        split(substr($0, RSTART + 4, RLENGTH - 5), f, " ")
        if (f[1] in want) for (i = 3; i in f; i++) print f[1], f[i]
      }
    }
    match($0, /<<-?.?[A-Z_]+/) { tag = substr($0, RSTART, RLENGTH); gsub(/[^A-Z_]/, "", tag) }' "$1"
}

# number — each number word on stdin, as digits.
number() {
  awk 'BEGIN { split("one two three four five six seven eight nine ten", w, " "); for (i in w) d[w[i]] = i }
       { print ($1 in d) ? d[$1] : $1 }'
}

check_fails=$fails n_modes=0 n_words=0 writers=""
callout=$(awk '/<div class="callout" id="check-lines">/ { p = 1 } p && /<ul>/ { exit } p' "$BIN1")
listed=$(grep -oE 'href="#[a-z-]+"' <<<"$callout" | sed -E 's/href="#(.*)"/\1/' | sort -u)
said=$(grep -oE '[A-Z][a-z]+ commands have a <code>--check</code>' <<<"$callout" | awk '{ print tolower($1) }' | number)
while IFS=$'\t' read -r name src; do
  [[ "$src" != tools/* ]] || continue
  calls=$(check_calls "$REPO_ROOT/$src")
  [[ -n "$calls" ]] || continue
  id=$(entry_of "$name")
  writers+=$'\n'$id
  n_modes=$((n_modes + 1))
  entry=$(awk -v id="$id" 'index($0, "<div class=\"proc\" id=\"" id "\"") { p = 1; next }
                           p && /<div class="proc" id=/ { exit } p' "$BIN1")
  # The items that describe the lines: each one that names --check or --details.
  items=$(grep -E '<li>.*<code>--(check|details)</code>' <<<"$entry")
  fields=$(awk '$1 == "fields" { print $2 }' <<<"$calls" | sort -un | paste -sd' ' -)
  said_fields=$(awk '{ s = $0
                       while (match(s, /(one|two|three|four|five|six|seven|eight|nine|ten) (tab-separated )?fields/)) {
                         w = substr(s, RSTART, RLENGTH); sub(/ .*/, "", w); print w; s = substr(s, RSTART + RLENGTH) } }' <<<"$items" \
                  | number | sort -un | paste -sd' ' -)
  [[ "$said_fields" == "$fields" ]] \
    || fail "$src writes lines of ${fields// / or } fields, and BIN-1's $id entry gives ${said_fields:-no number}"
  vars=$(awk '$1 == "var" { print $3 }' <<<"$calls" | sort -u | tr '\n' ' ')
  words=$( { awk '$1 == "word" { print $3 }' <<<"$calls"; check_vars "$REPO_ROOT/$src" "$vars" | awk '{ print $2 }'; } | sort -u)
  n_words=$((n_words + $(grep -c . <<<"$words")))
  for w in $words; do
    grep -qF "<code>$w</code>" <<<"$entry" || fail "$src can write the word $w in a --check line, and BIN-1's $id entry does not name it"
  done
  # A command that the text names, such as brew, is in the script too.
  while IFS= read -r w; do
    [[ -n "$w" ]] || continue
    grep -qxF "$w" <<<"$words" && continue
    # Not grep -q: it stops at the first match, and pipefail then reports the
    # first grep's SIGPIPE.
    grep -vE '^[[:space:]]*#' "$REPO_ROOT/$src" | grep -w -- "$w" >/dev/null && continue
    fail "BIN-1's $id entry names the word $w for --check, and $src does not have it"
  done < <(grep -oE '<code>[a-z]+</code>' <<<"$items" | sed -E 's#</?code>##g' | sort -u)
done <<<"$commands"
writers=$(grep . <<<"$writers" | sort -u)
[[ "$said" == "$(grep -c . <<<"$listed")" ]] \
  || fail "BIN-1's check-lines callout says ${said:-no number} commands, and links $(grep -c . <<<"$listed")"
[[ "$writers" == "$listed" ]] \
  || fail "BIN-1's check-lines callout links $(paste -sd' ' - <<<"$listed"), and the commands that call mrk_check_line are $(paste -sd' ' - <<<"$writers")"
if (( fails == check_fails && n_modes >= 5 && n_words >= 20 )); then
  pass "BIN-1 lists the $n_modes --check modes, with the fields of their lines and the $n_words words they write"
elif (( fails == check_fails )); then
  fail "found only $n_modes --check modes and $n_words words: check_calls no longer reads the scripts"
fi

(( fails == 0 ))
