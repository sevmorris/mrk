#!/usr/bin/env bash
# hide_tm.sh — hide Time Machine volumes from Finder sidebar
set -euo pipefail

VOLS="${TM_VOLUMES:-${1:-TimeMachine}}"

IFS=',' read -ra NAMES <<<"$VOLS"

for NAME in "${NAMES[@]}"; do
  NAME="$(echo "$NAME" | sed 's/^ *//; s/ *$//')" # trim
  [ -n "$NAME" ] || continue
  /usr/bin/osascript -e 'on run argv
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
        return e as text
      end try
    end tell
  end run' "$NAME" >/dev/null || true
done
