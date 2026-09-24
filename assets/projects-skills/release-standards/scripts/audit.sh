#!/usr/bin/env bash
# audit.sh — the read-only survey behind a release-standards pass in ~/Projects.
#
# Every release.sh in this collection is a separate copy of the same idea, so a
# lesson learned in one repo reaches the others only by hand. This prints which
# repos carry each guard, which are missing one, and the repo state a release
# would trip over. It changes nothing.
#
# Usage: audit.sh [--verbose] [PROJECTS_DIR]
#   PROJECTS_DIR  where the app repos live (default: $PROJECTS, then ~/Projects)
#   --verbose     also print the local/published version of each app

set -uo pipefail

VERBOSE=0
PROJECTS=""
for arg in "$@"; do
  case "$arg" in
    --verbose|-v) VERBOSE=1 ;;
    -h|--help)    sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)           echo "audit.sh: unknown option: $arg" >&2; exit 2 ;;
    *)            PROJECTS=$arg ;;
  esac
done
PROJECTS=${PROJECTS:-${PROJECTS_DIR:-$HOME/Projects}}
GREP=/usr/bin/grep   # not a shell function or alias, whatever the caller has

[[ -d "$PROJECTS" ]] || { echo "audit.sh: no such directory: $PROJECTS" >&2; exit 1; }

h() { printf '\n== %s\n' "$*"; }

# Repos with a release.sh, found rather than listed, so a new app appears here
# without editing this script. WireHack is retired and archived, and is not
# expected to carry the full set; it is still shown, marked.
REPOS=()
while IFS= read -r f; do REPOS+=("$(dirname "$f")"); done < <(
  find "$PROJECTS" -maxdepth 2 -name release.sh -not -path '*/node_modules/*' | sort
)
(( ${#REPOS[@]} )) || { echo "audit.sh: no release.sh found under $PROJECTS" >&2; exit 1; }

# Each guard: label, and the pattern that proves it is present. Patterns match
# the reference implementation in WaxOnWaxOff; a repo that solves the same
# problem differently will read as missing, which is a prompt to look, not a
# verdict.
GUARDS=(
  "notes-gate|NOTES_FILE"
  "notary|NOTARY_PROFILE"
  "py3-subproc|cannot start a subprocess"
  "remote-tags|fetch --tags"
  "ancestry|merge-base --is-ancestor"
  "atomic-push|push --atomic"
  "dmg-verify|DS_Store"
  "dmg-signed|timestamp --sign"
  "app-stapled|ditto -c -k"
  "generic-dest|generic/platform=macOS"
  "v-tag-filter|tag --list 'v\[0-9\]"
  "exit-trap|trap cleanup EXIT"
  "signal-trap|trap 'exit 143' TERM"
  "shared-files|check-shared"
)

h "Guards by repo  (yes = present, -- = missing)"
printf '%-24s' "REPO"
for g in "${GUARDS[@]}"; do printf '%-13s' "${g%%|*}"; done
printf '\n'
printf '%.0s-' $(seq 1 $((24 + 13 * ${#GUARDS[@]}))); printf '\n'

MISSING_REPORT=""
for d in "${REPOS[@]}"; do
  name=$(basename "$d")
  note=""
  [[ "$name" == "WireHack" ]] && note=" *"
  # Two guards only mean something for a styled DMG. A script that builds a
  # plain image with `hdiutil create` has no dmgbuild to crash and no installer
  # window to verify, so they are n/a rather than missing.
  styled=0
  $GREP -q -- "dmgbuild" "$d/release.sh" 2>/dev/null && styled=1
  # Shared-file checking only means something for a repo in the sibling set,
  # which is exactly the set that carries scripts/check-shared.sh.
  sibling=0
  [[ -f "$d/scripts/check-shared.sh" ]] && sibling=1
  printf '%-24s' "$name$note"
  for g in "${GUARDS[@]}"; do
    label="${g%%|*}"; pat="${g#*|}"
    if [[ $styled -eq 0 && ( "$label" == "dmg-verify" || "$label" == "py3-subproc" ) ]]; then
      printf '%-13s' "n/a"
    elif [[ $sibling -eq 0 && "$label" == "shared-files" ]]; then
      printf '%-13s' "n/a"
    elif $GREP -q -- "$pat" "$d/release.sh" 2>/dev/null; then
      printf '%-13s' "yes"
    else
      printf '%-13s' "--"
      MISSING_REPORT+="  $name: $label"$'\n'
    fi
  done
  printf '\n'
done
echo
echo "  * WireHack is retired and archived (ClipHack supersedes it); it is not expected to carry these."

h "Missing guards, as a list"
if [[ -n "$MISSING_REPORT" ]]; then printf '%s' "$MISSING_REPORT"; else echo "  (none)"; fi

h "Repo state a release would trip over"
for d in "${REPOS[@]}"; do
  name=$(basename "$d")
  cd "$d" 2>/dev/null || continue
  problems=""
  dirty=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  [[ "$dirty" != "0" ]] && problems+="dirty($dirty) "
  ahead=$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo "?")
  behind=$(git rev-list --count 'HEAD..@{u}' 2>/dev/null || echo "?")
  [[ "$ahead" != "0" && "$ahead" != "?" ]] && problems+="ahead($ahead) "
  [[ "$behind" != "0" && "$behind" != "?" ]] && problems+="behind($behind) "
  # A release-notes directory is where the gate looks; without one every
  # release needs --generated-notes.
  [[ -d "$d/release-notes" ]] || problems+="no-release-notes-dir "
  if [[ -n "$problems" ]]; then
    printf '  %-24s %s\n' "$name" "$problems"
  elif (( VERBOSE )); then
    printf '  %-24s clean\n' "$name"
  fi
done
(( VERBOSE )) || echo "  (repos not listed are clean and in sync; -v to show them)"

h "Version: local tag vs what the app's own updater would fetch"
if (( VERBOSE )); then
  for d in "${REPOS[@]}"; do
    name=$(basename "$d"); cd "$d" 2>/dev/null || continue
    tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null || echo "-")
    notes="$d/release-notes/${tag}.md"
    printf '  %-24s tag %-12s curated notes %s\n' "$name" "$tag" \
      "$( [[ -f "$notes" ]] && echo yes || echo '--' )"
  done
else
  echo "  (-v to show)"
fi

h "Next"
cat <<'TXT'
  Port a missing guard from WaxOnWaxOff's release.sh, which carries the full
  set. Keep the comment that says which failure it prevents — that is what
  stops the next person removing it as noise.
TXT
