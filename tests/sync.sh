#!/usr/bin/env bash
# sync.sh — prove that sync files each new package where it belongs and writes
# its picker description, so an add leaves check-picker-desc green.
#
# Until 2026-09-27 sync put every cask in the one cask section and wrote no
# description at all, so each add turned the gate red until someone described
# the package by hand: `sync: add prismlauncher`, then `picker: describe
# prismlauncher`. sync now reads Homebrew's description, and files a cask by the
# category its app declares in its Info.plist. It also proves that sync --check,
# which mrk-status reads, prints the drift and nothing else.
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
cp -p "$REPO_ROOT/tools/picker/main.go" "$R/tools/picker/"
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
# with PICKER_NONE set.
[[ -n "${PICKER_NONE:-}" ]] && exit 0
while (($#)); do [[ "$1" == --brewfile ]] && { f="$2"; shift; }; shift; done
sed -nE 's/^brew "([^"]+)".*/formula:\1/p; s/^cask "([^"]+)".*/cask:\1/p' "$f"
EOF
cat > "$W/stubs/gum" <<'EOF'
#!/bin/bash
# `gum choose [flags] choices...`: GUM_CHOICE when offered, else the first.
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

# desc_of NAME — NAME's description in main.go, unescaped, or nothing
desc_of() {
  python3 - "$R/tools/picker/main.go" "$1" <<'PY'
import ast, re, sys
m = re.search(r'^\t"' + re.escape(sys.argv[2]) + r'":\s*(".*"),$', open(sys.argv[1]).read(), re.M)
print(ast.literal_eval(m.group(1)) if m else '', end='')
PY
}

# The gate's rule, portably: every Brewfile package described, nothing extra.
descriptions_in_sync() {
  python3 - "$R/Brewfile" "$R/tools/picker/main.go" <<'PY'
import re, sys
pkgs = set(re.findall(r'^(?:brew|cask) "([^"]+)"', open(sys.argv[1]).read(), re.M))
keys = set(re.findall(r'^\t"([^"]+)":', open(sys.argv[2]).read(), re.M))
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
  pass "a dry run leaves the Brewfile and main.go alone"
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

# Formulae before the "// Casks" marker, casks after it in name order.
order="$(awk -F'"' '/^\t\/\/ Casks/ { print "CASKS"; next }
  /^\t"(flac|zqtool|zzmedia|zoom|zq-driver|zq-launcher|zq-ledger)":/ { print $2 }' "$R/tools/picker/main.go" | tr '\n' ' ')"
if [[ "$order" == "flac zqtool zzmedia CASKS zoom zq-driver zq-launcher zq-ledger " ]]; then
  pass "formula descriptions close the formulae block, casks sit in name order"
else
  fail "main.go order: $order"
fi

if command -v gofmt >/dev/null 2>&1; then
  if [[ -z "$(gofmt -l "$R/tools/picker/main.go" 2>&1)" ]]; then
    pass "main.go is gofmt-clean and parses"
  else
    fail "gofmt: $(gofmt -l "$R/tools/picker/main.go" 2>&1)"
  fi
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
      && "$files" == "Brewfile tools/picker/main.go " ]] && git -C "$R" diff --quiet; then
  pass "-c commits the Brewfile and main.go together"
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
python3 - "$R/tools/picker/main.go" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
open(p, 'w').write(s.replace('\t// Casks\n', '\t// Casks\n\t"zq-kept": "Hand-written words",\n', 1))
PY
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

if (( fails > 0 )); then
  err "sync: $fails check(s) failed"
  exit 1
fi
ok "sync: all checks passed"
