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

# git_clone_pinned URL TAG COMMIT DEST — clone URL at TAG into DEST, but only
# when TAG still names COMMIT.
#
# A tag can be moved and a commit id cannot, so the commit is the pin and the
# tag is only how to fetch it. The clone goes into a temporary directory beside
# DEST and is moved into place only after the check, so a refused clone leaves
# nothing where a shell would source it. Used for code every shell loads: nvm
# and the zsh plugins. Until 2026-09-18 nvm arrived by piping its install script
# from a tag into bash, with nothing checked. The reason for a refusal goes to
# stderr; the caller decides what a refusal costs.
git_clone_pinned() {
  local url="$1" tag="$2" commit="$3" dest="$4" parent tmp head
  if [[ -e "$dest" || -L "$dest" ]]; then
    warn "$dest already exists — not cloning over it"
    return 1
  fi
  parent="$(dirname "$dest")"
  mkdir -p "$parent" || return 1
  tmp="$(mktemp -d "$parent/.$(basename "$dest").XXXXXX")" || return 1
  if ! git -c advice.detachedHead=false clone -q --depth=1 --branch "$tag" "$url" "$tmp" 2>/dev/null; then
    rm -rf "$tmp"
    warn "could not clone $url at $tag"
    return 1
  fi
  head="$(git -C "$tmp" rev-parse HEAD 2>/dev/null || true)"
  if [[ "$head" != "$commit" ]]; then
    rm -rf "$tmp"
    warn "$url: $tag is now ${head:-unreadable}, not the pinned $commit — refused"
    info "A moved tag is a reason to look before installing, not to clone it by hand."
    return 1
  fi
  mv "$tmp" "$dest" || { rm -rf "$tmp"; return 1; }
}

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
  # eval on a validated name rather than `declare -n`: namerefs need bash 4.3,
  # and this library is sourced by scripts with no bash-4 guard (see confirm).
  # The paths themselves never pass through eval — only `$_cp_top/$_cp_f`,
  # quoted, which eval expands as variables. Prefixed locals keep a caller's
  # array name from colliding with this function's own.
  local _cp_name=$1 _cp_repo=$2 _cp_target=$3 _cp_top _cp_tmp _cp_f
  [[ "$_cp_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
  eval "$_cp_name=()"
  _cp_top=$(git -C "$_cp_repo" rev-parse --show-toplevel 2>/dev/null) || return 1
  _cp_tmp=$(mrk_mktemp) || return 1
  if ! git -C "$_cp_repo" diff "$_cp_target" --name-only --diff-filter=d -z -- >"$_cp_tmp"; then
    rm -f "$_cp_tmp"
    return 1
  fi
  while IFS= read -r -d '' _cp_f; do
    eval "$_cp_name+=(\"\$_cp_top/\$_cp_f\")"
  done <"$_cp_tmp"
  rm -f "$_cp_tmp"
}

# project_repos ROOT REPOS OTHERS — fill the array named REPOS with the path,
# relative to ROOT, of every git repository a sweep of ROOT should cover, and
# OTHERS with every folder that holds none. pushall pushes exactly the REPOS
# list and snapshot-prefs records exactly the same list in the manifest, so
# the two cannot disagree about what counts as a project.
#
#   ROOT/repo/            a repository                    → REPOS "repo"
#   ROOT/folder/repo/     one level down, in a folder
#                         that is not one itself          → REPOS "folder/repo"
#   ROOT/folder/other/    beside such a repo, not one     → OTHERS "folder/other"
#   ROOT/folder/          no repository at either level   → OTHERS "folder"
#   ROOT/name.git/        a bare repository               → neither
#
# One level down because that is how a folder wraps a project here —
# FloppyLetters/FloppyLetter2601, and JustIn/JustIn until JustIn was retired —
# and until 2026-09-10 neither pushall nor the manifest looked, so both repos
# were invisible to them. Never deeper, and never inside a repository, so a worktree kept in a
# repo is not mistaken for a project. A .git *file* (a linked worktree, whose
# repository lives elsewhere) is neither listed nor reported. Nor is a bare
# repository named *.git, such as DoublEnder's Cloud overlay: it has no working
# tree of its own to sweep, and pushall and snapshot-prefs look for it apart.
#
# eval on validated names, as commit_paths does: this library stays
# bash-3.2-clean, and the paths are expanded as variables, never as code.
project_repos() {
  local _pr_root=$1 _pr_repos=$2 _pr_other=$3 _pr_top _pr_sub _pr_t _pr_s _pr_nested
  [[ "$_pr_repos" =~ ^[A-Za-z_][A-Za-z0-9_]*$ && "$_pr_other" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || return 1
  eval "$_pr_repos=()"
  eval "$_pr_other=()"
  for _pr_top in "$_pr_root"/*/; do
    _pr_top=${_pr_top%/}
    [[ -d "$_pr_top" ]] || continue        # the unexpanded glob of an empty ROOT
    _pr_t=${_pr_top##*/}
    [[ "$_pr_t" == *.git && -f "$_pr_top/HEAD" && -d "$_pr_top/objects" ]] && continue
    if [[ -d "$_pr_top/.git" ]]; then
      eval "$_pr_repos+=(\"\$_pr_t\")"
      continue
    fi
    [[ -e "$_pr_top/.git" ]] && continue
    _pr_nested=0
    for _pr_sub in "$_pr_top"/*/; do
      _pr_sub=${_pr_sub%/}
      [[ -d "$_pr_sub/.git" ]] || continue
      _pr_s="$_pr_t/${_pr_sub##*/}"
      eval "$_pr_repos+=(\"\$_pr_s\")"
      _pr_nested=1
    done
    if (( _pr_nested )); then
      for _pr_sub in "$_pr_top"/*/; do
        _pr_sub=${_pr_sub%/}
        [[ -e "$_pr_sub/.git" ]] && continue
        _pr_s="$_pr_t/${_pr_sub##*/}"
        eval "$_pr_other+=(\"\$_pr_s\")"
      done
    else
      eval "$_pr_other+=(\"\$_pr_t\")"
    fi
  done
  return 0
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

# prefs_source ID — print the domain to hand `defaults export` so that it reads
# the preferences app ID really uses: the path of ~/Library/Preferences/ID.plist
# when that file exists, and otherwise ID itself.
#
# Given a bare ID, defaults reads the copy in the app's sandbox container
# whenever the container holds one. That is right for a sandboxed app and wrong
# for one that has since shipped unsandboxed, because the container outlives
# the build that wrote it. Five of my own apps are in that state, and until
# 2026-09-11 snapshot-prefs saved their abandoned container copies: JustIn's
# with one key where the live file has five, WaxOn's without its settings at
# all. A sandboxed app leaves nothing outside its container for this to prefer:
# its first launch moves ~/Library/Preferences/ID.plist inside (measured with a
# sandboxed test app, 2026-09-11).
prefs_source() {
  local f="$HOME/Library/Preferences/$1.plist"
  if [[ -f "$f" ]]; then
    printf '%s\n' "${f%.plist}"
  else
    printf '%s\n' "$1"
  fi
}

# picard_settings INI — print Picard's settings from INI with its credentials
# taken out, for snapshot-prefs to keep as history. The output is a record to
# diff, not a file to restore: post-install never reads it.
#
# Kept: [application] (the version that wrote the file), [setting], [profiles]
# and each Picard 3 [plugin.<uuid>]. Dropped: [persist], which holds the OAuth
# tokens beside window geometry and changes every session, and [General] and
# [com], which are macOS's global defaults that Qt copies into the file.
#
# A kept key whose name says it holds a credential has a non-empty value
# replaced with <redacted>, so the diff still shows whether one is set. This
# cannot lean on scan_for_secrets: none of its patterns names fanart.tv's
# client_key, which would have been committed in full.
picard_settings() {
  awk '
    BEGIN { printed = 0 }
    /^\[/ {
      keep = ($0 == "[application]" || $0 == "[setting]" || $0 == "[profiles]" || $0 ~ /^\[plugin\./)
      if (keep) { if (printed) print ""; print; printed = 1 }
      next
    }
    !keep || /^[[:space:]]*$/ { next }
    {
      eq = index($0, "=")
      key = tolower(substr($0, 1, eq - 1))
      if (eq > 1 && substr($0, eq + 1) != "" &&
          key ~ /token|password|passwd|passphrase|secret|apikey|api_key|client_key|oauth|username|email|(^|_)key$/) {
        print substr($0, 1, eq) "<redacted>"
        next
      }
      print
    }' "$1"
}

# ─── mrk-picker descriptions ─────────────────────────────────────────────────
#
# tools/picker/main.go holds the one description table, `var descriptions`, and
# check-picker-desc holds it to the Brewfile in both directions. Two things
# write it: sync, as it adds and prunes, and check-picker-desc --fix, for every
# other way a Brewfile line comes and goes — Barkeep and a hand edit. They share
# these functions, so a description is worded, placed and formatted one way.
#
# The two writers go through a temp file beside main.go, named in PICKER_TMP so
# that the caller's EXIT trap can remove it after an interrupt, and run gofmt on
# it before it replaces main.go. The map is column-aligned, and the longest key
# in a block sets the padding of every line beside it; and a file gofmt cannot
# parse never lands.

# brew_describe BREW PICKER_GO KIND:NAME... — look each package up in Homebrew
# and print one record for it: kind, name, section (casks only), why that
# section, description, and 1 when PICKER_GO already describes the name.
#
# Fields are split by the unit separator rather than a tab: bash's `read` folds
# a run of tabs into one, so an empty field would shift the rest.
#
#   - The description is Homebrew's own `desc`. A cask whose token does not
#     name the product gets its display name in front ("GitHub Desktop — …"),
#     as the hand-written entries do.
#   - A cask's section is the category its app declares, LSApplicationCategoryType
#     in the Info.plist, mapped onto the Brewfile's `## Casks - X` names. An app
#     that declares none, or a cask with no app bundle to read, gets Utilities.
#     Only sync files entries; check-picker-desc --fix reads the description.
brew_describe() {
  python3 - "$@" <<'PYEOF'
import json, os, plistlib, re, subprocess, sys

brew, picker_go = sys.argv[1], sys.argv[2]
pkgs = [a.split(':', 1) for a in sys.argv[3:]]

# LSApplicationCategoryType, without its public.app-category. prefix, to the
# Brewfile section a cask declaring it goes to. Names stay short enough for
# mrk-picker's category pane, and free of " & " and " / ", which its
# categoryName() reads as qualifiers to cut. Two merges: music is Audio,
# because the apps here record and route sound rather than play songs, and
# business joins social-networking as Communication, because the business apps
# here are Slack and Zoom.
SECTIONS = {
    'business': 'Communication',
    'developer-tools': 'Developer Tools',
    'education': 'Education',
    'entertainment': 'Entertainment',
    'finance': 'Finance',
    'games': 'Games',
    'graphics-design': 'Graphics',
    'healthcare-fitness': 'Health',
    'lifestyle': 'Lifestyle',
    'medical': 'Medical',
    'music': 'Audio',
    'news': 'News',
    'photography': 'Photography',
    'productivity': 'Productivity',
    'reference': 'Reference',
    'social-networking': 'Communication',
    'sports': 'Sports',
    'travel': 'Travel',
    'utilities': 'Utilities',
    'video': 'Video',
    'weather': 'Weather',
}
FALLBACK = 'Utilities'
# Homebrew's default appdir, and the one HOMEBREW_CASK_OPTS most often names.
APP_DIRS = ['/Applications', os.path.expanduser('~/Applications')]
PREFIX = 'public.app-category.'

described = set(re.findall(r'^\t"([^"]+)":', open(picker_go, encoding='utf-8').read(), re.M)) \
    if os.path.isfile(picker_go) else set()

def norm(s):
    return re.sub(r'[^a-z0-9]', '', s.lower())

def info(kind, name):
    try:
        r = subprocess.run([brew, 'info', '--json=v2', '--' + kind, name],
                           stdin=subprocess.DEVNULL, capture_output=True, text=True)
        data = json.loads(r.stdout) if r.returncode == 0 else {}
    except (OSError, ValueError):
        data = {}
    items = data.get('formulae' if kind == 'formula' else 'casks') or []
    return items[0] if items and isinstance(items[0], dict) else None

def app_bundles(item):
    """The .app names a cask installs: each app artifact's target, or its
    source when it has none; then each display name, which finds the app a
    pkg installer puts in /Applications without declaring it."""
    names = []
    for art in item.get('artifacts') or []:
        args = art.get('app') if isinstance(art, dict) else None
        if not args or not isinstance(args[0], str):
            continue
        opts = args[1] if len(args) > 1 and isinstance(args[1], dict) else {}
        names.append(os.path.basename(str(opts.get('target') or args[0]).rstrip('/')))
    names += [n + '.app' for n in item.get('name') or [] if isinstance(n, str)]
    return list(dict.fromkeys(names))

def section_for(item):
    for app in app_bundles(item):
        for d in APP_DIRS:
            plist = os.path.join(d, app, 'Contents', 'Info.plist')
            if not os.path.isfile(plist):
                continue
            try:
                with open(plist, 'rb') as f:
                    declared = plistlib.load(f).get('LSApplicationCategoryType')
            except Exception:
                return FALLBACK, f'{app} has an Info.plist that cannot be read'
            if not isinstance(declared, str) or not declared.strip():
                return FALLBACK, f'{app} declares no category'
            declared = declared.strip()
            key = declared.lower()
            key = key[len(PREFIX):] if key.startswith(PREFIX) else key
            if key.endswith('-games'):
                key = 'games'
            if key in SECTIONS:
                return SECTIONS[key], f'{app} declares {declared}'
            return FALLBACK, f'{app} declares {declared}, which maps to no section'
    return FALLBACK, 'no installed app bundle to read'

def describe(kind, name, item):
    desc = ' '.join(str(item.get('desc') or '').split())
    if not desc:
        return ''
    if kind == 'cask':
        display = next((n for n in item.get('name') or [] if isinstance(n, str) and n.strip()), '')
        token = name.rsplit('/', 1)[-1]
        if display and norm(display) != norm(token) and norm(display) not in norm(desc):
            desc = f'{display.strip()} — {desc}'
    return desc

for kind, name in pkgs:
    item = info(kind, name)
    section = reason = desc = ''
    if item is None:
        reason = 'Homebrew has no record of it'
        if kind == 'cask':
            section = FALLBACK
    else:
        desc = describe(kind, name, item)
        if kind == 'cask':
            section, reason = section_for(item)
    fields = [kind, name, section, reason, desc, '1' if name in described else '0']
    print('\x1f'.join(f.replace('\x1f', ' ').replace('\n', ' ') for f in fields))
PYEOF
}

# picker_add_descriptions PICKER_GO FILE — add the descriptions FILE holds, one
# per line as kind, name and description split by the unit separator. A name
# the map already has is left as it is, so a description reworded by hand
# sticks, and a record with no description is skipped. A formula goes at the end
# of the map's formulae block, which is in no order, and a cask in alphabetical
# order among the casks.
picker_add_descriptions() {
  local go=$1 adds=$2
  PICKER_TMP="$(mktemp "${go%/*}/.main.go.XXXXXX")"
  if ! python3 - "$go" "$adds" "$PICKER_TMP" <<'PYEOF'
import re, sys

go_path, adds_path, out_path = sys.argv[1:4]
with open(go_path, encoding='utf-8') as f:
    lines = f.read().split('\n')
try:
    start = next(i for i, l in enumerate(lines) if l.startswith('var descriptions = map[string]string{'))
    end = next(i for i in range(start + 1, len(lines)) if lines[i] == '}')
except StopIteration:
    sys.exit('the descriptions map was not found in tools/picker/main.go')

key_re = re.compile(r'^\t"([^"]+)":')
have = {m.group(1) for m in map(key_re.match, lines[start:end]) if m}
casks_at = next((i for i in range(start, end) if lines[i].strip() == '// Casks'), end)

def literal(s):
    s = ''.join(c for c in s if c >= ' ')
    return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'

with open(adds_path, encoding='utf-8') as f:
    for record in f:
        kind, name, desc = record.rstrip('\n').split('\x1f', 2)
        if name in have or not desc:
            continue
        if kind == 'formula':
            idx = casks_at
            casks_at += 1
        else:
            idx = next((i for i in range(casks_at + 1, end)
                        if (m := key_re.match(lines[i])) and m.group(1) > name), end)
        lines.insert(idx, f'\t{literal(name)}: {literal(desc)},')
        end += 1
        have.add(name)

with open(out_path, 'w', encoding='utf-8') as f:
    f.write('\n'.join(lines))
PYEOF
  then
    rm -f "$PICKER_TMP"; PICKER_TMP=""
    return 1
  fi
  _picker_replace "$go"
}

# picker_remove_descriptions PICKER_GO NAME... — delete the description lines
# for the names given.
#
# awk rather than sed because a package name is not a regex: python@3.12 would
# otherwise match python@3-12. Splitting on quotes makes field 2 the key, the
# comparison is exact, and only lines inside `var descriptions` are touched.
picker_remove_descriptions() {
  local go=$1; shift
  PICKER_TMP="$(mktemp "${go%/*}/.main.go.XXXXXX")"
  DROP_NAMES="$(printf '%s\n' "$@")" awk -F'"' '
    BEGIN { n = split(ENVIRON["DROP_NAMES"], a, "\n"); for (i = 1; i <= n; i++) drop[a[i]] = 1 }
    /^var descriptions = map\[string\]string\{/ { inmap = 1 }
    inmap && /^}/                               { inmap = 0 }
    inmap && /^\t"/ && ($2 in drop)             { next }
    { print }' "$go" > "$PICKER_TMP"

  local want got
  want=$(( $(wc -l < "$go") - $# ))
  got=$(wc -l < "$PICKER_TMP")
  if (( got != want )); then
    err "Expected $want lines in tools/picker/main.go after removing $#, got $got — left it unchanged."
    rm -f "$PICKER_TMP"; PICKER_TMP=""
    return 1
  fi
  _picker_replace "$go"
}

# _picker_replace PICKER_GO — gofmt PICKER_TMP and move it over PICKER_GO.
_picker_replace() {
  if command -v gofmt >/dev/null 2>&1; then
    if ! gofmt -w "$PICKER_TMP"; then
      err "gofmt rejected the new tools/picker/main.go — left it unchanged."
      rm -f "$PICKER_TMP"; PICKER_TMP=""
      return 1
    fi
  else
    warn "gofmt not found — tools/picker/main.go may need realigning (gofmt -w)."
  fi
  chmod 644 "$PICKER_TMP"
  mv "$PICKER_TMP" "$1"
  PICKER_TMP=""
}

# picker_desc_fix REPO [--dry-run] — for mrk-push and pushall, before they stage:
# when REPO's check-picker-desc fails, run it again with --fix, so the
# descriptions go into the commit that is about to be made. Silent when the
# check passes.
#
# sync describes each package it adds and deletes the description of each one
# it prunes. Barkeep adds and removes Brewfile lines and writes no description,
# and neither does a hand edit, so each of those turned CI red until someone
# wrote the description by hand. Every change to ~/mrk reaches GitHub through
# mrk-push or pushall, so the push is where all three can be caught.
#
# The trigger is the check failing, not the Brewfile having changed. The first
# version ran --fix only when the Brewfile differed from HEAD, so a Brewfile
# committed some other way — a plain `git commit` after a Barkeep session —
# reached GitHub undescribed, and nothing at push time looked. The check reads
# two files and calls nothing, about 50 ms, so it runs on every push; Homebrew
# is asked only when there is something to describe.
#
# A dry run shows what the check finds and changes nothing. What --fix cannot
# settle — a package Homebrew has no description for — is warned about and the
# commit goes ahead: holding back every other change would not make CI green.
picker_desc_fix() {
  local repo=$1 dry=${2:-}
  local check="$repo/scripts/check-picker-desc"
  [[ -x "$check" ]] || return 0
  "$check" >/dev/null 2>&1 && return 0
  if [[ "$dry" == --dry-run ]]; then
    "$check" || true
    info "A real run runs check-picker-desc --fix before it stages."
    return 0
  fi
  "$check" --fix && return 0
  warn "check-picker-desc still fails, for the reason above. The commit goes ahead, and CI will fail until that is fixed."
  return 0
}
