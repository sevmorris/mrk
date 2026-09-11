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

# Prompt for confirmation. The ">" marker is a leftover of the adventure mode
# removed in 2026-08; it stayed because it reads well and is already familiar.
# Proceeds on anything except an explicit quit (quit/exit/q/n/no).
# Skipped if not a TTY or NONINTERACTIVE=1.
#
# The hint is not decoration. A bare ">" carries no indication that anything is
# wanted, and the first thing it guards in hardening.sh is an edit to
# /etc/pam.d/sudo — where a prompt that reads as a hang is the worst outcome.
# The marker stays; it just says what it wants now.
confirm() {
  if [[ ! -t 0 ]] || (( ${NONINTERACTIVE:-0} )); then return 0; fi
  printf '\n%s>%s %s[Enter to continue · q to quit]%s ' "$_B" "$_R" "$_D" "$_R" >&2
  local _ans
  read -r _ans </dev/tty
  # tr rather than ${_ans,,}: this library is sourced by scripts that carry no
  # bash-4 re-exec guard, and ${x,,} is a runtime "bad substitution" under the
  # bash 3.2 macOS ships — which neither shellcheck nor `bash -n` reports.
  _ans=$(printf '%s' "$_ans" | tr '[:upper:]' '[:lower:]')
  [[ ! "$_ans" =~ ^(quit|exit|q|n|no)$ ]]
}

# mrk_help_guard USAGE "$@" — the -h/--help contract for a command that takes
# no options of its own.
#
# Prints USAGE and exits 0 for -h or --help. Prints USAGE to stderr and exits 2
# for any other argument.
#
# The second half is the point, and it is why this is a guard rather than a
# usage() function. A script with no option parser does not *ignore* a flag it
# does not recognise — it runs, with the flag silently discarded. That is how
# `mrk-push --help` committed and pushed uncommitted work in 2026-09: it was
# invoked as a harmless help probe and there was nothing there to refuse it.
# Six commands in this repo had the same shape, two of them destructive
# (uninstall unlinks ~/bin before its only prompt; post-install runs in full).
# Refusing the unknown argument closes it for every typo, not just for --help.
#
# Call it before anything that touches the system, and before any TTY check, so
# that help still works when stdin is not a terminal.
mrk_help_guard() {
  local usage=$1; shift
  local arg
  for arg in "$@"; do
    case "$arg" in
      -h|--help)
        printf '%s\n' "$usage"
        exit 0
        ;;
      *)
        printf '%s\n' "$usage" >&2
        printf '\nunknown argument: %s\n' "$arg" >&2
        exit 2
        ;;
    esac
  done
}

