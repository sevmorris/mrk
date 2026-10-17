#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # check evals its single-quoted tests, which read RC, $T and the helpers
# prune-deployments.sh — prove that prune-deployments, run outside a git
# repository with no --repo, works on every Pages site the account owns and on
# nothing else, and that inside a repository or with --repo it still works on
# that one repository alone.
#
# gh is a stub that answers from JSON fixtures and applies each --jq filter
# with /usr/bin/jq, so the filters in the script are the ones tested. It
# records every call. The account owns five repositories:
# - Alpha: a Pages site with 12 deployments. #112 to #103 failed and #102 is
#   live, so keeping 10 must delete #101 and protect #102.
# - Beta: a Pages site, but archived, so it is read-only and left out.
# - Gamma: no Pages site.
# - Delta: a Pages site with 3 deployments, so nothing to prune.
# - Epsilon: a Pages site whose deployments gh cannot fetch.
# Nothing outside the scratch folder is read or written. prune-deployments
# needs bash 4, and hands itself to Homebrew's under an older one. ci-check
# runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"
S="$REPO_ROOT/bin/prune-deployments"

[[ -x /usr/bin/jq ]] || { err "/usr/bin/jq not found; the gh stub needs it"; exit 1; }

T=$(mrk_mktemp_d) || exit 1
T=$(cd "$T" && pwd -P)
trap 'rm -rf "$T"' EXIT
F="$T/fixtures"
mkdir -p "$T/fakebin" "$F" "$T/out"
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
printf '[init]\n\tdefaultBranch = main\n' > "$GIT_CONFIG_GLOBAL"

pass=0; fails=0
check() { if eval "$2"; then pass=$((pass + 1)); else err "$1"; sed 's/^/    /' "$T/out/last"; fails=$((fails + 1)); fi; }

# ── Fixtures ──
cat > "$F/user-repos.json" <<'EOF'
[
  {"full_name": "testowner/Alpha",   "has_pages": true,  "archived": false},
  {"full_name": "testowner/Beta",    "has_pages": true,  "archived": true},
  {"full_name": "testowner/Gamma",   "has_pages": false, "archived": false},
  {"full_name": "testowner/Delta",   "has_pages": true,  "archived": false},
  {"full_name": "testowner/Epsilon", "has_pages": true,  "archived": false}
]
EOF
deployments() {  # deployments NAME ID... — newest first, as the API returns them
  local name=$1; shift
  printf '%s\n' "$@" | /usr/bin/jq -R '{id: tonumber}' | /usr/bin/jq -s . > "$F/$name.json"
}
deployments Alpha 112 111 110 109 108 107 106 105 104 103 102 101
deployments Beta  204 203 202 201 200 199 198 197 196 195 194 193
deployments Delta 403 402 401
for id in 112 111 110 109 108 107 106 105 104 103; do echo '[{"state":"failure"}]' > "$F/status-$id.json"; done
for id in 102 101 204 403 402 401; do echo '[{"state":"success"}]' > "$F/status-$id.json"; done

# fake gh: every call to $T/calls; GETs answered from $F through --jq; Epsilon's
# deployments fail; POST and DELETE succeed and print nothing.
cat > "$T/fakebin/gh" <<EOF
#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2034  # check evals its single-quoted tests, which read RC, $T and the helpers
echo "\$*" >> "$T/calls"
[[ \$1 == api ]] || exit 1; shift
method=GET path="" jq="."
while (( \$# )); do
  case "\$1" in
    -X) method=\$2; shift 2 ;;
    --jq) jq=\$2; shift 2 ;;
    -f) shift 2 ;;
    --paginate|--silent) shift ;;
    *) path=\$1; shift ;;
  esac
done
[[ \$method == GET ]] || exit 0
case "\$path" in
  /user/repos*) f="$F/user-repos.json" ;;
  /repos/testowner/Epsilon/deployments*) exit 1 ;;
  /repos/testowner/*/deployments/*/statuses) id=\${path%/statuses}; f="$F/status-\${id##*/}.json" ;;
  /repos/testowner/*/deployments*) n=\${path#/repos/testowner/}; f="$F/\${n%%/*}.json" ;;
  *) exit 1 ;;
esac
[[ -f \$f ]] || exit 1
/usr/bin/jq -r "\$jq" "\$f"
EOF
chmod +x "$T/fakebin/gh"
export PATH="$T/fakebin:$PATH"

RC=0
run() {  # run DIR ARGS... — run prune-deployments in DIR with a fresh call log
  local dir=$1; shift
  : > "$T/calls"
  (cd "$dir" && "$S" "$@") > "$T/out/last" 2>&1
  RC=$?
}
called() { grep -qF -- "$1" "$T/calls"; }
deletes() { grep '^api -X DELETE' "$T/calls" | sed 's|.*/deployments/||' | sort -n | tr '\n' ' '; }

