#!/usr/bin/env bash
# common.sh — shared library for ~/bin scripts
# Source this file: source "$(dirname "$0")/lib/common.sh"

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

debug() {
  [[ "${DEBUG:-0}" -eq 1 ]] && printf "%s[debug] %s%s\n" "$_cyan" "$*" "$_reset" >&2
}

# Default DEBUG to 0 if not set
: "${DEBUG:=0}"

# --- Interactive prompts ---

# confirm PROMPT — interactive yes/no prompt
# Returns 0 for yes, 1 for no/empty/invalid
# Sets CONFIRM_LAST to: "yes", "no", "empty", or "invalid"
# If YES=1 is set, auto-confirms
confirm() {
  local prompt="${1:-Proceed?} [y/N] "
  CONFIRM_LAST=""

  if [[ "${YES:-0}" -eq 1 ]]; then
    CONFIRM_LAST="yes"
    return 0
  fi

  read -r -p "$prompt" ans || ans=""

  if [[ -z "$ans" ]]; then
    CONFIRM_LAST="empty"
    printf "  (no input — defaulting to No)\n"
    return 1
  fi

  case "$ans" in
    y|Y|yes|YES) CONFIRM_LAST="yes"; return 0 ;;
    n|N|no|NO)   CONFIRM_LAST="no";  return 1 ;;
    *)           CONFIRM_LAST="invalid"; return 1 ;;
  esac
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

# --- File size utilities ---

# human_bytes BYTES — convert bytes to human-readable format
human_bytes() {
  local bytes="${1:-0}"
  if [[ ! "$bytes" =~ ^[0-9]+$ ]]; then
    echo "invalid"
    return 1
  fi
  awk -v b="$bytes" 'BEGIN {
    s = "B K M G T P E Z Y"
    i = 0
    while (b >= 1024 && i < 8) {
      b /= 1024
      i++
    }
    unit = substr(s, i * 2 + 1, 1)
    if (unit == " ") unit = "B"
    printf "%.1f %s", b, unit
  }' 2>/dev/null || echo "${bytes}B"
}

# du_bytes PATH [PATH...] — calculate total size in bytes
du_bytes() {
  local sum=0 k
  if [[ $# -eq 0 ]]; then
    echo 0
    return
  fi
  while IFS= read -r -d '' p; do
    [[ ! -e "$p" ]] && continue
    k=$(du -sk "$p" 2>/dev/null | awk '{print $1}')
    [[ -n "$k" && "$k" =~ ^[0-9]+$ ]] && sum=$((sum + k))
  done < <(printf '%s\0' "$@")
  echo $((sum * 1024))
}

# --- Safe file operations ---

# resolve_path PATH — resolve to absolute path, following symlinks (macOS-compatible)
resolve_path() {
  local path="$1"
  if command -v python3 >/dev/null 2>&1; then
    python3 -c "import os, sys; print(os.path.realpath(sys.argv[1]))" "$path" 2>/dev/null || echo "$path"
  else
    # Fallback: use cd/pwd (doesn't follow symlinks but gets absolute path)
    local dir_part base_part
    dir_part=$(cd "$(dirname "$path")" 2>/dev/null && pwd) || dir_part=""
    base_part=$(basename "$path")
    if [[ -n "$dir_part" ]]; then
      echo "$dir_part/$base_part"
    else
      echo "$path"
    fi
  fi
}

# safe_rm PATH [PATH...] — remove paths safely (HOME-scoped only)
# Returns bytes that were freed (or would be freed in dry-run)
# Respects DRY_RUN=1 environment variable
safe_rm() {
  if [[ $# -eq 0 ]]; then
    echo 0
    return
  fi

  # Validate all paths first
  for p in "$@"; do
    # Skip unexpanded globs
    if [[ "$p" == *'*'* ]]; then
      warn "safe_rm: skipping unexpanded glob: $p"
      continue
    fi

    local real_path
    real_path=$(resolve_path "$p")

    # Ensure resolved path is within HOME
    if [[ "$real_path" != "$HOME"/* ]]; then
      err "Refusing to touch non-home path: $p (resolved: $real_path)"
      return 3
    fi
  done

  local before
  before=$(du_bytes "$@")

  if [[ "${DRY_RUN:-0}" -eq 1 ]]; then
    for p in "$@"; do
      [[ "$p" == *'*'* ]] && continue
      [[ -e "$p" ]] && echo "  (dry-run) rm -rf $p"
    done
  else
    for p in "$@"; do
      [[ "$p" == *'*'* ]] && continue
      [[ -e "$p" ]] && rm -rf "$p"
    done
  fi

  echo "$before"
}
