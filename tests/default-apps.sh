#!/usr/bin/env bash
# default-apps.sh — hold default-apps to what it says it reads and changes.
#
# default-apps keeps the app that opens each type to config/default-apps.tsv.
# --check must show each type of the list as a line with the four fields and
# five states of the contract. The report, --check and --apply -n must change
# nothing, and --apply must change nothing when NONINTERACTIVE=1. --apply must
# ask for each type that another app opens, or no app opens, with one call for
# each app, in the order of the list: macOS shows one dialog for each type, and
# stacked dialogs moved their buttons under the pointer. A type kept for the
# other app in the dialog is not a failure; an error is. --snapshot must take
# from Launch Services each type chosen by hand and each of the http, https and
# mailto schemes, and no other scheme, no com.apple.default-app.* entry and no
# app that is not on the Mac. It must change only the app of a listed type and
# add a new type at the end, and leave each comment as it is. A list it cannot
# use (a carriage return, a type listed twice, a line that is not a type and an
# app) must stop it with exit 1, and a bad command line with exit 2.
#
# default-apps runs from a copy of the repository under a throwaway HOME, with
# `env -i` and PATH cut to the system directories. MRK_LSDEFAULT is a stub of
# the lsdefault helper that reads and writes files in the sandbox, so nothing
# reaches this Mac's Launch Services. MRK_LS_PLIST is a scratch copy of Launch
# Services' list of choices. Last, the real helper is built from its source
# into the scratch HOME, when swiftc is there, and must answer for a type that
# no app declares and an app that is not installed. Each case runs under
# /bin/bash and under the bash running this file. ci-check runs it.

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

W=$(mrk_mktemp_d) || exit 1
W=$(cd "$W" && pwd -P)
trap 'rm -rf "$W"' EXIT
R="$W/repo"; H="$W/home"; SB="$W/sandbox"
mkdir -p "$R/scripts" "$R/config" "$R/assets/default-apps" "$H" "$SB" "$W/tmp"
cp -p "$REPO_ROOT/scripts/default-apps" "$REPO_ROOT/scripts/lib.sh" "$R/scripts/"
cp -p "$REPO_ROOT/assets/default-apps/lsdefault.swift" "$R/assets/default-apps/"
LIST="$R/config/default-apps.tsv"

# The real list must be one default-apps accepts, and is replaced below by one
# that holds each state.
cp -p "$REPO_ROOT/config/default-apps.tsv" "$LIST"

# ── The stub of lsdefault ────────────────────────────────────────────────────
#
# handlers: "type<TAB>app" for each type an app opens. unknown: a type no app
# declares, one a line. installed: the bundle identifier of each app on the
# Mac. decline: a type whose dialog is answered "keep". fail: a type whose
# change fails. calls: each call of set, as its arguments.
STUB="$W/lsdefault"
cat > "$STUB" <<'EOF'
#!/bin/bash
SB="${STUB_SANDBOX:?}"
cmd=$1; shift
case "$cmd" in
  get)
    for t in "$@"; do
      if grep -qxF "$t" "$SB/unknown" 2>/dev/null; then printf '%s\tunknown\t\n' "$t"; continue; fi
      a=$(awk -F'\t' -v t="$t" '$1 == t { print $2 }' "$SB/handlers" 2>/dev/null)
      if [[ -n "$a" ]]; then printf '%s\tapp\t%s\n' "$t" "$a"; else printf '%s\tnone\t\n' "$t"; fi
    done ;;
  app)
    for a in "$@"; do
      if grep -qxF "$a" "$SB/installed" 2>/dev/null; then printf '%s\t/Applications/%s.app\n' "$a" "$a"; else printf '%s\t\n' "$a"; fi
    done ;;
  set)
    app=$1; shift
    printf '%s\n' "$app $*" >> "$SB/calls"
    for t in "$@"; do
      printf '%s\tasking\n' "$t"
      if grep -qxF "$t" "$SB/decline" 2>/dev/null; then printf '%s\tdeclined The file couldn’t be opened.\n' "$t"
      elif grep -qxF "$t" "$SB/fail" 2>/dev/null; then printf '%s\terror no answer in two minutes\n' "$t"
      else
        grep -v "^$t	" "$SB/handlers" > "$SB/h.tmp" 2>/dev/null; mv "$SB/h.tmp" "$SB/handlers"
        printf '%s\t%s\n' "$t" "$app" >> "$SB/handlers"
        printf '%s\tset\n' "$t"
      fi
    done ;;
  *) exit 2 ;;
