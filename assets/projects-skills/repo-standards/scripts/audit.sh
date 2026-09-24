#!/usr/bin/env bash
# audit.sh — the read-only survey behind a repo-standards pass.
#
# release-standards covers the release machinery inside each app. This covers
# everything around it, for every repository on the account: branch rules,
# secret push protection, vulnerability alerts, Pages, licence, README, tests in
# CI, current CI actions, and no committed executables. It reads the published
# state from GitHub, so a repository with no clone here is still audited. It
# changes nothing.
#
# Usage: audit.sh [-v] [--owner NAME] [REPO...]
#   REPO       audit only these repositories (default: every non-archived one)
#   --owner    GitHub account (default: the one gh is logged in as)
#   -v         also list the repositories where a check is n/a, and why

if (( BASH_VERSINFO[0] < 4 )); then
  for b in /opt/homebrew/bin/bash /usr/local/bin/bash; do [[ -x $b ]] && exec "$b" "$0" "$@"; done
  echo "audit.sh: needs bash 4 or later" >&2; exit 1
fi
set -uo pipefail

VERBOSE=0; OWNER=""; ONLY=()
while (( $# )); do
  case "$1" in
    -v|--verbose) VERBOSE=1 ;;
    --owner)      OWNER="${2:-}"; shift ;;
    -h|--help)    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)           echo "audit.sh: unknown option: $1" >&2; exit 2 ;;
    *)            ONLY+=("$1") ;;
  esac
  shift
done

for t in gh jq git file; do
  command -v "$t" >/dev/null 2>&1 || { echo "audit.sh: $t not found" >&2; exit 1; }
