#!/usr/bin/env bash
# check-picker-desc.sh — prove that a package added or removed through Barkeep
# leaves check-picker-desc passing once mrk-push or pushall has committed it.
#
# sync writes a package's mrk-picker description as it adds the package, and
# deletes it as it prunes. Barkeep adds and removes Brewfile lines and writes no
# description, so until 2026-09-27 every Barkeep add turned CI red until someone
# described the package by hand. check-picker-desc --fix now describes it in
# Homebrew's words and deletes the orphans, and mrk-push and pushall run it
# before they commit a changed Brewfile.
#
# Everything runs against copies of this repository's Brewfile and main.go, in
# throwaway repositories whose pushes go to local bares. brew is a stub named by
# MRK_BREW that answers `brew info --json=v2` from fixtures, and gh a stub that
# refuses to run. Nothing is installed. ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

for tool in python3 git gofmt; do
  command -v "$tool" >/dev/null 2>&1 || { fail "$tool not found"; exit 1; }
done

# The developer's git config sets color.ui=always, which would colour the
# output this test reads, and may sign commits. The sandbox needs neither, and
# must never stop to ask for a password.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_TERMINAL_PROMPT=0

W="$(mktemp -d "${TMPDIR:-/tmp}/check-picker-desc.XXXXXX")"
trap 'rm -rf "$W"' EXIT
BREW_FIXTURES="$W/fixtures"
mkdir -p "$W/stubs" "$BREW_FIXTURES/info"

# ── Stubs and fixtures ───────────────────────────────────────────────────────

cat > "$W/stubs/brew" <<'EOF'
#!/bin/bash
# `brew info --json=v2 --formula|--cask NAME`, from $BREW_FIXTURES/info/NAME.json.
[[ "$1" == shellenv ]] && exit 0
[[ "$1" == info ]] || { echo "brew stub: unexpected: $*" >&2; exit 1; }
f="$BREW_FIXTURES/info/${!#}.json"
if [[ -f "$f" ]]; then cat "$f"; else echo "Error: No available formula or cask with the name \"${!#}\"." >&2; exit 1; fi
EOF
printf '#!/bin/sh\necho "check-picker-desc.sh: gh must not be called" >&2\nexit 97\n' > "$W/stubs/gh"
chmod +x "$W/stubs/brew" "$W/stubs/gh"
# Not FIX: check-picker-desc has a FIX of its own, and would hand the stub that.
export BREW_FIXTURES MRK_BREW="$W/stubs/brew"

python3 - "$BREW_FIXTURES/info" <<'PY'
import json, sys
d = sys.argv[1]
def cask(token, name, desc):
    json.dump({'formulae': [], 'casks': [{'token': token, 'full_token': token, 'name': [name],
               'desc': desc, 'artifacts': [{'app': [name + '.app']}]}]}, open(f'{d}/{token}.json', 'w'))
def formula(name, desc):
    json.dump({'formulae': [{'name': name, 'full_name': name, 'desc': desc}], 'casks': []},
              open(f'{d}/{name}.json', 'w'))
cask('zq-adopted', 'Zq Adopted', 'Menu bar tidier')
cask('zq-studio', 'Zq Studio Pro', 'Edits "quoted" paths like C:\\temp')
cask('zq-nodesc', 'Zq NoDesc', None)
formula('zqtool', 'Zq command-line tool')
PY

# mkrepo DIR — a repository holding copies of what check-picker-desc, mrk-push
# and pushall need, with one commit pushed to DIR.git, its origin.
mkrepo() {
  local d=$1
  mkdir -p "$d/scripts" "$d/bin" "$d/tools/picker"
  cp -p "$REPO_ROOT/scripts/check-picker-desc" "$REPO_ROOT/scripts/lib.sh" "$d/scripts/"
  cp -p "$REPO_ROOT/bin/mrk-push" "$REPO_ROOT/bin/pushall" "$d/bin/"
  cp -p "$REPO_ROOT/Brewfile" "$d/"
  cp -p "$REPO_ROOT/tools/picker/main.go" "$d/tools/picker/"
  git init -q --bare -b main "$d.git"
  git init -q -b main "$d"
  git -C "$d" config user.name "check-picker-desc test"
  git -C "$d" config user.email "check-picker-desc-test@example.invalid"
  git -C "$d" add -A
  git -C "$d" commit -qm fixture
  git -C "$d" remote add origin "$d.git"
  git -C "$d" push -q -u origin main 2>/dev/null
}