esac
EOF
chmod +x "$STUB"

# run [VAR=VALUE...] -- ARGS: default-apps with a clean environment. Its stdout
# goes to $W/out, stderr to $W/err, and its exit status to RC.
run() {
  local envs=()
  while [[ "$1" != -- ]]; do envs+=("$1"); shift; done
  shift
  env -i HOME="$H" PATH="/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$W/tmp" \
      MRK_LSDEFAULT="$STUB" STUB_SANDBOX="$SB" MRK_LS_PLIST="$SB/ls.plist" \
      ${envs[@]+"${envs[@]}"} \
      "$BASH_UNDER_TEST" "$R/scripts/default-apps" "$@" > "$W/out" 2> "$W/err"
  RC=$?
}

reset_sandbox() {
  rm -f "$SB"/*
  printf '%s\t%s\n' \
    public.mp3 com.example.opener \
    public.mpeg-4 com.example.tagger \
    scheme:https com.example.browser > "$SB/handlers"
  printf '%s\n' com.example.opener com.example.browser com.example.tagger > "$SB/installed"
  printf '%s\n' org.example.nosuch > "$SB/unknown"
  : > "$SB/calls"
}

write_list() {
  cat > "$LIST" <<'EOF'
# A comment, kept by --snapshot.
scheme:https	com.example.browser

# Audio
public.mp3	com.example.opener
public.aiff-audio	com.example.opener
public.mpeg-4	com.example.opener
public.avi	com.example.player
org.example.nosuch	com.example.opener
public.mp2	com.example.opener
EOF
}

# ── 1. The real list is one default-apps accepts ─────────────────────────────

reset_sandbox
run -- --check
if (( RC == 0 )) && [[ -s "$W/out" ]]; then
  pass "--check reads config/default-apps.tsv: $(wc -l < "$W/out" | tr -d ' ') types"
else
  fail "--check on config/default-apps.tsv: exit $RC: $(cat "$W/err")"
fi

# ── 2. --check: each state, in the order of the list ─────────────────────────

write_list
reset_sandbox
printf '%s\n' public.mp2 >> "$SB/fail"
cp -p "$LIST" "$W/list.orig"
run -- --check
expected=$(printf '%s\t%s\t%s\t%s\n' \
  scheme:https com.example.browser com.example.browser set \
  public.mp3 com.example.opener com.example.opener set \
  public.aiff-audio com.example.opener "" none \
  public.mpeg-4 com.example.opener com.example.tagger differs \
  public.avi com.example.player "" noapp \
  org.example.nosuch com.example.opener "" unknown \
  public.mp2 com.example.opener "" none)
if (( RC == 0 )) && [[ "$(cat "$W/out")" == "$expected" ]]; then
  pass "--check: one line for each type, with set, none, differs, noapp and unknown"
else
  fail "--check: exit $RC, lines:"$'\n'"$(cat "$W/out")"$'\n'"expected:"$'\n'"$expected"
fi
if "$REPO_ROOT/tests/lib/contract-lines" scripts/default-apps < "$W/out"; then
  pass "--check: its lines obey scripts/mrk-contract"
else
  fail "--check: its lines do not obey scripts/mrk-contract"
fi

# ── 3. The report, --apply -n and NONINTERACTIVE change nothing ──────────────

for case in "report" "--apply -n" "--apply --dry-run" "NONINTERACTIVE"; do
  case "$case" in
    report)         run -- ;;
    NONINTERACTIVE) run NONINTERACTIVE=1 -- --apply ;;
    *)              read -r -a a <<< "$case"; run -- "${a[@]}" ;;
  esac
  if (( RC == 0 )) && [[ ! -s "$SB/calls" ]] && cmp -s "$LIST" "$W/list.orig"; then
    pass "$case: exit 0, no type changed"
  else
    fail "$case: exit $RC, calls: $(cat "$SB/calls"): $(cat "$W/err")"
  fi
done
run -- --apply -n
if grep -q 'Would make com.example.opener open public.mpeg-4 (now: com.example.tagger)' "$W/err" \
   && grep -q 'Would make com.example.opener open public.aiff-audio (now: no app)' "$W/err"; then
  pass "--apply -n names each type it would change, and the app that opens it now"
else
  fail "--apply -n: $(cat "$W/err")"
fi

# ── 4. --apply: one call for each app, the types that differ or have none ────

reset_sandbox
printf '%s\n' public.mp2 > "$SB/fail"
printf '%s\n' public.aiff-audio > "$SB/decline"
run -- --apply
if [[ "$(cat "$SB/calls")" == "com.example.opener public.aiff-audio public.mpeg-4 public.mp2" ]]; then
  pass "--apply: one call for com.example.opener, with its three types in the order of the list"
else
  fail "--apply: calls: $(cat "$SB/calls")"
fi
if (( RC == 1 )) && grep -q 'public.mp2: error no answer' "$W/err" \
   && grep -q 'public.aiff-audio (kept for the other app' "$W/err" \
   && grep -q 'public.avi (com.example.player is not on this Mac)' "$W/err" \
   && grep -q 'org.example.nosuch (no app on this Mac declares this type)' "$W/err"; then
  pass "--apply: exit 1 for an error; a declined type, a missing app and an unknown type are skipped"
else
  fail "--apply: exit $RC: $(cat "$W/err")"
fi
reset_sandbox
printf '%s\n' public.aiff-audio > "$SB/decline"
run -- --apply
if (( RC == 0 )); then
  pass "--apply: exit 0 when the only type left is one kept in the dialog"
else
  fail "--apply with a declined type: exit $RC: $(cat "$W/err")"
fi
run -- --apply
if (( RC == 0 )) && [[ "$(tail -1 "$SB/calls")" == "com.example.opener public.aiff-audio" ]]; then
  pass "--apply again: asks only for the type still kept for the other app"
else
  fail "--apply again: exit $RC, calls: $(cat "$SB/calls")"
fi

# ── 5. --snapshot ────────────────────────────────────────────────────────────

reset_sandbox
write_list
printf '%s\n' com.example.player com.example.mail > "$SB/installed.add"
cat "$SB/installed.add" >> "$SB/installed"
cat > "$SB/ls.json" <<'EOF'
{"LSHandlers": [
  {"LSHandlerContentType": "public.mp3", "LSHandlerRoleAll": "com.example.opener"},
  {"LSHandlerContentType": "public.mpeg-4", "LSHandlerRoleAll": "com.example.player"},
  {"LSHandlerContentType": "public.plain-text", "LSHandlerRoleViewer": "com.example.player"},
  {"LSHandlerContentType": "public.aiff-audio", "LSHandlerRoleAll": "local.gone.app"},
  {"LSHandlerContentType": "com.apple.default-app.web-browser", "LSHandlerRoleAll": "com.example.browser"},
  {"LSHandlerURLScheme": "mailto", "LSHandlerRoleAll": "com.example.mail"},
  {"LSHandlerURLScheme": "slack", "LSHandlerRoleAll": "com.example.player"},
  {"LSHandlerURLScheme": "https", "LSHandlerRoleAll": "Com.Example.Browser"}
]}
EOF
plutil -convert binary1 -o "$SB/ls.plist" "$SB/ls.json"
cp -p "$LIST" "$W/list.orig"
run -- --snapshot -n
if (( RC == 0 )) && cmp -s "$LIST" "$W/list.orig" && grep -q 'Change: public.mpeg-4 → com.example.player' "$W/err"; then
  pass "--snapshot -n: names the changes, and leaves the list as it was"
else
  fail "--snapshot -n: exit $RC: $(cat "$W/err")"
fi
run -- --snapshot
expected=$(cat <<'EOF'
# A comment, kept by --snapshot.
scheme:https	com.example.browser

# Audio
public.mp3	com.example.opener
public.aiff-audio	com.example.opener
public.mpeg-4	com.example.player
public.avi	com.example.player
org.example.nosuch	com.example.opener
public.mp2	com.example.opener
public.plain-text	com.example.player
scheme:mailto	com.example.mail
EOF
)
if (( RC == 0 )) && [[ "$(cat "$LIST")" == "$expected" ]]; then
  pass "--snapshot: changes a listed type, adds a file type and mailto; no other scheme, no default-app entry, no missing app"
else
  fail "--snapshot: exit $RC, list:"$'\n'"$(cat "$LIST")"$'\n'"$(cat "$W/err")"
fi
run -- --snapshot
if (( RC == 0 )) && grep -q 'The list has each type that you chose by hand' "$W/err"; then
  pass "--snapshot again: nothing to change"
else
  fail "--snapshot again: exit $RC: $(cat "$W/err")"
fi

# ── 6. Refusals ──────────────────────────────────────────────────────────────

refuse() { # NAME WANT LINE-OF-LIST... — the list, then default-apps --check
  local name=$1 want=$2; shift 2
  printf '%s\n' "$@" > "$LIST"
  run -- --check
  if (( RC == want )) && [[ ! -s "$W/out" ]]; then
    pass "refuses $name: exit $want, nothing on stdout"
  else
    fail "$name: exit $RC, want $want: $(cat "$W/out") $(cat "$W/err")"
  fi
}
reset_sandbox
refuse "a carriage return" 1 $'public.mp3\tcom.example.opener\r'
refuse "a type listed twice" 1 $'public.mp3\tcom.example.opener' $'public.mp3\tcom.example.player'
refuse "a line with no tab" 1 'public.mp3 com.example.opener'
refuse "a line with two tabs" 1 $'public.mp3\tcom.example.opener\tx'
refuse "an empty list" 1 '# only a comment'
write_list
for args in "--frobnicate" "--check --apply" "--apply --snapshot" "-n" "--check -n"; do
  read -r -a a <<< "$args"
  run -- "${a[@]}"
  if (( RC == 2 )) && [[ ! -s "$W/out" ]]; then
    pass "refuses $args: exit 2"
  else
    fail "$args: exit $RC: $(cat "$W/err")"
  fi
done

# ── 7. The real helper ───────────────────────────────────────────────────────
#
# Built from its source into the scratch HOME, as default-apps builds it. A
# type that no app declares is unknown, and an app that is not installed has
# no path; neither depends on what this Mac has installed.

if command -v swiftc >/dev/null 2>&1; then
  # shellcheck disable=SC2016  # expanded by the inner bash, not this one
  out=$(env HOME="$H" STATE_DIR="$H/.mrk" TMPDIR="$W/tmp" MRK_LSDEFAULT= \
        "$BASH_UNDER_TEST" -c '
          set -e
          src=$1
          sha=$(shasum -a 256 < "$src" | cut -c1-16)
          mkdir -p "$HOME/.mrk/bin"
          swiftc -O -o "$HOME/.mrk/bin/lsdefault-$sha" "$src" 2>&1 >/dev/null
          "$HOME/.mrk/bin/lsdefault-$sha" get org.example.nosuch.type
          "$HOME/.mrk/bin/lsdefault-$sha" app org.example.nosuch.app
        ' _ "$R/assets/default-apps/lsdefault.swift" 2>&1)
  if [[ "$out" == $'org.example.nosuch.type\tunknown\t\norg.example.nosuch.app\t' ]]; then
    pass "lsdefault builds, and answers unknown for an undeclared type and no path for a missing app"
  else
    fail "lsdefault: $out"
  fi
else
  warn "swiftc not found: the real lsdefault is not built"
fi

if (( fails > 0 )); then
  err "$fails failure(s)"
  exit 1
fi
ok "default-apps: all checks passed"
