#!/usr/bin/env bash
# check.sh — are the third-party pieces the apps ship still current?
#
# Compares every vendored pin under ~/Projects (<repo>/Vendor/*-manifest.env:
# yt-dlp, FFmpeg, LAME) with its latest upstream release, and lists open
# Dependabot alerts across the account. It changes nothing in any repository;
# updating is the skill's procedure, not this script's.
#
# Usage: check.sh [--session | --refresh | --list | --ack ID...|all]
#   (none)     check now, print the report, and refresh the cache
#   --session  SessionStart hook: print what the cache says is behind, from
#              cache only, and refresh it in the background once it is older
#              than DEPS_TTL_HOURS (default 12). Fast, silent when current,
#              and always exits 0 so it can never block a session.
#   --refresh  check now, update the cache, print nothing
#   --list     the cached findings with their ids, and which are acknowledged
#   --ack      stop surfacing these findings at session start. An id names the
#              upstream version it was raised for, so a newer release raises
#              it again. "all" acknowledges everything currently cached.
#
# Env: DEPS_PROJECTS_DIR (default ~/Projects), DEPS_STATE_DIR (default
# ~/Library/Caches/dependency-updates), DEPS_TTL_HOURS.

if (( BASH_VERSINFO[0] < 4 )); then
  for b in /opt/homebrew/bin/bash /usr/local/bin/bash; do [[ -x $b ]] && exec "$b" "$0" "$@"; done
  [[ ${1:-} == --session ]] && exit 0
  echo "check.sh: needs bash 4 or later" >&2; exit 1
fi
set -uo pipefail

# A hook can start with launchd's PATH, which has no Homebrew. Without this the
# background refresh would find no gh or jq, and the cache would never update.
for d in /opt/homebrew/bin /usr/local/bin; do
  [[ -d $d && ":$PATH:" != *":$d:"* ]] && PATH="$PATH:$d"
done

PROJECTS=${DEPS_PROJECTS_DIR:-$HOME/Projects}
STATE=${DEPS_STATE_DIR:-$HOME/Library/Caches/dependency-updates}
TTL_HOURS=${DEPS_TTL_HOURS:-12}
FINDINGS="$STATE/findings.tsv"    # id <TAB> summary, one per thing that needs attention
REPORT="$STATE/report.txt"
STAMP="$STATE/checked-at"         # epoch seconds of the last complete check
ACKED="$STATE/acked"
SELF="${BASH_SOURCE[0]}"

MODE=report; ACK_IDS=()
case "${1:-}" in
  "")         ;;
  --session)  MODE=session ;;
  --refresh)  MODE=refresh ;;
  --list)     MODE=list ;;
  --ack)      MODE=ack; shift; ACK_IDS=("$@") ;;
  -h|--help)  sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  *)          echo "check.sh: unknown option: $1" >&2; exit 2 ;;
esac

mkdir -p "$STATE" 2>/dev/null || { [[ $MODE == session ]] && exit 0; echo "check.sh: cannot create $STATE" >&2; exit 1; }
touch "$ACKED" 2>/dev/null

# ── Session mode: read the cache, never the network ────────────────────────────

if [[ $MODE == session ]]; then
  now=$(date +%s); last=$(cat "$STAMP" 2>/dev/null || echo 0)
  if (( now - last > TTL_HOURS * 3600 )); then
    # One refresh at a time. mkdir is atomic; a lock older than ten minutes is
    # from a refresh that died, and is taken over.
    lock="$STATE/refresh.lock"
    if [[ -d $lock ]] && [[ -n $(find "$lock" -maxdepth 0 -mmin +10 2>/dev/null) ]]; then rmdir "$lock" 2>/dev/null; fi
    if mkdir "$lock" 2>/dev/null; then
      ( trap 'rmdir "$lock" 2>/dev/null' EXIT; "$SELF" --refresh ) </dev/null >/dev/null 2>&1 &
      disown 2>/dev/null
    fi
  fi
  [[ -s $FINDINGS ]] || exit 0
  pending=$(awk -F'\t' 'FILENAME == ARGV[1] { acked[$1] = 1; next } !($1 in acked) { print "- " $2 }' "$ACKED" "$FINDINGS")
  [[ -n $pending ]] || exit 0
  printf -v when '%(%Y-%m-%d %H:%M)T' "$last"
  dir=$(cd "$(dirname "$SELF")/.." && pwd)
  cat <<EOF
