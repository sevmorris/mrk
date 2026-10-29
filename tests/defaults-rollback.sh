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
# write. Last, the options of one key, on a copy of the repository: --key
# writes that key alone, --revert puts back the value it had before mrk,
# --skip and --unskip edit config/defaults-skip.tsv and change nothing on the
# Mac, a run and --check pass over a skipped key, and a bad option, key or
# skip line changes nothing. And a key in a container that macOS does not let
# the process read: noaccess, passed over by a run, refused by --key and
# --revert. ci-check runs it.

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
# escaped as config/defaults.tsv escapes them, a delete as its domain and key,
# and any other call as its verb.
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
case "$verb" in read|read-type|write|export|delete) ;; *) echo "defaults $*" >> "$STORE/refused"; exit 2 ;; esac
case "$dom" in ""|-*|/*) echo "defaults $*" >> "$STORE/refused"; exit 2 ;; esac
if [[ "$verb" == write ]]; then
  printf 'write\t%s\t%s\t%s\t%s\n' "$(esc "$dom")" "$(esc "$3")" "${4#-}" "$(esc "$5")" >> "$CALLS"
elif [[ "$verb" == delete ]]; then
  printf 'delete\t%s\t%s\n' "$(esc "$dom")" "$(esc "$3")" >> "$CALLS"
else
  printf '%s\n' "$verb" >> "$CALLS"
fi
[[ "$verb" == write && "$dom" == "${FAIL_DOMAIN:-}" ]] && exit 1
shift 2
exec /usr/bin/defaults "$verb" "$STORE/$dom" "$@"
EOF
# shellcheck disable=SC2016  # expanded by the stub, not here
printf '#!/bin/bash\necho "killall $*" >> "$CALLS"\nexit 0\n' > "$DS/killall"
# ls refuses the Preferences folder of each container that DENY names, as macOS
# refuses Mail's to a process without Full Disk Access, and lists anything
# else.
cat > "$DS/ls" <<'EOF'
#!/bin/bash
for a in "$@"; do
  for d in ${DENY:-}; do
    if [[ "$a" == "$HOME/Library/Containers/$d/Data/Library/Preferences" ]]; then
      echo "ls: $a: Operation not permitted" >&2; exit 1
    fi
  done
done
exec /bin/ls "$@"
EOF
chmod +x "$DS"/*

# run NAME [ARGS...] — defaults.sh from ROOT (the repository, or a copy with a
# table of its own), with a HOME, a store and a call log of NAME's own, which
# the runs of one NAME share. stdout in $T/NAME/out, stderr in $T/NAME/err,
# the exit status in RC.
run() {
  local name=$1; shift
  mkdir -p "$T/$name/home" "$T/$name/store"
  env -i HOME="$T/$name/home" PATH="$DS:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$T/tmp" \
    STORE="$T/$name/store" CALLS="$T/$name/calls" FAIL_DOMAIN="${FAIL_DOMAIN:-}" DENY="${DENY:-}" MRK_LOCK_WAIT="${MRK_LOCK_WAIT:-}" \
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

# The restarts, and the undo file's own. ControlCenter draws the menu bar
# clock and reads its keys only when it starts; until 2026-10-22 a run
# restarted SystemUIServer alone, and a changed clock key waited for a login.
restarts=$'killall Finder\nkillall Dock\nkillall SystemUIServer\nkillall ControlCenter'
if [[ "$(grep '^killall' "$T/clean/calls")" == "$restarts" ]] \
   && [[ "$(grep '^killall' "$T/clean/home/.mrk/defaults-rollback.sh" | sed 's/ >.*//')" == "$restarts" ]]; then
  ok "a run restarts Finder, the Dock, SystemUIServer and ControlCenter, and the undo file restarts the same four"
