#!/usr/bin/env bash
# snapshot-prefs.sh — prove that snapshot-prefs leaves out a plist that changed
# only in keys that change on their own, makes no commit when that is all that
# changed, and that --dry-run commits, pushes and writes nothing. And that a
# commit whose push failed is pushed by the next run, also when that run finds
# nothing new: "No changes to push." must mean the remote has the last commit.
#
# Until 2026-09-30 any difference from the last commit made a commit, and in
# the sixty snapshots before then a plist had changed in nothing but update
# check times, window positions, launch counters and the like 274 times.
#
# Each case runs the real snapshot-prefs under a throwaway HOME, with defaults
# a stub first on PATH: it knows four io.github.sevmorris.* domains, written
# here as plists, and answers read, export and domains for those alone, so
# every named app is skipped as having no preferences, here or on a Mac that
# has it installed. PREFS_REPO is a scratch bare repository, cloned into the
# throwaway ~/.mrk/preferences on the first run.
# Nothing reaches the real HOME, the network or any preferences.
# snapshot-prefs needs bash 4, and hands itself to Homebrew's when it is run
# under an older one. ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

REAL_GIT="$(command -v git)" || { fail "git not found"; exit 1; }
command -v python3 >/dev/null || { fail "python3 not found"; exit 1; }

W=$(mrk_mktemp_d) || exit 1
W=$(cd "$W" && pwd -P)
trap 'rm -rf "$W"' EXIT
H="$W/home"           # the throwaway HOME
S="$W/stubs"          # first on PATH
D="$W/domains"        # what the stub defaults holds
ORIGIN="$W/prefs.git" # PREFS_REPO
P="$H/.mrk/preferences"
mkdir -p "$H" "$S" "$D"
: > "$W/calls"

# ── Stubs ────────────────────────────────────────────────────────────────────

cat > "$S/defaults" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$W/calls"
case "\$1" in
  domains) cat "$W/domain-list" ;;
  read)    [ -f "$D/\$2.plist" ] ;;
  export)  [ -f "$D/\$2.plist" ] && cp "$D/\$2.plist" "\$3" ;;
  *)       exit 1 ;;
esac
EOF
chmod +x "$S/defaults"
# macOS has plutil; elsewhere the fixtures are xml1 already.
if ! command -v plutil >/dev/null 2>&1; then
  printf '#!/bin/sh\nexit 0\n' > "$S/plutil"; chmod +x "$S/plutil"
fi
ln -s "$BASH" "$S/bash"
ln -s "$REAL_GIT" "$S/git"

# fixtures THEME MODE TICK ORDER [GAMMA] — write the domains. THEME and MODE
# are settings; TICK drives every key that changes on its own (Sparkle's check
# time, a window frame, launch counters at the top and nested, MBM's update
# check); ORDER 1 writes the same JSON and archived dictionary in another order.
# GAMMA adds a fourth domain holding nothing but a Sparkle time.
cat > "$W/fixtures.py" <<'PY'
import datetime, json, plistlib, sys
from plistlib import UID
d, theme, mode, tick, order = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4]), int(sys.argv[5])
gamma = len(sys.argv) > 6
t = datetime.datetime(2026, 9, 1) + datetime.timedelta(hours=tick)
def archive(pairs):
    objs, ks, vs = ["$null"], [], []
    for k, v in pairs:
        objs.append(k); ks.append(UID(len(objs) - 1))
        objs.append(v); vs.append(UID(len(objs) - 1))
    objs.append({"$classes": ["NSDictionary", "NSObject"], "$classname": "NSDictionary"})
    objs.append({"NS.keys": ks, "NS.objects": vs, "$class": UID(len(objs) - 1)})
    return plistlib.dumps({"$archiver": "NSKeyedArchiver", "$version": 100000,
                           "$objects": objs, "$top": {"root": UID(len(objs) - 1)}}, fmt=plistlib.FMT_BINARY)
pairs = [("x", 1), ("y", 2)]
blob = {"a": 1, "b": 2}
if order:
    pairs.reverse(); blob = {"b": 2, "a": 1}
