#!/usr/bin/env bash
# sync-login-items.sh — prove that sync-login-items reads back exactly what it
# writes, for login items with awkward names, and that its decisions on the
# command line take exactly what --check lists.
#
# The tracked login items are config/login-items.txt, one path a line, which
# sync-login-items edits line by line. On 2026-09-18, when the list was
# add_login_item lines in post-install, a first write was already right, but
# reading it back was not: an app named with $ or a backtick came back with its
# escaping backslash, one with a double quote was not recognised at all, and an
# accented name spelled one way by System Events and another by the file system
# never matched. Each was re-added on every run. The same twelve names run
# through the plain list here.
#
# --check, --add, --ignore and --remove are for a program with no terminal
# (mrk Settings). Each refusal must change nothing, and a decision must
# start no gum. --remove in particular must stop, as an interactive run does,
# when System Events returns no login items.
#
# The committed list is checked too: every line an app path, in byte order,
# each app once. The manual links to the list and does not copy it, so no run
# writes docs/manual.md: every check below that a file is unchanged includes
# the manual (section 11). Until 2026-10-29 the manual named the apps in a
# sentence that each run rewrote, and --manual repaired it (audit 22, D-3).
#
# Everything runs against a copy of the repository, under a throwaway HOME.
# osascript is a stub that prints the login items from a fixture, and gum is a
# stub that selects every choice and records each call. An interactive run
# calls gum with </dev/tty, so it runs inside a pseudo-terminal from script(1);
# a decision runs with no terminal at all. No System Events query is made, so
# there is no Automation prompt. ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

for tool in python3 script git; do
  command -v "$tool" >/dev/null 2>&1 || { fail "$tool not found"; exit 1; }
done

LIST="config/login-items.txt"

# ── 0. The committed list ────────────────────────────────────────────────────

entries=()
while IFS= read -r p; do entries+=("$p"); done < <(mrk_config_entries "$REPO_ROOT/$LIST")
bad=""
for p in "${entries[@]}"; do
  [[ "$p" == /*.app ]] || bad+=" '$p'"
done
if (( ${#entries[@]} >= 3 )) && [[ -z "$bad" ]] \
   && printf '%s\n' "${entries[@]}" | LC_ALL=C sort -c 2>/dev/null \
   && [[ -z "$(printf '%s\n' "${entries[@]##*/}" | sort | uniq -d)" ]]; then
  pass "$LIST: ${#entries[@]} app paths, in byte order, each app once"
else
  fail "$LIST: a line is not an app path, or the paths are out of byte order, or an app is listed twice:$bad"
fi

# ── The copy ─────────────────────────────────────────────────────────────────

W="$(mktemp -d "${TMPDIR:-/tmp}/sli.XXXXXX")"
trap 'rm -rf "$W"' EXIT
R="$W/repo"
mkdir -p "$R/scripts" "$R/docs" "$R/config" "$W/home" "$W/stubs"
cp -p "$REPO_ROOT/scripts/sync-login-items" "$REPO_ROOT/scripts/lib.sh" "$R/scripts/"
cp -p "$REPO_ROOT/$LIST" "$R/config/"
cp -p "$REPO_ROOT/docs/manual.md" "$R/docs/"
cp -p "$R/$LIST" "$W/list.orig"
cp -p "$R/docs/manual.md" "$W/manual.orig"

cat > "$W/stubs/osascript" <<'EOF'
#!/bin/bash
[[ "$FIXTURE" == FAIL ]] && { echo "execution error: Not authorised to send Apple events to System Events. (-1743)" >&2; exit 1; }
cat "$FIXTURE"
EOF
cat > "$W/stubs/gum" <<'EOF'
#!/bin/bash
# `gum choose [flags] choices...`: select every choice, and record the call.
echo called >> "$GUM_CALLS"
shift
for a in "$@"; do [[ "$a" == --* ]] || printf '%s\n' "$a"; done
EOF
chmod +x "$W/stubs/osascript" "$W/stubs/gum"
export GUM_CALLS="$W/gum-calls"