else
  fail "the restarts of a run, or of its undo file, are not Finder, Dock, SystemUIServer and ControlCenter:"
  grep '^killall' "$T/clean/calls" "$T/clean/home/.mrk/defaults-rollback.sh" >&2
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
# A when=existing row whose domain does not exist yet is nodomain, not absent:
# a run does not write it until the app makes its preferences.
run fresh --check
if [[ $RC == 0 && -s "$T/fresh/out" && ! -e "$T/fresh/home/.mrk" ]] \
   && [[ "$(grep $'\tnodomain$' "$T/fresh/out" | cut -f1,2)" == "$(expected existing x | cut -f1,2)" ]] \
   && ! grep -v $'\tnodomain$' "$T/fresh/out" | grep -qv $'\tabsent$' && ! grep -q '^killall' "$T/fresh/calls"; then
  ok "--check on a Mac never set up: every row absent, Mail's and TextEdit's nodomain; no ~/.mrk, no undo file, no restart"
else
  fail "--check on a fresh store: exit $RC"; grep -v $'\tabsent$' "$T/fresh/out" >&2; head -3 "$T/fresh/err" >&2
fi
/usr/bin/defaults write "$T/fresh/store/com.apple.mail" Seeded -bool true   # Mail is set up
run fresh --check
if [[ $RC == 0 ]] && grep -q $'^com\\.apple\\.mail\t.*\tabsent$' "$T/fresh/out" \
   && ! grep -q $'^com\\.apple\\.mail\t.*\tnodomain$' "$T/fresh/out" \
   && grep -q $'^com\\.apple\\.TextEdit\t.*\tnodomain$' "$T/fresh/out"; then
  ok "--check: once Mail has a domain its row is absent, and TextEdit's is still nodomain"
else
  fail "--check with Mail set up: exit $RC"; grep -E '^com\.apple\.(mail|TextEdit)' "$T/fresh/out" >&2
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
# ── One key at a time: --key, --revert, --skip and --unskip ──────────────────
# On a copy of the repository, because --skip and --unskip write its
# config/defaults-skip.tsv. Dipstick's mrk Settings turns a key off with
# --skip and --revert in one run, and on with --unskip and --key.

K="$T/onekey"; mkdir -p "$K/scripts" "$K/config"
cp "$REPO_ROOT/scripts/defaults.sh" "$REPO_ROOT/scripts/lib.sh" "$K/scripts/"
cp "$REPO_ROOT/config/defaults.tsv" "$REPO_ROOT/config/defaults-skip.tsv" "$K/config/"
SK="$K/config/defaults-skip.tsv"
cp "$SK" "$T/skip.orig"
since() { sed -n "$(( $2 + 1 )),\$p" "$T/$1/calls" 2>/dev/null; }   # since NAME N — the calls after the first N
dock() { /usr/bin/defaults read "$T/$1/store/com.apple.dock" "$2" 2>/dev/null; }
# no_stray — true when config/ holds the two files and no temporary one
no_stray() { [[ "$(find "$K/config" -mindepth 1 | wc -l | tr -d ' ')" == 2 ]]; }

mkdir -p "$T/one/store"
/usr/bin/defaults write "$T/one/store/com.apple.dock" tilesize -int 48
ROOT=$K run one --key com.apple.dock tilesize
if [[ $RC == 0 && "$(writes one)" == $'com.apple.dock\ttilesize\tint\t36' && "$(dock one tilesize)" == 36 ]] \
   && [[ "$(grep '^killall' "$T/one/calls")" == "$restarts" ]] \
   && grep -qx 'defaults write com.apple.dock tilesize -int 48' "$T/one/home/.mrk/defaults-rollback.sh" \
   && grep -qx 'killall Dock >/dev/null 2>&1 || true' "$T/one/home/.mrk/defaults-rollback.sh"; then
  ok "--key writes that key alone, records the value it had, and restarts the four"
else
  fail "--key com.apple.dock tilesize: exit $RC; writes: $(writes one | tr '\n' ' ')"; tail -3 "$T/one/err" >&2
fi
n=$(calls one)
ROOT=$K run one --key com.apple.dock tilesize
if [[ $RC == 0 ]] && ! since one "$n" | grep -qE '^(write|killall)' && grep -q 'com.apple.dock tilesize is set already' "$T/one/err"; then
  ok "--key on a key that is set writes nothing and restarts nothing"
