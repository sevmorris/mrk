#!/usr/bin/env bash
# dock-setup.sh — hold make dock to what it says it builds. Audit 15, T-14.
#
# Until 2026-09-28 DOCK_APPS was an older layout, not the Dock in use, and
# dock-setup added /Applications as a grid where the Dock in use has the Work
# Apps folder as a list. make dock would have replaced the live Dock with it,
# without asking. The list now is that Dock, and the folder is DOCK_FOLDER,
# added only when it exists.
#
# dock-setup runs from a copy of the repository under a throwaway HOME, with
# `env -i` and PATH cut to stubs and the system directories. dockutil,
# defaults, killall and brew are stubs that record their arguments, so nothing
# reaches the real Dock. The /Applications paths in the copy point into the
# sandbox. Each case runs under /bin/bash and under the bash running this file.
# ci-check runs it.

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
done < <(git -C "$REPO_ROOT" ls-files -z scripts)
sed "s#/Applications/#$APPS/#g" "$R/scripts/dock-setup" > "$W/rewrite" && cat "$W/rewrite" > "$R/scripts/dock-setup"
if grep -n '"/Applications/' "$R/scripts/dock-setup"; then
  fail "a real /Applications path survived the rewrite — refusing to run"
  exit 1
fi

# DOCK_APPS as the copy spells it, one path per line
DOCK_APPS=()
while IFS= read -r app; do DOCK_APPS+=("$app"); done < <(
  sed -n '/^DOCK_APPS=(/,/^)/p' "$R/scripts/dock-setup" | sed -nE 's/^[[:space:]]*"([^"]+)".*/\1/p')
(( ${#DOCK_APPS[@]} >= 3 )) || { fail "read ${#DOCK_APPS[@]} DOCK_APPS entries; expected more"; exit 1; }

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
  env -i "${ENV[@]}" "$S/bash" "$R/scripts/dock-setup" </dev/null > "$W/out" 2>&1
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

(( fails == 0 ))
