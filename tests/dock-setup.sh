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
# first dockutil call. --dry-run must call nothing at all.
#
# dock-setup runs from a copy of the repository under a throwaway HOME, with
# `env -i` and PATH cut to stubs and the system directories. dockutil,
# defaults, killall and brew are stubs that record their arguments, so nothing
# reaches the real Dock. The /Applications paths in the copy of config/dock.txt
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
for cmd in dockutil killall brew; do cp "$S/record" "$S/$cmd"; done
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

(( fails == 0 ))
