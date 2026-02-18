#!/usr/bin/env bash
# lib.sh — shared helpers for mrk scripts
# Source this file; do not execute directly.

# Constants
STATE_DIR="$HOME/.mrk"
LOGFILE="$STATE_DIR/install.log"
LOG_MAX_SIZE=10485760  # 10MB

# Colors (disabled if not a terminal)
if [[ -t 2 ]]; then
  _C_RESET='\033[0m'
  _C_BOLD='\033[1m'
  _C_DIM='\033[2m'
  _C_GREEN='\033[32m'
  _C_YELLOW='\033[33m'
  _C_RED='\033[31m'
  _C_CYAN='\033[36m'
  _C_BLUE='\033[34m'
else
  _C_RESET='' _C_BOLD='' _C_DIM='' _C_GREEN='' _C_YELLOW='' _C_RED='' _C_CYAN='' _C_BLUE=''
fi

# Logging helpers
log()     { printf "${_C_CYAN}[mrk]${_C_RESET} %s\n" "$*" >&2; }
ok()      { printf "${_C_GREEN}  ✓${_C_RESET} %s\n" "$*" >&2; }
warn()    { printf "${_C_YELLOW}  ⚠${_C_RESET} %s\n" "$*" >&2; }
err()     { printf "${_C_RED}  ✗${_C_RESET} %s\n" "$*" >&2; }
dry()     { if (( DRY_RUN )); then printf "${_C_DIM}[dry]${_C_RESET} %s\n" "$*"; else log "$@"; fi; }
logskip() { printf "${_C_DIM}  ⏭${_C_RESET} %s ${_C_DIM}(%s)${_C_RESET}\n" "$1" "$2" >&2; }
header()  { printf "\n${_C_BOLD}${_C_BLUE}━━ %s${_C_RESET}\n\n" "$*" >&2; }

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
    mv "$LOGFILE" "${LOGFILE}.old" 2>/dev/null || true
    echo "[mrk] Rotated log file (exceeded $((LOG_MAX_SIZE / 1024 / 1024))MB)" >&2
  fi
}

# Ensure DRY_RUN is defined (default 0 if not set by caller)
: "${DRY_RUN:=0}"
