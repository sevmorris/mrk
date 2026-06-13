#!/usr/bin/env bash
# common.sh — shared library for ~/bin scripts
# Source this file: source "$(dirname "$0")/lib/common.sh"
# Scope: standalone bin/ tools (bin/) — mrk install-phase scripts use scripts/lib.sh

# shellcheck disable=SC2034  # Variables used by sourcing scripts

# Prevent double-sourcing
[[ -n "${_COMMON_SH_LOADED:-}" ]] && return 0
_COMMON_SH_LOADED=1

# --- Color definitions (tput-based with fallback) ---
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
  _green=$(tput setaf 2)
  _yellow=$(tput setaf 3)
  _red=$(tput setaf 1)
  _blue=$(tput setaf 4)
  _cyan=$(tput setaf 6)
  _bold=$(tput bold)
  _reset=$(tput sgr0)
else
  _green=""
  _yellow=""
  _red=""
  _blue=""
  _cyan=""
  _bold=""
  _reset=""
fi

# --- Logging functions ---
# All output to stderr except info() which goes to stdout

ok() {
  printf "%s✓ %s%s\n" "$_green" "$*" "$_reset" >&2
}

warn() {
  printf "%s⚠ %s%s\n" "$_yellow" "$*" "$_reset" >&2
}

err() {
  printf "%s✗ %s%s\n" "$_red" "$*" "$_reset" >&2
}

info() {
  printf "%s→ %s%s\n" "$_blue" "$*" "$_reset"
}

# --- Process/app utilities ---

# is_running PATTERN — check if process matching pattern is running
is_running() {
  pgrep -f "$1" >/dev/null 2>&1
}

# require_cmd CMD [CMD...] — exit with error if any command is missing
require_cmd() {
  local missing=()
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    err "Missing required command(s): ${missing[*]}"
    return 1
  fi
  return 0
}

