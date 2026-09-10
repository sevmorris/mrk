#!/usr/bin/env bash
# hide_tm.sh — hide Time Machine volumes from Finder sidebar
set -euo pipefail

usage() {
  cat <<'EOF'
hide_tm.sh — hide Time Machine volumes from the Finder sidebar

Usage:
  hide_tm.sh [volume[,volume...]]

Options:
  -h, --help      Show this help

hide_tm.sh takes one optional argument: a comma-separated list of volume names,
defaulting to "TimeMachine". Set TM_VOLUMES to the same list to supply it from
the environment instead; the environment wins when both are given.

  hide_tm.sh                        hides "TimeMachine"
  hide_tm.sh "TM Backup,Archive"    hides both
EOF
}

# One argument, not several. The list is comma-separated precisely so that
# several volumes fit in one word, and reading only $1 meant a space-separated
# attempt lost everything after the first name without saying so.
case "${1:-}" in
  -h|--help) usage; exit 0 ;;
  -*)        usage >&2; printf '\nunknown argument: %s\n' "$1" >&2; exit 2 ;;
esac
if (( $# > 1 )); then
  usage >&2
  printf '\nToo many arguments — pass one comma-separated list: "%s"\n' "$*" >&2
  exit 2
fi

VOLS="${TM_VOLUMES:-${1:-TimeMachine}}"

IFS=',' read -ra NAMES <<<"$VOLS"

for NAME in "${NAMES[@]}"; do
  NAME="${NAME#"${NAME%%[![:space:]]*}"}"  # trim leading whitespace
  NAME="${NAME%"${NAME##*[![:space:]]}"}"  # trim trailing whitespace
  [ -n "$NAME" ] || continue
  if ! /usr/bin/osascript -e 'on run argv
    set volName to item 1 of argv
    tell application "System Events"
      try
        tell application "Finder"
          set sidebarList to name of every disk
          repeat with d in sidebarList
            if d as text is equal to volName as text then
              set visible of disk (d as text) to false
            end if
          end repeat
        end tell
        return "OK"
      on error e
        error e
      end try
    end tell
  end run' "$NAME" >/dev/null; then
    printf "[hide_tm] warning: osascript failed for volume: %s\n" "$NAME" >&2
  fi
done
