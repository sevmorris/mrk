#!/usr/bin/env bash
# shellcheck disable=SC2016  # single quotes on purpose: check and the stubs expand them when they run
# tidy-projects.sh — prove that tidy-projects offers to remove only what is safe to remove, and
# that --apply removes exactly that.
#
# A throwaway HOME holds four clones: Alpha, with every branch and worktree case (a branch at
# its merged PR's head, one behind it, one with commits the PR did not merge, a closed PR, no
# PR, a never-pushed branch; a merged worktree, a dirty one, one a process sits in, one whose
# folder is gone; a stash, a build/ folder, a Pages site with 12 deployments, and main one
# commit behind); Beta, with no remote and a build/ folder git tracks; Gamma, whose remote is
# off GitHub with a token in its URL; Delta, on a work branch with an uncommitted change.
# "GitHub" is local bare repositories, reached through url.insteadOf in a test git config, and
# gh is a stub that answers from fixtures. prune-deployments, clear-derived-data and trash are
# stubs that record their calls. Nothing outside the scratch folder is read or written.
# tidy-projects needs bash 4, and hands itself to Homebrew's under an older one. ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"
S="$REPO_ROOT/bin/tidy-projects"

T=$(mrk_mktemp_d) || exit 1
T=$(cd "$T" && pwd -P)
trap 'kill "${INUSE:-}" 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p "$T/remotes" "$T/Projects" "$T/fakebin" "$T/prs" "$T/trash" "$T/DerivedData"
export GIT_CONFIG_GLOBAL="$T/gitconfig" GIT_CONFIG_NOSYSTEM=1
cat > "$GIT_CONFIG_GLOBAL" <<EOF
[user]
	name = test
	email = test@example.com
[init]
	defaultBranch = main
[url "$T/remotes/"]
	insteadOf = git@github.com:testowner/
[url "$T/remotes/other/"]
	insteadOf = https://example.invalid/secret-token-abc/
EOF
pass=0; fails=0
check() { if eval "$2"; then pass=$((pass + 1)); else err "$1"; fails=$((fails + 1)); fi; }

