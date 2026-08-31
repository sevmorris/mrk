#!/usr/bin/env bash
# lib.sh — shared helpers for mrk scripts
# Source this file; do not execute directly.
# Scope: mrk install-phase scripts (scripts/) — standalone bin/ tools use bin/lib/common.sh

# Guard against multiple sourcing
[[ -n "${_LIB_SH_LOADED:-}" ]] && return 0
_LIB_SH_LOADED=1

# Constants
STATE_DIR="$HOME/.mrk"
LOGFILE="$STATE_DIR/install.log"
LOG_MAX_SIZE=10485760  # 10MB

# Colors (disabled if not a terminal)
if [[ -t 2 ]]; then
  _R=$'\033[0m'        # Reset
  _B=$'\033[1m'        # Bold
  _D=$'\033[2m'        # Dim
  _RED=$'\033[31m'     # Red
  _GRN=$'\033[32m'     # Green
  _YLW=$'\033[33m'     # Yellow
  _BLU=$'\033[34m'     # Blue
  _CYN=$'\033[36m'     # Cyan
else
  _R='' _B='' _D='' _RED='' _GRN='' _YLW='' _BLU='' _CYN=''
fi

# Logging helpers
log()     { printf '%s  ▸%s %s\n' "$_CYN" "$_R" "$*" >&2; }
ok()      { printf '%s  ✓%s %s\n' "$_GRN" "$_R" "$*" >&2; }
warn()    { printf '%s  ⚠%s %s\n' "$_YLW" "$_R" "$*" >&2; }
err()     { printf '%s  ✗%s %s\n' "$_RED" "$_R" "$*" >&2; }
info()    { printf '    %s\n' "$*" >&2; }
dry()     { if (( DRY_RUN )); then printf '%s  ◦%s %s\n' "$_BLU" "$_R" "$*" >&2; else log "$@"; fi; }
logskip() { printf '%s  · %s (%s)%s\n' "$_YLW" "$1" "$2" "$_R" >&2; }
section() { printf '\n%s%s══ %s%s\n\n' "$_B" "$_BLU" "$*" "$_R" >&2; }

# Prompt for confirmation using a classic text-adventure > prompt.
# Proceeds on anything except an explicit quit (quit/exit/q/n/no).
# Skipped if not a TTY or NONINTERACTIVE=1.
confirm() {
  if [[ ! -t 0 ]] || (( ${NONINTERACTIVE:-0} )); then return 0; fi
  printf '\n%s>%s ' "$_B" "$_R" >&2
  local _ans
  read -r _ans </dev/tty
  # tr rather than ${_ans,,}: this library is sourced by scripts that carry no
  # bash-4 re-exec guard, and ${x,,} is a runtime "bad substitution" under the
  # bash 3.2 macOS ships — which neither shellcheck nor `bash -n` reports.
  _ans=$(printf '%s' "$_ans" | tr '[:upper:]' '[:lower:]')
  [[ ! "$_ans" =~ ^(quit|exit|q|n|no)$ ]]
}

# Refresh sudo timestamp to prevent timeout during long-running installs.
# Uses -n (non-interactive) so it never prompts — only extends an active session.
sudo_refresh() { sudo -n -v 2>/dev/null || true; }

# Portable mktemp: GNU mktemp (gnubin on PATH) rejects BSD-style `-t mrk`
# ("too few X's in template"), so always use an explicit template.
mrk_mktemp()   { mktemp    "${TMPDIR:-/tmp}/mrk.XXXXXX"; }
mrk_mktemp_d() { mktemp -d "${TMPDIR:-/tmp}/mrk.XXXXXX"; }

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
  if [[ -f "$LOGFILE" ]] && [[ $(wc -c < "$LOGFILE" 2>/dev/null || echo 0) -gt $LOG_MAX_SIZE ]]; then
    mv "$LOGFILE" "${LOGFILE}.$(date +%s).old" 2>/dev/null || true
    echo "[mrk] Rotated log file (exceeded $((LOG_MAX_SIZE / 1024 / 1024))MB)" >&2
  fi
}

# Ensure DRY_RUN is defined (default 0 if not set by caller)
: "${DRY_RUN:=0}"

# Report plist entries where a suggestive key NAME is paired with a substantial
# <string> value. The name alone is not evidence: Keka stores ExportPassword as
# <false/> and iTerm2 stores AiMaxTokens as <integer>. Flagging those would
# train the user to wave the gate through.
# Input must be xml1. Prints "<lineno>:<key line>" for each hit.
_scan_plist_key_values() {
  awk '
    /<[kK][eE][yY]>/ {
      if (tolower($0) ~ /<key>[^<]*(api[_-]?key|token|secret|password|passphrase|credential)s?<\/key>/) {
        keyline = $0; keyno = NR; pending = 1
      } else { pending = 0 }
      next
    }
    pending {
      if (match($0, /<string>[^<]*<\/string>/)) {
        # inner text = match minus "<string>" (8) and "</string>" (9)
        if (RLENGTH - 17 >= 12) printf "%d:%s\n", keyno, keyline
      }
      pending = 0
    }
  ' "$1" 2>/dev/null || true
}

