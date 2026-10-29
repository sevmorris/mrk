#!/usr/bin/env bash
set -euo pipefail

# mrk defaults - apply macOS defaults and generate a rollback script
#
# The keys are config/defaults.tsv: edit that file, not this script.

ROLL_DIR="$HOME/.mrk"
ROLLBACK="${ROLLBACK:-$HOME/.mrk/defaults-rollback.sh}"

usage() {
  cat <<'EOF'
mrk-defaults — apply the macOS defaults and record how to undo them

Usage:
  mrk-defaults [--with-trackpad] [--check] [--help | -h]
  mrk-defaults (--skip | --unskip | --key | --revert) DOMAIN KEY ...

Options:
      --with-trackpad  Also apply the trackpad gesture settings
      --check          Compare each key with this Mac, and change nothing.
                       One line for each key, tab-separated: the domain, the
                       key, the value mrk sets, the value it has now, and set,
                       differs, absent, nodomain, skipped or noaccess. Nothing
                       else on stdout. Exits 0 when it could tell, 1 when it
                       refused, 2 for a bad option.
  -h, --help           Show this help

mrk-defaults writes the keys that config/defaults.tsv lists, in its order,
and appends an undo line for each one to ~/.mrk/defaults-rollback.sh, so
every change it makes can be reversed. It is idempotent: a second run leaves
both the system state and the rollback script unchanged. It refuses the whole
file, before it writes anything, when a line is not one key. It does not
write a key that config/defaults-skip.tsv lists, and it refuses that file too
when a line is not one key of config/defaults.tsv. Run it as `make defaults`,
or with the trackpad keys as `make trackpad`.

With --check, a field escapes a tab, a newline and a backslash as
config/defaults.tsv does (\t, \n, \\), and a bool's value is true or false.
A key whose value is right but whose type is not differs, as a run would
write it. A key that config/defaults.tsv writes only to a domain that exists
(when existing) is nodomain when its domain does not exist yet: a run does
not write it. A key that config/defaults-skip.tsv lists is skipped, whatever
its value. A key is noaccess when its app keeps its preferences in a
container that macOS does not let this process read: Mail's, without Full
Disk Access, and TextEdit's and Passwords', without permission to get the
data of other apps as well. Its value cannot be known, the fourth field is
empty, and a run passes it over. --with-trackpad adds the trackpad keys to
the check as well.
A later version may add fields at the end of a line, and never removes or
reorders one.

One key at a time, for a program such as Dipstick. Each option takes
the domain and the key of a line of config/defaults.tsv, and refuses any
other key. Give each option as many times as you need. A run with these
options changes only the keys that it names.
  --skip DOMAIN KEY    Add the key to config/defaults-skip.tsv, so that a run
                       does not write it. This does not change the Mac.
  --unskip DOMAIN KEY  Delete the key from config/defaults-skip.tsv. This does
                       not change the Mac.
  --key DOMAIN KEY     Write the key as a run writes it, with its undo line.
                       It refuses a key that config/defaults-skip.tsv lists.
                       A key that waits for its domain is not written.
  --revert DOMAIN KEY  Put back the value that the key had before mrk wrote
                       it, from the line of the key in
                       ~/.mrk/defaults-rollback.sh. A key with no line there
                       stays as it is: mrk did not change it on this Mac.
mrk-defaults changes the skip list first, then the keys. It checks every key
before it changes anything, and refuses --key and --revert for a key that
this process may not read. When a key changed, it restarts Finder, the Dock,
SystemUIServer and ControlCenter, as a run does. It exits 0 when it is done,
1 when it refuses or a write fails, and 2 for a bad option.
EOF
}

bad_usage() {
  usage >&2
  printf '\n%s\n' "$1" >&2
  exit 2
}

WITH_TRACKPAD=false
CHECK=false
TAB=$'\t'
# The keys that the options of one key name, each as its domain, a tab and the
# key
SKIP=() UNSKIP=() KEY=() REVERT=()
while (( $# > 0 )); do
  case "$1" in
    --with-trackpad) WITH_TRACKPAD=true ;;
    --check)         CHECK=true ;;
    --skip|--unskip|--key|--revert)
      if (( $# < 3 )) || [[ -z "$2" || -z "$3" ]]; then
        bad_usage "$1 takes a domain and a key"
      fi
      case "$1" in
        --skip)   SKIP+=("$2$TAB$3") ;;
        --unskip) UNSKIP+=("$2$TAB$3") ;;
        --key)    KEY+=("$2$TAB$3") ;;
        --revert) REVERT+=("$2$TAB$3") ;;
      esac
      shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *)               bad_usage "unknown argument: $1" ;;
  esac
  shift
