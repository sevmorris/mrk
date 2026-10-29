#!/usr/bin/env bash
# dock-setup.sh — hold make dock to what it says it builds. Audit 15, T-14.
#
# Until 2026-09-28 the app list was an older layout, not the Dock in use, and
# dock-setup added /Applications as a grid where the Dock in use has the Work
# Apps folder as a list. make dock would have replaced the live Dock with it,
# without asking. The list now is that Dock, in config/dock.txt, and the Work
# Apps folder is its last line, added only when it exists.
#
# dock-setup empties the Dock before it adds anything, so a list it cannot use
# (no file, no app in it, a line that is not a path) must stop it before the
# first dockutil call. --dry-run must call nothing at all. --check, which shows
# each item as a line for a program to read, must call only dockutil --list:
# it says whether each item is in the Dock now, and names each item in the
# Dock that the list does not have, which make dock would delete. On
# 2026-10-22 the Dock held Signal, which the list did not, and --check could
# not see it. Safari is in the Dock by its cryptex path, which
# /Applications/Safari.app is a symlink to, and must still match.
#
# dock-setup runs from a copy of the repository under a throwaway HOME, with
# `env -i` and PATH cut to stubs and the system directories. dockutil,
# defaults, killall and brew are stubs that record their arguments, so nothing
# reaches the real Dock. dockutil --list shows $SANDBOX/dock-list, in
# dockutil's own form, and fails when there is no such file. The /Applications paths in the copy of config/dock.txt
# point into the sandbox. Each case runs under /bin/bash and under the bash
# running this file. ci-check runs it.

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
R="$W/repo"; H="$W/home"; S="$W/stubs"; APPS="$W/Applications"
mkdir -p "$R" "$S" "$W/tmp" "$APPS"

# ── The repository copy ──────────────────────────────────────────────────────

while IFS= read -r -d '' f; do
  [[ -f "$REPO_ROOT/$f" ]] || continue
  mkdir -p "$R/$(dirname "$f")"
  cp -p "$REPO_ROOT/$f" "$R/$f"
done < <(git -C "$REPO_ROOT" ls-files -z scripts config)
LIST="$R/config/dock.txt"
sed "s#/Applications/#$APPS/#g" "$LIST" > "$W/rewrite" && cat "$W/rewrite" > "$LIST"
if grep -n '/Applications/' "$LIST" | grep -vF "$APPS/"; then
  fail "a real /Applications path survived the rewrite — refusing to run"
  exit 1
fi
cp -p "$LIST" "$W/dock.orig"