domains = {
    "io.github.sevmorris.Alpha": {
        "theme": theme, "SULastCheckTime": t, "NSWindow Frame Main": f"{tick} 0 800 600 0 0 1512 945 ",
        "launchCount": tick, "panel": {"launchCount": tick, "width": 300},
        "blob": json.dumps(blob).encode(), "archive": archive(pairs)},
    "io.github.sevmorris.BackupRestore": {"BackupSettings": "kept", "MBM_lastUpdateCheckDate": t},
    "io.github.sevmorris.Beta": {"mode": mode},
    "io.github.sevmorris.KeyVault": {"CollapsedNoteCategories": ["Work"]},
}
if gamma:
    domains["io.github.sevmorris.Gamma"] = {"SULastCheckTime": t}
for name, value in domains.items():
    with open(f"{d}/{name}.plist", "wb") as f:
        plistlib.dump(value, f, fmt=plistlib.FMT_XML)
print(", ".join(domains))
PY
fixtures() { python3 "$W/fixtures.py" "$D" "$@" > "$W/domain-list"; }

ENV=(env -i HOME="$H" PATH="$S:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="${TMPDIR:-/tmp}" TERM=dumb
     PREFS_REPO="$ORIGIN" NONINTERACTIVE=1
     GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
     GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test.invalid
     GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test.invalid)

# snap [ARGS] — snapshot-prefs. Output in $W/out, exit status in RC.
RC=0
snap() {
  "${ENV[@]}" "$REPO_ROOT/scripts/snapshot-prefs" "$@" > "$W/out" 2>&1
  RC=$?
}
show()     { sed 's/^/    /' "$W/out"; }
pushed()   { "$REAL_GIT" -C "$ORIGIN" rev-list --count --all 2>/dev/null || echo 0; }
# last_files — the files the last commit pushed changed
last_files() { "$REAL_GIT" -C "$ORIGIN" show --format= --name-only HEAD 2>/dev/null; }
clean()    { [[ -z "$("$REAL_GIT" -C "$P" status --porcelain)" ]]; }
# fingerprint — HEAD, status, and every file's content in ~/.mrk/preferences
fingerprint() {
  { "$REAL_GIT" -C "$P" rev-parse HEAD; "$REAL_GIT" -C "$P" status --porcelain
    (cd "$P" && find . -type f -not -path './.git/*' | LC_ALL=C sort | while IFS= read -r f; do cksum "$f"; done)
  } | cksum
}
pushed_value() { # FILE KEY — KEY's value in the pushed copy of sevmorris-apps/FILE
  "$REAL_GIT" -C "$ORIGIN" show "HEAD:sevmorris-apps/$1" | python3 -c 'import plistlib,sys; print(plistlib.loads(sys.stdin.buffer.read()).get(sys.argv[1]))' "$2"
}

"$REAL_GIT" init -q --bare "$ORIGIN"

# ── 1. The first run: everything committed and pushed ────────────────────────

fixtures dark a 0 0
snap
if (( RC == 0 )) && [[ "$(pushed)" == 1 ]] && last_files | grep -qx 'sevmorris-apps/io.github.sevmorris.Alpha.plist' \
   && grep -q 'io.github.sevmorris.Beta.plist (new)' "$W/out" && clean; then
  pass "the first run commits and pushes every export"
else
  fail "the first run: rc $RC, $(pushed) commit(s) pushed"; show
fi

# ── 2. Nothing changed: no commit ────────────────────────────────────────────

snap
if (( RC == 0 )) && [[ "$(pushed)" == 1 ]] && grep -q 'No changes to push' "$W/out" && ! grep -q 'Left out' "$W/out"; then
  pass "nothing changed: no commit"
else
  fail "nothing changed: rc $RC, $(pushed) commit(s)"; show
fi

# ── 3. Only keys that change on their own: no commit, the tree left clean ────

fixtures dark a 1 1
snap
if (( RC == 0 )) && [[ "$(pushed)" == 1 ]] && grep -q 'No changes to push' "$W/out" \
   && grep -q 'Left out, changed only in keys that change on their own: .*io.github.sevmorris.Alpha.plist' "$W/out" \
   && grep -q 'io.github.sevmorris.BackupRestore.plist' "$W/out" && clean; then
  pass "only self-changing keys, JSON and an archive reordered: no commit, and the tree left clean"
