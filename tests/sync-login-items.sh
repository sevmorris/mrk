#!/usr/bin/env bash
# sync-login-items.sh — prove that sync-login-items reads back exactly what it
# writes, for login items with awkward names.
#
# sync-login-items rewrites the add_login_item block in scripts/post-install and
# a sentence in docs/manual.md through embedded Python. On 2026-09-18 a first
# write was already right, but reading it back was not: an app named with $ or
# a backtick came back with its escaping backslash, one with a double quote was
# not recognised at all, and an accented name spelled one way by System Events
# and another by the file system never matched. Each was re-added on every run.
#
# Everything runs against a copy of the repository, under a throwaway HOME.
# osascript is a stub that prints the login items from a fixture, and gum is a
# stub that selects every choice. gum is called with </dev/tty, so the script
# runs inside a pseudo-terminal from script(1). No System Events query is made,
# so there is no Automation prompt. ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

for tool in python3 script; do
  command -v "$tool" >/dev/null 2>&1 || { fail "$tool not found"; exit 1; }
done

W="$(mktemp -d "${TMPDIR:-/tmp}/sli.XXXXXX")"
trap 'rm -rf "$W"' EXIT
R="$W/repo"
mkdir -p "$R/scripts" "$R/docs" "$W/home" "$W/stubs"
cp -p "$REPO_ROOT/scripts/sync-login-items" "$REPO_ROOT/scripts/lib.sh" \
      "$REPO_ROOT/scripts/post-install" "$R/scripts/"
cp -p "$REPO_ROOT/docs/manual.md" "$R/docs/"
cp -p "$R/scripts/post-install" "$W/post-install.orig"
cp -p "$R/docs/manual.md" "$W/manual.orig"

cat > "$W/stubs/osascript" <<'EOF'
#!/bin/bash
cat "$FIXTURE"
EOF
cat > "$W/stubs/gum" <<'EOF'
#!/bin/bash
# `gum choose [flags] choices...`: select every choice.
shift
for a in "$@"; do [[ "$a" == --* ]] || printf '%s\n' "$a"; done
EOF
chmod +x "$W/stubs/osascript" "$W/stubs/gum"

# sli FIXTURE — run sync-login-items against that fixture; output in $W/out
sli() {
  FIXTURE="$1" HOME="$W/home" PATH="$W/stubs:$PATH" \
    script -q /dev/null bash "$R/scripts/sync-login-items" </dev/null 2>&1 \
    | tr -d '\r' | sed 's/\x1b\[[0-9;]*m//g' > "$W/out"
}

nfd() { python3 -c 'import sys, unicodedata; print(unicodedata.normalize("NFD", sys.argv[1]), end="")' "$1"; }

# The items post-install tracks now, listed the way System Events lists them.
BASE="$W/base"
grep -E '^add_login_item "' "$W/post-install.orig" \
  | sed -E 's/^add_login_item "([^"]+)".*/\1/' \
  | while IFS= read -r p; do n="${p##*/}"; printf '%s\t%s\n' "${n%.app}" "$p"; done > "$BASE"

AWKWARD="$W/awkward"
{
  printf '%s\t%s\n' "Magic Backup Machine" "/Applications/Magic Backup Machine.app"
  printf '%s\t%s\n' 'Say "Hi"'             '/Applications/Say "Hi".app'
  # shellcheck disable=SC2016  # a literal $ in an app name is the point
  printf '%s\t%s\n' 'Cash $App'            '/Applications/Cash $App.app'
  printf '%s\t%s\n' 'Tick`Tock'            '/Applications/Tick`Tock.app'
  printf '%s\t%s\n' "Joe's App"            "/Applications/Joe's App.app"
  printf '%s\t%s\n' "Foo, Inc"             "/Applications/Foo, Inc.app"
  printf '%s\t%s\n' "Back\\slash"          "/Applications/Back\\slash.app"
  printf '%s\t%s\n' "Café Noir"            "/Applications/Café Noir.app"
  # System Events composed and the path decomposed, then the other way round
  printf '%s\t%s\n' "Crème"                "/Applications/$(nfd "Crème").app"
  printf '%s\t%s\n' "$(nfd "Über")"        "/Applications/Über.app"
  printf '%s\t%s\n' "Helper"               "/Users/Shared/Applications/Helper.app"
  printf '%s\t%s\n' "Deep Helper"          "/Library/Application Support/Vendor/Deep Helper.app"
} > "$AWKWARD"
n_awkward=$(wc -l < "$AWKWARD" | tr -d ' ')
cat "$BASE" "$AWKWARD" > "$W/all"

# 1. Add every awkward item.
sli "$W/all"
if grep -q "Updated post-install: $n_awkward added, 0 removed" "$W/out"; then
  pass "all $n_awkward awkward names are offered and added"
else
  fail "adding the awkward names: $(grep -E 'Updated|Warning|✗' "$W/out" | head -3)"
fi

if bash -n "$R/scripts/post-install"; then
  pass "post-install still parses"
else
  fail "post-install no longer parses"
fi

# Each generated line, run by bash, must hand add_login_item its exact path.
grep -E '^add_login_item ' "$R/scripts/post-install" > "$W/lines"
bash -c 'add_login_item() { printf "%s\n" "$1"; }; failed=0; source "$1"' _ "$W/lines" \
  | sort > "$W/got"
cut -f2 "$W/all" | sort > "$W/want"
if cmp -s "$W/want" "$W/got"; then
  pass "every generated line gives bash back its exact path"
else
  fail "generated lines give back different paths:"
  diff "$W/want" "$W/got" | sed 's/^/      /' >&2
fi

if grep -qF "Tick\`Tock" "$R/docs/manual.md" && grep -qF 'Say "Hi"' "$R/docs/manual.md"; then
  pass "the manual's login-items sentence names them as written"
else
  fail "the manual's login-items sentence: $(grep -F 'Login items:**' "$R/docs/manual.md")"
fi

# 2. Nothing changed on the system, so nothing may change in the repository.
cp -p "$R/scripts/post-install" "$W/post-install.after-add"
sli "$W/all"
if grep -q 'Login items are up to date' "$W/out" \
   && cmp -s "$R/scripts/post-install" "$W/post-install.after-add"; then
  pass "a second run over the same items finds nothing to do"
else
  fail "a second run over the same items is not a no-op:"
  grep -E '^\s+[+-] ' "$W/out" | sed 's/^/      /' >&2
fi

# 3. Remove them again.
sli "$BASE"
if grep -q "Updated post-install: 0 added, $n_awkward removed" "$W/out"; then
  pass "all $n_awkward are recognised as tracked, and removed"
else
  fail "removing them: $(grep -E 'Updated|Warning|✗' "$W/out" | head -3)"
fi
if cmp -s "$R/scripts/post-install" "$W/post-install.orig" && cmp -s "$R/docs/manual.md" "$W/manual.orig"; then
  pass "post-install and the manual are back byte for byte"
else
  fail "post-install or the manual differs from where it started"
fi

sli "$BASE"
if grep -q 'Login items are up to date' "$W/out"; then
  pass "and a last run finds nothing to do"
else
  fail "the last run was not a no-op: $(grep -E '^\s+[+-] ' "$W/out" | tr '\n' ' ')"
fi

(( fails == 0 ))
