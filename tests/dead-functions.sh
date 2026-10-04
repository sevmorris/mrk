#!/usr/bin/env bash
# dead-functions.sh — every shell function mrk defines has a caller. Audit 21, Y-8.
#
# SC2329, the shellcheck check for a function that is never invoked, is blind
# in most of this repository: on 2026-10-04 a probe function added to
# each tracked bash script was reported in 8 of the 80. It missed err in doctor
# while SC2329 was disabled for every file, and ask_yes in post-install, which
# became dead when the extension-list prompts went (audit 21, D-1).
#
# So this counts by name instead. Each function defined in a tracked bash
# script, outside a heredoc, must be named again in the same file, on a line
# that is not a comment. A function in scripts/lib.sh or bin/lib/common.sh may
# be named in another tracked file instead, since that is what a library is for.
# A name in a heredoc is a stub a test writes into a scratch copy, not a
# definition here. ci-check runs it.

set -uo pipefail
export LC_ALL=C

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

# defs FILE — "LINE NAME" for each function FILE defines outside a heredoc.
defs() {
  awk '
    term != "" {
      line = $0
      if (strip) sub(/^\t+/, "", line)
      if (line == term) term = ""
      next
    }
    /^[ \t]*(function[ \t]+)?[A-Za-z_][A-Za-z0-9_]*[ \t]*\(\)/ {
      name = $0
      sub(/^[ \t]*(function[ \t]+)?/, "", name)
      sub(/[ \t]*\(\).*/, "", name)
      print NR, name
    }
    {
      # The heredoc that starts on this line, if any: <<WORD, <<-WORD,
      # <<"WORD" or <<'"'"'WORD'"'"', and not a <<< here-string.
      s = $0
      while ((i = index(s, "<<")) > 0) {
        rest = substr(s, i + 2)
        if (substr(rest, 1, 1) == "<") { s = substr(rest, 2); continue }
        strip = (substr(rest, 1, 1) == "-")
        if (strip) rest = substr(rest, 2)
        sub(/^[ \t]*["'"'"']?/, "", rest)
        if (match(rest, /^[A-Za-z_][A-Za-z0-9_]*/)) { term = substr(rest, 1, RLENGTH); break }
        s = rest
      }
    }
  ' "$1"
}

# uses FILE NAME DEFLINE — lines of FILE, other than DEFLINE and comments, that
# name NAME as a word.
uses() {
  grep -nw -- "$2" "$1" 2>/dev/null \
    | grep -v -E "^$3:" \
    | grep -c -v -E '^[0-9]+:[[:space:]]*#'
}

files=()
while IFS= read -r f; do
  [[ -f "$REPO_ROOT/$f" ]] && head -1 "$REPO_ROOT/$f" | grep -qE '^#!.*bash' && files+=("$f")
done < <(git -C "$REPO_ROOT" ls-files)

total=0
dead=()
for f in "${files[@]}"; do
  while read -r line name; do
    [[ -n "$name" ]] || continue
    total=$((total + 1))
    (( $(uses "$REPO_ROOT/$f" "$name" "$line") > 0 )) && continue
    case "$f" in
      scripts/lib.sh|bin/lib/common.sh)
        others=$(git -C "$REPO_ROOT" grep -nw -e "$name" -- ':!audit' ':!docs' ":!$f" 2>/dev/null \
                   | grep -c -v -E '^[^:]+:[0-9]+:[[:space:]]*#')
        (( others > 0 )) && continue
        ;;
    esac
    dead+=("$f:$line $name")
  done < <(defs "$REPO_ROOT/$f")
done

if (( ${#files[@]} > 0 && total > 0 && ${#dead[@]} == 0 )); then
  pass "all $total functions in ${#files[@]} bash scripts have a caller"
else
  fail "functions with no caller (of $total in ${#files[@]} scripts):"
  for d in ${dead[@]+"${dead[@]}"}; do info "$d"; done
fi

(( fails == 0 ))