# The apps in the copy's list, one path per line, in order. Its one folder is
# ~/Work Apps, the last line; the cases below hold it to that.
DOCK_APPS=()
while IFS= read -r app; do DOCK_APPS+=("$app"); done < <(mrk_config_entries "$LIST" | grep '\.app$')
(( ${#DOCK_APPS[@]} >= 3 )) || { fail "read ${#DOCK_APPS[@]} apps from config/dock.txt; expected more"; exit 1; }
# shellcheck disable=SC2088  # the literal line, as the file holds it
if [[ "$(mrk_config_entries "$LIST" | grep -v '\.app$')" == "~/Work Apps" ]]; then
  pass "config/dock.txt: ${#DOCK_APPS[@]} apps, then ~/Work Apps"
else
  fail "config/dock.txt: expected one folder, ~/Work Apps; found: $(mrk_config_entries "$LIST" | grep -v '\.app$' | tr '\n' ' ')"
fi

# ── Stubs ────────────────────────────────────────────────────────────────────

# Each writes its name and its arguments, quoted, one line per call.
cat > "$S/record" <<'EOF'
#!/bin/bash
{ printf '%s' "${0##*/}"; printf ' %q' "$@"; printf '\n'; } >> "$SANDBOX/calls"
EOF
for cmd in killall brew; do cp "$S/record" "$S/$cmd"; done
cat > "$S/dockutil" <<'EOF'
#!/bin/bash
{ printf 'dockutil'; printf ' %q' "$@"; printf '\n'; } >> "$SANDBOX/calls"
if [[ "${1:-}" == --list ]]; then
  [[ -f "$SANDBOX/dock-list" ]] || exit 1
  cat "$SANDBOX/dock-list"
fi
exit 0
EOF
cat > "$S/defaults" <<'EOF'
#!/bin/bash
{ printf 'defaults'; printf ' %q' "$@"; printf '\n'; } >> "$SANDBOX/calls"
[[ "${1:-}" == export ]] && printf '<plist version="1.0"><dict/></plist>\n' > "$3"
exit 0
EOF
chmod +x "$S"/*
ln -s "$BASH_UNDER_TEST" "$S/bash"

ENV=(HOME="$H" USER="${USER:-$(id -un)}" TMPDIR="$W/tmp" TERM=dumb
     PATH="$S:/usr/bin:/bin:/usr/sbin:/sbin" SANDBOX="$W")
for cmd in defaults dockutil killall; do
  if [[ "$(env -i "${ENV[@]}" "$S/bash" -c "command -v $cmd")" != "$S/$cmd" ]]; then
    fail "the $cmd stub is not first on PATH — refusing to run against the real one"
    exit 1
  fi
done

# call ARGS... — one recorded dockutil line, as the stub writes it
call() { printf 'dockutil'; printf ' %q' "$@"; printf '\n'; }
run() {
  : > "$W/calls"
  env -i "${ENV[@]}" "$S/bash" "$R/scripts/dock-setup" "$@" </dev/null > "$W/out" 2>&1
  RC=$?
}
show() { sed 's/^/      /' "$W/out" | tail -"${1:-12}" >&2; }

# ── Every app installed, and the folder there ────────────────────────────────

rm -rf "$H"; mkdir -p "$H/Work Apps"
for app in "${DOCK_APPS[@]}"; do mkdir -p "$app"; done
run
want="$(call --remove all --no-restart)"$'\n'
for app in "${DOCK_APPS[@]}"; do want+="$(call --add "$app" --no-restart)"$'\n'; done
want+="$(call --add "$H/Work Apps" --view list --display stack --sort name --no-restart)"
got="$(grep '^dockutil ' "$W/calls")"
if [[ $RC == 0 && "$got" == "$want" ]] && grep -qx 'killall Dock' "$W/calls" \
   && grep -q "^defaults import com.apple.dock " "$H/.mrk/defaults-rollback.sh" 2>/dev/null; then
  pass "all ${#DOCK_APPS[@]} apps added in order, then Work Apps as a list; the old Dock saved for the undo"
else
  fail "every app installed (exit $RC): dockutil calls differ, or no killall or undo line"
  diff <(printf '%s\n' "$want") <(printf '%s\n' "$got") | sed 's/^/      /' >&2
  show
fi

# ── One app missing, and no folder ───────────────────────────────────────────

rm -rf "$H"; mkdir -p "$H"
gone="${DOCK_APPS[1]}"
rm -rf "$gone"
run
name="$(basename "$gone" .app)"
if [[ $RC == 0 ]] && grep -qF "Skipped: $name (not installed)" "$W/out" \
   && grep -qF "Skipped: Work Apps folder (no $H/Work Apps)" "$W/out" \
   && ! grep -qF -- "--add $(printf '%q' "$gone")" "$W/calls" \
   && ! grep -q 'Work' "$W/calls" \
   && [[ "$(grep -c '^dockutil --add ' "$W/calls")" == $(( ${#DOCK_APPS[@]} - 1 )) ]]; then
  pass "a missing app and a missing folder are each skipped, and said so; the rest still added"
else
  fail "one app missing, no folder (exit $RC)"
  show; sed 's/^/      /' "$W/calls" >&2
fi

# ── --dry-run: the same list, and nothing called ─────────────────────────────

rm -rf "$H"; mkdir -p "$H/Work Apps"
for app in "${DOCK_APPS[@]}"; do mkdir -p "$app"; done
rm -rf "$gone"
run --dry-run
would=$(grep -c 'Would add: ' "$W/out")
if [[ $RC == 0 && ! -s "$W/calls" && ! -e "$H/.mrk" ]] \
   && [[ "$would" == "${#DOCK_APPS[@]}" ]] \
   && grep -qF "Skipped: $name (not installed)" "$W/out" \
   && grep -qF "Would add: Work Apps folder, as a list" "$W/out"; then
  pass "--dry-run: names each app and the folder it would add, and the one it would skip; calls nothing, saves nothing"
else
  fail "--dry-run (exit $RC)"
  show; sed 's/^/      /' "$W/calls" >&2
fi

# ── --check: each item as a line for a program, and nothing called ───────────

# run_check ARGS... — dock-setup with stdout and stderr apart
run_check() {
  : > "$W/calls"
  env -i "${ENV[@]}" "$S/bash" "$R/scripts/dock-setup" "$@" </dev/null > "$W/stdout" 2> "$W/stderr"
  RC=$?
}
TAB=$'\t'
PLIST="$H/Library/Preferences/com.apple.dock.plist"
# dock_item LABEL PATH SECTION — one line of dockutil --list for PATH: its URL
# percent encoded and ending in /, as dockutil shows a file in the Dock
dock_item() {
  printf '%s\t%s\t%s\t%s\t\n' "$1" \
    "$(python3 -c 'import sys, urllib.parse; print("file://" + urllib.parse.quote(sys.argv[1]) + "/")' "$2")" \
    "$3" "$PLIST"
}
# The folder's name holds a backslash and a tab, which the line must escape.
odd="$H/Odd\\name${TAB}here"
rm -rf "$H"; mkdir -p "$H/Work Apps" "$odd"
for app in "${DOCK_APPS[@]}"; do mkdir -p "$app"; done
rm -rf "$gone"
# Safari as macOS has it: the app in a cryptex, and a symlink to it.
safari="$APPS/Safari.app"
crypt_safari="$W/Preboot/Cryptexes/App/System/Applications/Safari.app"
rm -rf "$safari"; mkdir -p "$crypt_safari"; ln -s "$crypt_safari" "$safari"
undocked="${DOCK_APPS[2]}"
if [[ "$undocked" == "$safari" || "$undocked" == "$gone" ]] || ! printf '%s\n' "${DOCK_APPS[@]}" | grep -qxF "$safari"; then
  fail "the list's apps are not as this test needs them: Safari, and a third app that is neither Safari nor the second"
  exit 1
fi
signal="$APPS/Signal Desktop.app"; mkdir -p "$signal"
ghost="$W/Gone Café.app"
# shellcheck disable=SC2088  # the literal line, as the file holds it
printf '~/Odd\\name\there\n' >> "$LIST"

# The Dock: each app of the list but one, the missing app among them, Safari
# by its cryptex path, Work Apps, and two apps the list does not have, one of
# them no longer installed. Then three items --check does not show: a spacer,
# a web link and a recent app.
{
  for app in "${DOCK_APPS[@]}"; do
    case "$app" in
      "$undocked") ;;
      "$safari") dock_item Safari "$crypt_safari" persistentApps ;;
      *) dock_item "$(basename "$app" .app)" "$app" persistentApps ;;
    esac
  done
  dock_item Signal "$signal" persistentApps
  printf '\t\tpersistentApps\t%s\t\n' "$PLIST"
  dock_item Gone "$ghost" persistentApps
  dock_item "Work Apps" "$H/Work Apps" persistentOthers
  printf 'Docs\thttps://example.com/docs/\tpersistentOthers\t%s\t\n' "$PLIST"
  dock_item Notes "$APPS/Notes.app" recentApps
} > "$W/dock-list"

# want_lines [DOCK] — the lines --check shows: with no DOCK, for the Dock
# above; with one, every item of the list with DOCK as its Dock state
want_lines() {
  local app state docked
  for app in "${DOCK_APPS[@]}"; do
    state=present; [[ "$app" == "$gone" ]] && state=missing
    docked=${1:-docked}; [[ -z "${1:-}" && "$app" == "$undocked" ]] && docked=undocked
    printf 'app\t%s\t%s\t%s\t%s\n' "$app" "$app" "$state" "$docked"
  done
  printf 'folder\t~/Work Apps\t%s\tpresent\t%s\n' "$H/Work Apps" "${1:-docked}"
  printf 'folder\t~/Odd\\\\name\\there\t%s\tpresent\t%s\n' "$H/Odd\\\\name\\there" "${1:-undocked}"
  if [[ -z "${1:-}" ]]; then
    printf 'unlisted\t\t%s\tpresent\tdocked\n' "$signal"
    printf 'unlisted\t\t%s\tmissing\tdocked\n' "$ghost"
  fi
}
want=$(want_lines)
run_check --check
if [[ $RC == 0 && "$(cat "$W/stdout")" == "$want" && "$(cat "$W/calls")" == "dockutil --list" && ! -e "$H/.mrk" ]]; then
  pass "--check: app or folder, the line, the path, present or missing, and docked or undocked, then each unlisted item; calls only dockutil --list"
else
  fail "--check (exit $RC)"
  diff <(printf '%s\n' "$want") "$W/stdout" | sed 's/^/      /' >&2
  sed 's/^/      /' "$W/stderr" "$W/calls" >&2
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
on_tty "$W/stdout.tty" env -i "${ENV[@]}" "$S/bash" "$R/scripts/dock-setup" --check
if same_on_tty "$W/stdout.tty" "$want"; then
  pass "--check with stderr on a terminal: the same lines, and no colour on stdout"
else
  fail "--check with stderr on a terminal"; diff <(printf '%s\n' "$want") "$W/stdout.tty" | sed 's/^/      /' >&2
fi
if [[ "$(grep -F "$safari" "$W/stdout")" == "app$TAB$safari$TAB$safari${TAB}present${TAB}docked" ]] \
   && grep -qxF "unlisted$TAB$TAB$signal${TAB}present${TAB}docked" "$W/stdout"; then
  pass "--check: Safari in the Dock by its cryptex path is docked, and Signal, not in the list, is unlisted"
else
  fail "--check: Safari or Signal: $(grep -E 'Safari|Signal' "$W/stdout" | tr '\n' ' ')"
fi
run_check --dry-run --check
if [[ $RC == 0 && "$(cat "$W/stdout")" == "$want" && "$(cat "$W/calls")" == "dockutil --list" ]]; then
  pass "--check takes precedence over --dry-run"
else
  fail "--dry-run --check (exit $RC)"; sed 's/^/      /' "$W/stdout" "$W/stderr" >&2
fi

# No Dock to read: each item unknown, no unlisted line, and still exit 0.
mv "$W/dock-list" "$W/dock-list.saved"
run_check --check
if [[ $RC == 0 && "$(cat "$W/stdout")" == "$(want_lines unknown)" ]] && grep -q 'dockutil --list failed' "$W/stderr"; then
  pass "--check when dockutil --list fails: each item unknown, no unlisted line, exit 0"
else
  fail "--check with dockutil --list failing (exit $RC)"
  diff <(want_lines unknown) "$W/stdout" | sed 's/^/      /' >&2; sed 's/^/      /' "$W/stderr" >&2
fi
mv "$W/dock-list.saved" "$W/dock-list"
mv "$S/dockutil" "$W/dockutil.saved"
run_check --check
if [[ $RC == 0 && "$(cat "$W/stdout")" == "$(want_lines unknown)" && ! -s "$W/calls" ]] && grep -q 'dockutil not found' "$W/stderr"; then
  pass "--check with no dockutil: each item unknown, nothing called, exit 0"
else
  fail "--check with no dockutil (exit $RC)"
  diff <(want_lines unknown) "$W/stdout" | sed 's/^/      /' >&2; sed 's/^/      /' "$W/stderr" >&2
fi
mv "$W/dockutil.saved" "$S/dockutil"
cp -p "$W/dock.orig" "$LIST"
printf 'Applications/Safari.app\n' >> "$LIST"
run_check --check
if [[ $RC == 1 && ! -s "$W/stdout" && ! -s "$W/calls" ]] && grep -q 'Not a path' "$W/stderr"; then
  pass "--check on a list dock-setup refuses: exit 1, the reason on stderr, no line"
else
  fail "--check on a bad list (exit $RC)"; sed 's/^/      /' "$W/stdout" "$W/stderr" >&2
fi
cp -p "$W/dock.orig" "$LIST"
run_check --check --bogus
if [[ $RC == 2 && ! -s "$W/stdout" && ! -s "$W/calls" ]]; then
  pass "--check with an unknown option: exit 2"
else
  fail "--check --bogus (exit $RC)"; sed 's/^/      /' "$W/stdout" "$W/stderr" >&2
fi

# ── A list dock-setup cannot use stops it before the Dock is touched ─────────

# bad_list LABEL — dock-setup must exit 1 with no call at all
bad_list() {
  run
  if [[ $RC == 1 && ! -s "$W/calls" ]] && grep -q 'the Dock is unchanged' "$W/out"; then
    pass "$1: exit 1 before any call, so the Dock is unchanged"
  else
    fail "$1 (exit $RC)"
    show; sed 's/^/      /' "$W/calls" >&2
  fi
  cp -p "$W/dock.orig" "$LIST"
}
rm -f "$LIST";                                     bad_list "no config/dock.txt"
grep '^#' "$W/dock.orig" > "$LIST";                bad_list "a config/dock.txt with no app"
printf 'Applications/Safari.app\n' >> "$LIST";     bad_list "a line in config/dock.txt that is not a path"
# CRLF line ends made every app a folder that did not exist, which a run
# skipped, until 2026-10-28 (audit 22, Z-6).
printf '/Applications/Safari.app\r\n' >> "$LIST";  bad_list "a line in config/dock.txt that ends in a carriage return"

(( fails == 0 ))
