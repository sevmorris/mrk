#!/usr/bin/env bash
# check-updates.sh — prove that check-updates compares at every shell start,
# fetches at most once a day, and asks once for each new remote head.
#
# Until 2026-09-30 the whole check ran at most once every 7 days. A commit
# pushed the day after a check waited up to a week to be offered, and nothing
# tested any of it.
#
# The cases run in order against one scratch origin and a clone of it, the
# checkout REPO_DIR names, under a throwaway HOME, and each runs check-updates
# in a pseudo-terminal, since it does nothing without one. git is the real git
# except for fetch, which only records the call: the cases move origin/main
# themselves, with a real fetch, which is what the background fetch would have
# done by the next shell. make is a stub that records `make pull`, and fails
# when a case tells it to.
# Nothing reaches the real HOME, the network, or ~/mrk.
# It runs under /bin/bash and under the bash running this file. ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" != --inner ]]; then
  run_under() {
    # shellcheck disable=SC2016  # expanded by the inner bash, not this one
    printf '  under bash %s\n' "$("$1" -c 'echo "${BASH_VERSION%%(*}"')"
    "$1" "${BASH_SOURCE[0]}" --inner "$1"
  }
  rc=0
  run_under /bin/bash || rc=1
  if [[ ! "$BASH" -ef /bin/bash ]]; then run_under "$BASH" || rc=1; fi
  exit "$rc"
fi
BASH_UNDER_TEST="$2"

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
H="$W/home"       # the throwaway HOME
S="$W/stubs"      # first on PATH
ORIGIN="$W/origin.git"
UP="$W/upstream"  # where the cases commit, then push to ORIGIN
CLONE="$H/mrk"    # REPO_DIR
CACHE="$H/.cache/mrk"
STAMP="$CACHE/last-update-check"
mkdir -p "$H" "$S" "$UP"
: > "$W/fetches"; : > "$W/makes"

# ── Stubs ────────────────────────────────────────────────────────────────────

cat > "$S/git" <<EOF
#!/bin/sh
for a in "\$@"; do
  [ "\$a" = fetch ] && { echo fetch >> "$W/fetches"; exit 0; }
done
exec "$REAL_GIT" "\$@"
EOF
# make records the call, and how many fetches had started by then, after a
# pause when $W/make-waits is there. It exits with the status in $W/make-rc
# when that file is there: a pull that fails.
cat > "$S/make" <<EOF
#!/bin/sh
printf 'make %s\\n' "\$*" >> "$W/makes"
[ -f "$W/make-waits" ] && sleep 0.3
wc -l < "$W/fetches" | tr -d ' ' > "$W/fetches-at-make"
[ -f "$W/make-rc" ] && exit "\$(cat "$W/make-rc")"
exit 0
EOF
chmod +x "$S/git" "$S/make"
ln -s "$BASH_UNDER_TEST" "$S/bash"

# CMD in a pseudo-terminal, as the session leader. When "[y/N]" appears it
# types ANSWER and Return, or Ctrl-D for EOF. SIGHUP is ignored before the exec,
# as it is in effect under a real shell: the session leader's exit would
# otherwise hang up the disowned fetch before it had started.
cat > "$W/at-a-terminal.py" <<'PY'
import os, pty, select, signal, sys, time
answer, argv = sys.argv[1], sys.argv[2:]
keys = b"\x04" if answer == "EOF" else answer.encode() + b"\n"
pid, fd = pty.fork()
if pid == 0:
    signal.signal(signal.SIGHUP, signal.SIG_IGN)
    os.execvp(argv[0], argv)
out, sent, status, t0 = b"", False, None, time.time()
while time.time() - t0 < 30:
    r, _, _ = select.select([fd], [], [], 0.1)
    if r:
        try: chunk = os.read(fd, 4096)
        except OSError: chunk = b""
        if chunk:
            out += chunk
            if not sent and b"[y/N]" in out:
                os.write(fd, keys); sent = True
            continue
    done, st = os.waitpid(pid, os.WNOHANG)
    if done:
        status = st; break
if status is None:
    os.kill(pid, signal.SIGKILL); os.waitpid(pid, 0); rc = 124
elif os.WIFEXITED(status):
    rc = os.WEXITSTATUS(status)
else:
    rc = 128 + os.WTERMSIG(status)
sys.stdout.write(out.decode("utf-8", "replace").replace("\r", ""))
sys.exit(rc)
PY

ENV=(env -i HOME="$H" REPO_DIR="$CLONE" PATH="$S:/usr/bin:/bin:/usr/sbin:/sbin"
     TMPDIR="${TMPDIR:-/tmp}" TERM=dumb
     GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
     GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=test@test.invalid
     GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=test@test.invalid)
CU="$REPO_ROOT/scripts/check-updates"

# check [ANSWER] — check-updates at a terminal, ANSWER typed at any prompt
# (default n). Output in $W/out, exit status in RC.
RC=0
check() {
  "${ENV[@]}" python3 "$W/at-a-terminal.py" "${1:-n}" "$CU" > "$W/out" 2>&1
  RC=$?
}
asked()  { grep -q 'Update now? \[y/N\]' "$W/out"; }
fetches() { wc -l < "$W/fetches" | tr -d ' '; }
makes()   { wc -l < "$W/makes" | tr -d ' '; }
# await_fetches N — wait for the disowned fetch to record itself, up to 5 s
await_fetches() {
  local i
  for (( i = 0; i < 50; i++ )); do
    (( $(fetches) >= $1 )) && return 0
    sleep 0.1
  done
  return 1
}
# settle — long enough for a fetch that should not have started to show up
settle() { sleep 0.5; }
now() { date +%s; }
show() { sed 's/^/    /' "$W/out"; }

g() { "${ENV[@]}" git "$@"; }
rg() { "${ENV[@]}" "$REAL_GIT" "$@"; }  # git with a real fetch
# upstream N — commit N times upstream, push, and fetch it into the clone
upstream() {
  local i
  for (( i = 0; i < $1; i++ )); do
    echo "$RANDOM $i" >> "$UP/file"
    g -C "$UP" commit -qam "upstream $i" || return 1
  done
  g -C "$UP" push -q origin main && rg -C "$CLONE" fetch -q origin
}
markers() { find "$CACHE" -maxdepth 1 -name 'asked-*' -exec basename {} \; 2>/dev/null | sort | tr '\n' ' '; }
remote_head() { rg -C "$CLONE" rev-parse origin/main; }

echo seed > "$UP/file"
g -C "$UP" init -q -b main
g -C "$UP" add -A
g -C "$UP" commit -qm seed
g clone -q --bare "$UP" "$ORIGIN"
g -C "$UP" remote add origin "$ORIGIN"
g clone -q "$ORIGIN" "$CLONE" || { fail "could not clone the scratch origin"; exit 1; }

# ── 1. --help, and a shell with no terminal: nothing written, nothing fetched ─

"${ENV[@]}" "$CU" --help > "$W/out" 2>&1; rc_help=$?
"${ENV[@]}" "$CU" < /dev/null > "$W/out2" 2>&1; rc_quiet=$?
settle
if (( rc_help == 0 && rc_quiet == 0 )) && grep -q '^Usage:' "$W/out" && [[ ! -s "$W/out2" ]] \
   && [[ ! -e "$H/.cache" && "$(fetches)" == 0 ]]; then
  pass "--help and a shell with no terminal write nothing and fetch nothing"
else
  fail "--help ($rc_help) or no terminal ($rc_quiet) wrote or fetched something"; show; sed 's/^/    /' "$W/out2"
fi

# ── 2. Up to date, never fetched: silent, and the first fetch starts ─────────

t=$(now)
check
if (( RC == 0 )) && ! asked && [[ ! -s "$W/out" ]] && await_fetches 1 \
   && (( $(cat "$STAMP") >= t )); then
  pass "up to date, never fetched: silent, and a background fetch starts"
else
  fail "up to date, never fetched: rc $RC, $(fetches) fetch(es)"; show
fi

# ── 3. A fetch an hour ago: none now ─────────────────────────────────────────

echo $(( $(now) - 3600 )) > "$STAMP"; before=$(cat "$STAMP")
check; settle
if (( RC == 0 )) && ! asked && [[ "$(fetches)" == 1 && "$(cat "$STAMP")" == "$before" ]]; then
  pass "a fetch an hour ago: no fetch, the timestamp kept"
else
  fail "a fetch an hour ago: $(fetches) fetch(es), timestamp $(cat "$STAMP") (was $before)"; show
fi

# ── 4. A fetch 25 hours ago: a new one ───────────────────────────────────────

echo $(( $(now) - 90000 )) > "$STAMP"; t=$(now)
check
if (( RC == 0 )) && await_fetches 2 && (( $(cat "$STAMP") >= t )); then
  pass "a fetch 25 hours ago: a new one starts"
else
  fail "a fetch 25 hours ago: $(fetches) fetch(es) in all, expected 2"; show
fi

# ── 5. Behind, fetched an hour ago: asked, though no fetch is due ────────────

upstream 1
echo $(( $(now) - 3600 )) > "$STAMP"
check n; settle
head5=$(remote_head)
if (( RC == 0 )) && asked && grep -q 'mrk: 1 new commit on origin/main' "$W/out" \
   && grep -q 'Not asking again until origin/main moves' "$W/out" && grep -q "make -C ~/mrk pull" "$W/out" \
   && [[ "$(makes)" == 0 && "$(fetches)" == 2 && "$(markers)" == "asked-$head5 " ]]; then
  pass "behind, no fetch due: the compare still runs; asked, and a no pulls nothing"
else
  fail "behind, no fetch due: rc $RC, $(makes) make(s), $(fetches) fetch(es), markers: $(markers)"; show
fi

# ── 6. The same remote head: not asked again ─────────────────────────────────

check y; settle
if (( RC == 0 )) && ! asked && [[ ! -s "$W/out" && "$(makes)" == 0 ]]; then
  pass "the same remote head: not asked again, nothing pulled"
else
  fail "the same remote head: asked again, or pulled"; show
fi

# ── 7. A new remote head: asked again, counting from HEAD; yes runs make pull

upstream 2
head7=$(remote_head)
check y; settle
if (( RC == 0 )) && asked && grep -q 'mrk: 3 new commits on origin/main' "$W/out" \
   && [[ "$(cat "$W/makes")" == "make -C $CLONE pull" && "$(markers)" == "asked-$head7 " ]]; then
  pass "a new remote head: asked again, yes runs make pull, one marker kept"
else
  fail "a new remote head: rc $RC, makes: $(tr '\n' ';' < "$W/makes"), markers: $(markers)"; show
fi

# ── 7b. A yes whose pull fails: asked again at the next shell ────────────────

# The marker is written before the prompt. Until 2026-10-01 it stayed after a
# pull that failed, so the checkout was behind and nothing asked again until
# origin moved (audit 20, X-5).
upstream 1
head7b=$(remote_head)
echo 2 > "$W/make-rc"
check y; settle
rc_failed=$RC
kept=$(markers)
said=0; grep -q 'The pull failed. The next shell asks again.' "$W/out" && said=1
check n; settle
rm -f "$W/make-rc"
if (( rc_failed == 2 && said == 1 )) && [[ -z "$kept" ]] && asked && [[ "$(makes)" == 2 && "$(markers)" == "asked-$head7b " ]]; then
  pass "a yes whose pull fails: exit 2, said so, no marker kept, and the next shell asks again"
else
  fail "a yes whose pull fails: rc $rc_failed, said $said, markers after it: '$kept', then: '$(markers)', $(makes) make(s)"; show
fi

# ── 7c. A yes with a fetch due: make pull first, the fetch after it ──────────

# check-updates fetches after the prompt, because a fetch still running when a
# yes starts make pull would contend with the pull's own fetch for the same
# refs. Until 2026-10-01 nothing held that order (audit 20, X-11). The make stub
# waits a moment, then records how many fetches had started.
upstream 1
echo $(( $(now) - 90000 )) > "$STAMP"
n=$(fetches)
: > "$W/make-waits"
check y
rm -f "$W/make-waits"
if (( RC == 0 )) && asked && [[ "$(makes)" == 3 && "$(cat "$W/fetches-at-make")" == "$n" ]] && await_fetches $(( n + 1 )); then
  pass "a yes with a fetch due: make pull runs first, and the fetch starts after it"
else
  fail "a yes with a fetch due: rc $RC, $(makes) make(s), fetches when make ran: $(cat "$W/fetches-at-make" 2>/dev/null) (were $n), now $(fetches)"; show
fi

# ── 8. Behind, on another branch: not asked ──────────────────────────────────

upstream 1
rg -C "$CLONE" switch -q -c feature
check y; settle
if (( RC == 0 )) && ! asked && [[ "$(makes)" == 3 ]]; then
  pass "behind, on another branch: not asked"
else
  fail "behind, on another branch: asked, or pulled"; show
fi
rg -C "$CLONE" switch -q main

# ── 9. Back on main, the same head: asked; Ctrl-D counts as no ───────────────

check EOF; settle
if (( RC == 0 )) && asked && grep -q 'Not asking again' "$W/out" && [[ "$(makes)" == 3 ]]; then
  pass "back on main: asked; Ctrl-D is a no, and exits 0"
else
  fail "back on main, Ctrl-D: rc $RC, $(makes) make(s)"; show
fi

# ── 10. A local commit origin lacks: not asked ───────────────────────────────

echo local >> "$CLONE/local"
g -C "$CLONE" add local && g -C "$CLONE" commit -qm local
upstream 1
check y; settle
if (( RC == 0 )) && ! asked && [[ "$(makes)" == 3 ]]; then
  pass "diverged from origin: not asked"
else
  fail "diverged from origin: asked, or pulled"; show
fi

# ── 11. A timestamp in the future: a fetch is due ────────────────────────────

n=$(fetches)
echo $(( $(now) + 864000 )) > "$STAMP"; t=$(now)
check
if (( RC == 0 )) && await_fetches $(( n + 1 )) && (( $(cat "$STAMP") <= t + 5 )); then
  pass "a timestamp in the future: a fetch starts, and the timestamp is reset"
else
  fail "a timestamp in the future: $(fetches) fetch(es), timestamp $(cat "$STAMP")"; show
fi

if (( fails )); then
  err "$fails check-updates check(s) failed"
  exit 1
fi
ok "check-updates checks passed"