Third-party dependency check, $when (skill: $dir/SKILL.md):
$pending
Mention this to the user once, briefly, at a natural point in the session; do not interrupt a task for it. An update changes pins, lockfiles or releases, so start one only on their go-ahead, following that skill. \`$dir/scripts/check.sh --ack all\` silences these until something newer appears.
EOF
  exit 0
fi

if [[ $MODE == list ]]; then
  [[ -s $FINDINGS ]] || { echo "No cached findings. Run check.sh to check now."; exit 0; }
  printf 'Checked %(%Y-%m-%d %H:%M)T\n' "$(cat "$STAMP" 2>/dev/null || echo 0)"
  awk -F'\t' 'FILENAME == ARGV[1] { acked[$1] = 1; next } { printf "%s  %s%s\n", $1, $2, ($1 in acked ? "   [acknowledged]" : "") }' "$ACKED" "$FINDINGS"
  exit 0
fi

if [[ $MODE == ack ]]; then
  (( ${#ACK_IDS[@]} )) || { echo "check.sh --ack: give one or more ids, or all" >&2; exit 2; }
  if [[ ${ACK_IDS[0]} == all ]]; then
    cut -f1 "$FINDINGS" 2>/dev/null >> "$ACKED"
  else
    for id in "${ACK_IDS[@]}"; do
      cut -f1 "$FINDINGS" 2>/dev/null | grep -qxF -- "$id" || { echo "check.sh: no current finding with id $id (see --list)" >&2; exit 1; }
      printf '%s\n' "$id" >> "$ACKED"
    done
  fi
  sort -u -o "$ACKED" "$ACKED"
  echo "Acknowledged. The session notice will skip these until upstream moves again."
  exit 0
fi

# ── A full check ───────────────────────────────────────────────────────────────

for t in gh jq curl; do
  command -v "$t" >/dev/null 2>&1 || { echo "check.sh: $t not found" >&2; exit 1; }
done
# Unreachable GitHub means nothing below can be trusted. Leave the cache as it
# was, stamp and all, so the next session tries again rather than going quiet.
if ! gh api rate_limit --silent >/dev/null 2>&1; then
  echo "check.sh: GitHub is unreachable or gh is not logged in; cache left as it was" >&2
  exit 1
fi

WORK=$(mktemp -d "${TMPDIR:-/tmp}/dependency-updates.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
: > "$WORK/pins"      # dep  repo  pinned  newest-on-branch  newest
: > "$WORK/findings"
: > "$WORK/notes"

newer() { [[ $1 != "$2" && $(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -1) == "$2" ]]; }  # is $2 newer than $1
val()   { sed -nE "s/^$1=\"?([^\"#]*)\"?.*/\1/p" "$2" | head -1 | tr -d '[:space:]'; }

# Upstream answers, asked once each however many repos pin them. The answer is
# left in UPV rather than printed: a $(...) caller would run this in a subshell,
# and the cache would be thrown away with it.
declare -A UP
upstream() {
  [[ -n ${UP[$1]+x} ]] && { UPV=${UP[$1]}; return; }
  local v=""
  case "$1" in
    yt-dlp:*)
      v=$(gh api "repos/${1#yt-dlp:}/releases/latest" --jq .tag_name 2>/dev/null) ;;
    ffmpeg-tags)
      v=$(gh api 'repos/FFmpeg/FFmpeg/git/matching-refs/tags/n' --jq '.[].ref' 2>/dev/null \
          | sed 's#^refs/tags/n##' | grep -E '^[0-9]+\.[0-9]+(\.[0-9]+)?$' | sort -V | tr '\n' ' ') ;;
    lame)
      v=$(curl -fsS --max-time 15 https://sourceforge.net/projects/lame/best_release.json 2>/dev/null \
          | jq -r '.release.filename // empty' | sed -nE 's#.*/lame-([0-9][0-9.]*)\.tar\.gz$#\1#p') ;;
  esac
  UP[$1]=$v; UPV=$v
}

while IFS= read -r m; do
  repo=${m#"$PROJECTS"/}; repo=${repo%%/*}
  if tag=$(val YTDLP_TAG "$m"); [[ -n $tag ]]; then
    src=$(val YTDLP_REPO "$m"); upstream "yt-dlp:${src:-yt-dlp/yt-dlp}"; latest=$UPV
    if [[ -z $latest ]]; then echo "yt-dlp ($repo): could not read the latest release" >> "$WORK/notes"
    else printf 'yt-dlp\t%s\t%s\t%s\t%s\n' "$repo" "$tag" "$latest" "$latest" >> "$WORK/pins"; fi
  fi
  if ff=$(val FFMPEG_SOURCE_RELEASE "$m"); [[ -n $ff ]]; then
    upstream ffmpeg-tags; tags=$UPV
    if [[ -z $tags ]]; then echo "FFmpeg ($repo): could not read the release tags" >> "$WORK/notes"
    else
      branch=$(cut -d. -f1-2 <<<"$ff")
      on_branch=$(tr ' ' '\n' <<<"$tags" | grep -E "^${branch//./\\.}(\.|$)" | tail -1)
      printf 'FFmpeg\t%s\t%s\t%s\t%s\n' "$repo" "$ff" "${on_branch:-$ff}" "$(tr ' ' '\n' <<<"$tags" | grep . | tail -1)" >> "$WORK/pins"
    fi
  fi
  lame=$(val LAME_VERSION "$m")
  [[ -z $lame ]] && lame=$(val LAME_SOURCE_URL "$m" | sed -nE 's#.*/lame-([0-9][0-9.]*)\.tar\.gz$#\1#p')
  if [[ -n $lame ]]; then
    upstream lame; latest=$UPV
    if [[ -z $latest ]]; then echo "LAME ($repo): could not read the latest release from SourceForge" >> "$WORK/notes"
    else printf 'LAME\t%s\t%s\t%s\t%s\n' "$repo" "$lame" "$latest" "$latest" >> "$WORK/pins"; fi
  fi
  # A pin this script has no upstream check for is a finding, not a footnote: a
  # new vendored tool must not go unwatched just because nobody taught this file.
  while IFS= read -r k; do
    case "$k" in YTDLP_VERSION|FFMPEG_VERSION|FFMPEG_SOURCE_RELEASE|LAME_VERSION) continue ;; esac
    v=$(val "$k" "$m")
    printf 'unchecked:%s:%s:%s\t%s pins %s %s (%s), and check.sh has no upstream check for it yet\n' \
      "$repo" "${k%_VERSION}" "$v" "$repo" "${k%_VERSION}" "$v" "${m#"$PROJECTS"/}" >> "$WORK/findings"
  done < <(sed -nE 's/^([A-Z0-9_]+_VERSION)=.*/\1/p' "$m")
done < <(find "$PROJECTS" -maxdepth 4 -path '*/Vendor/*-manifest.env' -not -path '*/build/*' -not -path '*/.build/*' 2>/dev/null | sort)

# One finding per dependency and pinned version, naming every repo that pins it.
# The id carries the upstream versions it was raised against, so acknowledging
# it lasts only until upstream moves.
sort -t$'\t' -k1,1 -k3,3V -k2,2f "$WORK/pins" | awk -F'\t' '
  { key = $1 FS $3 FS $4 FS $5; repos[key] = (key in repos ? repos[key] ", " : "") $2; if (!(key in seen)) { seen[key] = 1; order[++n] = key } }
  END { for (i = 1; i <= n; i++) print order[i] FS repos[order[i]] }' > "$WORK/grouped"
while IFS=$'\t' read -r dep pinned branch_new newest repos; do
  line=""; id=""
  if newer "$pinned" "$branch_new"; then
    line="$dep in $repos: $pinned → $branch_new"; id="$dep:$pinned:$branch_new"
    [[ $dep == FFmpeg ]] && line+=" (point release on its branch)"
  fi
  if [[ $dep == FFmpeg ]] && newer "$branch_new" "$newest" && [[ $(cut -d. -f1-2 <<<"$newest") != $(cut -d. -f1-2 <<<"$pinned") ]]; then
    if [[ -n $line ]]; then line+="; newest line is $newest"; else line="$dep in $repos: $pinned is current on its branch; newest line is $newest"; fi
    id="${id:-$dep:$pinned}:$newest"
  fi
  [[ -n $line ]] && printf '%s\t%s\n' "${id,,}" "$line" >> "$WORK/findings"
done < "$WORK/grouped"

# Dependabot, for every non-archived repository the account owns. The id is
# the newest alert's number, so a new alert raises it again.
gql='query { viewer { repositories(first: 100, ownerAffiliations: OWNER, isArchived: false) { nodes { name
  vulnerabilityAlerts(states: OPEN, first: 100) { totalCount nodes { number dependencyScope securityVulnerability { severity } } } } } } }'
if alerts=$(gh api graphql -f query="$gql" 2>/dev/null); then
  jq -r '.data.viewer.repositories.nodes[] | select(.vulnerabilityAlerts.totalCount > 0) | .vulnerabilityAlerts as $a
    | ([$a.nodes[] | select(.securityVulnerability.severity == "HIGH" or .securityVulnerability.severity == "CRITICAL")] | length) as $hi
    | ([$a.nodes[].dependencyScope] | unique) as $sc
    | "alerts:\(.name):\([$a.nodes[].number] | max)\t\(.name): \($a.totalCount) open Dependabot alert\(if $a.totalCount == 1 then "" else "s" end)"
      + (if $hi > 0 then ", \($hi) high or critical" else "" end)
      + (if $sc == ["DEVELOPMENT"] then ", all in development dependencies" else "" end)' <<<"$alerts" >> "$WORK/findings"
else
  echo "Dependabot: the GraphQL query failed" >> "$WORK/notes"
fi

{
  echo "== Vendored pins (<repo>/Vendor/*-manifest.env)"
  if [[ -s $WORK/pins ]]; then
    { printf 'DEPENDENCY\tREPO\tPINNED\tNEWEST ON BRANCH\tNEWEST\n'; sort -t$'\t' -k1,1 -k2,2f "$WORK/pins"; } | column -t -s$'\t' | sed 's/^/  /'
  else
    echo "  none found under $PROJECTS"
  fi
  echo; echo "== Needs attention"
  if [[ -s $WORK/findings ]]; then
    awk -F'\t' 'FILENAME == ARGV[1] { acked[$1] = 1; next } { printf "  %s%s\n      id: %s\n", $2, ($1 in acked ? "   [acknowledged]" : ""), $1 }' "$ACKED" "$WORK/findings"
  else
    echo "  nothing"
  fi
  if [[ -s $WORK/notes ]]; then echo; echo "== Not checked"; sed 's/^/  /' "$WORK/notes"; fi
} > "$WORK/report"

cp "$WORK/findings" "$FINDINGS" && cp "$WORK/report" "$REPORT" && date +%s > "$STAMP"
# Acknowledgements for findings that no longer exist are dropped, so the file
# does not grow for ever.
awk -F'\t' 'FILENAME == ARGV[1] { cur[$1] = 1; next } $1 in cur' "$FINDINGS" "$ACKED" > "$WORK/acked" && cp "$WORK/acked" "$ACKED"

[[ $MODE == report ]] && cat "$REPORT"
exit 0