# Scan files for patterns that look like secrets (API keys, tokens, private keys).
# Prints findings to stderr; returns 1 if any match, 0 if clean.
#
# Three complementary classes:
#   1. credential material that identifies itself (private keys)
#   2. field NAMES that conventionally hold a credential — catches a secret
#      whose value has no recognisable shape (a bare hex string, say)
#   3. value SHAPES with a vendor prefix — catches a secret filed under a
#      field name we do not recognise
#
# Patterns must compile under BSD grep, which is what /usr/bin/grep resolves to
# on macOS. It rejects an empty alternative such as `(RSA |EC |)` outright, and
# every pattern is passed with `-e` because several begin with `-`. A pattern
# that fails to compile is treated as a scan failure below, never as "clean".
scan_for_secrets() {
  (( $# == 0 )) && return 0

  # Case-INSENSITIVE: field names, and material that identifies itself.
  local -a patterns_i=(
    '-----BEGIN ([A-Z0-9]+ )?PRIVATE KEY-----'
    '(api[_-]?key|apikey|secret[_-]?key|access[_-]?token|auth[_-]?token|client[_-]?secret|password|passphrase|token)['\''"]?[[:space:]]*[:=][[:space:]]*['\''"]?[A-Za-z0-9_./+-]{12,}'
    'Bearer[[:space:]]+[A-Za-z0-9._-]{20,}'
  )

  # Case-SENSITIVE: vendor prefixes are defined by their exact casing, and
  # matching them with -i turns them into base64 noise — `AIza…` folded to
  # case-insensitive matched a <data> blob in a real BetterSnapTool.plist.
  # Case-sensitive, these produce zero hits across all 14 exported plists here.
  local -a patterns_s=(
    'sk-(ant-)?[A-Za-z0-9_-]{20,}'          # OpenAI sk- / sk-proj-, Anthropic sk-ant-
    'gh[pousr]_[A-Za-z0-9]{30,}'            # GitHub classic PAT / OAuth / refresh
    'github_pat_[A-Za-z0-9_]{20,}'          # GitHub fine-grained PAT
    'AKIA[0-9A-Z]{16}'                      # AWS access key id
    'xox[baprs]-[A-Za-z0-9-]{10,}'          # Slack
    'AIza[0-9A-Za-z_-]{35}'                 # Google API key
  )
  local pat file hits=0 line target tmp_xml out rc pass gflags
  local -a active
  for file in "$@"; do
    [[ -f "$file" ]] || continue

    # Binary plists are not greppable — the patterns below would silently match
    # nothing. snapshot-prefs converts its own `defaults export` output, but
    # Application Support and config-tree files are copied verbatim and are
    # routinely bplist00 (Loopback Devices.plist, SoundSource Sources.plist).
    # Scan an xml1 copy; the stored file is left untouched.
    target="$file"
    tmp_xml=""
    if [[ "$(head -c 8 "$file" 2>/dev/null)" == "bplist00" ]]; then
      tmp_xml="$(mrk_mktemp)"
      if plutil -convert xml1 -o "$tmp_xml" "$file" 2>/dev/null; then
        target="$tmp_xml"
      else
        warn "could not convert $file to xml1 — scanning raw bytes"
        rm -f "$tmp_xml"
        tmp_xml=""
      fi
    fi

    for pass in i s; do
      if [[ "$pass" == i ]]; then active=("${patterns_i[@]}"); gflags=-Ein
      else                        active=("${patterns_s[@]}"); gflags=-En
      fi
      for pat in "${active[@]}"; do
        # -e because several patterns begin with `-`. rc 0 = match, 1 = no
        # match, >1 = grep could not run the pattern at all.
        rc=0
        out=$(grep "$gflags" -e "$pat" "$target" 2>/dev/null) || rc=$?
        if (( rc > 1 )); then
          # A pattern that does not compile previously reported "clean". For a
          # gate that blocks a push, failing closed is the only safe reading.
          err "secret scan FAILED on ${file} (grep rc=${rc}) — pattern: ${pat:0:60}"
          hits=1
          continue
        fi
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          err "possible secret in ${file}: ${line:0:120}"
          hits=1
        done <<< "$out"
      done
    done

    # Suggestive plist key name AND a substantial <string> value. The name
    # alone is not enough: Keka stores ExportPassword as <false/> and iTerm2
    # stores AiMaxTokens as <integer>, and flagging those trains the user to
    # dismiss the gate.
    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      err "possible secret in ${file}: ${line:0:120}"
      hits=1
    done < <(_scan_plist_key_values "$target")

    [[ -n "$tmp_xml" ]] && rm -f "$tmp_xml"
  done
  return "$hits"
}

# Warn or abort when staged/content files look like secrets.
# With NONINTERACTIVE=1, abort instead of prompting.
require_clean_secrets() {
  scan_for_secrets "$@" && return 0
  warn "Potential secrets detected in files above."
  if (( ${NONINTERACTIVE:-0} )); then
    err "Aborting (NONINTERACTIVE=1)."
    return 1
  fi
  if [[ ! -t 0 ]]; then
    err "Aborting (not a TTY — cannot confirm)."
    return 1
  fi
  printf '%s  Push/commit anyway?%s ' "$_YLW" "$_R" >&2
  local _ans
  read -r _ans </dev/tty
  _ans=$(printf '%s' "$_ans" | tr '[:upper:]' '[:lower:]')
  [[ "$_ans" =~ ^(y|yes)$ ]]
}
