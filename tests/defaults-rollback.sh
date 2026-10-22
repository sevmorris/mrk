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
# under macOS's bash 3.2 on a new machine. It then runs defaults.sh whole, with
# `defaults` stubbed to keep every domain in the temporary directory: that it
# writes the keys of config/defaults.tsv in order, with their gates, that a
# second run writes nothing, how it ends when a write fails, what --check
# shows and that it writes nothing, and that a bad line stops it before any
# write. ci-check runs it.

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

fns=$(sed -n '/^backup_line(){/p; /^default_is_set(){/,/^}/p; /^exact_string(){/,/^}/p; /^value_fragment(){/,/^}/p; /^write_default(){/,/^}/p' \
  "$REPO_ROOT/scripts/defaults.sh")
for f in backup_line default_is_set exact_string value_fragment write_default; do
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
fail() { err "$*"; fails=$((fails + 1)); }
apply
lines=$(wc -l < "$ROLLBACK")
apply
if [[ "$(wc -l < "$ROLLBACK")" == "$lines" ]]; then
  ok "a second run adds nothing to the undo script, so the first run's values stand"
else
  fail "a second run added lines to the undo script — it would record mrk's values as the originals"
fi
if grep -q '^defaults write .*k_str -string Light$' "$ROLLBACK"; then
  ok "a plain string keeps its readable -string line"
else
  fail "a plain string's undo line is not the readable -string form"
fi

bash "$ROLLBACK" >/dev/null 2>&1
snapshot "$T/after"
if diff -q "$T/before" "$T/after" >/dev/null; then
  ok "the undo script restores all ${#keys[@]} kinds of value exactly"
else
  fail "the undo script changed these values:"
  diff "$T/before" "$T/after" | grep '^>' | cut -c1-140 >&2
fi

