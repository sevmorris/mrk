#!/bin/zsh -f
# cleanempties.zsh — test cleanempties (ce) and showempties (se) from
# dotfiles/.aliases against throwaway folders.
#
# Run by ci-check as `zsh -f -i tests/cleanempties.zsh`: .aliases loads only in
# an interactive shell, and -f keeps every other startup file out. `trash` is a
# stub that logs each path and moves it into the sandbox, failing with 5 as
# /usr/bin/trash does when it cannot move something, so nothing reaches the
# real Trash.
#
# Each case below is something the version before 2026-09-11 got wrong, or
# something the rewrite must keep doing: it trashed the whole tree's cruft
# before its [y/N], looped forever on a folder the Trash refused, broke git
# repositories by trashing refs/ and objects/, and stripped the ._ sidecars of
# files that still exist.

setopt no_monitor            # no job-control chatter from the watchdog below
zmodload zsh/zselect

repo=${0:A:h:h}
if [[ $- != *i* ]]; then
  print -u2 "run this as: zsh -f -i ${0:t}"
  exit 2
fi
source $repo/dotfiles/.aliases
if (( ! $+functions[cleanempties] || ! $+functions[showempties] )); then
  print -u2 "  ✗ dotfiles/.aliases no longer defines cleanempties and showempties"
  exit 1
fi

T=$(mktemp -d "${TMPDIR:-/tmp}/mrk-ce.XXXXXX") || exit 1
trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT
mkdir -p $T/stub $T/trash
cat > $T/stub/trash <<'EOF'
#!/bin/bash
rc=0
for f in "$@"; do
  printf '%s\n' "$f" >> "$TRASH_LOG"
  mv "$f" "$TRASH_DIR/$RANDOM$RANDOM-${f##*/}" 2>/dev/null || rc=5
done
exit $rc
EOF
chmod +x $T/stub/trash
path=($T/stub $path)
export TRASH_DIR=$T/trash TRASH_LOG=$T/trash.log
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

fails=0
pass() { print -r -- "  ✓ $*"; }
fail() { print -ru2 -- "  ✗ $*"; fails=$(( fails + 1 )); }
fresh() { rm -rf $T/w; mkdir -p $T/w; : > $TRASH_LOG; cd $T/w; }

# ── Nothing moves before the answer ──────────────────────────────────────────
fresh
mkdir -p docs icons photos empty
: > docs/.localized; : > icons/Icon$'\r'; : > photos/.DS_Store; : > photos/photo.jpg
print n | cleanempties . >/dev/null 2>&1
if [[ ! -s $TRASH_LOG && -e docs/.localized && -e photos/.DS_Store ]]; then
  pass "answering n moves nothing"
else
  fail "answering n still moved: $(tr '\n' ' ' < $TRASH_LOG)"
fi

# ── A folder the Trash refuses ends the run instead of looping ───────────────
fresh
mkdir -p locked/inner; chmod 555 locked
cleanempties -f . >$T/refused.out 2>&1 &
pid=$!
for i in {1..50}; do kill -0 $pid 2>/dev/null || break; zselect -t 10; done
if kill -0 $pid 2>/dev/null; then
  kill $pid; wait $pid 2>/dev/null
  fail "a folder the Trash refused kept cleanempties running for 5 s — the old loop is back"
else
  wait $pid; rc=$?
  if (( rc == 1 )) && grep -q 'The Trash refused 1 of 1' $T/refused.out; then
    pass "a folder the Trash refuses is reported, and the run ends with 1"
  else
    fail "a refused folder: exit $rc, output: $(tr '\n' ' ' < $T/refused.out)"
  fi
fi
chmod 755 locked

# ── Never inside a repository ────────────────────────────────────────────────
fresh
git init -q repo && print a > repo/a.txt && git -C repo add a.txt && git -C repo commit -qm a && git -C repo gc -q
if [[ -z $(find repo/.git/refs/heads -mindepth 1) ]]; then
  cleanempties -f . >/dev/null 2>&1
  if ! grep -q '/\.git' $TRASH_LOG && git -C repo status >/dev/null 2>&1; then
    pass "a repository after git gc keeps its empty refs/ folders and still works"
  else
    fail "a repository after git gc: trashed [$(tr '\n' ' ' < $TRASH_LOG)], git status: $(git -C repo status 2>&1 | head -1)"
  fi
else
  fail "the fixture is wrong: git gc left refs/heads non-empty, so this proves nothing"
fi
fresh
git init -q new
cleanempties -f . >/dev/null 2>&1
if git -C new status >/dev/null 2>&1; then
  pass "a fresh git init keeps its empty objects/ and refs/"
else
  fail "a fresh git init was broken: $(git -C new status 2>&1 | head -1)"
fi

# ── What goes, and what stays ────────────────────────────────────────────────
fresh
mkdir -p a/b/c cruft live kept album sealed/inner Foo.app/Contents/Resources/empty Song.logicx/Alternatives/000
: > cruft/.DS_Store; : > cruft/Icon$'\r'; : > cruft/._junk
: > live/.DS_Store; : > live/real.txt
: > kept/.gitkeep
: > album/foo.jpg; : > album/._foo.jpg
# 300: writable, so the Trash could move it, but not listable, so it looks empty.
: > sealed/inner/secret.txt; chmod 300 sealed
preview=$(showempties . 2>&1)
cleanempties -f . >/dev/null 2>&1
chmod 755 sealed
listed=( ${(f)"$(print -r -- $preview | tail -n +2)"} )
moved=( ${(f)"$(<$TRASH_LOG)"} )
[[ ! -e a && ${(M)#listed:#./a} == 1 && ${(M)#listed:#./a/*} == 0 ]] \
  && pass "nested empty folders go as one, listed once" \
  || fail "nested empty folders: a exists=$([[ -e a ]] && print y || print n), listed: $listed"
[[ ! -e cruft ]] && pass "a folder holding only cruft goes" || fail "a folder holding only cruft stayed"
[[ -e live/.DS_Store && -e live/real.txt ]] && pass "cruft beside a real file stays" || fail "cruft beside a real file was moved"
[[ -e kept/.gitkeep ]] && pass "a .gitkeep keeps its folder" || fail "a .gitkeep was moved"
[[ -e album/._foo.jpg ]] && pass "the ._ sidecar of a file that exists stays" || fail "a sidecar was stripped from a file that still exists"
[[ -d Foo.app/Contents/Resources/empty && -d Song.logicx/Alternatives/000 ]] \
  && pass "empty folders inside bundles stay" || fail "an empty folder inside a bundle was moved"
[[ -e sealed/inner/secret.txt && ${(M)#listed:#./sealed} == 0 ]] && pass "a folder that cannot be read counts as holding something" \
  || fail "an unreadable folder was listed or moved"
[[ ${(j:|:)${(o)listed}} == ${(j:|:)${(o)moved}} ]] && pass "showempties lists exactly what cleanempties moves" \
  || fail "showempties listed [$listed], cleanempties moved [$moved]"

(( fails == 0 )) || exit 1