# barkeep_add DIR KIND NAME SECTION — what BrewfileViewModel.add() writes: the
# bare canonical line after the last entry of SECTION, or at the end under a
# new `# SECTION` when no entry is in it. "Adopt" adds through the same path,
# under Adopted.
barkeep_add() {
  python3 - "$1/Brewfile" "$2" "$3" "$4" <<'PY'
import re, sys
path, kind, name, section = sys.argv[1:5]
lines = open(path).read().split('\n')
if lines and lines[-1] == '':
    lines.pop()
entry = f'{kind} "{name}"'
current, last = None, None
for i, l in enumerate(lines):
    if l.startswith('#'):
        body = l.lstrip('#').strip()
        if body:
            current = body
    elif re.match(r'^(brew|cask|tap) "', l) and current == section:
        last = i
if last is None:
    lines += ['', f'# {section}', entry]
else:
    lines.insert(last + 1, entry)
open(path, 'w').write('\n'.join(lines) + '\n')
PY
}

# barkeep_remove DIR KIND NAME — what "Remove from Brewfile" does.
barkeep_remove() {
  python3 - "$1/Brewfile" "$2" "$3" <<'PY'
import sys
path, kind, name = sys.argv[1:4]
lines = open(path).read().split('\n')
open(path, 'w').write('\n'.join(l for l in lines
    if not l.startswith(f'{kind} "{name}"')))
PY
}

# descs FILE — every description in main.go, as `name<TAB>description`, unescaped.
descs() {
  python3 - "$1" <<'PY'
import ast, re, sys
for k, v in re.findall(r'^\t"([^"]+)":\s*(".*"),$', open(sys.argv[1]).read(), re.M):
    print(f'{k}\t{ast.literal_eval(v)}')
PY
}
desc_of() { descs "$2/tools/picker/main.go" | awk -F'\t' -v k="$1" '$1 == k { print $2 }'; }
expect_desc() {  # expect_desc DIR NAME WANT
  local got; got="$(desc_of "$2" "$1")"
  if [[ "$got" == "$3" ]]; then pass "$2 is described as: $3"; else fail "$2 is described as '${got:-nothing}', want '$3'"; fi
}

# A cask to remove: the first one whose name no formula shares, since a shared
# name keeps its description while either entry remains.
GONE="$(python3 - "$REPO_ROOT/Brewfile" <<'PY'
import re, sys
s = open(sys.argv[1]).read()
f = set(re.findall(r'^brew "([^"]+)"', s, re.M))
print(next(c for c in re.findall(r'^cask "([^"]+)"', s, re.M) if c not in f))
PY
)"

# barkeep_session DIR — the edits one sitting in Barkeep makes: adopt a cask,
# add a formula and a cask into the sections the Brewfile already has, and
# remove a cask.
barkeep_session() {
  barkeep_add "$1" cask zq-adopted Adopted
  barkeep_add "$1" brew zqtool "CLI Tools - Media"
  barkeep_add "$1" cask zq-studio "Casks - Audio"
  barkeep_remove "$1" cask "$GONE"
}

# ── 1. check-picker-desc and --fix ───────────────────────────────────────────
log "check-picker-desc --fix"

R="$W/repo"
mkrepo "$R"
descs "$R/tools/picker/main.go" > "$W/before"
barkeep_session "$R"

rc=0; "$R/scripts/check-picker-desc" >"$W/check.log" 2>&1 || rc=$?
if (( rc == 1 )) && grep -qx '  zq-adopted' "$W/check.log" && grep -qx '  zqtool' "$W/check.log" \
   && grep -qx '  zq-studio' "$W/check.log" && grep -qx "  $GONE" "$W/check.log" \
   && grep -q 'check-picker-desc --fix describes the missing' "$W/check.log"; then
  pass "the check fails on Barkeep's edits, names each package, and points at --fix"
else
  fail "the check exited $rc and said:"; sed 's/^/      /' "$W/check.log" >&2
fi
if git -C "$R" diff --quiet -- tools/picker/main.go; then
  pass "the check without --fix writes nothing"
else
  fail "the check without --fix changed main.go"
fi

rc=0; "$R/scripts/check-picker-desc" --fix >"$W/fix.log" 2>&1 || rc=$?
if (( rc == 0 )) && grep -q 'OK (' "$W/fix.log"; then
  pass "--fix exits 0 and the check it runs again passes"