else
  fail "--key a second time: exit $RC"; since one "$n" >&2
fi
undo_one=$(undo one); n=$(calls one)
ROOT=$K run one --revert com.apple.dock tilesize
if [[ $RC == 0 && "$(dock one tilesize)" == 48 && "$(undo one)" == "$undo_one" ]] \
   && [[ "$(since one "$n" | grep '^killall')" == "$restarts" ]]; then
  ok "--revert puts back the value the key had before mrk, restarts the four, and keeps the undo file"
else
  fail "--revert com.apple.dock tilesize: exit $RC, tilesize $(dock one tilesize)"; tail -3 "$T/one/err" >&2
fi
ROOT=$K run one --key NSGlobalDomain AppleShowAllExtensions
ROOT=$K run one --revert NSGlobalDomain AppleShowAllExtensions
if [[ $RC == 0 ]] && ! /usr/bin/defaults read "$T/one/store/NSGlobalDomain" AppleShowAllExtensions >/dev/null 2>&1 \
   && grep -qx $'delete\tNSGlobalDomain\tAppleShowAllExtensions' "$T/one/calls"; then
  ok "--revert of a key that was absent before mrk deletes it again"
else
  fail "--revert NSGlobalDomain AppleShowAllExtensions: exit $RC"; tail -3 "$T/one/err" >&2
fi
/usr/bin/defaults write "$T/one/store/com.apple.dock" orientation -string bottom
n=$(calls one)
ROOT=$K run one --revert com.apple.dock orientation
if [[ $RC == 0 && "$(dock one orientation)" == bottom ]] && ! since one "$n" | grep -qE '^(write|delete|killall)' \
   && grep -q 'com.apple.dock orientation has no line in' "$T/one/err"; then
  ok "--revert of a key that mrk did not write on this Mac leaves it as it is, and restarts nothing"
else
  fail "--revert of a key with no undo line: exit $RC, orientation $(dock one orientation)"; since one "$n" >&2
fi
ROOT=$K run one --key com.apple.mail AddressesIncludeNameOnPasteboard
if [[ $RC == 0 ]] && ! grep -q $'^write\tcom.apple.mail' "$T/one/calls" \
   && grep -q 'com.apple.mail AddressesIncludeNameOnPasteboard (its domain does not exist yet)' "$T/one/err"; then
  ok "--key passes over a key that waits for its domain, as a run does"
else
  fail "--key on a key with no domain yet: exit $RC"; tail -3 "$T/one/err" >&2
fi

# The skip list. A run of these options with no --key or --revert does not
# read or write the Mac at all.
ROOT=$K run skip --skip com.apple.dock tilesize --skip NSGlobalDomain AppleShowAllExtensions
if [[ $RC == 0 && "$(cat "$SK")" == "$(cat "$T/skip.orig")"$'\nNSGlobalDomain\tAppleShowAllExtensions\ncom.apple.dock\ttilesize' ]] \
   && [[ ! -e "$T/skip/calls" && ! -e "$T/skip/home/.mrk" ]] && no_stray; then
  ok "--skip adds each key to config/defaults-skip.tsv in byte order, changes nothing on the Mac, and leaves no temporary file"
else
  fail "--skip of two keys: exit $RC"; cat "$SK" >&2; find "$K/config" >&2
fi
ROOT=$K run skip --check
if [[ $RC == 0 && "$(grep $'\tskipped$' "$T/skip/out" | cut -f1,2)" == $'NSGlobalDomain\tAppleShowAllExtensions\ncom.apple.dock\ttilesize' ]]; then
  ok "--check shows the two skipped keys as skipped, and no other"
else
  fail "--check with two keys skipped: exit $RC"; grep $'\tskipped$' "$T/skip/out" >&2
fi
ROOT=$K run skip
if [[ $RC == 0 && "$(writes skip)" == "$(expected always "$T/skip/home" | grep -v -e $'^NSGlobalDomain\tAppleShowAllExtensions\t' -e $'^com.apple.dock\ttilesize\t')" ]] \
   && grep -q 'com.apple.dock tilesize (config/defaults-skip.tsv skips it)' "$T/skip/err"; then
  ok "a run writes every always row but the two skipped keys, and says it skips them"