# init_rollback PATH — make sure PATH is a usable rollback script, without ever
# discarding undo history.
#
# The check this replaces truncated the file whenever it did not contain a line
# matching exactly `#!/usr/bin/env bash`. That is the right question asked in a
# way that fails destructively, and it was tested to fail: a shebang retyped as
# `#!/bin/bash`, or one carrying a trailing space, silently emptied a rollback
# holding real entries. Neither is reachable through mrk's own history — it has
# only ever written one shebang — but this file is the undo button for
# system-wide settings, the one artifact whose loss cannot be recovered, and it
# lives in the user's home directory where it can be opened and edited.
#
# Two changes. The test is now "does line 1 begin with #!", which accepts any
# shebang and tolerates trailing whitespace; and reading only line 1 also stops
# a file being accepted because the string appears somewhere in the middle,
# which the whole-file grep did. And a file that still fails is moved aside
# rather than overwritten, so nothing is ever silently lost.
init_rollback() {
  local rb="$1" aside

  # Create the directory. Both original callers happened to `mkdir -p` their
  # state dir first, so this helper never needed it and never had it — until a
  # third caller did not, and the redirect below failed with "No such file or
  # directory". `make dock` as the first mrk command on a fresh machine reaches
  # exactly that state. Producing a usable rollback file is this function's job,
  # and that includes somewhere to put it.
  mkdir -p "$(dirname "$rb")" || { err "cannot create $(dirname "$rb")"; return 1; }

  if [[ -f "$rb" ]]; then
    if head -1 "$rb" 2>/dev/null | grep -q '^#!'; then
      chmod +x "$rb" 2>/dev/null || true
      return 0
    fi
    if [[ -s "$rb" ]]; then
      aside="${rb}.unrecognised-$(date +%Y%m%d%H%M%S)"
      if mv "$rb" "$aside"; then
        warn "rollback file had no shebang on line 1 — kept the old one at $aside"
      else
        err "refusing to overwrite $rb: it has content and could not be moved aside"
        return 1
      fi
    fi
  fi

  printf '#!/usr/bin/env bash\n' > "$rb" || { err "cannot initialise rollback script: $rb"; return 1; }
  chmod +x "$rb" || { err "cannot set executable on rollback script: $rb"; return 1; }
  return 0
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
    # A symlink commits its target PATH, not the target's content, so there is
    # nothing of it to scan; following it read a file that was not being
    # committed. A directory here is a submodule pointer.
    [[ -L "$file" || -d "$file" ]] && continue

    # Anything else that cannot be read is a bug in the caller's file list,
    # and it used to be skipped as though it were clean. That is how a secret
    # got past every commit gate in a sandbox on 2026-09-10: git C-quotes an
    # unusual name ("caf\303\251.txt"), and mrk-push run from a subdirectory
    # handed over root-relative paths. Each named no file, so nothing was
    # read and the scan returned clean. Fail closed, as for a bad pattern.
    if [[ ! -f "$file" || ! -r "$file" ]]; then
      err "secret scan could not read ${file} — treating it as a failure"
      hits=1
      continue
    fi

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

# commit_paths ARRAY REPO TARGET — fill ARRAY with the absolute path of every
# file whose content the next commit would carry: the list to hand to
# require_clean_secrets. TARGET is --cached for what is staged now, or HEAD
# for what `git add -u` is about to stage, which is the dry-run view.
#
# It replaces `git diff --cached --name-only --diff-filter=AM`, the list all
# three commit gates used, which let a secret reach a remote in a sandbox on
# 2026-09-10 in three separate ways:
#   - git C-quotes an unusual name, and "caf\303\251.txt" is not a path;
#   - a staged rename is R, not A, so the renamed file was never read;
#   - a symlink replaced by a regular file is T, not M.
# -z stops the quoting, and =d keeps every status except deletion, so a rename
# and a type change are both listed, by their new path. The paths are made
# absolute because --name-only answers relative to the top level, not to the
# current directory — and a relative name the scanner resolves from the
# current directory reads whatever file of that name happens to be there.
#
# Returns 1 with ARRAY empty when git cannot produce the list. A caller must
# not commit then: an empty list scans clean.
commit_paths() {
  # Prefixed locals: a nameref resolves to the nearest variable of that name,
  # so a caller's array called `top` would otherwise be this function's own.
  declare -n _cp_out=$1
  local _cp_repo=$2 _cp_target=$3 _cp_top _cp_tmp _cp_f
  _cp_out=()
  _cp_top=$(git -C "$_cp_repo" rev-parse --show-toplevel 2>/dev/null) || return 1
  _cp_tmp=$(mrk_mktemp) || return 1
  if ! git -C "$_cp_repo" diff "$_cp_target" --name-only --diff-filter=d -z -- >"$_cp_tmp"; then
    rm -f "$_cp_tmp"
    return 1
  fi
  while IFS= read -r -d '' _cp_f; do
    _cp_out+=("$_cp_top/$_cp_f")
  done <"$_cp_tmp"
  rm -f "$_cp_tmp"
}

# git_in_progress REPO — print what REPO is in the middle of and return 0, or
# return 1 when it is idle.
#
# Anything that stages with `git add -u` or `-A` and then commits must leave
# such a repository alone. add -u marks every conflicted file resolved,
# conflict markers and all, and the commit then concludes the merge; pushall
# did exactly that to a sandbox repo on 2026-09-10 and pushed `<<<<<<< HEAD`
# to its remote. The last test catches a conflicted `git stash pop`, which
# leaves unmerged files and no *_HEAD behind.
git_in_progress() {
  local repo=$1 gd
  gd=$(git -C "$repo" rev-parse --absolute-git-dir 2>/dev/null) || return 1
  if   [[ -e "$gd/MERGE_HEAD" ]];                   then echo "merge in progress"
  elif [[ -e "$gd/CHERRY_PICK_HEAD" ]];             then echo "cherry-pick in progress"
  elif [[ -e "$gd/REVERT_HEAD" ]];                  then echo "revert in progress"
  elif [[ -d "$gd/rebase-merge" ]];                 then echo "rebase in progress"
  elif [[ -e "$gd/rebase-apply/applying" ]];        then echo "git am in progress"
  elif [[ -d "$gd/rebase-apply" ]];                 then echo "rebase in progress"
  elif [[ -e "$gd/BISECT_LOG" ]];                   then echo "bisect in progress"
  elif [[ -n "$(git -C "$repo" ls-files -u 2>/dev/null)" ]]; then echo "unresolved conflicts"
  else return 1
  fi
}
