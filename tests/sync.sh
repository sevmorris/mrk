#!/usr/bin/env bash
# sync.sh — prove that sync files each new package where it belongs and writes
# its picker description, so an add leaves check-picker-desc green.
#
# Until 2026-09-27 sync put every cask in the one cask section and wrote no
# description at all, so each add turned the gate red until someone described
# the package by hand: `sync: add prismlauncher`, then `picker: describe
# prismlauncher`. sync now reads Homebrew's description, and files a cask by the
# category its app declares in its Info.plist. It also proves that sync --check,
# which mrk-status reads, prints the drift and nothing else, and that
# --check --details adds the section and the description after those fields.
# Then the decisions a program makes with no terminal, for Barkeep: --add,
# --ignore and --prune with a name write what the picker's answers would, start
# neither the picker nor gum, and refuse what the picker would not offer.
#
# Everything runs against a copy of the repository, under a throwaway HOME whose
# ~/Applications holds fake apps. brew is a stub named by MRK_BREW that prints
# the installed lists and `brew info --json=v2` from fixtures, mrk-picker is a
# stub that selects every candidate, gum a stub that picks GUM_CHOICE, and uname
# a stub that says Darwin. gum is called with </dev/tty, so sync runs inside a
# pseudo-terminal from script(1). Nothing is installed. ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

for tool in python3 script git; do
  command -v "$tool" >/dev/null 2>&1 || { fail "$tool not found"; exit 1; }
done

W="$(mktemp -d "${TMPDIR:-/tmp}/sync.XXXXXX")"
trap 'rm -rf "$W"' EXIT
R="$W/repo"
FIX="$W/fixtures"
mkdir -p "$R/scripts" "$R/tools/picker" "$R/bin" "$W/home/Applications" "$W/stubs" "$FIX/info"
cp -p "$REPO_ROOT/scripts/sync" "$REPO_ROOT/scripts/lib.sh" "$R/scripts/"
cp -p "$REPO_ROOT/Brewfile" "$R/"
cp -p "$REPO_ROOT/tools/picker/descriptions.tsv" "$R/tools/picker/"
TABLE="$R/tools/picker/descriptions.tsv"
git -C "$R" init -q
git -C "$R" config user.name "sync test"
git -C "$R" config user.email "sync-test@example.invalid"
git -C "$R" add -A
git -C "$R" commit -qm "fixture"

# ── Stubs ────────────────────────────────────────────────────────────────────

cat > "$W/stubs/brew" <<'EOF'
#!/bin/bash
case "$1" in
  shellenv) ;;
  leaves)   cat "$FIX/leaves" ;;
  list)     if [[ "$2" == --cask ]]; then cat "$FIX/casks"; else cat "$FIX/formulae"; fi ;;
  info)     f="$FIX/info/${!#}.json"
            if [[ -f "$f" ]]; then cat "$f"; else echo "Error: No available formula or cask with the name \"${!#}\"." >&2; exit 1; fi ;;
  *)        echo "brew stub: unexpected: $*" >&2; exit 1 ;;