else
  fail "a run with two keys skipped: exit $RC"
  diff <(expected always "$T/skip/home") <(writes skip) | head -5 >&2
fi
cp "$SK" "$T/skip.two"; n=$(calls skip)
ROOT=$K run skip --key com.apple.dock tilesize
if [[ $RC == 1 && "$(calls skip)" == "$n" ]] && cmp -s "$SK" "$T/skip.two" && grep -q 'Give --unskip too' "$T/skip/err"; then
  ok "--key refuses a skipped key, and changes nothing"
else
  fail "--key on a skipped key: exit $RC"; tail -2 "$T/skip/err" >&2
fi
ROOT=$K run skip --skip com.apple.dock tilesize
if [[ $RC == 0 ]] && cmp -s "$SK" "$T/skip.two" && grep -q 'com.apple.dock tilesize was skipped already' "$T/skip/err" \
   && no_stray; then
  ok "--skip on a skipped key leaves the file as it was"
else
  fail "--skip a second time: exit $RC"; diff "$T/skip.two" "$SK" >&2
fi
n=$(calls skip)
ROOT=$K run skip --unskip com.apple.dock tilesize --key com.apple.dock tilesize
if [[ $RC == 0 && "$(cat "$SK")" == "$(cat "$T/skip.orig")"$'\nNSGlobalDomain\tAppleShowAllExtensions' ]] \
   && [[ "$(since skip "$n" | grep '^write')" == $'write\tcom.apple.dock\ttilesize\tint\t36' ]]; then
  ok "--unskip and --key in one run: the line goes, then the key is written"
else
  fail "--unskip and --key: exit $RC"; cat "$SK" >&2; since skip "$n" | grep '^write' >&2
fi

# A line goes in before the first key that sorts after it, and comments stay
# where they are.
{ cat "$T/skip.orig"; printf 'NSGlobalDomain\tAppleShowAllExtensions\n# kept by hand\ncom.apple.finder\tShowPathbar\n'; } > "$SK"
ROOT=$K run skip --skip com.apple.dock tilesize --unskip NSGlobalDomain AppleShowAllExtensions
if [[ $RC == 0 && "$(cat "$SK")" == "$(cat "$T/skip.orig")"$'\n# kept by hand\ncom.apple.dock\ttilesize\ncom.apple.finder\tShowPathbar' ]]; then
  ok "--skip puts a line before the first key that sorts after it, --unskip deletes one, and a comment stays"
else
  fail "a skip list with a comment: exit $RC"; tail -4 "$SK" >&2
fi
cp "$T/skip.orig" "$SK"

# Two runs at once, each for its own key, as two switches flipped together.
# Until 2026-10-28 one key of the two was lost every time: each run read the
# list, wrote its own and renamed it over the other's (audit 22, Z-7). The
# skip list's lock makes the second wait for the first.
LOCK="$K/config/.defaults-skip.tsv.lock"
lost=0
for i in 1 2 3 4 5; do
  cp "$T/skip.orig" "$SK"
  ROOT=$K run race1 --skip com.apple.dock tilesize &
  ROOT=$K run race2 --skip NSGlobalDomain AppleShowAllExtensions &
  wait
  { grep -qx $'com.apple.dock\ttilesize' "$SK" && grep -qx $'NSGlobalDomain\tAppleShowAllExtensions' "$SK"; } || lost=$((lost + 1))
done
if (( lost == 0 )) && [[ ! -e "$LOCK" ]] && no_stray; then
  ok "two --skip runs at once keep both keys, five times of five, and leave no lock"
else
  fail "two --skip runs at once lost a key $lost times of five"; ls -a "$K/config" >&2
fi
cp "$T/skip.orig" "$SK"

