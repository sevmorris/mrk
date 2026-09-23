#!/usr/bin/env bash
# tests/topgrade-npm.sh — topgrade's npm steps load nvm from where mrk installs it.
#
# post-install clones nvm into ~/.nvm; Node is not a Homebrew formula here. Until
# 2026-09-23 both npm steps in assets/topgrade.toml sourced
# /opt/homebrew/opt/nvm/nvm.sh, which exists only when nvm is a Homebrew
# formula, so on a Mac set up by mrk the source was skipped every time. npm
# was found only when topgrade inherited a PATH from a shell that had already
# loaded nvm; from any other parent, `npm update -g` failed with "command not
# found" and `npm cache verify` silently did nothing.
#
# Each step's command is taken from the TOML as written and run the way
# topgrade runs a custom command, through `sh -c`. The environment is cleared,
# HOME is a scratch directory holding a stub ~/.nvm/nvm.sh, and PATH is the
# system's alone, so the only npm the step can reach is the one nvm puts on
# PATH. The stub records every call; a real npm elsewhere on the system cannot
# satisfy the test, because it records nothing.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOML="$REPO_ROOT/assets/topgrade.toml"

failures=0
pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; failures=$(( failures + 1 )); }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/topgrade-npm.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

mkdir -p "$ROOT/home/.nvm/stubbin"
cat > "$ROOT/home/.nvm/nvm.sh" <<'STUB'
# stub nvm.sh: what the real one does for these steps, put the default Node on PATH
export PATH="$NVM_DIR/stubbin:$PATH"
STUB
cat > "$ROOT/home/.nvm/stubbin/npm" <<STUB
#!/bin/sh
printf '%s\n' "\$*" >> "$ROOT/npm.log"
STUB
chmod +x "$ROOT/home/.nvm/stubbin/npm"

# step NAME -> the command string topgrade would run, TOML escapes undone.
step() {
  local line
  line=$(grep -F "\"$1\" = " "$TOML") || return 1
  line=${line#*= \"}
  printf '%s' "${line%\"}" | sed 's/\\"/"/g'
}

# run_step NAME EXPECTED-NPM-ARGS
run_step() {
  local name=$1 want=$2 cmd
  if ! cmd=$(step "$name"); then
    fail "\"$name\" is missing from assets/topgrade.toml"
    return
  fi
  : > "$ROOT/npm.log"
  env -i HOME="$ROOT/home" PATH=/usr/bin:/bin /bin/sh -c "$cmd" >/dev/null 2>&1 || true
  if grep -qFx -- "$want" "$ROOT/npm.log"; then
    pass "\"$name\" runs npm $want with nvm loaded from ~/.nvm"
  else
    fail "\"$name\" never reached nvm's npm — it does not load ~/.nvm/nvm.sh"
  fi
}

run_step "npm global update" "update -g"
run_step "npm cache verify" "cache verify"

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures"
  exit 1
fi
