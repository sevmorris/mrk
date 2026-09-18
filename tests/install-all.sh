#!/usr/bin/env bash
# install-all.sh — prove that `mrk-install --all` is `make all`, not a second
# definition of a full install.
#
# Until 2026-09-18 scripts/install --all ran setup, brew and post-install
# itself, and did less than `make all`: no fix-exec first, no TUI build after,
# none of the closing notes. It now runs make all. make and xcode-select are
# stubs here, so nothing is installed: the make stub records its arguments, and
# the xcode-select stub decides whether the Command Line Tools are present.
#
# Runs scripts/install under /bin/bash as well as the bash running it, because
# on a new Mac it runs before Homebrew's bash exists. ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/install-all.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
STUBS="$WORK/bin"
mkdir -p "$STUBS"

# make: one argument per line, so a value with a space stays one argument.
cat > "$STUBS/make" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$MAKE_LOG"
EOF
# xcode-select -p: present unless CLT_MISSING is set.
cat > "$STUBS/xcode-select" <<'EOF'
#!/bin/bash
[[ -n "${CLT_MISSING:-}" ]] && exit 2
echo /Library/Developer/CommandLineTools
EOF
chmod +x "$STUBS/make" "$STUBS/xcode-select"

# run SHELL [args...] — run scripts/install with the stubs first on PATH.
# Leaves the exit status in RC and make's arguments in MADE ("" if not run).
RC=0
MADE=""
run() {
  local sh="$1"
  shift
  rm -f "$WORK/make.log"
  CLT_MISSING="${CLT_MISSING:-}" MAKE_LOG="$WORK/make.log" PATH="$STUBS:$PATH" \
    "$sh" "$REPO_ROOT/scripts/install" "$@" >"$WORK/out" 2>&1
  RC=$?
  MADE=""
  [[ -f "$WORK/make.log" ]] && MADE="$(tr '\n' '|' < "$WORK/make.log")"
}

cases() {
  local sh="$1"
  local want="--no-print-directory|-C|$REPO_ROOT|all|"

  run "$sh" --all
  if [[ $RC -eq 0 && "$MADE" == "$want" ]]; then
    pass "--all runs make all in the repository"
  else
    fail "--all: exit $RC, make got \"$MADE\", wanted \"$want\""
  fi

  run "$sh" --all --yes
  if [[ "$MADE" == "${want}ARGS=--yes|" ]]; then
    pass "a flag reaches the phases as ARGS"
  else
    fail "--all --yes: make got \"$MADE\""
  fi

  run "$sh" --yes --all --continue-on-error
  if [[ "$MADE" == "${want}ARGS=--yes --continue-on-error|" ]]; then
    pass "two flags, on either side of --all, arrive as one ARGS"
  else
    fail "--yes --all --continue-on-error: make got \"$MADE\""
  fi

  CLT_MISSING=1 run "$sh" --all
  if [[ $RC -eq 1 && -z "$MADE" ]] && grep -q 'Phase 1' "$WORK/out"; then
    pass "without the Command Line Tools: exit 1, no make, and it points at Phase 1"
  else
    fail "without the Command Line Tools: exit $RC, make got \"$MADE\""
  fi

  run "$sh" --help
  if [[ $RC -eq 0 && -z "$MADE" ]] && grep -q 'make all' "$WORK/out"; then
    pass "--help says --all is make all, and runs nothing"
  else
    fail "--help: exit $RC, make got \"$MADE\""
  fi
}

# shellcheck disable=SC2016  # expanded by the inner bash, not this one
printf '  under bash %s\n' "$(/bin/bash -c 'echo "${BASH_VERSION%%(*}"')"
cases /bin/bash
if [[ ! "$BASH" -ef /bin/bash ]]; then
  # shellcheck disable=SC2016  # expanded by the inner bash, not this one
  printf '  under bash %s\n' "$("$BASH" -c 'echo "${BASH_VERSION%%(*}"')"
  cases "$BASH"
fi

# The Makefile is now the only definition, so it must still be the whole one.
all_deps="$(grep -E '^all:' "$REPO_ROOT/Makefile" || true)"
all_deps="${all_deps#all:}"
all_deps="${all_deps%%##*}"   # the ## help text names the phases too
missing=()
for step in fix-exec setup brew post-install build-tools; do
  [[ " $all_deps " == *" $step "* ]] || missing+=("$step")
done
if (( ${#missing[@]} == 0 )); then
  pass "make all still runs fix-exec, setup, brew, post-install and build-tools"
else
  fail "make all no longer runs: ${missing[*]}"
fi

(( fails == 0 ))