# A lock whose process is gone, after a SIGKILL or a crash, is taken over. A
# lock that a live run holds is waited for, MRK_LOCK_WAIT seconds, and then
# the run says which process holds it and changes nothing.
sh -c 'exit 0' & dead=$!; wait "$dead"
mkdir "$LOCK" && printf '%s\n' "$dead" > "$LOCK/pid"
ROOT=$K run lock --skip com.apple.dock tilesize
if [[ $RC == 0 && ! -e "$LOCK" ]] && grep -qx $'com.apple.dock\ttilesize' "$SK"; then
  ok "a lock left by a process that is gone is taken over"
else
  fail "a stale lock: exit $RC"; tail -2 "$T/lock/err" >&2
fi
cp "$T/skip.orig" "$SK"
sleep 30 & holder=$!
mkdir "$LOCK" && printf '%s\n' "$holder" > "$LOCK/pid"
MRK_LOCK_WAIT=1 ROOT=$K run lock --skip com.apple.dock tilesize
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
if [[ $RC == 1 ]] && cmp -s "$SK" "$T/skip.orig" && grep -q "Another mrk run (process $holder) is changing defaults-skip.tsv" "$T/lock/err"; then
  ok "a lock a live run holds: waited for, then exit 1, the holder named, and nothing changed"
else
  fail "a held lock: exit $RC"; tail -2 "$T/lock/err" >&2
fi
rm -rf "$LOCK"

# A bad skip list stops a run, --check and every option before any change.
for line in $'com.example.gone\tGoneKey' 'com.apple.dock tilesize' $'com.apple.dock\ttilesize\t36'; do
  { cat "$T/skip.orig"; printf '%s\n' "$line"; } > "$SK"; cp "$SK" "$T/skip.bad"
  bad=""
  for args in "" "--check" "--key com.apple.dock tilesize" "--skip com.apple.finder ShowPathbar"; do
    rm -rf "$T/badskip"
    # shellcheck disable=SC2086  # the words of args are the options
    ROOT=$K run badskip $args
    if [[ $RC != 1 || -s "$T/badskip/out" || -e "$T/badskip/calls" || -e "$T/badskip/home/.mrk" ]] \
       || ! grep -q 'Nothing was changed' "$T/badskip/err" || ! cmp -s "$SK" "$T/skip.bad"; then
      bad+=" [${args:-a run}: exit $RC]"
    fi
  done
  if [[ -z "$bad" ]]; then
    ok "a skip line \"${line//$'\t'/<tab>}\": a run, --check, --key and --skip refuse it and change nothing"
  else
    fail "a skip line \"${line//$'\t'/<tab>}\":$bad"
  fi
done
cp "$T/skip.orig" "$SK"

# usage CASE WANT TEXT ARGS... — defaults.sh ARGS exits WANT, says TEXT, and
# changes nothing
usage_case() {
  local what=$1 want=$2 text=$3; shift 3
  rm -rf "$T/usage"
  ROOT=$K run usage "$@"
  if [[ $RC == "$want" && ! -e "$T/usage/calls" ]] && cmp -s "$SK" "$T/skip.orig" && grep -qF -- "$text" "$T/usage/err"; then
    ok "$what: exit $want, and nothing changed"
  else
    fail "$what: exit $RC, want $want with \"$text\""; tail -2 "$T/usage/err" >&2
  fi
}
usage_case "--key with no key" 2 "--key takes a domain and a key" --key com.apple.dock
usage_case "--check with --skip" 2 "do not go with" --check --skip com.apple.dock tilesize
usage_case "--with-trackpad with --key" 2 "do not go with" --with-trackpad --key com.apple.dock tilesize
usage_case "--skip and --unskip of one key" 2 "--skip and --unskip both name com.apple.dock tilesize" \
  --skip com.apple.dock tilesize --unskip com.apple.dock tilesize
usage_case "--key and --revert of one key" 2 "--key and --revert both name com.apple.dock tilesize" \
  --key com.apple.dock tilesize --revert com.apple.dock tilesize
usage_case "a key that is not in the table" 1 "com.example.gone GoneKey is not a key of config/defaults.tsv" \
  --skip com.apple.dock tilesize --skip com.example.gone GoneKey