else
  fail "--fix exited $rc and said:"; sed 's/^/      /' "$W/fix.log" >&2
fi
expect_desc "$R" zq-adopted "Menu bar tidier"
expect_desc "$R" zqtool     "Zq command-line tool"
expect_desc "$R" zq-studio  'Zq Studio Pro — Edits "quoted" paths like C:\temp'
if [[ -z "$(desc_of "$GONE" "$R")" ]]; then
  pass "the removed cask's description is deleted ($GONE)"
else
  fail "the removed cask's description is still there ($GONE)"
fi

# Every other description is exactly as it was: --fix writes only what is absent.
descs "$R/tools/picker/main.go" > "$W/after"
changed="$(diff <(awk -F'\t' '$1 != "zq-adopted" && $1 != "zqtool" && $1 != "zq-studio"' "$W/after") \
               <(awk -F'\t' -v gone="$GONE" '$1 != gone' "$W/before") 2>&1)"
if [[ -z "$changed" ]]; then
  pass "no other description changed"
else
  fail "other descriptions changed:"; printf '%s\n' "$changed" | sed 's/^/      /' >&2
fi

order="$(awk -F'"' '/^\t\/\/ Casks/ { print "CASKS"; next } /^\t"(zqtool|zq-adopted|zq-studio)":/ { print $2 }' \
         "$R/tools/picker/main.go" | tr '\n' ' ')"
if [[ "$order" == "zqtool CASKS zq-adopted zq-studio " ]]; then
  pass "the formula closes the formulae block, the casks sit in name order"
else
  fail "main.go order: $order"
fi
if [[ -z "$(gofmt -l "$R/tools/picker/main.go" 2>&1)" ]]; then
  pass "main.go is gofmt-clean and parses"
else
  fail "gofmt: $(gofmt -l "$R/tools/picker/main.go" 2>&1)"
fi
if [[ -z "$(find "$R/tools/picker" -name '.main.go.*')" ]]; then
  pass "--fix leaves no temp file beside main.go"
else
  fail "--fix left: $(find "$R/tools/picker" -name '.main.go.*' | tr '\n' ' ')"
fi
if "$R/scripts/check-picker-desc" >/dev/null 2>&1; then
  pass "check-picker-desc passes after --fix"
else
  fail "check-picker-desc still fails after --fix"
fi

cp "$R/tools/picker/main.go" "$W/main.go.fixed"
"$R/scripts/check-picker-desc" --fix >/dev/null 2>&1
if cmp -s "$R/tools/picker/main.go" "$W/main.go.fixed"; then
  pass "a second --fix changes nothing"
else
  fail "a second --fix rewrote main.go"
fi

# ── 2. What --fix cannot settle ──────────────────────────────────────────────
log "check-picker-desc --fix: the refusals"

barkeep_add "$R" cask zq-nodesc Adopted
barkeep_add "$R" cask zq-ghost Adopted
rc=0; "$R/scripts/check-picker-desc" --fix >"$W/nodesc.log" 2>&1 || rc=$?
if (( rc == 1 )) && grep -q 'Homebrew has no description for: zq-ghost zq-nodesc' "$W/nodesc.log" \
   && [[ -z "$(desc_of zq-nodesc "$R")$(desc_of zq-ghost "$R")" ]]; then
  pass "a package Homebrew cannot describe is named, left undescribed, and --fix exits 1"
else
  fail "--fix exited $rc on packages Homebrew cannot describe:"; sed 's/^/      /' "$W/nodesc.log" >&2
fi
barkeep_remove "$R" cask zq-nodesc
barkeep_remove "$R" cask zq-ghost

cp "$R/tools/picker/main.go" "$W/main.go.keep"
barkeep_add "$R" cask zq-adopted2 Adopted
rc=0; MRK_BREW="$W/stubs/no-such-brew" "$R/scripts/check-picker-desc" --fix >"$W/nobrew.log" 2>&1 || rc=$?
if (( rc == 1 )) && grep -q 'needs Homebrew' "$W/nobrew.log" && cmp -s "$R/tools/picker/main.go" "$W/main.go.keep"; then
  pass "--fix without Homebrew exits 1 and writes nothing"
else
  fail "--fix without Homebrew exited $rc:"; sed 's/^/      /' "$W/nobrew.log" >&2
fi
barkeep_remove "$R" cask zq-adopted2