# defaults.sh whole. `defaults` is a stub that keeps every domain as a plist
# file under $STORE, and adds each call to $CALLS: a write as its four fields,
# escaped as config/defaults.tsv escapes them, and any other call as its verb.
# FAIL_DOMAIN makes writes to one domain fail, as a managed or locked key does;
# killall records and does nothing. Until 2026-09-28 a failed write was warned
# about, and then the script printed "Defaults applied" and exited 0, so
# setup's "defaults.sh returned non-zero" warning could never fire (audit 19,
# W-19).
DS="$T/stubs"; mkdir -p "$DS" "$T/tmp"
cat > "$DS/defaults" <<'EOF'
#!/bin/bash
esc() { local s=${1//\\/\\\\}; s=${s//$'\t'/\\t}; printf '%s' "${s//$'\n'/\\n}"; }
verb="${1:-}"; dom="${2:-}"
case "$verb" in read|read-type|write|export) ;; *) echo "defaults $*" >> "$STORE/refused"; exit 2 ;; esac
case "$dom" in ""|-*|/*) echo "defaults $*" >> "$STORE/refused"; exit 2 ;; esac
if [[ "$verb" == write ]]; then
  printf 'write\t%s\t%s\t%s\t%s\n' "$(esc "$dom")" "$(esc "$3")" "${4#-}" "$(esc "$5")" >> "$CALLS"
else
  printf '%s\n' "$verb" >> "$CALLS"
fi
[[ "$verb" == write && "$dom" == "${FAIL_DOMAIN:-}" ]] && exit 1
shift 2
exec /usr/bin/defaults "$verb" "$STORE/$dom" "$@"
EOF
# shellcheck disable=SC2016  # expanded by the stub, not here
printf '#!/bin/bash\necho "killall $*" >> "$CALLS"\nexit 0\n' > "$DS/killall"
chmod +x "$DS"/*

# run NAME [ARGS...] — defaults.sh from ROOT (the repository, or a copy with a
# table of its own), with a HOME, a store and a call log of NAME's own, which
# the runs of one NAME share. stdout in $T/NAME/out, stderr in $T/NAME/err,
# the exit status in RC.
run() {
  local name=$1; shift
  mkdir -p "$T/$name/home" "$T/$name/store"
  env -i HOME="$T/$name/home" PATH="$DS:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$T/tmp" \
    STORE="$T/$name/store" CALLS="$T/$name/calls" FAIL_DOMAIN="${FAIL_DOMAIN:-}" \
    "$BASH" "${ROOT:-$REPO_ROOT}/scripts/defaults.sh" "$@" </dev/null > "$T/$name/out" 2> "$T/$name/err"
  RC=$?
}
writes() { { grep '^write' "$T/$1/calls" 2>/dev/null || true; } | cut -f2-; }
calls() { wc -l < "$T/$1/calls" 2>/dev/null | tr -d ' '; }
undo() { cat "$T/$1/home/.mrk/defaults-rollback.sh" 2>/dev/null; }

# expected WHEN HOME — the rows a run writes, as the stub logs them: WHEN is
# an extended regex of the gates that apply, and HOME the run's, for a ~/ path.
expected() {
  local when=$1 home=$2 i v
  defaults_table "$REPO_ROOT/config/defaults.tsv" || return 1
  for i in "${!DT_DOMAIN[@]}"; do
    [[ "${DT_WHEN[i]}" =~ ^($when)$ ]] || continue
    v=${DT_VALUE[i]}
    # shellcheck disable=SC2088  # a literal ~/ in the file
    [[ "${DT_TYPE[i]}" == string && "$v" == "~/"* ]] && v="$home/${v#"~/"}"
    printf '%s\t%s\t%s\t%s\n' "${DT_DOMAIN[i]}" "${DT_KEY[i]}" "${DT_TYPE[i]}" "$v"
  done
}

# ── The keys of config/defaults.tsv, in order, with their gates ──────────────

run clean; rc_clean=$RC
FAIL_DOMAIN=com.apple.dock run locked; rc_locked=$RC
if [[ $rc_clean == 0 ]] && grep -q 'Defaults applied' "$T/clean/err" && [[ ! -e "$T/clean/store/refused" ]]; then
  ok "defaults.sh with every write accepted: exits 0, \"Defaults applied\""
else
  fail "defaults.sh with every write accepted: exit $rc_clean; refused: $(head -2 "$T/clean/store/refused" 2>/dev/null)"
  tail -3 "$T/clean/err" >&2
fi
if [[ "$(writes clean)" == "$(expected always "$T/clean/home")" ]] \
   && grep -q 'com.apple.mail AddressesIncludeNameOnPasteboard (its domain does not exist yet)' "$T/clean/err" \
   && grep -q 'com.apple.TextEdit RichText (its domain does not exist yet)' "$T/clean/err"; then
  ok "it writes the $(writes clean | wc -l | tr -d ' ') always rows of config/defaults.tsv, in order, ~/ as the home directory; Mail's and TextEdit's wait for a domain"
else
  fail "the writes are not config/defaults.tsv's always rows, in order:"
  diff <(expected always "$T/clean/home") <(writes clean) | head -5 >&2
fi
if [[ $rc_locked == 1 ]] && grep -q 'default(s) failed to apply' "$T/locked/err" \
   && ! grep -q 'Defaults applied' "$T/locked/err" && [[ -f "$T/locked/store/com.apple.finder.plist" ]] \
   && grep -q '^killall Dock' "$T/locked/home/.mrk/defaults-rollback.sh"; then
  ok "defaults.sh with the Dock's writes refused: exits 1, says so, and still applies the rest and writes the undo"
else
  fail "defaults.sh with the Dock's writes refused: exit $rc_locked"
  tail -3 "$T/locked/err" >&2
fi

mkdir -p "$T/full/store"
/usr/bin/defaults write "$T/full/store/com.apple.mail" Seeded -bool true       # Mail is set up
/usr/bin/defaults write "$T/full/store/com.apple.TextEdit" Seeded -bool true   # TextEdit has been used
run full --with-trackpad; rc_full=$RC
if [[ $rc_full == 0 && "$(writes full)" == "$(expected 'always|trackpad|existing' "$T/full/home")" ]] \
   && grep -q 'Applying trackpad defaults' "$T/full/err" && ! grep -q 'does not exist yet' "$T/full/err" \
   && grep -qx $'com.apple.TextEdit\tRichText\tint\t0' <(writes full); then
  ok "with --with-trackpad, Mail set up and TextEdit used: all $(writes full | wc -l | tr -d ' ') rows, TextEdit's RichText among them, each where the file has it"
else
  fail "with --with-trackpad, Mail set up and TextEdit used: exit $rc_full, or not every row in order:"
  diff <(expected 'always|trackpad|existing' "$T/full/home") <(writes full) | head -5 >&2
fi
n_full=$(calls full); undo_full=$(undo full)
run full --with-trackpad
if [[ $RC == 0 && "$(undo full)" == "$undo_full" ]] && ! sed -n "$((n_full + 1)),\$p" "$T/full/calls" | grep -q '^write'; then
  ok "a second run writes nothing, and leaves the undo file as it was"
else
  fail "a second run: exit $RC; it wrote, or changed the undo file"
fi

# ── --check ──────────────────────────────────────────────────────────────────

n_full=$(calls full)
run full --check --with-trackpad
check_calls=$(sed -n "$((n_full + 1)),\$p" "$T/full/calls" | sort -u | tr '\n' ' ')
if [[ $RC == 0 && "$(wc -l < "$T/full/out" | tr -d ' ')" == "$(expected 'always|trackpad|existing' x | wc -l | tr -d ' ')" \
      && -z "$(awk -F'\t' 'NF != 5' "$T/full/out")" && ! -s "$T/full/err" \
      && "$check_calls" == "read read-type " && "$(undo full)" == "$undo_full" ]] \
   && ! grep -qv $'\tset$' "$T/full/out"; then
  ok "--check after a run: every row set, in five fields, and nothing on stderr; it only reads, and the undo file is as it was"
else
  fail "--check after a run: exit $RC; calls: $check_calls"
  grep -v $'\tset$' "$T/full/out" | head -3 >&2; head -3 "$T/full/err" >&2
fi
run full --check
if [[ $RC == 0 && "$(wc -l < "$T/full/out" | tr -d ' ')" == "$(expected 'always|existing' x | wc -l | tr -d ' ')" ]] \
   && grep -q $'^com.apple.screencapture\tlocation\t'"$T/full/home/Desktop"$'\t'"$T/full/home/Desktop"$'\tset$' "$T/full/out" \
   && grep -q $'^NSGlobalDomain\tNSAutomaticWindowAnimationsEnabled\tfalse\tfalse\tset$' "$T/full/out"; then
  ok "--check without --with-trackpad leaves the trackpad rows out; a ~/ path and a bool read as the file writes them"
else
  fail "--check without --with-trackpad: exit $RC"; head -3 "$T/full/out" >&2
fi

st="$T/full/store"
/usr/bin/defaults write "$st/com.apple.dock" tilesize -int 48
/usr/bin/defaults write "$st/com.apple.dock" orientation -int 1
/usr/bin/defaults delete "$st/NSGlobalDomain" AppleShowAllExtensions
run full --check
if grep -qx $'com.apple.dock\ttilesize\t36\t48\tdiffers' "$T/full/out" \
   && grep -qx $'com.apple.dock\torientation\tleft\t1\tdiffers' "$T/full/out" \
   && grep -qx $'NSGlobalDomain\tAppleShowAllExtensions\ttrue\t\tabsent' "$T/full/out" \
   && [[ "$(grep -vc $'\tset$' "$T/full/out")" == 3 ]]; then
  ok "--check: another value, another type and a deleted key read differs, differs and absent"
else
  fail "--check after three changes:"; grep -v $'\tset$' "$T/full/out" >&2
fi
run fresh --check
if [[ $RC == 0 && -s "$T/fresh/out" && ! -e "$T/fresh/home/.mrk" ]] \
   && ! grep -qv $'\tabsent$' "$T/fresh/out" && ! grep -q '^killall' "$T/fresh/calls"; then
  ok "--check on a Mac never set up: every row absent; no ~/.mrk, no undo file, no restart"
else
  fail "--check on a fresh store: exit $RC"; head -3 "$T/fresh/out" "$T/fresh/err" >&2
fi

# ── A table of its own: escapes, and the lines defaults.sh refuses ───────────

R="$T/repo"; mkdir -p "$R/scripts" "$R/config"
cp "$REPO_ROOT/scripts/defaults.sh" "$REPO_ROOT/scripts/lib.sh" "$R/scripts/"
# shellcheck disable=SC2016  # a literal $HOME is the point: it must be written as it is
{
  printf '# a comment, then an empty line\n\n'
  printf 'com.example.probe\tTricky\tstring\t%s\talways\tProbe\n' 'tab\there\nline two \\ "quoted" $HOME'
  printf 'com.example.probe\tEmpty\tstring\t\talways\tProbe\n'
  printf 'com.example.probe\tAccent\tstring\tcafé ✓\talways\tProbe\n'
  printf 'com.example.probe\tRatio\tfloat\t0.25\talways\tProbe\n'
} > "$R/config/defaults.tsv"
# shellcheck disable=SC2016
tricky=$'tab\there\nline two \\ "quoted" $HOME'
ROOT=$R run probe
# PlistBuddy, not defaults read, which shows a backslash doubled
/usr/bin/defaults export "$T/probe/store/com.example.probe" "$T/probe.plist"
got=$(/usr/libexec/PlistBuddy -c 'Print :Tricky' "$T/probe.plist" && printf x); got=${got%$'\nx'}
empty=$(/usr/bin/defaults read-type "$T/probe/store/com.example.probe" Empty 2>/dev/null)
n_probe=$(calls probe)
ROOT=$R run probe
again=$(sed -n "$((n_probe + 1)),\$p" "$T/probe/calls" | grep -c '^write')
ROOT=$R run probe --check
# shellcheck disable=SC2016
want_tricky=$'com.example.probe\tTricky\ttab\\there\\nline two \\\\ "quoted" $HOME\ttab\\there\\nline two \\\\ "quoted" $HOME\tset'
if [[ $RC == 0 && "$got" == "$tricky" && "$empty" == "Type is string" && "$(head -1 "$T/probe/out")" == "$want_tricky" ]] \
   && grep -qx $'com.example.probe\tEmpty\t\t\tset' "$T/probe/out" \
   && grep -qx $'com.example.probe\tAccent\tcafé ✓\tcafé ✓\tset' "$T/probe/out"; then
  ok "a value with a tab, a newline, a backslash, quotes and a \$ is written exactly, an empty string too, and --check escapes them as the file does"
else
  fail "the escapes: exit $RC; written $(printf '%q' "$got"), Empty: '$empty'"; cat "$T/probe/out" >&2
fi
if [[ "$again" == 0 ]]; then
  ok "a second run writes none of them again: a backslash and an accent read back as set, not as defaults read shows them"
else
  fail "a second run wrote $again of the probe's keys again"
fi

# refuse WHAT LINE — the table and LINE: a run and --check refuse it, and write nothing
n_bad=0
refuse() {
  local name="bad$((n_bad += 1))" rc_apply rc_check
  cp "$R/config/defaults.tsv" "$T/good.tsv"
  printf '%s\n' "$2" >> "$R/config/defaults.tsv"
  ROOT=$R run "$name"; rc_apply=$RC
  ROOT=$R run "$name" --check; rc_check=$RC
  cp "$T/good.tsv" "$R/config/defaults.tsv"
  if [[ $rc_apply == 1 && $rc_check == 1 && ! -s "$T/$name/out" && ! -e "$T/$name/calls" && ! -e "$T/$name/home/.mrk" ]] \
     && grep -q 'Nothing was changed' "$T/$name/err"; then
    ok "$1: refused before any write, by a run and by --check, and no undo file"
  else
    fail "$1: a run exits $rc_apply, --check $rc_check"; head -3 "$T/$name/err" >&2
  fi
}
refuse "a bool that is not true or false" $'com.example.probe\tFlag\tbool\tyes\talways\tProbe'
refuse "a line of five fields" $'com.example.probe\tFlag\tbool\ttrue\talways'
refuse "a backslash that is not an escape" $'com.example.probe\tPath\tstring\tC:\\temp\\x\talways\tProbe'
refuse "a domain and key on two lines" $'com.example.probe\tRatio\tfloat\t0.5\talways\tProbe'
refuse "a when that is not always, trackpad or existing" $'com.example.probe\tFlag\tbool\ttrue\tsometimes\tProbe'

ROOT=$R run opt --bogus
if [[ $RC == 2 && ! -e "$T/opt/calls" ]] && grep -q 'unknown argument: --bogus' "$T/opt/err"; then
  ok "an unknown argument: exit 2, before anything is read"
else
  fail "an unknown argument: exit $RC"
fi
(( fails == 0 ))