mkdir -p "$T/home"

# ── 1. Outside a git repository, a dry run checks every Pages site and deletes nothing ──
run "$T/home" --dry-run
check "dry run outside a repo: lists the account's repositories"  'called "api --paginate /user/repos?affiliation=owner&per_page=100"'
check "dry run outside a repo: says it is checking three sites"   'grep -qF "checking all 3 Pages sites" "$T/out/last"'
check "dry run outside a repo: Alpha would lose #101 only"        'grep -A2 "Would delete" "$T/out/last" | grep -qx "    #101" && [[ $(grep -c "^    #" "$T/out/last") == 1 ]]'
check "dry run outside a repo: no POST and no DELETE"             '! grep -q -- "-X" "$T/calls"'
check "dry run outside a repo: Epsilon is reported, exit 1"       '(( RC == 1 )) && grep -qF "Could not fetch the deployments of 1 of 3 sites: testowner/Epsilon" "$T/out/last"'

# ── 2. Outside a git repository, a real run prunes each site and only them ──
run "$T/home"
check "run outside a repo: deletes #101 and nothing else"         '[[ $(deletes) == "101 " ]]'
check "run outside a repo: marks #101 inactive first"             'grep -n "deployments" "$T/calls" | grep -E "POST .*/101/statuses|DELETE .*/101$" | head -1 | grep -q POST'
check "run outside a repo: the live #102 is protected"            'grep -qF "#102 is serving the site" "$T/out/last" && ! grep -qE -- "-X (POST|DELETE) .*/deployments/102(/|$)" "$T/calls"'
check "run outside a repo: Delta is examined, nothing to prune"   'called "/repos/testowner/Delta/deployments?" && grep -qF "Nothing to prune — 3 deployment(s)" "$T/out/last"'
check "run outside a repo: archived Beta is left alone"           '! called "testowner/Beta"'
check "run outside a repo: Gamma, with no Pages, is left alone"   '! called "testowner/Gamma"'
check "run outside a repo: Epsilon is still tried, then exit 1"   'called "/repos/testowner/Epsilon/deployments?" && (( RC == 1 ))'

# ── 3. Outside a git repository, --repo names one repository ──
run "$T/home" --repo testowner/Delta
check "--repo outside a repo: no account listing, exit 0"         '! called "/user/repos" && called "/repos/testowner/Delta/deployments?" && ! called "Alpha" && (( RC == 0 ))'

# ── 4. Inside a git repository, the origin remote names the repository ──
git init -q "$T/Alpha"
git -C "$T/Alpha" remote add origin git@github.com:testowner/Alpha.git
run "$T/Alpha"
check "inside a repo: prunes its origin alone, exit 0"            '! called "/user/repos" && [[ $(deletes) == "101 " ]] && ! called "Delta" && (( RC == 0 ))'

# ── 5. Inside a git repository with no origin, it stops and says so ──
git init -q "$T/noorigin"
run "$T/noorigin"
check "inside a repo with no origin: exit 1, gh lists nothing"    '(( RC == 1 )) && grep -qF "No '"'"'origin'"'"' remote found" "$T/out/last" && ! called "/user/repos"'

# ── 6. An account with no Pages sites is not an error ──
echo '[{"full_name": "testowner/Gamma", "has_pages": false, "archived": false}]' > "$F/user-repos.json"
run "$T/home"
check "no Pages sites: says so, exit 0, deletes nothing"          '(( RC == 0 )) && grep -qF "you own no Pages sites" "$T/out/last" && ! grep -q -- "-X" "$T/calls"'

if (( fails )); then
  err "prune-deployments: $fails of $((pass + fails)) checks failed"
  exit 1
fi
ok "prune-deployments: all $pass checks passed"