printf 'brew  "zq-spaced"\n' >> "$R/Brewfile"
rc=0; "$R/scripts/check-picker-desc" --fix >"$W/unparsable.log" 2>&1 || rc=$?
if (( rc == 1 )) && grep -q 'mrk cannot parse' "$W/unparsable.log" && cmp -s "$R/tools/picker/main.go" "$W/main.go.keep"; then
  pass "--fix refuses a Brewfile line mrk cannot parse, as the check does, and writes nothing"
else
  fail "--fix on an unparsable line exited $rc:"; sed 's/^/      /' "$W/unparsable.log" >&2
fi

rc=0; "$R/scripts/check-picker-desc" --fxi >/dev/null 2>&1 || rc=$?
if (( rc == 2 )); then pass "an unknown argument exits 2"; else fail "an unknown argument exited $rc"; fi

# ── 3. mrk-push ──────────────────────────────────────────────────────────────
log "mrk-push after a Barkeep session"

# pushed DIR — a fresh clone of what DIR pushed, with its check run on it.
pushed() {
  rm -rf "$W/clone"
  git clone -q "$1.git" "$W/clone" 2>/dev/null && "$W/clone/scripts/check-picker-desc" >/dev/null 2>&1
}

# mrk-push parses origin as a GitHub remote, so origin names one and pushes to
# the bare. Nothing here fetches.
M="$W/mp"
mkrepo "$M"
git -C "$M" remote set-url origin https://github.com/example/mrk.git
git -C "$M" remote set-url --push origin "$M.git"
barkeep_session "$M"
b="$(git -C "$M.git" rev-parse main)"
rc=0; ( cd "$M" && PATH="$W/stubs:$PATH" HOME="$W/home" bin/mrk-push --dry-run ) >"$W/mp-dry.log" 2>&1 || rc=$?
if (( rc == 0 )) && git -C "$M" diff --quiet -- tools/picker/main.go && [[ "$(git -C "$M.git" rev-parse main)" == "$b" ]] \
   && grep -q 'A real run runs check-picker-desc --fix' "$W/mp-dry.log"; then
  pass "mrk-push --dry-run reports the missing descriptions and writes nothing"
else
  fail "mrk-push --dry-run exited $rc:"; sed 's/^/      /' "$W/mp-dry.log" >&2
fi

rc=0; ( cd "$M/tools" && PATH="$W/stubs:$PATH" HOME="$W/home" "$M/bin/mrk-push" "Barkeep edits" ) >"$W/mp.log" 2>&1 || rc=$?
files="$(git -C "$M.git" show --name-only --format= main | sort | tr '\n' ' ')"
if (( rc == 0 )) && [[ "$files" == "Brewfile tools/picker/main.go " ]]; then
  pass "mrk-push commits the descriptions with the Brewfile"
else
  fail "mrk-push exited $rc and committed: $files"; sed 's/^/      /' "$W/mp.log" >&2
fi
if pushed "$M"; then
  pass "check-picker-desc passes on what mrk-push pushed"
else
  fail "check-picker-desc fails on what mrk-push pushed"
fi

# ── 4. pushall ───────────────────────────────────────────────────────────────
# pushall sweeps the mrk it lives in, so this copy of it sweeps this repository.
# An empty ~/Projects in a throwaway HOME leaves mrk the only thing it touches.
log "pushall after a Barkeep session"

P="$W/pa"
mkrepo "$P"
mkdir -p "$W/pa-home/Projects"
barkeep_session "$P"
rc=0; PATH="$W/stubs:$PATH" HOME="$W/pa-home" "$P/bin/pushall" >"$W/pa.log" 2>&1 || rc=$?
files="$(git -C "$P.git" show --name-only --format= main | sort | tr '\n' ' ')"
if (( rc == 0 )) && [[ "$files" == "Brewfile tools/picker/main.go " ]]; then
  pass "pushall commits mrk's descriptions with its Brewfile"
else
  fail "pushall exited $rc and committed: $files"; sed 's/^/      /' "$W/pa.log" >&2
fi
if pushed "$P"; then
  pass "check-picker-desc passes on what pushall pushed"
else
  fail "check-picker-desc fails on what pushall pushed"
fi

if grep -q 'gh must not be called' "$W"/*.log; then
  fail "gh was called — the sandbox leaked"
fi

printf '\n' >&2
if (( fails > 0 )); then
  err "check-picker-desc: $fails check(s) failed"
  exit 1
fi
ok "check-picker-desc: all checks passed"
