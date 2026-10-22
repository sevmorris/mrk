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

Options:
      --with-trackpad  Also apply the trackpad gesture settings
      --check          Compare each key with this Mac, and change nothing.
                       One line for each key, tab-separated: the domain, the
                       key, the value mrk sets, the value it has now, and set,
                       differs or absent. Nothing else on stdout. Exits 0 when
                       it could tell, 1 when it refused, 2 for a bad option.
  -h, --help           Show this help

mrk-defaults writes the keys that config/defaults.tsv lists, in its order,
and appends an undo line for each one to ~/.mrk/defaults-rollback.sh, so
every change it makes can be reversed. It is idempotent: a second run leaves
both the system state and the rollback script unchanged. It refuses the whole
file, before it writes anything, when a line is not one key. Run it as
`make defaults`, or with the trackpad keys as `make trackpad`.

With --check, a field escapes a tab, a newline and a backslash as
config/defaults.tsv does (\t, \n, \\), and a bool's value is true or false.
A key whose value is right but whose type is not differs, as a run would
write it. --with-trackpad adds the trackpad keys to the check as well.
EOF
}

WITH_TRACKPAD=false
CHECK=false
for arg in "$@"; do
  case "$arg" in
    --with-trackpad) WITH_TRACKPAD=true ;;
    --check)         CHECK=true ;;
    -h|--help)       usage; exit 0 ;;
    *)               usage >&2
                     printf '\nunknown argument: %s\n' "$arg" >&2
                     exit 2 ;;
  esac
done

# --check is for a program to read (the Settings app), on stdout, which holds
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

# ── --check ──────────────────────────────────────────────────────────────────
# Reads each key, as write_default does, and writes nothing: no default, no
# undo line, and no restart.
if $CHECK; then
  command -v defaults >/dev/null 2>&1 || { err "defaults not found, so there is nothing to compare"; exit 1; }
  # check_field TEXT — TEXT as a field of config/defaults.tsv
  check_field(){
    local s=${1//\\/\\\\}
    s=${s//$'\t'/\\t}
    printf '%s' "${s//$'\n'/\\n}"
  }
  for i in "${!DT_DOMAIN[@]}"; do
    [[ "${DT_WHEN[i]}" == trackpad ]] && ! $WITH_TRACKPAD && continue
    domain=${DT_DOMAIN[i]} key=${DT_KEY[i]} state=absent current=""
    if current=$(defaults read "$domain" "$key" 2>/dev/null); then
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
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$(check_field "$domain")" "$(check_field "$key")" \
      "$(check_field "${DT_VALUE[i]}")" "$(check_field "$current")" "$state" >&3
  done
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
# Usage: write_default <domain> <key> <type> <value>
write_default(){
  local domain="$1" key="$2" type="$3" value="$4"
  local current current_type

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
}

log "Applying macOS defaults..."

# Track failures
failed=0
said_trackpad=false

for i in "${!DT_DOMAIN[@]}"; do
  case "${DT_WHEN[i]}" in
    trackpad)
      $WITH_TRACKPAD || continue
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
      if ! defaults read "${DT_DOMAIN[i]}" >/dev/null 2>&1; then
        logskip "${DT_DOMAIN[i]} ${DT_KEY[i]}" "its domain does not exist yet"
        continue
      fi
      ;;
  esac
  write_default "${DT_DOMAIN[i]}" "${DT_KEY[i]}" "${DT_TYPE[i]}" "${DT_VALUE[i]}" || failed=$(( failed + 1 ))
done

log "Writing rollback helper to $ROLLBACK"
backup_line "killall Finder >/dev/null 2>&1 || true"
backup_line "killall Dock >/dev/null 2>&1 || true"
backup_line "killall SystemUIServer >/dev/null 2>&1 || true"

# Apply immediate effects
killall Finder >/dev/null 2>&1 || true
killall Dock >/dev/null 2>&1 || true
killall SystemUIServer >/dev/null 2>&1 || true

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
