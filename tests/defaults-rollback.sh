#!/usr/bin/env bash
# defaults-rollback.sh — prove that the undo script `make defaults` writes puts
# every value back exactly.
#
# write_default (scripts/defaults.sh) records each key's value before it
# changes it. Until 2026-09-11 it recorded what `defaults read` prints, which
# is a description rather than the value, and a round trip through the undo
# script changed 7 of 23 kinds of value: arrays, dictionaries, dates and data
# came back as strings, non-ASCII text as escape codes, a backslash doubled,
# and a float rounded to seven digits.
#
# Hermetic: the domain is a plist file in a temporary directory, which
# `defaults` accepts as a domain wherever it takes a name, so nothing touches
# the preferences of the user running it. The round trip runs under
# /bin/bash as well as the bash running this file, because defaults.sh runs
# under macOS's bash 3.2 on a new machine. ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" != --inner ]]; then
  run_under() {
    # shellcheck disable=SC2016  # expanded by the inner bash, not this one
    printf '  under bash %s\n' "$("$1" -c 'echo "${BASH_VERSION%%(*}"')"
    "$1" "${BASH_SOURCE[0]}" --inner
  }
  rc=0
  run_under /bin/bash || rc=1
  if [[ ! "$BASH" -ef /bin/bash ]]; then run_under "$BASH" || rc=1; fi
  exit "$rc"
fi

# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"
T=$(mrk_mktemp_d) || exit 1
trap 'rm -rf "$T"' EXIT
D="$T/probe"                 # a path-form domain: $T/probe.plist
ROLLBACK="$T/rollback.sh"
init_rollback "$ROLLBACK" >/dev/null 2>&1 || { err "init_rollback failed"; exit 1; }

fns=$(sed -n '/^backup_line(){/p; /^value_fragment(){/,/^}/p; /^write_default(){/,/^}/p' \
  "$REPO_ROOT/scripts/defaults.sh")
for f in backup_line value_fragment write_default; do
  grep -q "^$f(){" <<<"$fns" || { err "scripts/defaults.sh no longer defines $f() where this test expects it"; exit 1; }
done
eval "$fns"

keys=(k_bool k_int k_float k_float_zero k_float_double k_float_precise k_str k_str_unicode k_str_backslash k_str_newline
      k_str_empty k_array k_dict k_date k_data k_int_as_bool k_absent)
defaults write "$D" k_bool -bool true
defaults write "$D" k_int -int 42
defaults write "$D" k_float -float 0.5
defaults write "$D" k_float_zero -float 0
# A double, as macOS stores com.apple.mouse.doubleClickThreshold: -float would
# write it back as the 32-bit 0.800000011920929.
defaults write "$D" k_float_double '<real>0.8</real>'
defaults write "$D" k_float_precise -float 1.23456789012345
defaults write "$D" k_str -string Light
defaults write "$D" k_str_unicode -string 'café ✓ 日本'
# shellcheck disable=SC2016  # a literal $HOME is the point: it must come back as written
defaults write "$D" k_str_backslash -string 'a\b "q" $HOME'
defaults write "$D" k_str_newline -string $'line1\nline2'
defaults write "$D" k_str_empty -string ''
defaults write "$D" k_array -array a 'b c'
defaults write "$D" k_dict -dict k1 v1
defaults write "$D" k_date -date '2021-06-01 12:00:00 +0000'
defaults write "$D" k_data -data 48656c6c6f
defaults write "$D" k_int_as_bool -int 1

snapshot() {  # snapshot FILE — each key's value as XML, or <absent>
  local k exp
  exp=$(mrk_mktemp) || return 1
  defaults export "$D" "$exp" 2>/dev/null
  for k in "${keys[@]}"; do
    printf '%s=' "$k"
    /usr/libexec/PlistBuddy -x -c "Print \":$k\"" "$exp" 2>/dev/null | tr -d '\n' || printf '<absent>'
    printf '\n'
  done > "$1"
  rm -f "$exp"
}
snapshot "$T/before"

apply() {
  write_default "$D" k_bool bool false;         write_default "$D" k_int int 7
  write_default "$D" k_float float 1.25;        write_default "$D" k_float_precise float 3
  write_default "$D" k_float_zero float 1;      write_default "$D" k_float_double float 1
  local k
  for k in k_str k_str_unicode k_str_backslash k_str_newline k_str_empty k_array k_dict k_date k_data; do
    write_default "$D" "$k" string x
  done
  write_default "$D" k_int_as_bool bool true;   write_default "$D" k_absent bool true
}

fails=0
apply
lines=$(wc -l < "$ROLLBACK")
apply
if [[ "$(wc -l < "$ROLLBACK")" == "$lines" ]]; then
  ok "a second run adds nothing to the undo script, so the first run's values stand"
else
  err "a second run added lines to the undo script — it would record mrk's values as the originals"
  fails=$((fails + 1))
fi
if grep -q '^defaults write .*k_str -string Light$' "$ROLLBACK"; then
  ok "a plain string keeps its readable -string line"
else
  err "a plain string's undo line is not the readable -string form"; fails=$((fails + 1))
fi

bash "$ROLLBACK" >/dev/null 2>&1
snapshot "$T/after"
if diff -q "$T/before" "$T/after" >/dev/null; then
  ok "the undo script restores all ${#keys[@]} kinds of value exactly"
else
  err "the undo script changed these values:"
  diff "$T/before" "$T/after" | grep '^>' | cut -c1-140 >&2
  fails=$((fails + 1))
fi
(( fails == 0 ))