# ── A key that macOS does not let the process read ───────────────────────────
# Mail's preferences are in a container that macOS keeps from a process
# without Full Disk Access, and TextEdit's and Passwords' from one without
# permission to get the data of other apps as well: their Preferences folder
# cannot be listed, and defaults reads the domain from ~/Library/Preferences,
# or finds none. On 2026-10-23 Gearbox, without Full Disk Access, read Mail's
# key as nodomain; a launchd job, with neither permission, read Passwords'
# from the copy outside the container, which a run would have written to.
# Here the store holds values for Mail and Passwords, which a read would find,
# and DENY makes the stub ls refuse them.

mkdir -p "$T/deny/store"
for d in com.apple.mail com.apple.Passwords com.apple.TextEdit; do
  mkdir -p "$T/deny/home/Library/Containers/$d/Data/Library/Preferences"
done
/usr/bin/defaults write "$T/deny/store/com.apple.mail" AddressesIncludeNameOnPasteboard -bool false
/usr/bin/defaults write "$T/deny/store/com.apple.Passwords" showMenuBarExtra -bool false
export DENY="com.apple.mail com.apple.Passwords"
ROOT=$K run deny --check
denied_rows=$'com.apple.mail\tAddressesIncludeNameOnPasteboard\tfalse\t\tnoaccess\ncom.apple.Passwords\tshowMenuBarExtra\tfalse\t\tnoaccess\ncom.apple.Passwords\tEnableMenuBarExtra\tfalse\t\tnoaccess'
if [[ $RC == 0 && "$(grep $'\tnoaccess$' "$T/deny/out" | sort)" == "$(sort <<<"$denied_rows")" ]] \
   && grep -qx $'com.apple.TextEdit\tRichText\t0\t\tnodomain' "$T/deny/out"; then
  ok "--check: a key in a container this process may not read is noaccess, with no value, though a read would find one; a readable container with no domain is still nodomain"
else
  fail "--check with Mail and Passwords denied: exit $RC"; grep -E $'\t(noaccess|nodomain)$' "$T/deny/out" >&2
fi
ROOT=$K run deny
if [[ $RC == 0 ]] && ! writes deny | grep -qE '^com\.apple\.(mail|Passwords)'$'\t' \
   && ! grep -qE 'com\.apple\.(mail|Passwords) ' "$T/deny/home/.mrk/defaults-rollback.sh" \
   && grep -q 'com.apple.Passwords showMenuBarExtra (macOS does not let this process read its app' "$T/deny/err" \
   && grep -q '3 key(s) passed over' "$T/deny/err" && grep -q 'Full Disk Access' "$T/deny/err"; then
  ok "a run passes over the three keys, with no write and no undo line, and says to give Full Disk Access"
else
  fail "a run with Mail and Passwords denied: exit $RC"; writes deny | grep -E '^com\.apple\.(mail|Passwords)' >&2; tail -3 "$T/deny/err" >&2
fi
n=$(calls deny)
ROOT=$K run deny --key com.apple.Passwords showMenuBarExtra
rc_key=$RC
ROOT=$K run deny --skip com.apple.Passwords showMenuBarExtra --revert com.apple.Passwords showMenuBarExtra
if [[ $rc_key == 1 && $RC == 1 ]] && ! since deny "$n" | grep -qE '^(write|delete|killall)' \
   && cmp -s "$SK" "$T/skip.orig" && grep -q 'cannot change com.apple.Passwords showMenuBarExtra' "$T/deny/err" \
   && grep -q 'Nothing was changed' "$T/deny/err"; then
  ok "--key and --revert refuse a key this process may not read, and the skip list stays as it was"
else
  fail "--key or --revert on a denied key: exit $rc_key and $RC"; tail -3 "$T/deny/err" >&2
fi
ROOT=$K run deny --skip com.apple.Passwords showMenuBarExtra
if [[ $RC == 0 ]] && grep -qx $'com.apple.Passwords\tshowMenuBarExtra' "$SK"; then
  ok "--skip alone changes only the list, so it takes a key this process may not read"
else
  fail "--skip of a denied key: exit $RC"; tail -2 "$T/deny/err" >&2
fi
cp "$T/skip.orig" "$SK"
unset DENY
(( fails == 0 ))