# sli FIXTURE — an interactive run against that fixture; output in $W/out
sli() {
  FIXTURE="$1" HOME="$W/home" PATH="$W/stubs:$PATH" \
    script -q /dev/null bash "$R/scripts/sync-login-items" </dev/null 2>&1 \
    | tr -d '\r' | sed 's/\x1b\[[0-9;]*m//g' > "$W/out"
}

# slx FIXTURE ARGS... — a run with no terminal: stdout in $W/out, stderr in
# $W/err, status in $RC, and $GUMS the number of times gum was started
slx() {
  local fixture=$1; shift
  rm -f "$GUM_CALLS"
  FIXTURE="$fixture" HOME="$W/home" PATH="$W/stubs:$PATH" \
    bash "$R/scripts/sync-login-items" "$@" </dev/null > "$W/out" 2> "$W/err"
  RC=$?
  GUMS=0
  [[ -f "$GUM_CALLS" ]] && GUMS=$(wc -l < "$GUM_CALLS" | tr -d ' ')
}

unchanged() { cmp -s "$R/$LIST" "$W/list.orig" && cmp -s "$R/docs/manual.md" "$W/manual.orig"; }
reset_copy() { cp -p "$W/list.orig" "$R/$LIST"; cp -p "$W/manual.orig" "$R/docs/manual.md"; rm -f "$W/home/.mrk/login-items-ignore"; }
why() { sed 's/^/      /' "$W/err" "$W/out" | tail -"${1:-6}" >&2; }

nfd() { python3 -c 'import sys, unicodedata; print(unicodedata.normalize("NFD", sys.argv[1]), end="")' "$1"; }

# The items the list tracks now, listed the way System Events lists them.
BASE="$W/base"
for p in "${entries[@]}"; do n="${p##*/}"; printf '%s\t%s\n' "${n%.app}" "$p"; done > "$BASE"

AWKWARD="$W/awkward"
{
  printf '%s\t%s\n' "Magic Backup Machine" "/Applications/Magic Backup Machine.app"
  printf '%s\t%s\n' 'Say "Hi"'             '/Applications/Say "Hi".app'
  # shellcheck disable=SC2016  # a literal $ in an app name is the point
  printf '%s\t%s\n' 'Cash $App'            '/Applications/Cash $App.app'
  printf '%s\t%s\n' 'Tick`Tock'            '/Applications/Tick`Tock.app'
  printf '%s\t%s\n' "Joe's App"            "/Applications/Joe's App.app"
  printf '%s\t%s\n' "Foo, Inc"             "/Applications/Foo, Inc.app"
  printf '%s\t%s\n' "Back\\slash"          "/Applications/Back\\slash.app"
  printf '%s\t%s\n' "Café Noir"            "/Applications/Café Noir.app"
  # System Events composed and the path decomposed, then the other way round
  printf '%s\t%s\n' "Crème"                "/Applications/$(nfd "Crème").app"
  printf '%s\t%s\n' "$(nfd "Über")"        "/Applications/Über.app"
  printf '%s\t%s\n' "Helper"               "/Users/Shared/Applications/Helper.app"
  printf '%s\t%s\n' "Deep Helper"          "/Library/Application Support/Vendor/Deep Helper.app"
} > "$AWKWARD"
n_awkward=$(wc -l < "$AWKWARD" | tr -d ' ')
cat "$BASE" "$AWKWARD" > "$W/all"

# ── 1. Add every awkward item ────────────────────────────────────────────────

sli "$W/all"
if grep -q "Updated $LIST: $n_awkward added, 0 removed" "$W/out"; then
  pass "all $n_awkward awkward names are offered and added"
else
  fail "adding the awkward names: $(grep -E 'Updated|Warning|✗' "$W/out" | head -3)"
fi