else
  fail "only self-changing keys: rc $RC, $(pushed) commit(s), status: $("$REAL_GIT" -C "$P" status --porcelain | tr '\n' ' ')"; show
fi

# ── 4. One real change beside them: only that plist committed ────────────────

fixtures dark b 2 0
snap
if (( RC == 0 )) && [[ "$(pushed)" == 2 && "$(last_files)" == "sevmorris-apps/io.github.sevmorris.Beta.plist" ]] \
   && grep -q 'io.github.sevmorris.Beta.plist: mode' "$W/out" && clean; then
  pass "a real change in one plist: that one committed, the others left out"
else
  fail "a real change in one plist: rc $RC, last commit: $(last_files | tr '\n' ' ')"; show
fi

# ── 5. A real change and a self-changing one in the same plist: committed whole

fixtures light b 3 0
snap
t3="2026-09-01 03:00:00"
if (( RC == 0 )) && [[ "$(pushed)" == 3 ]] && [[ "$(pushed_value io.github.sevmorris.Alpha.plist theme)" == light ]] \
   && [[ "$(pushed_value io.github.sevmorris.Alpha.plist SULastCheckTime)" == "$t3" ]] \
   && grep -q 'io.github.sevmorris.Alpha.plist: theme$' "$W/out"; then
  pass "a real change beside a self-changing key: the plist committed whole, and only the real key reported"
else
  fail "a real change beside a self-changing key: rc $RC, theme $(pushed_value io.github.sevmorris.Alpha.plist theme), SULastCheckTime $(pushed_value io.github.sevmorris.Alpha.plist SULastCheckTime)"; show
fi

# ── 6. --dry-run with a real change: reported, nothing written ───────────────

fixtures light c 4 1
before=$(fingerprint)
snap --dry-run
if (( RC == 0 )) && [[ "$(pushed)" == 3 && "$(fingerprint)" == "$before" ]] \
   && grep -q 'Would commit 1 file(s)' "$W/out" && grep -q 'io.github.sevmorris.Beta.plist: mode' "$W/out" \
   && grep -q 'Left out, .*io.github.sevmorris.Alpha.plist' "$W/out" && grep -q 'nothing was committed or pushed' "$W/out"; then
  pass "--dry-run: reports the commit it would make, and ~/.mrk/preferences and the remote are as they were"
else
  fail "--dry-run: rc $RC, $(pushed) commit(s), tree $([[ "$(fingerprint)" == "$before" ]] && echo unchanged || echo CHANGED)"; show
fi

# ── 7. -n with only self-changing keys: nothing to commit ────────────────────

fixtures light b 5 1
before=$(fingerprint)
snap -n
if (( RC == 0 )) && [[ "$(pushed)" == 3 && "$(fingerprint)" == "$before" ]] && grep -q 'No changes to push' "$W/out"; then
  pass "-n with only self-changing keys: nothing to commit, nothing written"
else
  fail "-n with only self-changing keys: rc $RC"; show
fi

# ── 8. A new plist is committed, whatever it holds ───────────────────────────

fixtures light b 6 0 gamma
snap
if (( RC == 0 )) && [[ "$(pushed)" == 4 ]] && last_files | grep -qx 'sevmorris-apps/io.github.sevmorris.Gamma.plist' \
   && ! last_files | grep -q 'Alpha'; then
  pass "a new plist is committed, though it holds only a Sparkle time"
else
  fail "a new plist: rc $RC, last commit: $(last_files | tr '\n' ' ')"; show
fi

# ── 9. -n with a KeyVault copy saved: reported as a removal, nothing written ─