done
gh auth status >/dev/null 2>&1 || { echo "audit.sh: gh is not logged in" >&2; exit 1; }
OWNER=${OWNER:-$(gh api user --jq .login)}
GREP=/usr/bin/grep
WORK=$(mktemp -d "${TMPDIR:-/tmp}/repo-standards.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# ── Which repositories, and which have a clone here ─────────────────────────────

gh repo list "$OWNER" --limit 500 --json name,visibility,isArchived,isFork,defaultBranchRef \
  --jq '.[] | select(.isArchived | not) | select(.isFork | not)
        | [.name, (.visibility | ascii_downcase), (.defaultBranchRef.name // "")] | @tsv' \
  | sort -f > "$WORK/repos"
if (( ${#ONLY[@]} )); then
  # Exact names, ignoring case. A grep -w word match let FL2601 select
  # FL2601-Windows too, and mrk select mrk-prefs: a hyphen ends a word.
  want=$(IFS=,; printf '%s' "${ONLY[*],,}")
  awk -F'\t' -v want="$want" '
    BEGIN { n = split(want, w, ","); for (i = 1; i <= n; i++) keep[w[i]] = 1 }
    tolower($1) in keep' "$WORK/repos" > "$WORK/only"
  mv "$WORK/only" "$WORK/repos"
fi
[[ -s "$WORK/repos" ]] || { echo "audit.sh: no repositories to audit" >&2; exit 1; }

# Local clones, matched to repositories by their origin URL rather than by
# folder name: PasswordGen is ppg, and some sit one folder down.
declare -A CLONE=()
while IFS= read -r -d '' g; do
  d=$(dirname "$g")
  url=$(git -C "$d" remote get-url origin 2>/dev/null) || continue
  [[ "$url" =~ github\.com[:/]([^/]+)/([^/]+)$ ]] || continue
  [[ "${BASH_REMATCH[1],,}" == "${OWNER,,}" ]] || continue
  CLONE["${BASH_REMATCH[2]%.git}"]=$d
done < <(find "$HOME/Projects" "$HOME/mrk" -maxdepth 3 -name .git -not -path '*/node_modules/*' -print0 2>/dev/null)

# Latest major version of each CI action, looked up once per action.
declare -A LATEST=()
latest_major() { # owner/repo -> major number, or "" if unknown
  local a="$1"
  if [[ -z "${LATEST[$a]+x}" ]]; then
    LATEST[$a]=$(gh api "repos/$a/releases/latest" --jq '.tag_name' 2>/dev/null | sed -nE 's/^v?([0-9]+).*/\1/p')
  fi
  printf '%s' "${LATEST[$a]}"
}

# Standards that do not apply to a repository by design: repo:standard|reason.
# Keep the reason — it is what stops the next pass "fixing" it.
EXEMPT=(
  "DoublEnder-cloud:readme|an overlay sharing DoublEnder's working tree; a README would collide with DoublEnder's"
  "DoublEnder-cloud:tests-in-ci|an overlay; its code builds and is tested only inside DoublEnder's tree"
  "mrk-prefs:readme|a data store that snapshot-prefs writes and nothing reads a README from"
)
exempt() { # repo standard -> prints the reason if exempt
  local e
  for e in "${EXEMPT[@]}"; do
    [[ "${e%%|*}" == "$1:$2" ]] && { printf '%s' "${e#*|}"; return 0; }
  done
  return 1
}

# ── The checks ─────────────────────────────────────────────────────────────────
# Each prints: yes | -- | n/a, then a tab and a note. -- always carries the note
# that says what to do.

STANDARDS=(branch-rules push-protect vuln-alerts no-binaries nojekyll pages-https homepage deploys licence readme tests-in-ci ci-current)

audit_repo() { # name visibility default_branch -> one TSV line per standard
  local r="$1" vis="$2" def="$3" j tree
  j=$(gh api "repos/$OWNER/$r") || { echo "api-error"; return; }
  tree=$(gh api "repos/$OWNER/$r/git/trees/$def?recursive=1" --jq '.tree[].path' 2>/dev/null || true)
  has() { $GREP -qE "$1" <<<"$tree"; }
  out() {
    local why
    if [[ $2 == -- ]] && why=$(exempt "$r" "$1"); then
      printf '%s\tn/a\texempt: %s\n' "$1" "$why"
    else
      printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}"
    fi
  }

  # branch-rules
  if [[ $vis != public ]]; then out branch-rules n/a "private: rulesets need GitHub Pro"
  else
    local rules; rules=$(gh api "repos/$OWNER/$r/rules/branches/$def" --jq '[.[].type] | join(",")' 2>/dev/null)
    if [[ $rules == *non_fast_forward* && $rules == *deletion* ]]; then out branch-rules yes
    else out branch-rules -- "add the no-force-push, no-deletion ruleset on $def"; fi
  fi

  # push-protect
  if [[ $vis != public ]]; then out push-protect n/a "private: needs GitHub Advanced Security"
  else
    local ss pp
    ss=$(jq -r '.security_and_analysis.secret_scanning.status // ""' <<<"$j")
    pp=$(jq -r '.security_and_analysis.secret_scanning_push_protection.status // ""' <<<"$j")
    if [[ $ss == enabled && $pp == enabled ]]; then out push-protect yes
    else out push-protect -- "secret scanning $ss, push protection $pp"; fi
  fi

  # vuln-alerts: only where GitHub can read a dependency manifest
  if has '(^|/)(go\.mod|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|Package\.resolved|requirements[^/]*\.txt|Pipfile\.lock|poetry\.lock|pyproject\.toml|Gemfile\.lock|[^/]+\.csproj|packages\.lock\.json|Cargo\.lock)$'; then
    if gh api "repos/$OWNER/$r/vulnerability-alerts" >/dev/null 2>&1; then out vuln-alerts yes
    else out vuln-alerts -- "has $(sed -nE 's#.*/##; /^(go\.mod|package-lock\.json|Package\.resolved|requirements.*\.txt|pyproject\.toml|.*\.csproj|Cargo\.lock)$/p' <<<"$tree" | sort -u | head -2 | tr '\n' ' ')but Dependabot alerts are off"; fi
  else out vuln-alerts n/a "no dependency manifest"; fi

  # no-binaries: needs file contents, so only where there is a clone
  local d="${CLONE[$r]:-}"
  if [[ -z $d ]]; then out no-binaries n/a "no clone here"
  else
    local bins; bins=$(cd "$d" && git ls-files -z | xargs -0 file 2>/dev/null | $GREP -E ': .*(Mach-O|ELF|PE32)' | cut -d: -f1 | head -3 | tr '\n' ' ')
    if [[ -z $bins ]]; then out no-binaries yes; else out no-binaries -- "executables tracked: $bins"; fi
  fi

  # Pages: nojekyll, https, homepage, deployments
  local p; p=$(gh api "repos/$OWNER/$r/pages" 2>/dev/null || true)
  if [[ -z $p || $p == *'"status":"404"'* ]]; then
    for s in nojekyll pages-https homepage deploys; do out "$s" n/a "no Pages site"; done
  else
    local pdir https home n
    pdir=$(jq -r '.source.path // "/"' <<<"$p"); pdir=${pdir#/}
    if has "^${pdir:+$pdir/}\.nojekyll$"; then out nojekyll yes
    elif has "^${pdir:+$pdir/}_config\.yml$"; then out nojekyll n/a "uses Jekyll on purpose (_config.yml)"
    else out nojekyll -- "add an empty ${pdir:+$pdir/}.nojekyll"; fi
    https=$(jq -r '.https_enforced' <<<"$p")
    if [[ $https == true ]]; then out pages-https yes; else out pages-https -- "enforce HTTPS in Settings › Pages"; fi
    home=$(jq -r '.homepage // ""' <<<"$j")
    if [[ -n $home ]]; then out homepage yes
    else out homepage -- "set it to $(jq -r '.html_url' <<<"$p")"; fi
    n=$(gh api "repos/$OWNER/$r/deployments?per_page=100" --jq 'length' 2>/dev/null || echo 0)
    # Every push to a Pages site adds a deployment, so a busy one passes ten
    # between prunes as a matter of course. Flag only a real pile-up, more than
    # twenty, and prune back to ten, so a routine push never reads as a gap.
    if (( n <= 20 )); then out deploys yes "$n"
    else out deploys -- "$n$( (( n >= 100 )) && echo '+') deployments: prune-deployments --repo $OWNER/$r --keep 10"; fi
  fi

  # licence
  if [[ $vis != public ]]; then out licence n/a "private"
  elif [[ -n $(jq -r '.license.spdx_id // ""' <<<"$j") ]] || has '^(LICEN[CS]E|COPYING)'; then out licence yes
  else out licence -- "no licence: all rights reserved by default"; fi

  # readme
  if has '^README(\.[a-z]+)?$'; then out readme yes; else out readme -- "no README at the root"; fi

  # tests-in-ci and ci-current, from the workflows as pushed
  local wf; wf=$(sed -nE '/^\.github\/workflows\/[^/]+\.ya?ml$/p' <<<"$tree")
  local wftext=""
  if [[ -n $wf ]]; then
    while IFS= read -r f; do
      wftext+=$(gh api "repos/$OWNER/$r/contents/$f?ref=$def" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null)$'\n'
    done <<<"$wf"
  fi
  # A command split with trailing backslashes is one command: `xcodebuild \`
  # on one line and `test` four lines down is how both app workflows run it.
  local runs_tests='xcodebuild[^#]*[[:space:]]test([[:space:]]|$)|swift test|go test|npm (run )?test|npx vitest|vitest run|pytest|ci-check|make check'
  wftext=$(awk '{ if (sub(/\\$/, "")) printf "%s ", $0; else print }' <<<"$wftext")
  if has '(^|/)[A-Za-z0-9]+Tests/|(^|/)tests?/|_test\.go$|\.test\.[jt]s$|\.spec\.[jt]s$|(^|/)vitest\.config'; then
    if $GREP -qE "$runs_tests" <<<"$wftext"; then
      out tests-in-ci yes
    elif has '^release\.sh$' && gh api "repos/$OWNER/$r/contents/release.sh?ref=$def" --jq '.content' 2>/dev/null \
         | base64 -d 2>/dev/null | awk '{ if (sub(/\\$/, "")) printf "%s ", $0; else print }' | $GREP -qE "$runs_tests"; then
      out tests-in-ci yes "release.sh runs them"
    elif [[ $vis == public ]]; then
      out tests-in-ci -- "has tests and nothing runs them: port WaxOnWaxOff's ci.yml"
    else
      out tests-in-ci -- "has tests and nothing runs them: CI (Actions minutes on a private repo) or release.sh"
    fi
  else out tests-in-ci n/a "no tests"; fi

  if [[ -z $wf ]]; then out ci-current n/a "no workflows"
  else
    local stale="" a v m
    while read -r a v; do
      [[ $a == */* && $v =~ ^v?([0-9]+) ]] || continue
      m=$(latest_major "$(cut -d/ -f1-2 <<<"$a")")
      [[ -n $m ]] && (( BASH_REMATCH[1] < m )) && stale+="$a@$v→v$m "
    done < <($GREP -oE 'uses:[[:space:]]*[^[:space:]@]+@[^[:space:]]+' <<<"$wftext" | sed -E 's/uses:[[:space:]]*//; s/@/ /' | sort -u)
    if [[ -z $stale ]]; then out ci-current yes; else out ci-current -- "behind: $stale"; fi
  fi
}

# ── Run, a few repositories at a time ──────────────────────────────────────────

n_repos=$(wc -l < "$WORK/repos" | tr -d ' ')
echo "Auditing $n_repos repositories on $OWNER…" >&2
while IFS=$'\t' read -r r vis def; do
  while (( $(jobs -rp | wc -l) >= 6 )); do sleep 0.2; done
  audit_repo "$r" "$vis" "$def" > "$WORK/r.$r" &
done < "$WORK/repos"
wait

h() { printf '\n== %s\n' "$*"; }

h "Standards by repository  (yes = met, -- = missing, n/a = does not apply)"
printf '%-26s' "REPO"; for s in "${STANDARDS[@]}"; do printf '%-13s' "$s"; done; printf '\n'
printf '%.0s-' $(seq 1 $((26 + 13 * ${#STANDARDS[@]}))); printf '\n'
MISSING=""; NA=""
while IFS=$'\t' read -r r vis def; do
  label="$r"; [[ $vis != public ]] && label+=" (p)"
  printf '%-26s' "$label"
  for s in "${STANDARDS[@]}"; do
    line=$($GREP -m1 "^$s"$'\t' "$WORK/r.$r" 2>/dev/null)
    st=$(cut -f2 <<<"$line"); note=$(cut -f3 <<<"$line")
    printf '%-13s' "${st:-?}"
    [[ $st == -- ]] && MISSING+="  $r: $s — $note"$'\n'
    [[ $st == n/a && -n $note ]] && NA+="  $r: $s — $note"$'\n'
  done
  printf '\n'
done < "$WORK/repos"
echo; echo "  (p) = private. The account's plan decides what a private repository can have."

h "Missing, with what to do"
if [[ -n $MISSING ]]; then printf '%s' "$MISSING"; else echo "  (none)"; fi

if (( VERBOSE )); then h "Not applicable, and why"; printf '%s' "${NA:-  (none)
}"; fi

h "Clones here: uncommitted or unpushed work"
any=0
for r in "${!CLONE[@]}"; do
  d=${CLONE[$r]}; p=""
  dirty=$(git -C "$d" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  (( dirty )) && p+="dirty($dirty) "
  ahead=$(git -C "$d" rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
  (( ahead )) && p+="unpushed($ahead) "
  [[ -n $p ]] && { printf '  %-26s %s\n' "$r" "$p"; any=1; }
done
(( any )) || echo "  (all clean and pushed)"
without=$(cut -f1 "$WORK/repos" | while read -r r; do [[ -z "${CLONE[$r]:-}" ]] && printf '%s ' "$r"; done)
[[ -n $without ]] && echo "  No clone here (audited from GitHub only): $without"

h "Next"
cat <<'TXT'
  Every fix above changes a repository's settings or adds a commit to it, so
  list them for the owner and apply them together once they say so. The fix
  for each standard is in SKILL.md §2.
TXT
