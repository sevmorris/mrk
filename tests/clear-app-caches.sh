#!/usr/bin/env bash
# clear-app-caches.sh — hold clear-app-caches to what it clears and what it
# leaves. Audit 18.
#
# Until 2026-09-28 it also cleared Helium's GPU caches, daily and at login.
# Those hold compiled Metal pipelines, and each came back to 548 KB within an
# hour while Helium recompiled them. It now clears the browsers' HTTP and code
# caches and leaves their GPU caches alone, as it always did for Chrome.
#
# clear-app-caches runs from the repository under a throwaway HOME holding a
# copy of each folder it clears, each GPU cache it must leave, and profile data
# it must never touch. It only ever deletes under $HOME, so the scratch HOME
# keeps it to itself. Each case runs under /bin/bash and under the bash running
# this file. ci-check runs it.

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
H="$W/home"
SCRIPT="$REPO_ROOT/bin/clear-app-caches"

LC="Library/Caches"
AS="Library/Application Support"
# Folders clear-app-caches must remove
GONE=(
  "$LC/net.imput.helium/Default/Cache"
  "$LC/net.imput.helium/Default/Code Cache"
  "$LC/Google/Chrome/Default/Cache"
  "$LC/Google/Chrome/Profile 1/Cache"
  "$LC/Google/Chrome/Profile 1/Code Cache"
  "$AS/Slack/Cache"
  "$AS/Slack/Code Cache"
  "$AS/Slack/Service Worker/CacheStorage"
  "$LC/com.tinyspeck.slackmacgap"
)
# GPU caches it must leave
GPU=(
  "$AS/net.imput.helium/Default/GPUCache"
  "$AS/net.imput.helium/Default/DawnGraphiteCache"
  "$AS/net.imput.helium/Default/DawnWebGPUCache"
  "$AS/net.imput.helium/Profile 1/GPUCache"
  "$AS/net.imput.helium/GraphiteDawnCache"
  "$AS/Google/Chrome/Profile 1/GPUCache"
)
# Profile data, which is never a cache
KEPT=(
  "$AS/net.imput.helium/Default/History"
  "$AS/Google/Chrome/Profile 1/Bookmarks"
  "$AS/Slack/storage"
)

fill_home() {
  rm -rf "$H"
  local d
  for d in "${GONE[@]}" "${GPU[@]}" "${KEPT[@]}"; do
    mkdir -p "$H/$d" && echo x > "$H/$d/data"
  done
}
# present LIST... — the names in LIST that still hold their data
present() {
  local d out=""
  for d in "$@"; do [[ -f "$H/$d/data" ]] && out="$out [$d]"; done
  printf '%s' "$out"
}
run() {
  env -i HOME="$1" PATH=/usr/bin:/bin "$BASH_UNDER_TEST" "$SCRIPT" "${@:2}" > "$W/out" 2>&1
  RC=$?
}

# ── A run ────────────────────────────────────────────────────────────────────

fill_home
run "$H"
left="$(present "${GONE[@]}")"
if [[ $RC == 0 && -z "$left" ]]; then
  pass "every HTTP, code and Slack cache is cleared (${#GONE[@]} folders)"
else
  fail "a run (exit $RC) left:$left"
fi
lost="$(present "${GPU[@]}")"
if [[ "$lost" == "$(for d in "${GPU[@]}"; do printf ' [%s]' "$d"; done)" ]]; then
  pass "Helium's and Chrome's GPU caches are left alone (${#GPU[@]} folders)"
else
  fail "GPU caches still there:${lost:- none}"
fi
if [[ -z "$(for d in "${KEPT[@]}"; do [[ -f "$H/$d/data" ]] || printf x; done)" ]]; then
  pass "profile data is untouched"
else
  fail "profile data removed; left:$(present "${KEPT[@]}")"
fi

# ── Refusals ─────────────────────────────────────────────────────────────────

fill_home
run "$H" --help
help_rc=$RC
run "$H" --wat
bad_rc=$RC
run "$W/no-such-home"
nohome_rc=$RC
if [[ $help_rc == 0 && $bad_rc == 2 && $nohome_rc == 1 && -z "$(for d in "${GONE[@]}"; do [[ -f "$H/$d/data" ]] || printf x; done)" ]]; then
  pass "--help, an unknown argument and a missing HOME remove nothing (exit 0, 2, 1)"
else
  fail "--help $help_rc, unknown argument $bad_rc, missing HOME $nohome_rc; caches left:$(present "${GONE[@]}")"
fi

(( fails == 0 ))
