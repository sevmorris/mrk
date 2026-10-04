#!/usr/bin/env bash
# gitconfig.sh — hold dotfiles/.gitconfig to what it promises. Audit 21, Y-1.
#
# Until 2026-10-04 .gitconfig set color.ui, and five commands' colour, to
# always. Every pipe of git output then carried escape codes, and the
# local-branches alias, which parsed `git branch -vv` through cut and awk,
# listed branches that had an upstream, each name wrapped in escape codes. The
# alias now reads for-each-ref, and colour is auto.
#
# The file is used as the global config of a throwaway HOME, against a scratch
# repository with a scratch bare origin. The real ~/.gitconfig is never read.
# ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

W=$(mrk_mktemp_d) || exit 1
W=$(cd "$W" && pwd -P)
trap 'rm -rf "$W"' EXIT

export HOME="$W/home" GIT_CONFIG_GLOBAL="$REPO_ROOT/dotfiles/.gitconfig" GIT_CONFIG_NOSYSTEM=1
mkdir -p "$HOME"
ESC=$'\033'

git init -q --bare "$W/origin.git"
git clone -q "$W/origin.git" "$W/w" 2>/dev/null
cd "$W/w" || exit 1
git commit -q --allow-empty -m one
git push -q -u origin HEAD:main 2>/dev/null
git branch -q -u origin/main
tracked=$(git branch --show-current)

# No branch without an upstream yet: nothing, and exit 0.
out=$(git local-branches); rc=$?
if [[ $rc == 0 && -z "$out" ]]; then
  pass "local-branches: every branch has an upstream, so it prints nothing"
else
  fail "local-branches with every branch tracked: exit $rc, printed: $(printf '%q' "$out")"
fi

# zz-last sorts after the tracked branch, so a line left blank for it would
# fall between two names rather than at the end, where $(...) drops it.
git branch -q feature
git branch -q fix/two-parts
git branch -q zz-last
want=$'feature\nfix/two-parts\nzz-last'

out=$(git local-branches)
if [[ "$out" == "$want" ]]; then
  pass "local-branches names the three branches with no upstream, and not $tracked"
else
  fail "local-branches printed $(printf '%q' "$out"), want $(printf '%q' "$want")"
fi

out=$(git -c color.ui=always -c color.branch=always local-branches)
if [[ "$out" == "$want" ]]; then
  pass "local-branches gives the same names with colour forced on"
else
  fail "local-branches with colour forced on printed $(printf '%q' "$out")"
fi

out=$(git branch -vv | cat; git log --oneline --decorate | cat; git diff HEAD~0 | cat)
if [[ "$out" != *"$ESC"* ]]; then
  pass "branch, log and diff write no escape codes into a pipe"
else
  fail "git wrote escape codes into a pipe: $(printf '%q' "$out" | head -c 200)"
fi

if [[ "$(git config --get color.ui)" == auto ]]; then
  pass "color.ui is auto"
else
  fail "color.ui is '$(git config --get color.ui)', want auto"
fi

(( fails == 0 ))