# What post-install reads back (the same function, under /bin/bash too) must
# be each exact path, with the header kept and the paths in byte order.
cut -f2 "$W/all" | LC_ALL=C sort > "$W/want"
# shellcheck disable=SC2016  # expanded by the inner bash
for b in /bin/bash bash; do
  "$b" -c '. "$1"; mrk_config_entries "$2"' _ "$R/scripts/lib.sh" "$R/$LIST" > "$W/got"
  if cmp -s "$W/want" "$W/got"; then
    pass "under $("$b" -c 'echo "bash ${BASH_VERSION%%(*}"'), the list gives back every exact path, in byte order"
  else
    fail "under $b, the list gives back different paths, or out of order:"
    diff "$W/want" "$W/got" | sed 's/^/      /' >&2
  fi
done
if [[ "$(grep '^#' "$R/$LIST")" == "$(grep '^#' "$W/list.orig")" ]]; then
  pass "the header comment is kept"
else
  fail "the header comment changed"
fi

if cmp -s "$R/docs/manual.md" "$W/manual.orig"; then
  pass "the manual is not written"
else
  fail "adding the awkward names wrote docs/manual.md"
fi

# ── 2. Nothing changed on the system, so nothing may change ──────────────────

cp -p "$R/$LIST" "$W/list.after-add"
sli "$W/all"
if grep -q 'Login items are up to date' "$W/out" && cmp -s "$R/$LIST" "$W/list.after-add"; then
  pass "a second run over the same items finds nothing to do"
else
  fail "a second run over the same items is not a no-op:"
  grep -E '^\s+[+-] ' "$W/out" | sed 's/^/      /' >&2
fi

# ── 3. Remove them again ─────────────────────────────────────────────────────

sli "$BASE"
if grep -q "Updated $LIST: 0 added, $n_awkward removed" "$W/out"; then
  pass "all $n_awkward are recognised as tracked, and removed"
else
  fail "removing them: $(grep -E 'Updated|Warning|✗' "$W/out" | head -3)"
fi
if unchanged; then
  pass "$LIST and the manual are back byte for byte"
else
  fail "$LIST or the manual differs from where it started"
fi

sli "$BASE"
if grep -q 'Login items are up to date' "$W/out"; then
  pass "and a last run finds nothing to do"
else
  fail "the last run was not a no-op: $(grep -E '^\s+[+-] ' "$W/out" | tr '\n' ' ')"
fi

# ── 4. The apps that must not open at login ──────────────────────────────────
#
# MRK_NOT_AT_LOGIN's apps add themselves back. They are never offered for
# tracking, and nothing is written.
{
  cat "$BASE"
  printf '%s\t%s\n' "NordVPN"      "/Applications/NordVPN.app"
  printf '%s\t%s\n' "Google Drive" "/Applications/Google Drive.app"
} > "$W/not-wanted"
sli "$W/not-wanted"
if grep -q 'Login items are up to date' "$W/out" \
   && grep -q 'Not offering Google Drive: it must not open at login' "$W/out" \
   && grep -q 'Not offering NordVPN: it must not open at login' "$W/out" \
   && unchanged; then
  pass "Google Drive and NordVPN are not offered, and nothing is written"
else
  fail "the apps that must not open at login: $(grep -E 'Not offering|^\s+[+-] |Updated' "$W/out" | tr '\n' ' ')"
fi

# ── 5. --check ───────────────────────────────────────────────────────────────
#
# One fixture with every kind of line: a tracked app gone (stale), a tracked
# app in the ignore list (ignored), a new app (new), and three that are not
# offered: an ignored new one, one that must not open at login, and a login
# item that is not an app.
name_of() { local n="${1##*/}"; printf '%s' "${n%.app}"; }
STALE=$(name_of "${entries[0]}")
CONFLICT=$(name_of "${entries[1]}")
TRACKED=$(name_of "${entries[2]}")
mkdir -p "$W/home/.mrk"
printf '# test\n%s\nSkipMe\n' "$CONFLICT" > "$W/home/.mrk/login-items-ignore"
cp -p "$W/home/.mrk/login-items-ignore" "$W/ignore.orig"
{
  grep -v "^$STALE"$'\t' "$BASE"
  printf '%s\t%s\n' "Zéphyr"   "/Applications/Zéphyr.app"
  printf '%s\t%s\n' "SkipMe"   "/Applications/SkipMe.app"
  printf '%s\t%s\n' "NordVPN"  "/Applications/NordVPN.app"
  printf '%s\t%s\n' "Startup"  "/Users/Shared/startup.sh"
} > "$W/drift"
want=$(printf 'add\tZéphyr\t/Applications/Zéphyr.app\tnew\nremove\t%s\t%s\tstale\nremove\t%s\t%s\tignored' \
  "$STALE" "${entries[0]}" "$CONFLICT" "${entries[1]}")
slx "$W/drift" --check
if [[ $RC == 0 && "$(cat "$W/out")" == "$want" && $GUMS == 0 ]] && unchanged; then
  pass "--check: one tab-separated line for each new, stale and ignored item, and nothing else on stdout"
else
  fail "--check (exit $RC, gum started $GUMS times):"
  diff <(printf '%s\n' "$want") "$W/out" | sed 's/^/      /' >&2; why
fi

# on_tty OUT CMD... — CMD with stdout in OUT and stderr on a terminal from
# script(1), as a run from Terminal has it, so lib.sh turns its colours on.
# OUT.tty exists afterwards when stderr was a terminal. Until 2026-10-29 every
# --check here ran with stderr in a file (audit 22, Z-13).
on_tty() {
  local out=$1; shift
  rm -f "$out" "$out.tty"
  # shellcheck disable=SC2016  # expanded by the inner bash
  script -q /dev/null bash -c '[[ -t 2 ]] && : > "$1.tty"; exec > "$1"; shift; exec "$@"' _ "$out" "$@" </dev/null > "$out.term" 2>&1
}
# same_on_tty OUT WANT — OUT is WANT, stderr was a terminal, and OUT holds no
# escape character
same_on_tty() {
  [[ -e "$1.tty" ]] && [[ "$(cat "$1")" == "$2" ]] && ! LC_ALL=C grep -q $'\033' "$1"
}
on_tty "$W/out.tty" env FIXTURE="$W/drift" HOME="$W/home" PATH="$W/stubs:$PATH" bash "$R/scripts/sync-login-items" --check
if same_on_tty "$W/out.tty" "$want" && unchanged && LC_ALL=C grep -q $'\033\\[' "$W/out.tty.term"; then
  pass "--check with stderr on a terminal: the same lines, the colours on stderr alone, and nothing written"
else
  fail "--check with stderr on a terminal"; diff <(printf '%s\n' "$want") "$W/out.tty" | sed 's/^/      /' >&2
fi
if grep -q 'Not offering Startup: its login item is not an app' "$W/err"; then
  pass "--check: a login item that is not an app is not offered, and says why on stderr"
else
  fail "--check: the login item that is not an app: $(tr '\n' ' ' < "$W/err")"
fi

rm -f "$W/home/.mrk/login-items-ignore"
slx "$BASE" --check
if [[ $RC == 0 && ! -s "$W/out" ]]; then
  pass "--check with nothing to do: exit 0, no line"
else
  fail "--check with nothing to do (exit $RC): $(cat "$W/out")"
fi
cp -p "$W/ignore.orig" "$W/home/.mrk/login-items-ignore"

: > "$W/empty"
for fixture in "$W/empty" FAIL; do
  slx "$fixture" --check
  if [[ $RC == 1 && ! -s "$W/out" ]]; then
    pass "--check when System Events $([[ $fixture == FAIL ]] && echo fails || echo returns nothing): exit 1, no line"
  else
    fail "--check on $fixture (exit $RC): $(cat "$W/out")"
  fi
done

# A name with a backslash: --check escapes it, as every --check line does, and
# a program that undoes the escape gives --add the name it lists.
{ cat "$BASE"; printf '%s\t%s\n' 'Back\slash' '/Applications/Back\slash.app'; } > "$W/backslash"
rm -f "$W/home/.mrk/login-items-ignore"
slx "$W/backslash" --check
if [[ $RC == 0 && "$(cat "$W/out")" == 'add	Back\\slash	/Applications/Back\\slash.app	new' ]]; then
  pass "--check: a backslash in a name and a path is escaped as \\\\"
else
  fail "--check with a backslash (exit $RC): $(cat "$W/out")"; why
fi
slx "$W/backslash" --add 'Back\slash'
if [[ $RC == 0 ]] && mrk_config_entries "$R/$LIST" | grep -qxF '/Applications/Back\slash.app'; then
  pass "--add takes the name --check lists, with the escape undone"
else
  fail "--add with a backslash (exit $RC)"; why
fi
reset_copy
cp -p "$W/ignore.orig" "$W/home/.mrk/login-items-ignore"

# A name that starts with a dash: `--add NAME` takes it for an option, and
# `--add=NAME` takes it as a name. Until 2026-10-28 no decision could take
# one, and the exit 2 read to Dipstick as an older mrk (audit 22, Z-3).
{ cat "$BASE"; printf '%s\t%s\n' '-Dash App' '/Applications/-Dash App.app'; } > "$W/dash"
slx "$W/dash" --add '-Dash App'
dash_rc=$RC
reset_copy; cp -p "$W/ignore.orig" "$W/home/.mrk/login-items-ignore"
slx "$W/dash" --add='-Dash App'
if [[ $dash_rc == 2 && $RC == 0 ]] && mrk_config_entries "$R/$LIST" | grep -qxF '/Applications/-Dash App.app'; then
  pass "--add=NAME takes a name that starts with a dash, which --add NAME refuses with exit 2"
else
  fail "a name that starts with a dash: --add NAME exit $dash_rc, --add=NAME exit $RC"; why
fi
reset_copy; cp -p "$W/ignore.orig" "$W/home/.mrk/login-items-ignore"

# A run that writes holds the list's lock, so two decisions at once cannot
# lose one (audit 22, Z-7). --check only reads, and does not wait for it.
LOCK="$R/config/.login-items.txt.lock"
sleep 30 & holder=$!
mkdir "$LOCK" && printf '%s\n' "$holder" > "$LOCK/pid"
export MRK_LOCK_WAIT=1
slx "$W/dash" --check; check_rc=$RC
slx "$W/dash" --add='-Dash App'
unset MRK_LOCK_WAIT
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null; rm -rf "$LOCK"
if [[ $check_rc == 0 && $RC == 1 ]] && grep -q "Another mrk run (process $holder) is changing login-items.txt" "$W/err" && unchanged; then
  pass "a decision waits for the list's lock, then exits 1 and writes nothing; --check does not wait"
else
  fail "the list's lock: --check exit $check_rc, --add exit $RC"; why
fi
reset_copy; cp -p "$W/ignore.orig" "$W/home/.mrk/login-items-ignore"

# ── 6. --add ─────────────────────────────────────────────────────────────────

slx "$W/drift" --add "Zéphyr"
want_list=$(printf '%s\n' "${entries[@]}" "/Applications/Zéphyr.app" | LC_ALL=C sort)
if [[ $RC == 0 && $GUMS == 0 ]] && [[ "$(mrk_config_entries "$R/$LIST")" == "$want_list" ]] \
   && cmp -s "$R/docs/manual.md" "$W/manual.orig"; then
  pass "--add NAME, with no terminal: the path goes into the list in byte order, and nothing else is written; gum not started"
else
  fail "--add NAME (exit $RC, gum started $GUMS times)"; why
fi
reset_copy; cp -p "$W/ignore.orig" "$W/home/.mrk/login-items-ignore"

# The name decomposed, as a program might pass it: matched all the same.
slx "$W/drift" --add "$(nfd "Zéphyr")" -n
if [[ $RC == 0 ]] && grep -q '+ Zéphyr' "$W/out" && grep -q 'dry run' "$W/out" && unchanged; then
  pass "--add NAME -n, NAME decomposed: matched, shows the add, and writes nothing"
else
  fail "--add NAME -n (exit $RC)"; why
fi

# refuse_case LABEL WANT FIXTURE ARGS... — a decision that must exit 1, say
# WANT on stderr, and change neither file nor the ignore list
refuse_case() {
  local label=$1 want=$2; shift 2
  slx "$@"
  if [[ $RC == 1 ]] && grep -qF "$want" "$W/err" && unchanged \
     && cmp -s "$W/home/.mrk/login-items-ignore" "$W/ignore.orig"; then
    pass "$label: refused, and nothing written"
  else
    fail "$label (exit $RC)"; why
  fi
}
refuse_case "--add a tracked app"            "already tracks"             "$W/drift" --add "$TRACKED"
refuse_case "--add NordVPN"                  "must not open at login"     "$W/drift" --add NordVPN
refuse_case "--add an ignored app"           "is in ~/.mrk/login-items-ignore" "$W/drift" --add SkipMe
refuse_case "--add a login item not an app"  "is not an app"              "$W/drift" --add Startup
refuse_case "--add a name not a login item"  "does not list Nobody"       "$W/drift" --add Nobody

# ── 7. --ignore ──────────────────────────────────────────────────────────────

slx "$W/drift" --ignore "Zéphyr"
if [[ $RC == 0 && $GUMS == 0 ]] && [[ "$(tail -1 "$W/home/.mrk/login-items-ignore")" == "Zéphyr" ]] \
   && [[ "$(head -3 "$W/home/.mrk/login-items-ignore")" == "$(cat "$W/ignore.orig")" ]] && unchanged; then
  pass "--ignore NAME: appended to the ignore list, which keeps its lines; the list and the manual unchanged"
else
  fail "--ignore NAME (exit $RC)"; why
fi
slx "$W/drift" --ignore "Zéphyr"
if [[ $RC == 0 ]] && grep -q 'already in' "$W/err" && [[ "$(grep -c '^Zéphyr$' "$W/home/.mrk/login-items-ignore")" == 1 ]]; then
  pass "--ignore NAME again: done, not refused, and not written twice"
else
  fail "--ignore NAME again (exit $RC)"; why
fi
cp -p "$W/ignore.orig" "$W/home/.mrk/login-items-ignore"
refuse_case "--ignore a tracked app"         "already tracks"             "$W/drift" --ignore "$TRACKED"
refuse_case "--ignore a name not a login item" "does not list Nobody"     "$W/drift" --ignore Nobody

# ── 8. --remove ──────────────────────────────────────────────────────────────

for who in "$STALE" "$CONFLICT"; do
  slx "$W/drift" --remove "$who"
  gone=$(grep -n "/$who\.app$" "$R/$LIST")
  if [[ $RC == 0 && $GUMS == 0 && -z "$gone" ]] \
     && [[ "$(grep -vc '^#' "$R/$LIST")" == $(( ${#entries[@]} - 1 )) ]] \
     && cmp -s "$R/docs/manual.md" "$W/manual.orig"; then
    pass "--remove $([[ $who == "$STALE" ]] && echo 'a stale app' || echo 'an ignored app'): its line deleted, and nothing else written"
  else
    fail "--remove $who (exit $RC)"; why
  fi
  reset_copy; cp -p "$W/ignore.orig" "$W/home/.mrk/login-items-ignore"
done
refuse_case "--remove an app still at login"  "is a login item on this Mac" "$W/drift" --remove "$TRACKED"
refuse_case "--remove an app not tracked"     "does not track Nobody"       "$W/drift" --remove Nobody
refuse_case "--remove, System Events empty"   "returned no login items"     "$W/empty" --remove "$STALE"
refuse_case "--remove, System Events failing" "osascript exited 1"          FAIL       --remove "$STALE"

# ── 9. -c commits the decision ───────────────────────────────────────────────

# Under the scratch HOME, with no system config: none of this Mac's git
# settings (signing, hooks) reach the throwaway repository.
export GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
HOME="$W/home" git -C "$R" init -q
HOME="$W/home" git -C "$R" add -A
HOME="$W/home" git -C "$R" commit -qm base
slx "$W/drift" --remove "$STALE" -c
if [[ $RC == 0 && "$(git -C "$R" log -1 --format=%s)" == "login-items: remove $STALE" ]] \
   && [[ "$(git -C "$R" show --name-only --format= HEAD)" == "$LIST" ]] \
   && [[ -z "$(git -C "$R" status --porcelain)" ]]; then
  pass "--remove NAME -c: one commit, of the list alone"
else
  fail "--remove NAME -c (exit $RC): $(git -C "$R" log -1 --format=%s) / $(git -C "$R" show --name-only --format= HEAD | tr '\n' ' ')"; why
fi
rm -rf "$R/.git"; reset_copy; cp -p "$W/ignore.orig" "$W/home/.mrk/login-items-ignore"

# ── 10. Bad command lines, and a bad list ────────────────────────────────────

for args in "--add" "--add Zed --remove Foo" "--remove -n" "--manual" "--frob" "--check --frob"; do
  # shellcheck disable=SC2086  # each case is several words
  slx "$W/drift" $args
  if [[ $RC == 2 ]] && unchanged; then
    pass "sync-login-items $args: exit 2, nothing written"
  else
    fail "sync-login-items $args (exit $RC)"; why
  fi
done

printf 'Applications/NoSlash.app\n' >> "$R/$LIST"
cp -p "$R/$LIST" "$W/list.bad"
slx "$W/drift" --check
if [[ $RC == 1 && ! -s "$W/out" ]] && grep -qF 'Not an app path: Applications/NoSlash.app' "$W/err" \
   && cmp -s "$R/$LIST" "$W/list.bad"; then
  pass "a line in the list that is not an app path: named, exit 1, nothing written"
else
  fail "a bad line in the list (exit $RC)"; why
fi
reset_copy

# ── 11. The manual is not read ───────────────────────────────────────────────
#
# A manual with no login-items sentence, or no manual at all, changes nothing:
# each run, -c included, reads and writes the list and the ignore file only.

grep -v '^- \*\*Login items:\*\*' "$W/manual.orig" > "$R/docs/manual.md"
cp -p "$R/docs/manual.md" "$W/manual.none"
slx "$BASE"
if [[ $RC == 0 ]] && grep -q 'Login items are up to date' "$W/err" \
   && cmp -s "$R/docs/manual.md" "$W/manual.none" && cmp -s "$R/$LIST" "$W/list.orig"; then
  pass "a manual with no login-items sentence: exit 0, and nothing written"
else
  fail "a manual with no login-items sentence (exit $RC)"; why
fi
rm -f "$R/docs/manual.md"
mkdir -p "$W/home/.mrk"; cp -p "$W/ignore.orig" "$W/home/.mrk/login-items-ignore"
slx "$W/drift" --add "Zéphyr"
if [[ $RC == 0 && ! -e "$R/docs/manual.md" ]] && mrk_config_entries "$R/$LIST" | grep -qxF '/Applications/Zéphyr.app'; then
  pass "no manual at all: --add NAME still writes the list, and creates no manual"
else
  fail "--add NAME with no manual (exit $RC)"; why
fi
reset_copy

(( fails == 0 ))