# fake gh: logged in as testowner; Alpha has Pages with 12 deployments; PRs from $T/prs/<branch>
cat > "$T/fakebin/gh" <<EOF
#!/usr/bin/env bash
case "\$1 \$2" in "auth status") exit 0 ;; "api user") echo testowner; exit 0 ;; esac
if [[ \$1 == api ]]; then
  case "\$2" in
    repos/testowner/*/deployments*) echo 12 ;;
    repos/testowner/Alpha) echo "false true" ;;
    repos/testowner/*) echo "false false" ;;
    *) exit 1 ;;
  esac; exit 0
fi
if [[ \$1 == pr && \$2 == list ]]; then
  while (( \$# )); do [[ \$1 == --head ]] && h=\$2; shift; done
  f="$T/prs/\${h//\//_}"; [[ -f \$f ]] && cat "\$f"; exit 0
fi
exit 1
EOF
printf '#!/usr/bin/env bash\necho "prune $*" >> "%s/log"\n' "$T" > "$T/fakebin/prune"
printf '#!/usr/bin/env bash\necho "cleardd" >> "%s/log"\n' "$T" > "$T/fakebin/cleardd"
printf '#!/usr/bin/env bash\nmv "$1" "%s/trash/" && echo "trash $1" >> "%s/log"\n' "$T" "$T" > "$T/fakebin/trash"
chmod +x "$T/fakebin/"*
export PATH="$T/fakebin:$PATH"
dd if=/dev/zero of="$T/DerivedData/cache.bin" bs=1024 count=2048 2>/dev/null

q() { git "$@" >/dev/null 2>&1; }
newremote() { q init --bare -b main "$T/remotes/$1.git"; }
pr() { printf '%s %s %s\n' "$2" "$3" "$4" > "$T/prs/${1//\//_}"; }   # branch number state oid

# ── Alpha: every branch and worktree case ──
newremote Alpha
q clone "$T/remotes/Alpha.git" "$T/seed"
printf '.claude/\nbuild/\n' > "$T/seed/.gitignore"; echo one > "$T/seed/f.txt"
q -C "$T/seed" add -A; q -C "$T/seed" commit -m init; q -C "$T/seed" push -u origin main
q clone git@github.com:testowner/Alpha.git "$T/Projects/Alpha"; A="$T/Projects/Alpha"
branch() { # name: commit on a new branch from main and push it
  q -C "$A" switch -c "$1" main; echo "$1" > "$A/$1.txt"; q -C "$A" add -A; q -C "$A" commit -m "$1"
  q -C "$A" push -u origin "$1"; q -C "$A" switch main
}
gone() { q --git-dir="$T/remotes/Alpha.git" branch -D "$1"; }       # GitHub deleting it on merge
branch merged-ok;    pr merged-ok 11 MERGED "$(git -C "$A" rev-parse merged-ok)"; gone merged-ok
branch merged-extra; pr merged-extra 12 MERGED "$(git -C "$A" rev-parse merged-extra)"; gone merged-extra
q -C "$A" switch merged-extra; echo extra >> "$A/merged-extra.txt"; q -C "$A" commit -am "after the merge"; q -C "$A" switch main
branch closed;       pr closed 13 CLOSED "$(git -C "$A" rev-parse closed)"; gone closed
branch nopr;         gone nopr
branch merged2;      pr merged2 14 MERGED "$(git -C "$A" rev-parse merged2)"; gone merged2
# behind: the PR got a later commit from another clone; this clone's branch is behind its head.
# GitHub keeps the head at refs/pull/N/head after the branch goes, and so does this remote.
branch behind; q clone -q "$T/remotes/Alpha.git" "$T/other"; q -C "$T/other" switch behind
echo later >> "$T/other/behind.txt"; q -C "$T/other" commit -am later; q -C "$T/other" push origin behind
q --git-dir="$T/remotes/Alpha.git" update-ref refs/pull/15/head "$(git -C "$T/other" rev-parse HEAD)"
pr behind 15 MERGED "$(git -C "$T/other" rev-parse HEAD)"; gone behind
q -C "$A" switch -c localonly main; echo l > "$A/l.txt"; q -C "$A" add -A; q -C "$A" commit -m local; q -C "$A" switch main
mkdir -p "$A/.claude/worktrees"
q -C "$A" worktree add --detach "$A/.claude/worktrees/wt-merged" merged-ok
q -C "$A" worktree add "$A/.claude/worktrees/wt-dirty" merged2; echo scratch > "$A/.claude/worktrees/wt-dirty/untracked.txt"
q -C "$A" worktree add --detach "$A/.claude/worktrees/wt-inuse" main
q -C "$A" worktree add --detach "$A/.claude/worktrees/wt-missing" main; rm -rf "$A/.claude/worktrees/wt-missing"
echo changed >> "$A/f.txt"; q -C "$A" stash push -m test-stash                     # a stash, tree clean
mkdir -p "$A/build"; dd if=/dev/zero of="$A/build/out.bin" bs=1024 count=1024 2>/dev/null
echo two >> "$T/seed/f.txt"; q -C "$T/seed" commit -am two; q -C "$T/seed" push         # main moves on: Alpha is 1 behind
(cd "$A/.claude/worktrees/wt-inuse" && exec sleep 300) & INUSE=$!

# ── Beta: no remote, and a build/ folder git tracks ──
q init -b main "$T/Projects/Beta"; mkdir -p "$T/Projects/Beta/build"; echo src > "$T/Projects/Beta/build/tool.sh"
q -C "$T/Projects/Beta" add -A; q -C "$T/Projects/Beta" commit -m init
# ── Gamma: a remote off GitHub whose URL carries a token ──
mkdir -p "$T/remotes/other"; q init --bare -b main "$T/remotes/other/gamma.git"
q clone "$T/remotes/other/gamma.git" "$T/g"; echo g > "$T/g/g.txt"; q -C "$T/g" add -A; q -C "$T/g" commit -m g; q -C "$T/g" push -u origin main
q clone https://example.invalid/secret-token-abc/gamma.git "$T/Projects/Gamma"
# ── Delta: on a work branch, with an uncommitted change ──
newremote Delta; q clone "$T/remotes/Delta.git" "$T/d"; echo d > "$T/d/d.txt"; q -C "$T/d" add -A; q -C "$T/d" commit -m d; q -C "$T/d" push -u origin main
q clone git@github.com:testowner/Delta.git "$T/Projects/Delta"
q -C "$T/Projects/Delta" switch -c dev; echo wip >> "$T/Projects/Delta/d.txt"

export TIDY_ROOTS="$T/Projects" TIDY_DERIVED="$T/DerivedData" TIDY_TRASH="$T/fakebin/trash" \
       TIDY_PRUNE="$T/fakebin/prune" TIDY_CLEAR_DD="$T/fakebin/cleardd"

# ── 1. The survey: every case lands where it should, and nothing changes ──────

bash "$S" > "$T/s1" 2>&1
has() { grep -qF -- "$1" "$T/s1"; }
check "ff offered for Alpha (1 behind, clean)"                 'has "ff        Alpha: 1 commit(s) behind origin/main"'
check "refs: Alpha's deleted branches found stale"             'has "refs      Alpha:"'
check "branches: merged-ok offered (tip == merged PR head)"     'has "branches  Alpha: merged-ok (merged in PR #11)"'
check "kept: merged-extra has 1 commit the PR did not merge"    'has "branch merged-extra: has 1 commit(s) that PR #12 did not merge"'
check "branches: behind offered (tip is an ancestor of PR head)" 'has "branches  Alpha: behind (merged in PR #15)"'
check "kept: closed PR"                                         'has "branch closed: PR #13 was closed without merging"'
check "kept: no PR"                                             'has "branch nopr: gone from origin, and no pull request has it as its head"'
check "kept: merged2 pinned by its dirty worktree"              'has "branch merged2: merged in PR #14, but checked out in a worktree that stays"'
check "owner: localonly never pushed"                           'has "branch localonly was never pushed"'
check "worktrees: wt-merged offered (in merged PR #11)"         'has "wt-merged (clean, and its work is in merged PR #11)"'
check "worktrees: wt-missing offered as a stale entry"          'has "wt-missing (its folder is gone; a stale entry)"'
check "kept: wt-dirty has untracked files"                      'has "worktree .claude/worktrees/wt-dirty: has uncommitted or untracked files"'
check "kept: wt-inuse has a running process"                    'has "worktree .claude/worktrees/wt-inuse: a running process is working in it"'
check "owner: Alpha's stash reported"                           'has "Alpha: 1 stash(es)"'
check "build: Alpha build/ offered"                             'has "build     Alpha: build/ 1.0M"'
check "build: Beta's tracked build/ not offered"                '! has "build     Beta"'
check "build: DerivedData offered"                              'has "DerivedData 2.0M"'
check "deploys: Alpha 12 -> 10"                                 'has "deploys   Alpha: 12 Pages deployments, down to 10"'
check "owner: Beta has no remote"                               'has "Beta: no remote: this clone is the only copy"'
check "owner: Gamma is off GitHub"                              'has "Gamma: its remote is not on GitHub"'
check "the token in Gamma's URL is never printed"               '! has "secret-token-abc"'
check "owner: Delta on dev, with 1 uncommitted change"          'has "Delta: checked out on dev, not main" && has "Delta: 1 uncommitted change(s)"'
check "no ff offered for Delta (not on main)"                   '! has "ff        Delta"'
check "survey changed nothing (Alpha main still behind)"        '[[ $(git -C "$A" rev-list --count HEAD..origin/main) == 1 ]]'


# ── 2. --apply all: only what qualified goes, and everything kept stays ───────

bash "$S" --apply all > "$T/s2" 2>&1
check "Alpha fast-forwarded"                          '[[ $(git -C "$A" rev-list --count HEAD..origin/main) == 0 ]]'
check "stale refs pruned"                             '! git -C "$A" show-ref --verify --quiet refs/remotes/origin/merged-ok'
check "merged-ok and behind deleted"                  '! git -C "$A" show-ref --verify --quiet refs/heads/merged-ok && ! git -C "$A" show-ref --verify --quiet refs/heads/behind'
check "merged-extra, closed, nopr, merged2, localonly kept" 'for b in merged-extra closed nopr merged2 localonly; do git -C "$A" show-ref --verify --quiet refs/heads/$b || exit 1; done'
check "wt-merged removed"                             '[[ ! -d "$A/.claude/worktrees/wt-merged" ]]'
check "wt-missing entry pruned"                       '! git -C "$A" worktree list | grep -q wt-missing'
check "wt-dirty and its untracked file kept"          '[[ -f "$A/.claude/worktrees/wt-dirty/untracked.txt" ]]'
check "wt-inuse kept"                                 '[[ -d "$A/.claude/worktrees/wt-inuse" ]]'
check "stash kept"                                    '[[ $(git -C "$A" stash list | wc -l) -eq 1 ]]'
check "Alpha build/ went to the Trash"                '[[ ! -d "$A/build" && -d "$T/trash/build" ]]'
check "Beta tracked build/ untouched"                 '[[ -f "$T/Projects/Beta/build/tool.sh" ]]'
check "DerivedData cleared with clear-derived-data"   'grep -qx cleardd "$T/log"'
check "prune-deployments called for Alpha only"       '[[ $(grep -c "^prune --repo testowner/Alpha --keep 10$" "$T/log") == 1 && $(grep -c "^prune" "$T/log") == 1 ]]'
check "Delta's uncommitted change untouched"          'grep -q wip "$T/Projects/Delta/d.txt"'
check "apply reported no failures"                    'grep -q " 0 failed" "$T/s2"'


# ── 3. A second survey, and the command line ─────────────────────────────────

bash "$S" > "$T/s3" 2>&1
check "only the fakes' cleanups remain (deploys, DerivedData)" \
  '[[ $(sed -n "/^== Cleanups available/,/^== Kept/p" "$T/s3" | grep -cE "^  (ff|refs|worktrees|branches|build) ") == 1 ]] && grep -q "DerivedData" "$T/s3"'
check "--no-fetch survey runs"                        'bash "$S" --no-fetch >/dev/null 2>&1'
check "unknown cleanup refused with exit 2"           'bash "$S" --apply bogus >/dev/null 2>&1; [[ $? == 2 ]]'

kill "$INUSE" 2>/dev/null
if (( fails )); then
  for f in s1 s2 s3; do [[ -f "$T/$f" ]] && sed 's/^/    /' "$T/$f" >&2; done
  err "$fails tidy-projects check(s) failed"
  exit 1
fi
ok "tidy-projects checks passed ($pass)"
