#!/usr/bin/env bash
# lib.sh — shared helpers for mrk scripts
# Source this file; do not execute directly.

# Resolve the real path of a file, following symlinks.
# Works on macOS (which may lack readlink -f on older versions).
resolve_path() {
  local target="$1"
  while [[ -L "$target" ]]; do
    local dir
    dir="$(cd "$(dirname "$target")" && pwd)"
    target="$(readlink "$target")"
    # Handle relative symlink targets
    [[ "$target" != /* ]] && target="$dir/$target"
  done
  echo "$(cd "$(dirname "$target")" && pwd)/$(basename "$target")"
}

# Constants
STATE_DIR="$HOME/.mrk"
LOGFILE="$STATE_DIR/install.log"
LOG_MAX_SIZE=10485760  # 10MB

# Colors (disabled if not a terminal)
if [[ -t 2 ]]; then
  _B=$'\033[1m' _D=$'\033[2m' _R=$'\033[0m'
  _RED=$'\033[31m' _GRN=$'\033[32m' _YLW=$'\033[33m' _BLU=$'\033[34m' _CYN=$'\033[36m'
else
  _B='' _D='' _R='' _RED='' _GRN='' _YLW='' _BLU='' _CYN=''
fi

# Logging helpers
log()     { printf '%s  ▸%s %s\n' "$_CYN" "$_R" "$*" >&2; }
ok()      { printf '%s  ✓%s %s\n' "$_GRN" "$_R" "$*" >&2; }
warn()    { printf '%s  ⚠%s %s\n' "$_YLW" "$_R" "$*" >&2; }
err()     { printf '%s  ✗%s %s\n' "$_RED" "$_R" "$*" >&2; }
dry()     { if (( DRY_RUN )); then printf '%s  · [dry] %s%s\n' "$_D" "$*" "$_R"; else log "$@"; fi; }
logskip() { printf '%s  · %s (%s)%s\n' "$_YLW" "$1" "$2" "$_R" >&2; }
section() { printf '\n%s%s══ %s%s\n\n' "$_B" "$_BLU" "$*" "$_R" >&2; }

# Refresh sudo timestamp to prevent timeout during long-running installs.
# Uses -n (non-interactive) so it never prompts — only extends an active session.
sudo_refresh() { sudo -n -v 2>/dev/null || true; }

# macOS-only guard
check_macos() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "Error: This script is designed for macOS only." >&2
    echo "Detected OS: $(uname -s)" >&2
    exit 1
  fi
}

# Log rotation
setup_logging() {
  mkdir -p "$STATE_DIR"
  if [[ -f "$LOGFILE" ]] && [[ $(stat -f%z "$LOGFILE" 2>/dev/null || echo 0) -gt $LOG_MAX_SIZE ]]; then
    mv "$LOGFILE" "${LOGFILE}.$(date +%s).old" 2>/dev/null || true
    echo "[mrk] Rotated log file (exceeded $((LOG_MAX_SIZE / 1024 / 1024))MB)" >&2
  fi
}

# Ensure DRY_RUN is defined (default 0 if not set by caller)
: "${DRY_RUN:=0}"
