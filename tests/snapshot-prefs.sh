#!/usr/bin/env bash
# snapshot-prefs.sh — prove that snapshot-prefs leaves out a plist that changed
# only in keys that change on their own, makes no commit when that is all that
# changed, and that --dry-run commits, pushes and writes nothing.
#
# Until 2026-09-30 any difference from the last commit made a commit, and in
# the sixty snapshots before then a plist had changed in nothing but update
# check times, window positions, launch counters and the like 274 times.
#
# Each case runs the real snapshot-prefs under a throwaway HOME, with defaults
# a stub first on PATH: it knows three io.github.sevmorris.* domains, written
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

# ── 9. An unknown argument: refused before any export ────────────────────────

n_calls=$(wc -l < "$W/calls")
snap --bogus
if (( RC == 2 )) && [[ "$(wc -l < "$W/calls")" == "$n_calls" ]] && grep -q 'unknown argument: --bogus' "$W/out"; then
  pass "an unknown argument exits 2 before anything is exported"
else
  fail "an unknown argument: rc $RC, or defaults was called"; show
fi

# ── 10. defaults was only ever asked to read ─────────────────────────────────

if grep -vE '^(read|export|domains)( |$)' "$W/calls" | grep -q .; then
  fail "defaults was asked for more than read, export and domains:"; sed 's/^/    /' "$W/calls"
else
  pass "defaults was asked for read, export and domains, nothing else"
fi

if (( fails )); then
  err "$fails snapshot-prefs check(s) failed"
  exit 1
fi
ok "snapshot-prefs checks passed"
