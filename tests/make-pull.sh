#!/usr/bin/env bash
# make-pull.sh — prove that make pull rebuilds and relinks what the commits it
# pulled changed, and nothing else.
#
# Until 2026-09-30 make pull only fast-forwarded. A pull that changed tools/
# left the old Go binaries in ~/bin, one that added a script left it off the
# PATH, and one that added a dotfile left it unlinked, each until the matching
# make target was run by hand. check-updates and update-full both pull through
# it, so neither did any of this either.
#
# Each case commits to a scratch origin and runs make pull in a clone of it
# under a throwaway HOME, the checkout MRK_ROOT names, so setup links from it.
# go is a stub that records the build and writes a placeholder binary; sudo,
# defaults, osascript, launchctl, chsh and open are stubs that run nothing, and
# uname says Darwin.
# Nothing reaches the real HOME, ~/bin, the network or any preferences.
# setup runs under /bin/bash and under the bash running this file; make runs
# every recipe under /bin/bash. ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" != --inner ]]; then
  run_under() {
    # shellcheck disable=SC2016  # expanded by the inner bash, not this one
    printf '  under bash %s\n' "$("$1" -c 'echo "${BASH_VERSION%%(*}"')"
    "$1" "${BASH_SOURCE[0]}" --inner "$1"
  }
  rc=0
  run_under /bin/bash || rc=1
  if [[ ! "$BASH" -ef /bin/bash ]]; then run_under "$BASH" || rc=1; fi
  exit "$rc"
fi
BASH_UNDER_TEST="$2"

# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

REAL_GIT="$(command -v git)" || { fail "git not found"; exit 1; }
REAL_MAKE="$(command -v make)" || { fail "make not found"; exit 1; }

W=$(mrk_mktemp_d) || exit 1
W=$(cd "$W" && pwd -P)
trap 'rm -rf "$W"' EXIT
H="$W/home"       # the throwaway HOME
S="$W/stubs"      # first on PATH
ORIGIN="$W/origin.git"
UP="$W/upstream"  # where the cases commit, then push to ORIGIN
CLONE="$H/mrk"    # the checkout make pull runs in, and MRK_ROOT
mkdir -p "$H" "$S" "$UP"
: > "$W/calls"   # every stub call, across all the cases

# ── Stubs ────────────────────────────────────────────────────────────────────

for cmd in sudo defaults osascript launchctl chsh open; do
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "%s/calls"\n' "$cmd" "$W" > "$S/$cmd"
  chmod +x "$S/$cmd"
done
# go build -ldflags ... -o BINARY . — record the build, write BINARY.
cat > "$S/go" <<EOF
#!/bin/sh
out=""
while [ \$# -gt 0 ]; do
  [ "\$1" = -o ] && { out="\$2"; shift; }
  shift
done
printf 'go build %s\n' "\${out##*/}" >> "$W/go-builds"
[ -n "\$out" ] && printf '#!/bin/sh\n' > "\$out"
exit 0
EOF
chmod +x "$S/go"
# setup refuses anything but macOS. On a Mac this is what uname says anyway; it
# lets the test run on Linux too.
cat > "$S/uname" <<'EOF'
#!/bin/sh
echo Darwin
EOF
chmod +x "$S/uname"
ln -s "$BASH_UNDER_TEST" "$S/bash"
ln -s "$REAL_GIT" "$S/git"
ln -s "$REAL_MAKE" "$S/make"

run_env() {
  env -i HOME="$H" MRK_ROOT="$CLONE" PATH="$S:/usr/bin:/bin:/usr/sbin:/sbin" \
    TMPDIR="${TMPDIR:-/tmp}" TERM=dumb \
    GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 \
    GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test.invalid \
    GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test.invalid \
    "$@"
}

# ── The scratch origin: the repository's tracked files, as they are now ──────

while IFS= read -r -d '' f; do
  [[ -f "$REPO_ROOT/$f" ]] || continue
  mkdir -p "$UP/$(dirname "$f")"
  cp -p "$REPO_ROOT/$f" "$UP/$f"
done < <(git -C "$REPO_ROOT" ls-files -z Makefile scripts bin dotfiles tools docs/manual.md)
run_env git -C "$UP" init -q -b main
run_env git -C "$UP" add -A
run_env git -C "$UP" commit -qm seed
run_env git clone -q --bare "$UP" "$ORIGIN"
run_env git -C "$UP" remote add origin "$ORIGIN"
run_env git clone -q "$ORIGIN" "$CLONE" || { fail "could not clone the scratch origin"; exit 1; }
mkdir -p "$H/bin"

# commit_upstream MESSAGE — commit what the case changed in $UP, push it
commit_upstream() {
  run_env git -C "$UP" add -A &&
    run_env git -C "$UP" commit -qm "$1" &&
    run_env git -C "$UP" push -q origin main
}

# pull [MAKE ARGS] — make pull in the clone; its output in $W/out
pull() {
  : > "$W/go-builds"
  run_env make -C "$CLONE" pull "$@" > "$W/out" 2>&1
}

builds() { wc -l < "$W/go-builds" | tr -d ' '; }

# ── 1. Nothing new: nothing built or linked ──────────────────────────────────

if pull && [[ "$(builds)" == 0 && -z "$(ls -A "$H/bin")" ]]; then
  pass "up to date: nothing built, nothing linked"
else
  fail "up to date: expected no build and an empty ~/bin"; sed 's/^/    /' "$W/out"
fi

# ── 2. A docs-only pull: nothing built or linked ─────────────────────────────

printf '\nA line.\n' >> "$UP/docs/manual.md"
commit_upstream "docs only"
if pull && [[ "$(builds)" == 0 && -z "$(ls -A "$H/bin")" ]] \
   && [[ -z "$(find "$H" -maxdepth 1 -type l)" ]]; then
  pass "docs-only pull: nothing built, nothing linked"
else
  fail "docs-only pull: expected no build and no links"; sed 's/^/    /' "$W/out"
fi

# ── 3. tools/ changed: every Go tool rebuilt and linked ──────────────────────

printf '\n// A change.\n' >> "$UP/tools/mrk-menu/main.go"
commit_upstream "tools"
if pull; then
  got=$(sort "$W/go-builds" | tr '\n' ' ')
  if [[ "$got" == "go build mrk-menu go build mrk-picker go build mrk-status " ]]; then
    pass "tools/ pull: mrk-menu, mrk-picker and mrk-status rebuilt"
  else
    fail "tools/ pull: builds were: ${got:-none}"
  fi
  linked=1
  for n in mrk-menu mrk-picker mrk-status status; do
    [[ "$(readlink "$H/bin/$n")" == "$CLONE/bin/"* ]] || linked=0
  done
  if (( linked )); then
    pass "tools/ pull: the binaries linked into ~/bin"
  else
    fail "tools/ pull: ~/bin holds: $(find "$H/bin" -mindepth 1 -maxdepth 1 -exec basename {} \; | tr '\n' ' ')"
  fi
else
  fail "tools/ pull: make pull failed"; sed 's/^/    /' "$W/out"
fi

# ── 4. tools/ changed, PULL_BUILD=0: nothing built ───────────────────────────

printf '\n// Another.\n' >> "$UP/tools/mrk-menu/main.go"
commit_upstream "tools again"
if pull PULL_BUILD=0 && [[ "$(builds)" == 0 ]] && grep -q 'PULL_BUILD=0' "$W/out"; then
  pass "PULL_BUILD=0: the rebuild skipped, and said so"
else
  fail "PULL_BUILD=0: expected no build and a note"; sed 's/^/    /' "$W/out"
fi

# ── 5. A script added: linked into ~/bin ─────────────────────────────────────

printf '#!/usr/bin/env bash\necho hello\n' > "$UP/scripts/pull-test-cmd"
chmod +x "$UP/scripts/pull-test-cmd"
commit_upstream "add a script"
if pull && [[ "$(readlink "$H/bin/pull-test-cmd")" == "$CLONE/scripts/pull-test-cmd" \
             && -x "$H/bin/pull-test-cmd" && "$(builds)" == 0 ]]; then
  pass "script added: linked into ~/bin, nothing built"
else
  fail "script added: ~/bin/pull-test-cmd not linked"; sed 's/^/    /' "$W/out"
fi

# ── 6. The script removed: its dead link pruned ──────────────────────────────

rm "$UP/scripts/pull-test-cmd"
commit_upstream "remove the script"
if pull && [[ ! -L "$H/bin/pull-test-cmd" ]]; then
  pass "script removed: its ~/bin link pruned"
else
  fail "script removed: ~/bin/pull-test-cmd left behind"; sed 's/^/    /' "$W/out"
fi

# ── 7. A dotfile added: linked into ~ ────────────────────────────────────────

printf '# test\n' > "$UP/dotfiles/.pulltestrc"
commit_upstream "add a dotfile"
if pull && [[ "$(readlink "$H/.pulltestrc")" == "$CLONE/dotfiles/.pulltestrc" && "$(builds)" == 0 ]]; then
  pass "dotfile added: linked into ~, nothing built"
else
  fail "dotfile added: ~/.pulltestrc not linked"; sed 's/^/    /' "$W/out"
fi

# ── 8. Nothing ran for real ──────────────────────────────────────────────────

if grep -vE '^sudo -n -v ?$' "$W/calls" | grep -q .; then
  fail "a stub other than sudo -n -v was called:"; sed 's/^/    /' "$W/calls"
else
  pass "no sudo, defaults, osascript, launchctl, chsh or open call beyond sudo -n -v"
fi

if (( fails )); then
  err "$fails make pull check(s) failed"
  exit 1
fi
ok "make pull checks passed"