# The state every Mac was in from 2026-09-02 until 2026-09-30, when the group
# export took KeyVault's domain with the rest.
cp "$D/io.github.sevmorris.KeyVault.plist" "$P/sevmorris-apps/"
"${ENV[@]}" git -C "$P" add sevmorris-apps/io.github.sevmorris.KeyVault.plist
"${ENV[@]}" git -C "$P" commit -qm "a KeyVault copy, as the group export saved one"
"${ENV[@]}" git -C "$P" push -q origin HEAD 2>/dev/null
n_pushed=$(pushed)
before=$(fingerprint)
snap -n
if (( RC == 0 )) && [[ "$(pushed)" == "$n_pushed" && "$(fingerprint)" == "$before" ]] \
   && grep -q 'the real run removes it' "$W/out" && grep -q 'io.github.sevmorris.KeyVault.plist (removed)' "$W/out"; then
  pass "-n with a KeyVault copy saved: reported as a removal, and nothing written"
else
  fail "-n with a KeyVault copy saved: rc $RC"; show
fi

# ── 10. The saved KeyVault copy removed, and the removal pushed ──────────────

snap
if (( RC == 0 )) && [[ "$(pushed)" == $(( n_pushed + 1 )) && "$(last_files)" == "sevmorris-apps/io.github.sevmorris.KeyVault.plist" ]] \
   && ! "$REAL_GIT" -C "$ORIGIN" ls-tree -r --name-only HEAD | grep -q KeyVault && clean; then
  pass "a KeyVault copy saved before is removed, and the removal pushed"
else
  fail "the saved KeyVault copy: rc $RC, last commit: $(last_files | tr '\n' ' ')"; show
fi

# ── 11. A push that fails: the commit stays here, and is not called pushed ───

# Cases 11 to 14 are audit 20's X-1. Until 2026-10-01 the run after a failed
# push, when it found nothing new to commit, said "No changes to push." and
# exited 0 with the commit still absent from the remote. And a push that failed
# ended on git's error alone, with nothing to say the commit was kept (X-13).
ahead() { "$REAL_GIT" -C "$P" rev-list --count '@{upstream}..HEAD'; }
n_pushed=$(pushed)
fixtures dark b 7 0 gamma
mv "$ORIGIN" "$ORIGIN.away"
snap
rc_first=$RC
cp "$W/out" "$W/out-first"
# Again with the remote still out of reach, and nothing new to commit: the
# push of the earlier commit fails too, and must not pass for a push.
snap
mv "$ORIGIN.away" "$ORIGIN"
# said_kept FILE — mrk's own last word on a failed push, after git's (X-13)
said_kept() {
  grep -q 'The push failed (git exit [0-9]*): mrk-prefs does not have the last commit' "$1" \
    && grep -q 'The commit is kept in .*/.mrk/preferences. The next run of snapshot-prefs pushes it' "$1"
}
if (( rc_first != 0 )) && [[ "$(pushed)" == "$n_pushed" && "$(ahead)" == 1 ]] && ! grep -q 'Pushed to' "$W/out-first" \
   && said_kept "$W/out-first"; then
  pass "a push that fails: exit $rc_first, the commit kept here and said to be, and nothing said to be pushed"
else
  fail "a push that fails: rc $rc_first, $(pushed) commit(s) on the remote, $(ahead) ahead"; sed 's/^/    /' "$W/out-first"
fi
if (( RC != 0 && RC == rc_first )) && grep -q 'Pushing 1 commit(s) that an earlier run left unpushed' "$W/out" \
   && ! grep -q 'Pushed to\|No changes to push' "$W/out" && said_kept "$W/out"; then
  pass "the run after it, the remote still out of reach: exit $RC, and neither \"Pushed to\" nor \"No changes\""
else
  fail "the run after a failed push, the remote still out of reach: rc $RC"; show
fi

# ── 12. -n after it, with only self-changing keys since: says what would go ──

fixtures dark b 8 1 gamma
before=$(fingerprint)
snap -n
if (( RC == 0 )) && [[ "$(pushed)" == "$n_pushed" && "$(fingerprint)" == "$before" ]] \
   && grep -q 'The real run would push 1 commit(s) that an earlier run left unpushed' "$W/out" \
   && ! grep -q 'No changes to push' "$W/out"; then
  pass "-n with a commit unpushed: says the real run would push it, and pushes nothing"
else
  fail "-n with a commit unpushed: rc $RC, $(pushed) commit(s) on the remote"; show
fi

# ── 13. The real run after it: nothing to commit, and the commit is pushed ───