esac
EOF
cat > "$R/bin/mrk-picker" <<'EOF'
#!/bin/bash
# `mrk-picker --brewfile FILE ...`: select every package FILE lists, or none
# with PICKER_NONE set. With NO_UI set, record the start in that file and fail.
[[ -n "${NO_UI:-}" ]] && { echo "mrk-picker $*" >> "$NO_UI"; exit 97; }
[[ -n "${PICKER_NONE:-}" ]] && exit 0
while (($#)); do [[ "$1" == --brewfile ]] && { f="$2"; shift; }; shift; done
sed -nE 's/^brew "([^"]+)".*/formula:\1/p; s/^cask "([^"]+)".*/cask:\1/p' "$f"
EOF
cat > "$W/stubs/gum" <<'EOF'
#!/bin/bash
# `gum choose [flags] choices...`: GUM_CHOICE when offered, else the first.
# With NO_UI set, record the start in that file and fail.
[[ -n "${NO_UI:-}" ]] && { echo "gum $*" >> "$NO_UI"; exit 97; }
cmd="$1"; shift
[[ "$cmd" == choose ]] || exit 0
choices=()
for a in "$@"; do [[ "$a" == --* ]] || choices+=("$a"); done
for c in "${choices[@]}"; do [[ "$c" == "${GUM_CHOICE:-}" ]] && { printf '%s\n' "$c"; exit 0; }; done
printf '%s\n' "${choices[0]}"
EOF
cat > "$W/stubs/uname" <<'EOF'
#!/bin/bash
echo Darwin
EOF
chmod +x "$W/stubs/brew" "$R/bin/mrk-picker" "$W/stubs/gum" "$W/stubs/uname"

# ── Fixtures ─────────────────────────────────────────────────────────────────

# Homebrew's view of each new package, and the apps on disk. zq-ledger's
# Info.plist is binary, as many shipped apps' are. zq-studio installs its app
# under a target name. zq-pkgapp and zq-driver install through a pkg, so no app
# artifact names their bundle; zq-pkgapp's app is found by its display name.
python3 - "$FIX/info" "$W/home/Applications" <<'PY'
import json, os, plistlib, sys
info_dir, apps = sys.argv[1:3]

def cask(token, name, desc, artifacts):
    json.dump({'formulae': [], 'casks': [{'token': token, 'full_token': token, 'name': [name],
               'desc': desc, 'artifacts': artifacts}]}, open(f'{info_dir}/{token}.json', 'w'))

def formula(name, desc):
    json.dump({'formulae': [{'name': name, 'full_name': name, 'desc': desc}], 'casks': []},
              open(f'{info_dir}/{name}.json', 'w'))

def app(name, category=None, binary=False):
    os.makedirs(f'{apps}/{name}/Contents')
    plist = {'CFBundleName': name[:-4]}
    if category:
        plist['LSApplicationCategoryType'] = category
    with open(f'{apps}/{name}/Contents/Info.plist', 'wb') as f:
        plistlib.dump(plist, f, fmt=plistlib.FMT_BINARY if binary else plistlib.FMT_XML)

cask('zq-launcher', 'Zq Launcher', 'Minecraft launcher', [{'app': ['Zq Launcher.app']}, {'zap': [{'trash': '~/x'}]}])
app('Zq Launcher.app', 'public.app-category.role-playing-games')
cask('zq-ledger', 'Zq Ledger', 'Personal finance tracker', [{'app': ['Zq Ledger.app']}])
app('Zq Ledger.app', 'public.app-category.finance', binary=True)
cask('zq-studio', 'Zq Studio Pro', 'Edits "quoted" paths like C:\\temp',
     [{'app': ['ZqStudio-2.1.app', {'target': 'Zq Studio.app'}]}])
app('Zq Studio.app', 'public.app-category.music')
cask('zq-plain', 'Zq Plain', 'Plain utility', [{'app': ['Zq Plain.app']}])
app('Zq Plain.app')
cask('zq-pkgapp', 'Zq Pkg App', 'Video thing', [{'pkg': ['ZqPkgApp.pkg']}])
app('Zq Pkg App.app', 'public.app-category.video')
cask('zq-driver', 'Zq Driver', 'Driver for Zq devices', [{'pkg': ['ZqDriver.pkg']}])
formula('zqtool', 'Zq command-line tool')
formula('zzmedia', 'Zz media converter')

# The second run's edge cases.
cask('zq-nodesc', 'Zq NoDesc', None, [{'app': ['Zq NoDesc.app']}])
cask('zq-kept', 'Zq Kept', 'Homebrew words', [{'app': ['Zq Kept.app']}])
PY

# installed NEW... — the Brewfile's packages plus the new ones
installed() {
  { sed -nE 's/^brew "([^"]+)".*/\1/p' "$R/Brewfile"; printf '%s\n' "${@:1:$#-1}"; } > "$FIX/leaves"
  cp "$FIX/leaves" "$FIX/formulae"
  { sed -nE 's/^cask "([^"]+)".*/\1/p' "$R/Brewfile"; tr ' ' '\n' <<< "${!#}"; } > "$FIX/casks"
}

# run_sync ARGS... — output in $W/out. From HOME, not the repository, as sync
# is run.
run_sync() {
  cd "$W/home" || return 1
  local cmd=(env HOME="$W/home" PATH="$W/stubs:$PATH" MRK_BREW="$W/stubs/brew" FIX="$FIX"
             GUM_CHOICE="${GUM_CHOICE:-}" PICKER_NONE="${PICKER_NONE:-}" bash "$R/scripts/sync" "$@")
  # BSD script(1), on macOS, takes the command after the file; util-linux's takes -c.
  if [[ "$(uname -s)" == Darwin ]]; then
    script -q /dev/null "${cmd[@]}" </dev/null
  else
    script -qec "$(printf '%q ' "${cmd[@]}")" /dev/null </dev/null
  fi 2>&1 | tr -d '\r' | sed 's/\x1b\[[0-9;]*m//g' > "$W/out"
}

# section_of NAME — the ## section the Brewfile lists NAME under
section_of() {
  awk -v want="$1" '/^## /{s=substr($0,4)} $0 ~ "^(brew|cask) \""want"\"" {print s; exit}' "$R/Brewfile"
}

# desc_of NAME — NAME's description in the table, or nothing
desc_of() { awk -F'\t' -v n="$1" '!/^#/ && $1 == n { print $2; exit }' "$TABLE"; }

# The gate's rule, portably: every Brewfile package described, nothing extra.
descriptions_in_sync() {
  python3 - "$R/Brewfile" "$TABLE" <<'PY'
import re, sys
pkgs = set(re.findall(r'^(?:brew|cask) "([^"]+)"', open(sys.argv[1]).read(), re.M))
keys = {l.split('\t', 1)[0] for l in open(sys.argv[2]) if '\t' in l and not l.startswith('#')}
for n in sorted(pkgs - keys): print('  missing:', n)
for n in sorted(keys - pkgs): print('  orphaned:', n)
sys.exit(pkgs != keys)
PY
}

expect_section() {
  local got; got="$(section_of "$1")"
  if [[ "$got" == "$2" ]]; then pass "$1 is filed under $2"; else fail "$1 is under '${got:-nothing}', want '$2'"; fi
}
expect_desc() {
  local got; got="$(desc_of "$1")"
  if [[ "$got" == "$2" ]]; then pass "$1 is described as: $2"; else fail "$1 is described as '${got:-nothing}', want '$2'"; fi
}

NEW_CASKS="zq-driver zq-launcher zq-ledger zq-pkgapp zq-plain zq-studio"
installed zqtool zzmedia "$NEW_CASKS"
export GUM_CHOICE="CLI Tools - Media"

# 1. A dry run shows the filing and the descriptions, and writes nothing.
run_sync -n
if git -C "$R" diff --quiet; then
  pass "a dry run leaves the Brewfile and the description table alone"
else
  fail "a dry run changed: $(git -C "$R" diff --name-only | tr '\n' ' ')"
fi
if grep -qF '+ cask "zq-launcher", greedy: true  →  Casks - Games  (Zq Launcher.app declares public.app-category.role-playing-games)' "$W/out" \
   && grep -qF '"Minecraft launcher"' "$W/out"; then
  pass "a dry run names each cask's section, the reason and the description"
else
  fail "the dry run's summary:"; sed 's/^/      /' "$W/out" >&2
fi

# 2. The real run, committing.
run_sync -c

expect_section zq-launcher "Casks - Games"
expect_section zq-ledger   "Casks - Finance"
expect_section zq-studio   "Casks - Audio"
expect_section zq-pkgapp   "Casks - Video"
expect_section zq-plain    "Casks - Utilities"
expect_section zq-driver   "Casks - Utilities"
expect_section zqtool      "CLI Tools - Media"
expect_section zzmedia     "CLI Tools - Media"

headers="$(grep '^## Casks - ' "$R/Brewfile")"
if [[ "$headers" == "$(sort <<< "$headers")" ]] && grep -qx '## Casks - Finance' <<< "$headers"; then
  pass "the new Finance section sits in alphabetical order among the cask sections"
else
  fail "cask sections out of order: $(tr '\n' '|' <<< "$headers")"
fi

# The formulae sort after every Media entry, so they must land below yt-dlp and
# above the comment that introduces the cask sections, in name order.
if [[ "$(grep -A3 '^brew "yt-dlp"' "$R/Brewfile")" == "$(printf '%s\n' 'brew "yt-dlp"' 'brew "zqtool"' 'brew "zzmedia"' '')" ]]; then
  pass "formulae sorting last land after the section's last entry, above the cask comment"
else
  fail "the end of the Media section reads:"; grep -A4 '^brew "yt-dlp"' "$R/Brewfile" | sed 's/^/      /' >&2
fi
if grep -qE '^cask "zq-[a-z]+", greedy: true$' "$R/Brewfile" && ! grep -qE '^cask "zq-[a-z]+"$' "$R/Brewfile"; then
  pass "every new cask carries greedy: true"
else
  fail "a new cask went in without greedy: true"
fi

expect_desc zq-launcher "Minecraft launcher"
expect_desc zq-ledger   "Personal finance tracker"
expect_desc zq-studio   'Zq Studio Pro — Edits "quoted" paths like C:\temp'
expect_desc zq-pkgapp   "Video thing"
expect_desc zq-driver   "Driver for Zq devices"
expect_desc zqtool      "Zq command-line tool"

# Formulae and casks by one rule: every line in byte order of the name, below
# the header the table had.
if [[ "$(sed -n '/^#/!q;p' "$TABLE")" == "$(sed -n '/^#/!q;p' "$REPO_ROOT/tools/picker/descriptions.tsv")" ]] \
   && grep -v '^#' "$TABLE" | LC_ALL=C sort -c 2>/dev/null; then
  pass "the new descriptions sit in byte order of their names, below the header"
else
  fail "the table's header changed, or its lines are out of order:"
  grep -v '^#' "$TABLE" | LC_ALL=C sort -c 2>&1 | sed 's/^/      /' >&2
fi
if [[ -z "$(find "$R/tools/picker" -name '.descriptions.tsv.*')" && "$(/usr/bin/stat -f '%Lp' "$TABLE")" == 644 ]]; then
  pass "sync leaves no temp file beside the table, and the table's mode 644"
else
  fail "sync left: $(find "$R/tools/picker" -name '.descriptions.tsv.*' | tr '\n' ' '), mode $(/usr/bin/stat -f '%Lp' "$TABLE")"
fi

if out="$(descriptions_in_sync)"; then
  pass "every package in the Brewfile has a description, as check-picker-desc requires"
else
  fail "descriptions out of step with the Brewfile:"; printf '%s\n' "$out" >&2
fi

subject="$(git -C "$R" log -1 --format=%s)"
files="$(git -C "$R" show --name-only --format= HEAD | sort | tr '\n' ' ')"
# ", " between the names: until 2026-09-28 IFS=', ' joined on the comma alone
# (audit 19, W-18), and this check expected it.
if [[ "$subject" == "sync: add zq-driver, zq-launcher, zq-ledger, zq-pkgapp, zq-plain, zq-studio, zqtool, zzmedia" \
      && "$files" == "Brewfile tools/picker/descriptions.tsv " ]] && git -C "$R" diff --quiet; then
  pass "-c commits the Brewfile and the description table together"
else
  fail "the commit: '$subject' with: $files"
fi

# 3. Nothing new is installed, so nothing may change.
run_sync -c
if grep -q 'Brewfile is up to date' "$W/out" && [[ "$(git -C "$R" log -1 --format=%s)" == "$subject" ]]; then
  pass "a second run finds nothing to add"
else
  fail "a second run was not a no-op:"; sed "s/^/      /" "$W/out" >&2
fi

# 4. A cask Homebrew cannot describe, one it has no record of, and one whose
#    description was already written by hand.
awk '!done && !/^#/ && $1 > "zq-kept" { print "zq-kept\tHand-written words"; done = 1 } { print }' \
  "$TABLE" > "$TABLE.new" && mv "$TABLE.new" "$TABLE"
mkdir -p "$W/home/Applications/Zq Kept.app"
installed zqtool zzmedia "$NEW_CASKS zq-nodesc zq-ghost zq-kept"
run_sync

expect_section zq-nodesc "Casks - Utilities"
expect_section zq-ghost  "Casks - Utilities"
expect_desc    zq-kept   "Hand-written words"
if grep -q 'Homebrew has no description for: zq-ghost zq-nodesc' "$W/out" \
   && grep -qF 'zq-ghost", greedy: true  →  Casks - Utilities  (Homebrew has no record of it)' "$W/out"; then
  pass "a package Homebrew cannot describe is named, and still added"
else
  fail "the warnings:"; grep -E '⚠|zq-ghost|zq-nodesc' "$W/out" | sed 's/^/      /' >&2
fi
if [[ -z "$(desc_of zq-nodesc)$(desc_of zq-ghost)" ]]; then
  pass "sync writes no description it does not have"
else
  fail "sync invented a description"
fi

# 5. sync -p -c: a stale entry pruned, then the additions declined. The prune
#    must still be committed. Until 2026-09-28 sync stopped at "No packages
#    selected" before its commit step, and left the Brewfile and main.go
#    changed and uncommitted (audit 19, W-18).
git -C "$R" reset -q --hard
STALE="$(sed -nE 's/^cask "([^"]+)".*/\1/p' "$R/Brewfile" | grep -v '^zq-' | head -1)"
sed -nE 's/^brew "([^"]+)".*/\1/p' "$R/Brewfile" > "$FIX/leaves"
cp "$FIX/leaves" "$FIX/formulae"
{ sed -nE 's/^cask "([^"]+)".*/\1/p' "$R/Brewfile" | grep -vxF "$STALE"; echo zq-kept; } > "$FIX/casks"
before="$(git -C "$R" rev-parse HEAD)"
PICKER_NONE=1 run_sync -p -c
subject="$(git -C "$R" log -1 --format=%s)"
if [[ "$(git -C "$R" rev-parse HEAD)" != "$before" && "$subject" == "sync: remove $STALE" ]] \
   && git -C "$R" diff --quiet && ! grep -q "^cask \"$STALE\"" "$R/Brewfile" && grep -q 'No packages selected' "$W/out"; then
  pass "sync -p -c, the additions declined: the prune of $STALE is committed"
else
  fail "sync -p -c, the additions declined: last commit '$subject'; uncommitted: $(git -C "$R" diff --name-only | tr '\n' ' ')"
  grep -E 'No packages|Committed|stale|Stale' "$W/out" | sed 's/^/      /' >&2
fi
files="$(git -C "$R" show --name-only --format= HEAD | sort | tr '\n' ' ')"
if [[ -z "$(desc_of "$STALE")" && "$files" == "Brewfile tools/picker/descriptions.tsv " ]]; then
  pass "the prune deletes $STALE's description, and commits the table with the Brewfile"
else
  fail "after the prune $STALE is described as '$(desc_of "$STALE")', and the commit holds: $files"
fi

# 6. sync --check: the drift alone, for mrk-status. A new formula and cask, one
#    package sync-ignore names, and a Brewfile entry no longer installed. Only
#    the list on stdout, sorted within each kind, the ignored package absent,
#    and nothing written. Then a failing brew list: exit 1 and no list, never
#    an empty one, which mrk-status would read as "no drift".
git -C "$R" reset -q --hard
STALE="$(sed -nE 's/^brew "([^"]+)".*/\1/p' "$R/Brewfile" | head -1)"
{ sed -nE 's/^brew "([^"]+)".*/\1/p' "$R/Brewfile" | grep -vxF "$STALE"; printf 'zq-check-two\nzq-check-one\nzq-ignored-tool\n'; } > "$FIX/leaves"
cp "$FIX/leaves" "$FIX/formulae"
{ sed -nE 's/^cask "([^"]+)".*/\1/p' "$R/Brewfile"; echo zq-check-cask; } > "$FIX/casks"
mkdir -p "$W/home/.mrk"
printf '# test\nzq-ignored-tool\n' > "$W/home/.mrk/sync-ignore"
check_sync() {
  (cd "$W/home" && env HOME="$W/home" PATH="$W/stubs:$PATH" MRK_BREW="$W/stubs/brew" FIX="$FIX" \
    bash "$R/scripts/sync" --check "$@" > "$W/check.out" 2> "$W/check.err")
}
check_sync; rc=$?
want="$(printf 'add\tformula\tzq-check-one\nadd\tformula\tzq-check-two\nadd\tcask\tzq-check-cask\nprune\tformula\t%s' "$STALE")"
if (( rc == 0 )) && [[ "$(cat "$W/check.out")" == "$want" ]] && git -C "$R" diff --quiet \
   && grep -q 'Scanning installed Homebrew packages' "$W/check.err"; then
  pass "sync --check prints the drift alone, sync-ignore honoured, and changes nothing"
else
  fail "sync --check: rc $rc, stdout:"; sed 's/^/      /' "$W/check.out" >&2
  git -C "$R" diff --stat | sed 's/^/      /' >&2
fi

# on_tty OUT CMD... — CMD with stdout in OUT and stderr on a terminal from
# script(1), as a run from Terminal has it, so lib.sh turns its colours on.
# OUT.tty exists afterwards when stderr was a terminal. Until 2026-10-29 every
# --check here ran with stderr in a file (audit 22, Z-13).
on_tty() {
  local out=$1; shift
  rm -f "$out" "$out.tty"
  # shellcheck disable=SC2016  # expanded by the inner bash
  script -q /dev/null bash -c '[[ -t 2 ]] && : > "$1.tty"; exec > "$1"; shift; exec "$@"' _ "$out" "$@" </dev/null > "$out.term" 2>&1
}
# same_on_tty OUT WANT — OUT is WANT, stderr was a terminal, and OUT holds no
# escape character
same_on_tty() {
  [[ -e "$1.tty" ]] && [[ "$(cat "$1")" == "$2" ]] && ! LC_ALL=C grep -q $'\033' "$1"
}
(cd "$W/home" && on_tty "$W/check.tty" env HOME="$W/home" PATH="$W/stubs:$PATH" MRK_BREW="$W/stubs/brew" FIX="$FIX" \
  bash "$R/scripts/sync" --check)
if same_on_tty "$W/check.tty" "$want" && LC_ALL=C grep -q $'\033\\[' "$W/check.tty.term"; then
  pass "sync --check with stderr on a terminal: the same drift, the colours on stderr alone"
else
  fail "sync --check with stderr on a terminal:"; sed 's/^/      /' "$W/check.tty" >&2
fi
check_sync -c -p; rc=$?
if (( rc == 0 )) && [[ "$(cat "$W/check.out")" == "$want" ]] && git -C "$R" diff --quiet; then
  pass "--check takes precedence: with -c and -p it still writes and commits nothing"
else
  fail "sync --check -c -p: rc $rc, uncommitted: $(git -C "$R" diff --name-only | tr '\n' ' ')"
fi
mv "$FIX/formulae" "$FIX/formulae.ok"
check_sync; rc=$?
mv "$FIX/formulae.ok" "$FIX/formulae"
if (( rc == 1 )) && [[ ! -s "$W/check.out" ]] && grep -q 'brew list --formula failed' "$W/check.err"; then
  pass "sync --check with a failing brew list: exit 1, no list, and the reason on stderr"
else
  fail "sync --check with a failing brew list: rc $rc, stdout: $(tr '\n' ';' < "$W/check.out")"
fi

# ── 7. Decisions on the command line ─────────────────────────────────────────
#
# What Barkeep runs in place of the picker: one package a run, no terminal.
# No pseudo-terminal here, stdin is /dev/null, and the picker and gum stubs
# record any start in $W/ui and fail, so a decision that reached for either
# shows up there.
git -C "$R" reset -q --hard
python3 - "$FIX/info" "$W/home/Applications" <<'PY'
import json, os, plistlib, sys
info_dir, apps = sys.argv[1:3]
def app(name, category):
    os.makedirs(f'{apps}/{name}/Contents')
    with open(f'{apps}/{name}/Contents/Info.plist', 'wb') as f:
        plistlib.dump({'CFBundleName': name[:-4], 'LSApplicationCategoryType': category}, f)
def write(name, formulae=(), casks=()):
    json.dump({'formulae': list(formulae), 'casks': list(casks)}, open(f'{info_dir}/{name}.json', 'w'))
def f(name, desc): return {'name': name, 'full_name': name, 'desc': desc}
def c(token, name, desc): return {'token': token, 'full_token': token, 'name': [name], 'desc': desc,
                                  'artifacts': [{'app': [name + '.app']}]}
write('zq-chess', casks=[c('zq-chess', 'Zq Chess', 'Chess against the clock')])
app('Zq Chess.app', 'public.app-category.board-games')
write('zq-both', formulae=[f('zq-both', 'Both, the formula')], casks=[c('zq-both', 'Zq Both', 'Both, the cask')])
app('Zq Both.app', 'public.app-category.utilities')
write('zq-dec-tool', formulae=[f('zq-dec-tool', 'Decides things')])
write('zq-later', formulae=[f('zq-later', 'Later things in C:\\later')])
PY

# zq-twin is a formula and a cask in the Brewfile, sharing one description;
# only the formula is installed, so the cask is the one to prune.
python3 - "$R/Brewfile" <<'PY'
import sys
p = sys.argv[1]
lines = open(p).read().split('\n')
def after(entry, line):
    i = lines.index(entry)
    lines.insert(i + 1, line)
after('brew "xcodegen"', 'brew "zq-twin"')
last_util = max(i for i, l in enumerate(lines) if l.startswith('cask "') and
                max(j for j in range(i) if lines[j].startswith('## ')) ==
                lines.index('## Casks - Utilities'))
lines.insert(last_util + 1, 'cask "zq-twin", greedy: true')
open(p, 'w').write('\n'.join(lines))
PY
printf 'zq-twin\tTwin words\n' > "$W/twin.tsv"
picker_add_descriptions "$TABLE" "$W/twin.tsv"
git -C "$R" commit -qam "fixture: zq-twin"

STALE_F="$(sed -nE 's/^brew "([^"]+)".*/\1/p' "$R/Brewfile" | head -1)"
STALE_C="$(sed -nE 's/^cask "([^"]+)".*/\1/p' "$R/Brewfile" | grep -v '^zq-' | head -1)"
# decision_world — the installed lists for this section: the Brewfile less one
# stale formula and two stale casks, plus the new packages.
decision_world() {
  { sed -nE 's/^brew "([^"]+)".*/\1/p' "$R/Brewfile" | grep -vxF "$STALE_F"
    printf '%s\n' zq-both zq-dec-tool zq-later zq-ignored-tool; } | sort -u > "$FIX/leaves"
  { cat "$FIX/leaves"; echo zq-dep; } > "$FIX/formulae"
  { sed -nE 's/^cask "([^"]+)".*/\1/p' "$R/Brewfile" | grep -vxF -e "$STALE_C" -e zq-twin
    printf '%s\n' zq-both zq-chess; } | sort -u > "$FIX/casks"
}
decision_world
printf '# test\nzq-ignored-tool\n' > "$W/home/.mrk/sync-ignore"

# decide ARGS... — sync with no terminal. Output in $W/decide.out and
# $W/decide.err, the exit status in $rc.
decide() {
  rc=0
  (cd "$W/home" && env HOME="$W/home" PATH="$W/stubs:$PATH" MRK_BREW="$W/stubs/brew" FIX="$FIX" NO_UI="$W/ui" \
    bash "$R/scripts/sync" "$@" </dev/null >"$W/decide.out" 2>"$W/decide.err") || rc=$?
}
# unchanged — the repository as last committed, and no picker or gum started.
unchanged() { git -C "$R" diff --quiet && [[ ! -e "$W/ui" ]]; }
# expect_refusal RC WHAT PATTERN ARGS... — sync exits RC, says PATTERN on
# stderr, and changes nothing.
expect_refusal() {
  local want=$1 what=$2 pattern=$3
  shift 3
  decide "$@"
  if (( rc == want )) && grep -qiE "$pattern" "$W/decide.err" && unchanged; then
    pass "$what: exit $want, nothing changed"
  else
    fail "$what (sync $*): exit $rc, want $want; stderr:"; sed 's/^/      /' "$W/decide.err" >&2
    git -C "$R" diff --stat | sed 's/^/      /' >&2
  fi
}

# Malformed command lines: exit 2, before Homebrew is asked anything.
expect_refusal 2 "an unknown option"                   'Unknown option'        --frob
expect_refusal 2 "an unknown option with --check"      'Unknown option'        --check --frob
expect_refusal 2 "--add with no name"                  'needs a package name'  --add
expect_refusal 2 "two decisions in one run"            'one decision per run'  --add zq-dec-tool --ignore zq-later
expect_refusal 2 "--details without --check"           'only with --check'     --details
expect_refusal 2 "--section without --add"             'only with --add'       --section "Repo essentials"
expect_refusal 2 "--formula and --cask together"       'not both'              --add zq-both --formula --cask
expect_refusal 2 "a name Homebrew could not spell"     'Not a package name'    --add 'zq tool'
expect_refusal 2 "a formula into a cask section"       'not a formula section' --add zq-dec-tool --section "## Casks - Audio"
expect_refusal 2 "a formula into Taps"                 'not a formula section' --add zq-dec-tool --section Taps
expect_refusal 2 "the picker's --prune with a decision" 'does not combine'     -p --add zq-dec-tool

# --check --details: the three fields mrk-status reads, then the section, why,
# and the description the table will hold. Plain --check keeps three fields.
# zq-later's description holds a backslash, which the line escapes as \\.
decide --check --details
TAB=$'\t'
want="$(cat <<EOF
add${TAB}formula${TAB}zq-both${TAB}${TAB}${TAB}Both, the formula
add${TAB}formula${TAB}zq-dec-tool${TAB}${TAB}${TAB}Decides things
add${TAB}formula${TAB}zq-later${TAB}${TAB}${TAB}Later things in C:\\\\later
add${TAB}cask${TAB}zq-both${TAB}Casks - Utilities${TAB}Zq Both.app declares public.app-category.utilities${TAB}Both, the cask
add${TAB}cask${TAB}zq-chess${TAB}Casks - Games${TAB}Zq Chess.app declares public.app-category.board-games${TAB}Chess against the clock
prune${TAB}formula${TAB}${STALE_F}${TAB}$(section_of "$STALE_F")${TAB}${TAB}$(desc_of "$STALE_F")
prune${TAB}cask${TAB}${STALE_C}${TAB}$(section_of "$STALE_C")${TAB}${TAB}$(desc_of "$STALE_C")
prune${TAB}cask${TAB}zq-twin${TAB}Casks - Utilities${TAB}${TAB}Twin words
EOF
)"
if (( rc == 0 )) && [[ "$(cat "$W/decide.out")" == "$want" ]] && unchanged; then
  pass "--check --details adds the section, why, and the description, and changes nothing"
else
  fail "--check --details: rc $rc, got:"; diff <(printf '%s\n' "$want") "$W/decide.out" | sed 's/^/      /' >&2
fi
decide --check
if (( rc == 0 )) && [[ -s "$W/decide.out" ]] && awk -F'\t' 'NF != 3 { bad = 1 } END { exit bad }' "$W/decide.out" \
   && [[ "$(cut -f1-3 <<< "$want")" == "$(cat "$W/decide.out")" ]]; then
  pass "plain --check keeps the three fields mrk-status reads"
else
  fail "plain --check:"; sed 's/^/      /' "$W/decide.out" >&2
fi

# Refusals: what the picker would not have offered.
expect_refusal 1 "--add a formula with no --section"   'does not guess'            --add zq-dec-tool
expect_refusal 1 "--add a name that is both kinds"     'both a formula and a cask' --add zq-both
expect_refusal 1 "--add a cask with --section"         'Leave out --section'       --add zq-chess --section "Repo essentials"
expect_refusal 1 "--add a name sync-ignore lists"      'sync-ignore'               --add zq-ignored-tool --section "Repo essentials"
expect_refusal 1 "--add a dependency"                  'only as a dependency'      --add zq-dep --section "Repo essentials"
expect_refusal 1 "--add an entry the Brewfile has"     'already in the Brewfile'   --add zq-twin --section "Repo essentials"
expect_refusal 1 "--add a package not installed"       'does not list'             --add zq-nowhere --cask
expect_refusal 1 "--add a kind it is not"              'does not list'             --add zq-chess --formula --section "Repo essentials"

# --add, a cask: filed by its app's category, greedy, described, in name order.
decide --add zq-chess
if (( rc == 0 )) && [[ ! -e "$W/ui" ]]; then
  pass "--add runs without a terminal and starts neither the picker nor gum"
else
  fail "--add zq-chess: rc $rc, started: $(cat "$W/ui" 2>/dev/null)"; sed 's/^/      /' "$W/decide.err" >&2
fi
expect_section zq-chess "Casks - Games"
expect_desc    zq-chess "Chess against the clock"
games="$(awk '/^## /{s=$0} s == "## Casks - Games" && /^cask "/' "$R/Brewfile")"
if grep -qx 'cask "zq-chess", greedy: true' <<< "$games" && [[ "$games" == "$(LC_ALL=C sort <<< "$games")" ]]; then
  pass "--add puts the cask in name order among its section's entries, with greedy: true"
else
  fail "the Games section reads:"; awk '{ print "      " $0 }' <<< "$games" >&2
fi
git -C "$R" commit -qam "sync: add zq-chess"

# --add, a formula, with -n and then -c.
decide --add zq-dec-tool --section "## Repo essentials" -n
if (( rc == 0 )) && grep -qF '+ brew "zq-dec-tool"  →  Repo essentials' "$W/decide.out" && unchanged; then
  pass "--add -n shows the section and the description, and writes nothing"
else
  fail "--add -n: rc $rc"; sed 's/^/      /' "$W/decide.out" "$W/decide.err" >&2
fi
decide --add zq-dec-tool --section "## Repo essentials" -c
subject="$(git -C "$R" log -1 --format=%s)"
files="$(git -C "$R" show --name-only --format= HEAD | sort | tr '\n' ' ')"
if (( rc == 0 )) && [[ "$(grep -A1 -x 'brew "xcodegen"' "$R/Brewfile")" == "$(printf '%s\n' 'brew "xcodegen"' 'brew "zq-dec-tool"')" ]] \
   && [[ "$subject" == "sync: add zq-dec-tool" && "$files" == "Brewfile tools/picker/descriptions.tsv " ]] && unchanged; then
  pass "--add --section -c files the formula in name order and commits it with its description"
else
  fail "--add --section -c: rc $rc, commit '$subject' with: $files"; sed 's/^/      /' "$W/decide.err" >&2
fi
expect_desc zq-dec-tool "Decides things"
decide --add zq-both --cask -n
if (( rc == 0 )) && grep -qF '+ cask "zq-both", greedy: true  →  Casks - Utilities' "$W/decide.out" && unchanged; then
  pass "--cask settles a name that is both kinds"
else
  fail "--add zq-both --cask -n: rc $rc"; sed 's/^/      /' "$W/decide.out" "$W/decide.err" >&2
fi
decide --add zq-later --section "Zq Tools" -n
if (( rc == 0 )) && grep -q "no '## Zq Tools' section yet" "$W/decide.err" && unchanged; then
  pass "--section with a name no section has says that sync starts the section"
else
  fail "--add --section 'Zq Tools' -n: rc $rc"; sed 's/^/      /' "$W/decide.err" >&2
fi
if out="$(descriptions_in_sync)"; then
  pass "after the decisions every package in the Brewfile has a description"
else
  fail "descriptions out of step with the Brewfile:"; printf '%s\n' "$out" >&2
fi

# --ignore: appends, keeps the comments, mends a missing last newline.
IGN="$W/home/.mrk/sync-ignore"
printf '# test\n\nzq-ignored-tool  # kept by hand' > "$IGN"
decide --ignore zq-both
if (( rc == 0 )) && [[ "$(cat "$IGN")" == "$(printf '# test\n\nzq-ignored-tool  # kept by hand\nzq-both')" ]] && unchanged; then
  pass "--ignore adds the name at the end, keeps the comments, and needs no kind for a name that is both"
else
  fail "--ignore zq-both: rc $rc, the file reads:"; sed 's/^/      /' "$IGN" >&2
fi
cp "$IGN" "$W/ign.before"
decide --ignore zq-both
if (( rc == 0 )) && cmp -s "$IGN" "$W/ign.before" && grep -q 'already in' "$W/decide.err"; then
  pass "--ignore a name already listed: exit 0, the file unchanged"
else
  fail "--ignore zq-both again: rc $rc"; diff "$W/ign.before" "$IGN" | sed 's/^/      /' >&2
fi
decide --ignore zq-later -n
if (( rc == 0 )) && cmp -s "$IGN" "$W/ign.before"; then
  pass "--ignore -n writes nothing"
else
  fail "--ignore -n: rc $rc"; diff "$W/ign.before" "$IGN" | sed 's/^/      /' >&2
fi
expect_refusal 1 "--ignore an entry the Brewfile has" 'already in the Brewfile' --ignore zq-chess
decide --check
if ! grep -q 'zq-both' "$W/decide.out"; then
  pass "an ignored name leaves --check"
else
  fail "--check still lists zq-both after --ignore"
fi
rm -f "$IGN"
decide --ignore zq-later
if (( rc == 0 )) && [[ "$(grep -v '^#' "$IGN")" == zq-later ]] && grep -q '^# mrk sync ignore list' "$IGN"; then
  pass "--ignore creates the ignore file, with its header, when there is none"
else
  fail "--ignore with no file: rc $rc"; sed 's/^/      /' "$IGN" >&2
fi

# --prune: one stale entry, and its description unless another entry uses it.
expect_refusal 1 "--prune an installed package"     'is installed'          --prune zq-chess
expect_refusal 1 "--prune a name not in the Brewfile" 'has no'              --prune zq-nowhere
expect_refusal 1 "--prune a kind the Brewfile lacks" 'has no formula entry' --prune "$STALE_C" --formula
decide --prune "$STALE_C" -n
if (( rc == 0 )) && grep -q "Would remove 1 description" "$W/decide.out" && unchanged; then
  pass "--prune -n names the entry and its description, and writes nothing"
else
  fail "--prune -n: rc $rc"; sed 's/^/      /' "$W/decide.out" "$W/decide.err" >&2
fi
decide --prune "$STALE_C" -c
subject="$(git -C "$R" log -1 --format=%s)"
if (( rc == 0 )) && [[ "$subject" == "sync: remove $STALE_C" && -z "$(desc_of "$STALE_C")" ]] \
   && ! grep -q "^cask \"$STALE_C\"" "$R/Brewfile" && unchanged; then
  pass "--prune -c deletes the entry and its description, and commits both"
else
  fail "--prune -c: rc $rc, commit '$subject'"; sed 's/^/      /' "$W/decide.err" >&2
fi
decide --prune zq-twin -c
if (( rc == 0 )) && [[ "$(desc_of zq-twin)" == "Twin words" ]] && grep -qx 'brew "zq-twin"' "$R/Brewfile" \
   && ! grep -q '^cask "zq-twin"' "$R/Brewfile" && unchanged; then
  pass "--prune keeps a description the formula of the same name still uses"
else
  fail "--prune zq-twin: rc $rc, described as '$(desc_of zq-twin)'"; sed 's/^/      /' "$W/decide.err" >&2
fi
mv "$FIX/casks" "$FIX/casks.ok"
expect_refusal 1 "--prune when brew list fails" 'brew list --cask failed' --prune "$STALE_F"
mv "$FIX/casks.ok" "$FIX/casks"
mv "$FIX/formulae" "$FIX/formulae.ok"; mv "$FIX/casks" "$FIX/casks.ok"
: > "$FIX/formulae"; : > "$FIX/casks"
expect_refusal 1 "--prune when Homebrew reports nothing installed" 'refusing to prune' --prune "$STALE_F"
# --check takes precedence over -p there too, and shows every entry as prune.
check_sync -p; rc=$?
if (( rc == 0 )) && grep -q $'^prune\tformula\t' "$W/check.out" && ! grep -q 'refusing to prune' "$W/check.err"; then
  pass "--check -p with nothing installed: exit 0, the lines shown, nothing refused"
else
  fail "sync --check -p with nothing installed: rc $rc"; sed 's/^/      /' "$W/check.err" >&2
fi
mv "$FIX/formulae.ok" "$FIX/formulae"; mv "$FIX/casks.ok" "$FIX/casks"
if awk -F'\t' '!/^#/ { print $1 }' "$TABLE" | LC_ALL=C sort -c 2>/dev/null && out="$(descriptions_in_sync)"; then
  pass "after the prunes the table is in order and in step with the Brewfile"
else
  fail "after the prunes:"; printf '%s\n' "${out:-the table is out of order}" >&2
fi

if (( fails > 0 )); then
  err "sync: $fails check(s) failed"
  exit 1
fi
ok "sync: all checks passed"