done

# in_ids ID [ID...] — true when the first ID is one of the others
in_ids() {
  local id=$1 other; shift
  for other in "$@"; do [[ "$other" == "$id" ]] && return 0; done
  return 1
}
# shown ID — the domain and the key of ID, with a space between them
shown() { printf '%s %s' "${1%%"$TAB"*}" "${1#*"$TAB"}"; }

ONE_KEY=false
if (( ${#SKIP[@]} + ${#UNSKIP[@]} + ${#KEY[@]} + ${#REVERT[@]} > 0 )); then
  ONE_KEY=true
  if $CHECK || $WITH_TRACKPAD; then
    bad_usage "--check and --with-trackpad do not go with --skip, --unskip, --key or --revert"
  fi
  for id in ${SKIP[@]+"${SKIP[@]}"}; do
    if in_ids "$id" ${UNSKIP[@]+"${UNSKIP[@]}"}; then
      bad_usage "--skip and --unskip both name $(shown "$id")"
    fi
  done
  for id in ${KEY[@]+"${KEY[@]}"}; do
    if in_ids "$id" ${REVERT[@]+"${REVERT[@]}"}; then
      bad_usage "--key and --revert both name $(shown "$id")"
    fi
  done
fi

# --check is for a program to read (mrk Settings), on stdout, which holds
# nothing else: fd 3 is stdout, and everything else goes to stderr. Modelled on
# sync --check and snapshot-prefs --check.
if $CHECK; then
  exec 3>&1 1>&2
fi

_self="${BASH_SOURCE[0]}"
while [[ -L "$_self" ]]; do
  _dir="$(cd "$(dirname "$_self")" && pwd)"
  _self="$(readlink "$_self")"
  [[ "$_self" != /* ]] && _self="$_dir/$_self"
done
SCRIPT_DIR="$(cd "$(dirname "$_self")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

# ── The keys: config/defaults.tsv ────────────────────────────────────────────
# Read whole, and every line checked, before anything is written: a typo in a
# line, or one written by a program, must not leave a run half applied.
if ! defaults_table "$SCRIPT_DIR/../config/defaults.tsv"; then
  err "config/defaults.tsv has a line mrk-defaults cannot use (see above). Nothing was changed."
  exit 1
fi
# A string that starts with ~/ is a path in the home directory.
# shellcheck disable=SC2088  # a literal ~/ in the file, which this expands
for i in "${!DT_VALUE[@]}"; do
  if [[ "${DT_TYPE[i]}" == string && "${DT_VALUE[i]}" == "~/"* ]]; then
    DT_VALUE[i]="$HOME/${DT_VALUE[i]#"~/"}"
  fi
done

# ── The keys to skip: config/defaults-skip.tsv ───────────────────────────────
# Read whole and checked before anything is written, as the table is: a typo
# in a line must not let a run write a key that the line was to skip.
SKIP_FILE="$SCRIPT_DIR/../config/defaults-skip.tsv"
# Every run that can change the skip list, a key or the undo file holds the
# skip list's lock (mrk_lock, lib.sh) from before it reads the list, so a
# switch in Dipstick waits for a make defaults in Terminal, and the other way
# round. --check only reads.
if ! $CHECK; then
  mrk_lock "$SKIP_FILE" || exit 1
  trap 'mrk_unlock_all' EXIT
fi
if ! defaults_skips "$SKIP_FILE"; then
  err "config/defaults-skip.tsv has a line mrk-defaults cannot use (see above). Nothing was changed."
  exit 1
fi
# skipped DOMAIN KEY — true when config/defaults-skip.tsv lists the key
skipped() { [[ "$SKIP_IDS" == *$'\n'"$1$TAB$2"$'\n'* ]]; }

# default_is_set TYPE VALUE CURRENT CURRENT_TYPE — true when a key that
# `defaults read` shows as CURRENT, of the type `defaults read-type` names
# CURRENT_TYPE, already holds VALUE as TYPE. write_default skips such a key,
# and --check calls it set, so the two cannot disagree.
default_is_set(){
  local type="$1" value="$2" current="$3" current_type="$4"
  case "$type" in
    bool)
      local norm_val norm_cur
      [[ "$value" == "true" ]] && norm_val="1" || norm_val="0"
      # defaults read returns 1/0 for booleans
      [[ "$current" == "1" ]] && norm_cur="1" || norm_cur="0"
      [[ "$norm_val" == "$norm_cur" && "$current_type" == "boolean" ]]
      ;;
    int)
      [[ "$current" == "$value" && "$current_type" == "integer" ]]
      ;;
    float)
      [[ "$current_type" == "float" ]] || return 1
      local eq; eq=$(awk "BEGIN{print ($current == $value) ? 1 : 0}" 2>/dev/null || echo "0")
      [[ "$eq" == "1" ]]
      ;;
    string)
      [[ "$current" == "$value" && "$current_type" == "string" ]]
      ;;
    *) return 1 ;;
  esac
}

# exact_string DOMAIN KEY — set EXACT_STRING to the string KEY holds, read from
# an export, and return 1 when that cannot be done. `defaults read` shows a
# backslash in a string doubled, and a character that is not ASCII as an
# escape code, so a string with a backslash in what it shows is read again
# with this. Then a key that holds "a\b" or "café" reads as set, and a run
# does not write it again. A variable, because $( ) drops a final newline.
exact_string(){
  local tmp out
  tmp=$(mrk_mktemp) || return 1
  if ! defaults export "$1" "$tmp" 2>/dev/null ||
     ! out=$(/usr/libexec/PlistBuddy -c "Print \":$2\"" "$tmp" 2>/dev/null && printf x); then
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
  out=${out%x}
  EXACT_STRING=${out%$'\n'}
}

# domain_exists DOMAIN — true when DOMAIN has preferences. A run writes a
# when=existing key only then, and --check calls such a key nodomain when it
# is not, so the two cannot disagree.
domain_exists(){
  defaults read "$1" >/dev/null 2>&1
}

# A key whose app keeps its preferences in a container that this process may
# not read (mrk_container_denied, lib.sh) is neither read nor written. On
# 2026-10-23 Gearbox, without Full Disk Access, read Mail's key as nodomain
# while Terminal read it as set. A launchd job, with neither permission, also
# read TextEdit's as nodomain, and Passwords' from the copy outside the
# container, which a run would have written to.

# ── --check ──────────────────────────────────────────────────────────────────
# Reads each key, as write_default does, and writes nothing: no default, no
# undo line, and no restart.
if $CHECK; then
  command -v defaults >/dev/null 2>&1 || { err "defaults not found, so there is nothing to compare"; exit 1; }
  for i in "${!DT_DOMAIN[@]}"; do
    [[ "${DT_WHEN[i]}" == trackpad ]] && ! $WITH_TRACKPAD && continue
    domain=${DT_DOMAIN[i]} key=${DT_KEY[i]} state=absent current=""
    # No value: what defaults would read is not the one the app uses.
    if mrk_container_denied "$domain"; then
      state=noaccess
    elif current=$(defaults read "$domain" "$key" 2>/dev/null); then
      current_type=$(defaults read-type "$domain" "$key" 2>/dev/null | awk '{print $NF}' || echo "string")
      if [[ "$current_type" == string && "$current" == *\\* ]] && exact_string "$domain" "$key"; then
        current=$EXACT_STRING
      fi
      if default_is_set "${DT_TYPE[i]}" "${DT_VALUE[i]}" "$current" "$current_type"; then
        state="set"
      else
        state="differs"
      fi
      if [[ "$current_type" == boolean ]]; then
        [[ "$current" == 1 ]] && current=true || current=false
      fi
    else
      current=""
      if [[ "${DT_WHEN[i]}" == existing ]] && ! domain_exists "$domain"; then
        state=nodomain
      fi
    fi
    # A run does not write a skipped key, so its value is not drift.
    skipped "$domain" "$key" && state=skipped
    mrk_check_line "$domain" "$key" "${DT_VALUE[i]}" "$current" "$state" >&3
  done
  exit 0
fi

backup_line(){ grep -qFx "$1" "$ROLLBACK" 2>/dev/null && return 0; echo "$1" >> "$ROLLBACK"; }

# value_fragment DOMAIN KEY — print KEY's value as an XML plist fragment
# (<string>…</string>, <real>…</real>, <array>…</array>, …), which
# `defaults write DOMAIN KEY FRAGMENT` takes back with its type and value
# exact. Returns 1 when it cannot. The key is read from an export rather than
# with `defaults read`, which prints a description, not the value: a
# non-ASCII string comes back as escape codes, a backslash doubled, a float
# rounded to seven digits, and an array, dictionary, date or data value as
# text. Until 2026-09-11 the undo script restored those descriptions — a
# round trip through it changed 7 of 23 kinds of value, four of them into a
# string. PlistBuddy, because plutil's key paths split on the dots that
# NSGlobalDomain keys such as com.apple.sound.beep.sound are full of.
value_fragment(){
  local tmp out
  tmp=$(mrk_mktemp) || return 1
  if ! defaults export "$1" "$tmp" 2>/dev/null ||
     ! out=$(/usr/libexec/PlistBuddy -x -c "Print \":$2\"" "$tmp" 2>/dev/null); then
    rm -f "$tmp"
    return 1
  fi
  rm -f "$tmp"
  out=${out#*<plist version=\"1.0\">}
  out=${out%</plist>*}
  while [[ "$out" == $'\n'* ]]; do out=${out#$'\n'}; done
  while [[ "$out" == *$'\n' ]]; do out=${out%$'\n'}; done
  [[ -n "$out" ]] || return 1
  printf '%s' "$out"
}

# Helper: capture current value (if any) and append the inverse to rollback.
# Skips the write if the current value already matches the target (idempotent).
# Uses `defaults read-type` for authoritative type detection.
# Sets DEFAULT_WRITTEN to true when it wrote the key, and to false when not.
# Usage: write_default <domain> <key> <type> <value>
write_default(){
  local domain="$1" key="$2" type="$3" value="$4"
  local current current_type
  DEFAULT_WRITTEN=false

  # Shell-escape with printf %q so values containing ", \, $, newlines, or
  # shell metacharacters survive re-evaluation in the rollback script intact.
  local esc_domain esc_key
  esc_domain=$(printf '%q' "$domain")
  esc_key=$(printf '%q' "$key")

  if current=$(defaults read "$domain" "$key" 2>/dev/null); then
    # Authoritative type detection
    current_type=$(defaults read-type "$domain" "$key" 2>/dev/null | awk '{print $NF}' || echo "string")
    # The string itself, where defaults read shows it changed (exact_string)
    if [[ "$current_type" == string && "$current" == *\\* ]] && exact_string "$domain" "$key"; then
      current=$EXACT_STRING
    fi

    local esc_current
    esc_current=$(printf '%q' "$current")

    # Save rollback BEFORE idempotency check so re-runs preserve first-run originals.
    # Guard skips append when an entry for this domain+key already exists in the file,
    # in either form backup_line writes (trailing space stops prefix collisions).
    if ! grep -qF "defaults write $esc_domain $esc_key " "$ROLLBACK" 2>/dev/null && \
       ! grep -qF "defaults delete $esc_domain $esc_key " "$ROLLBACK" 2>/dev/null; then
      case "$current_type" in
        boolean)
          local bool_val
          [[ "$current" == "1" ]] && bool_val="true" || bool_val="false"
          backup_line "defaults write $esc_domain $esc_key -bool $bool_val"
          ;;
        integer) backup_line "defaults write $esc_domain $esc_key -int $current" ;;
        *)
          # Float, string, and every other type: the exact value, as a fragment.
          # Where the readable form is exact too — a plain ASCII string, a float
          # such as 0.5 — keep the readable form, so the file stays legible.
          local frag
          if ! frag=$(value_fragment "$domain" "$key"); then
            log "could not record $domain $key exactly; its undo line is approximate" >&2
            backup_line "defaults write $esc_domain $esc_key -string $esc_current"
          elif [[ "$current_type" == float && ( "$frag" == "<real>$current</real>" ||
                                                "$frag" == "<real>$current.0</real>" ) ]]; then
            # The second form is a whole number: XML writes 0.0 where defaults
            # read prints 0, and -float stores a whole number exactly.
            backup_line "defaults write $esc_domain $esc_key -float $current"
          elif [[ "$current_type" == string && "$frag" == "<string>$current</string>" ]]; then
            backup_line "defaults write $esc_domain $esc_key -string $esc_current"
          else
            backup_line "defaults write $esc_domain $esc_key $(printf '%q' "$frag")"
          fi
          ;;
      esac
    fi

    # Idempotency: skip write if already at target value and type
    if default_is_set "$type" "$value" "$current" "$current_type"; then
      return 0
    fi
  else
    backup_line "defaults delete $esc_domain $esc_key >/dev/null 2>&1 || true"
  fi

  case "$type" in
    bool)   defaults write "$domain" "$key" -bool "$value" || return 1 ;;
    int)    defaults write "$domain" "$key" -int "$value" || return 1 ;;
    float)  defaults write "$domain" "$key" -float "$value" || return 1 ;;
    string) defaults write "$domain" "$key" -string "$value" || return 1 ;;
    *) log "Unknown type: $type" >&2; return 1 ;;
  esac
  DEFAULT_WRITTEN=true
}

# restart_ui — give the undo script its restarts, and restart the four
# processes now, so the changes show at once. ControlCenter draws the menu bar
# clock and most of the menu bar's items, and reads com.apple.menuextra.clock
# only when it starts. Until 2026-10-22 only SystemUIServer was restarted
# here, so a clock key changed by a run showed only after the next login.
# launchd starts ControlCenter again, as it does SystemUIServer: its KeepAlive
# restarts it on any exit but a clean one.
restart_ui(){
  backup_line "killall Finder >/dev/null 2>&1 || true"
  backup_line "killall Dock >/dev/null 2>&1 || true"
  backup_line "killall SystemUIServer >/dev/null 2>&1 || true"
  backup_line "killall ControlCenter >/dev/null 2>&1 || true"
  killall Finder >/dev/null 2>&1 || true
  killall Dock >/dev/null 2>&1 || true
  killall SystemUIServer >/dev/null 2>&1 || true
  killall ControlCenter >/dev/null 2>&1 || true
}

# ── One key at a time: --skip, --unskip, --key and --revert ──────────────────
# For a program such as mrk Settings, which turns one key off or on: off is
# --skip and --revert, and on is --unskip and --key, in one run. Each key that
# is named, and the skip list as it will be, is checked before anything
# changes, as a run checks the table.

# key_index ID — set KEY_INDEX to the index of ID in config/defaults.tsv, or
# return 1 when the table has no such key
key_index(){
  local i
  for i in "${!DT_DOMAIN[@]}"; do
    if [[ "${DT_DOMAIN[i]}$TAB${DT_KEY[i]}" == "$1" ]]; then
      KEY_INDEX=$i; return 0
    fi
  done
  return 1
}

# skip_list_edit OUT — write config/defaults-skip.tsv to OUT with the keys of
# SKIP added and those of UNSKIP deleted. A new line goes before the first
# entry that sorts after it in byte order, or at the end, and a line leaves
# by its key. Comments, empty lines and the order of the rest stay as they
# are, as sync-login-items edits config/login-items.txt.
skip_list_edit(){
  local out=$1 id line i=0 adds=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && adds+=("$line")
  done < <(
    for id in ${SKIP[@]+"${SKIP[@]}"}; do
      skipped "${id%%"$TAB"*}" "${id#*"$TAB"}" && continue
      printf '%s\t%s\n' "$(mrk_tsv_escape "${id%%"$TAB"*}")" "$(mrk_tsv_escape "${id#*"$TAB"}")"
    done | LC_ALL=C sort -u
  )
  {
    if [[ -e "$SKIP_FILE" ]]; then
      while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" != '#'* && -n "${line//[[:space:]]/}" ]]; then
          mrk_tsv_fields "$line"
          in_ids "${TSV_FIELDS[0]}$TAB${TSV_FIELDS[1]}" ${UNSKIP[@]+"${UNSKIP[@]}"} && continue
          while (( i < ${#adds[@]} )) && ( LC_ALL=C; [[ "${adds[i]}" < "$line" ]] ); do
            printf '%s\n' "${adds[i]}"; i=$((i + 1))
          done
        fi
        printf '%s\n' "$line"
      done < "$SKIP_FILE"
    fi
    while (( i < ${#adds[@]} )); do printf '%s\n' "${adds[i]}"; i=$((i + 1)); done
  } > "$out"
}

# undo_line DOMAIN KEY — set UNDO_LINE to the line of the undo script that puts
# KEY back, in either form write_default writes, or return 1 when it has none
undo_line(){
  local w d line
  w="defaults write $(printf '%q' "$1") $(printf '%q' "$2") "
  d="defaults delete $(printf '%q' "$1") $(printf '%q' "$2") "
  [[ -r "$ROLLBACK" ]] || return 1
  while IFS= read -r line; do
    case "$line" in
      "$w"*|"$d"*) UNDO_LINE=$line; return 0 ;;
    esac
  done < "$ROLLBACK"
  return 1
}

if $ONE_KEY; then
  for id in ${SKIP[@]+"${SKIP[@]}"} ${UNSKIP[@]+"${UNSKIP[@]}"} ${KEY[@]+"${KEY[@]}"} ${REVERT[@]+"${REVERT[@]}"}; do
    if ! key_index "$id"; then
      err "$(shown "$id") is not a key of config/defaults.tsv. Nothing was changed."
      exit 1
    fi
  done
  # --skip and --unskip change only the list; --key and --revert change the
  # key, which a process that cannot read it cannot do right.
  for id in ${KEY[@]+"${KEY[@]}"} ${REVERT[@]+"${REVERT[@]}"}; do
    if mrk_container_denied "${id%%"$TAB"*}"; then
      err "macOS does not let this process read ${id%%"$TAB"*}, so it cannot change $(shown "$id")."
      info "Give Full Disk Access to the app that runs this (System Settings → Privacy & Security). Nothing was changed."
      exit 1
    fi
  done

  # The skip list as it will be, checked as a run checks it, and then the
  # keys to write against it
  new_list=""
  if (( ${#SKIP[@]} + ${#UNSKIP[@]} > 0 )); then
    was_skipped=$SKIP_IDS
    # Beside the file, so that mv replaces it in one step
    new_list=$(mktemp "${SKIP_FILE%/*}/.defaults-skip.tsv.XXXXXX") || { err "Cannot write a file beside $SKIP_FILE. Nothing was changed."; exit 1; }
    trap 'rm -f "$new_list"; mrk_unlock_all' EXIT
    skip_list_edit "$new_list"
    if ! defaults_skips "$new_list"; then
      err "config/defaults-skip.tsv would have a line mrk-defaults cannot use (see above). Nothing was changed."
      exit 1
    fi
  fi
  for id in ${KEY[@]+"${KEY[@]}"}; do
    if skipped "${id%%"$TAB"*}" "${id#*"$TAB"}"; then
      err "config/defaults-skip.tsv skips $(shown "$id"), so mrk-defaults does not write it. Give --unskip too. Nothing was changed."
      exit 1
    fi
  done

  if [[ -n "$new_list" ]]; then
    if [[ ! -e "$SKIP_FILE" ]] || ! cmp -s "$new_list" "$SKIP_FILE"; then
      chmod 644 "$new_list"
      mv -f "$new_list" "$SKIP_FILE"
    fi
    for id in ${SKIP[@]+"${SKIP[@]}"}; do
      if [[ "$was_skipped" == *$'\n'"$id"$'\n'* ]]; then
        log "$(shown "$id") was skipped already"
      else
        ok "Skipped $(shown "$id"): make defaults does not write it"
      fi
    done
    for id in ${UNSKIP[@]+"${UNSKIP[@]}"}; do
      if [[ "$was_skipped" == *$'\n'"$id"$'\n'* ]]; then
        ok "$(shown "$id") is not skipped now: make defaults writes it"
      else
        log "$(shown "$id") was not skipped"
      fi
    done
  fi

  changed=false
  failed=0
  if (( ${#KEY[@]} > 0 )); then
    init_rollback "$ROLLBACK" || exit 1
  fi
  for id in ${KEY[@]+"${KEY[@]}"}; do
    key_index "$id"; i=$KEY_INDEX
    if [[ "${DT_WHEN[i]}" == existing ]] && ! domain_exists "${DT_DOMAIN[i]}"; then
      logskip "$(shown "$id")" "its domain does not exist yet"
      continue
    fi
    if ! write_default "${DT_DOMAIN[i]}" "${DT_KEY[i]}" "${DT_TYPE[i]}" "${DT_VALUE[i]}"; then
      err "Could not write $(shown "$id")"
      failed=$(( failed + 1 ))
    elif $DEFAULT_WRITTEN; then
      ok "Wrote $(shown "$id")"
      changed=true
    else
      log "$(shown "$id") is set already"
    fi
  done
  for id in ${REVERT[@]+"${REVERT[@]}"}; do
    if ! undo_line "${id%%"$TAB"*}" "${id#*"$TAB"}"; then
      log "$(shown "$id") has no line in $ROLLBACK, so mrk did not change it on this Mac. It stays as it is."
      continue
    fi
    # The undo script's own line, which bash ~/.mrk/defaults-rollback.sh runs
    # too: write_default made it with printf %q, so eval runs it as written.
    if eval "$UNDO_LINE"; then
      ok "Put back $(shown "$id") as it was before mrk"
      changed=true
    else
      err "Could not put back $(shown "$id")"
      failed=$(( failed + 1 ))
    fi
  done

  if $changed; then
    restart_ui
  fi
  if (( failed > 0 )); then
    warn "$failed key(s) failed. Revert with: $ROLLBACK"
    exit 1
  fi
  exit 0
fi

# Create rollback directory and script with error checking
if ! mkdir -p "$ROLL_DIR"; then
  echo "Error: Failed to create rollback directory: $ROLL_DIR" >&2
  exit 1
fi

# Initialise the rollback script. This moved below the lib.sh source so that
# both writers of this file can share one implementation; nothing between the
# two depended on it. See init_rollback in lib.sh for why it no longer
# truncates.
init_rollback "$ROLLBACK" || exit 1

log "Applying macOS defaults..."

# Track failures, and keys this process may not read
failed=0
denied=0
said_trackpad=false

for i in "${!DT_DOMAIN[@]}"; do
  [[ "${DT_WHEN[i]}" == trackpad ]] && ! $WITH_TRACKPAD && continue
  if skipped "${DT_DOMAIN[i]}" "${DT_KEY[i]}"; then
    logskip "${DT_DOMAIN[i]} ${DT_KEY[i]}" "config/defaults-skip.tsv skips it"
    continue
  fi
  # Without access the key reads as absent, or from a file the app does not
  # read: write_default would record the wrong undo line, and the write would
  # fail or go to that file.
  if mrk_container_denied "${DT_DOMAIN[i]}"; then
    logskip "${DT_DOMAIN[i]} ${DT_KEY[i]}" "macOS does not let this process read its app's data"
    denied=$(( denied + 1 ))
    continue
  fi
  case "${DT_WHEN[i]}" in
    trackpad)
      if ! $said_trackpad; then
        log "Applying trackpad defaults..."
        said_trackpad=true
      fi
      ;;
    existing)
      # A sandboxed app keeps its preferences in its container, and they do
      # not exist until the app is set up or first used. Before that, a write
      # goes wrong in one of two ways. For Mail, `defaults write` fails
      # outright: a Mac where Mail was never set up reported a failed write
      # on every run, and a warning that is always there hides a real
      # failure. For TextEdit, the write succeeds into ~/Library/Preferences,
      # which TextEdit never reads once it has a container: on this Mac
      # RichText=0 sat there from 2026-09-15, and TextEdit never saw it.
      # Reading the domain is the test: the container directory exists
      # before the domain does. Once the app has preferences, `defaults`
      # reads and writes them in the container, and the next run writes the
      # key there.
      if ! domain_exists "${DT_DOMAIN[i]}"; then
        logskip "${DT_DOMAIN[i]} ${DT_KEY[i]}" "its domain does not exist yet"
        continue
      fi
      ;;
  esac
  write_default "${DT_DOMAIN[i]}" "${DT_KEY[i]}" "${DT_TYPE[i]}" "${DT_VALUE[i]}" || failed=$(( failed + 1 ))
done

log "Writing rollback helper to $ROLLBACK"
restart_ui

if (( denied > 0 )); then
  warn "$denied key(s) passed over: macOS does not let this process read their apps' data."
  info "Give Full Disk Access to the app that runs make defaults (System Settings → Privacy & Security), and run it again."
fi

# Exit 1 when any write failed, after every write has been tried and the undo
# lines written, as the six app-defaults scripts have since 2026-09-11. Until
# 2026-09-28 this warned, then printed "Defaults applied" and exited 0, so
# setup's "defaults.sh returned non-zero" warning could never fire and make
# defaults always succeeded (audit 19, W-19).
if (( failed > 0 )); then
  warn "$failed default(s) failed to apply; the rest are applied. Revert with: $ROLLBACK"
  exit 1
fi
ok "Defaults applied. Revert with: $ROLLBACK"