snap
if (( RC == 0 )) && [[ "$(pushed)" == $(( n_pushed + 1 )) && "$(ahead)" == 0 ]] \
   && [[ "$(pushed_value io.github.sevmorris.Alpha.plist theme)" == dark ]] \
   && grep -q 'Pushing 1 commit(s) that an earlier run left unpushed' "$W/out" \
   && tail -1 "$W/out" | grep -q 'Pushed to' && ! grep -q 'No changes to push' "$W/out" && clean; then
  pass "nothing new to commit, one commit unpushed: it is pushed, and the run ends on \"Pushed to\""
else
  fail "an unpushed commit: rc $RC, $(pushed) commit(s) on the remote, $(ahead) ahead, theme $(pushed_value io.github.sevmorris.Alpha.plist theme)"; show
fi
snap
if (( RC == 0 )) && [[ "$(pushed)" == $(( n_pushed + 1 )) ]] && tail -1 "$W/out" | grep -q 'No changes to push'; then
  pass "and the run after that: \"No changes to push.\", which now means the remote has the last commit"
else
  fail "the run after the push: rc $RC, $(pushed) commit(s) on the remote"; show
fi

# ── 14. The same on a branch with no upstream: a first push that failed ──────

# A second home, whose ~/.mrk/preferences is a plain directory: snapshot-prefs
# makes it a repository and adds the remote, and a first push that fails leaves
# the branch with no upstream to be ahead of.
H2="$W/home2"
ORIGIN2="$W/prefs2.git"
mkdir -p "$H2/.mrk/preferences"
snap2() {
  "${ENV[@]}" HOME="$H2" PREFS_REPO="$ORIGIN2" "$REPO_ROOT/scripts/snapshot-prefs" > "$W/out" 2>&1
  RC=$?
}
pushed2() { "$REAL_GIT" -C "$ORIGIN2" rev-list --count --all 2>/dev/null || echo 0; }
snap2
rc_first=$RC
"$REAL_GIT" init -q --bare "$ORIGIN2"
snap2
if (( rc_first != 0 && RC == 0 )) && [[ "$(pushed2)" == 1 ]] \
   && grep -q 'Pushing 1 commit(s) that an earlier run left unpushed' "$W/out" && tail -1 "$W/out" | grep -q 'Pushed to'; then
  pass "a first push that failed, so no upstream: the next run pushes the commit"
else
  fail "a first push that failed: first rc $rc_first, then rc $RC, $(pushed2) commit(s) on the remote"; show
fi

# ── 15. An unknown argument: refused before any export ───────────────────────

n_calls=$(wc -l < "$W/calls")
snap --bogus
if (( RC == 2 )) && [[ "$(wc -l < "$W/calls")" == "$n_calls" ]] && grep -q 'unknown argument: --bogus' "$W/out"; then
  pass "an unknown argument exits 2 before anything is exported"
else
  fail "an unknown argument: rc $RC, or defaults was called"; show
fi

# ── 16. defaults was only ever asked to read, and never about KeyVault ───────

if grep -vE '^(read|export|domains)( |$)' "$W/calls" | grep -q .; then
  fail "defaults was asked for more than read, export and domains:"; sed 's/^/    /' "$W/calls"
else
  pass "defaults was asked for read, export and domains, nothing else"
fi
kv_added=$("$REAL_GIT" -C "$ORIGIN" log --all --diff-filter=A --format=%s -- sevmorris-apps/io.github.sevmorris.KeyVault.plist)
if grep -q 'io.github.sevmorris.KeyVault' "$W/calls"; then
  fail "defaults was asked about KeyVault's domain:"; grep KeyVault "$W/calls" | sed 's/^/    /'
elif [[ "$kv_added" != "a KeyVault copy, as the group export saved one" ]]; then
  fail "a KeyVault plist was added by: $(tr '\n' ';' <<<"$kv_added")"
else
  pass "KeyVault's domain was never read or exported, and only the test ever committed a copy"
fi

if (( fails )); then
  err "$fails snapshot-prefs check(s) failed"
  exit 1
fi
ok "snapshot-prefs checks passed"
