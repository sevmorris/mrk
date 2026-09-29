#!/usr/bin/env bash
# install-apps.sh — hold install-apps to what it counts as a failure. Audit 11,
# R-2.
#
# Until 2026-09-28 every unauthenticated fetch that failed counted. Magic Backup
# Machine's repo is private, so on a new Mac, where gh is not yet logged in, the
# GitHub API answered 404, post-install exited 1, and `make all` stopped before
# build-tools. A 404 is now a skip, with the way to finish. Anything else is
# still a failure: a rate limit (403), no network, a DMG that will not download.
#
# scripts/install-apps is sourced, which defines its functions and runs nothing.
# curl, gh and hdiutil are stubs first on PATH, so no request leaves the machine
# and nothing is mounted. install_github_app runs against app paths in a scratch
# folder, never /Applications. Each case runs under /bin/bash and under the bash
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

# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

W=$(mrk_mktemp_d) || exit 1
W=$(cd "$W" && pwd -P)
trap 'rm -rf "$W"' EXIT
S="$W/stubs"; mkdir -p "$S" "$W/tmp" "$W/Applications"

# curl: CURL_CODE decides the API's answer. `-o FILE` is the DMG download.
cat > "$S/curl" <<'EOF'
#!/bin/bash
printf 'curl %s\n' "$*" >> "$SANDBOX/calls"
out=""; prev=""
for a in "$@"; do [[ "$prev" == -o ]] && out="$a"; prev="$a"; done
if [[ -n "$out" ]]; then echo DMG > "$out"; exit 0; fi
case "$CURL_CODE" in
  000) exit 6 ;;
  200) printf '{"assets":[{"name":"App-1.0.dmg","browser_download_url":"https://example.invalid/App-1.0.dmg"}]}\n200' ;;
  *)   printf '{"message":"Not Found"}\n%s' "$CURL_CODE" ;;
esac
EOF
cat > "$S/gh" <<'EOF'
#!/bin/bash
printf 'gh %s\n' "$*" >> "$SANDBOX/calls"
exit 1
EOF
cat > "$S/hdiutil" <<'EOF'
#!/bin/bash
printf 'hdiutil %s\n' "$*" >> "$SANDBOX/calls"
exit 0
EOF
chmod +x "$S"/*
export PATH="$S:/usr/bin:/bin:/usr/sbin:/sbin" SANDBOX="$W" TMPDIR="$W/tmp"
for cmd in curl gh hdiutil; do
  [[ "$(command -v "$cmd")" == "$S/$cmd" ]] || { fail "the $cmd stub is not first on PATH — refusing to run"; exit 1; }
done

# shellcheck source=../scripts/install-apps
source "$REPO_ROOT/scripts/install-apps"
set +e   # the sourced script sets -e; these cases read return codes

# fetch CODE — fetch_release_dmg with the API answering CODE; sets RC and OUT
fetch() {
  : > "$W/calls"; rm -f "$W/dest"
  OUT=$(CURL_CODE="$1" fetch_release_dmg sevmorris/example "$W/dest" Example 2>&1); RC=$?
}

# ── fetch_release_dmg ────────────────────────────────────────────────────────

fetch 404
if [[ $RC == 3 ]] && grep -q 'gh auth login' <<<"$OUT" && grep -q 'make apps' <<<"$OUT" \
   && ! grep -qi 'warning' <<<"$OUT"; then
  pass "a 404 without gh is a skip (3), and says: gh auth login, then make apps"
else
  fail "404: exit $RC, said: $OUT"
fi
fetch 403
if [[ $RC == 1 ]] && grep -q 'HTTP 403' <<<"$OUT"; then
  pass "a 403 (rate limit) is still a failure"
else
  fail "403: exit $RC, said: $OUT"
fi
fetch 000
if [[ $RC == 1 ]] && grep -q 'HTTP 000' <<<"$OUT"; then
  pass "no network is still a failure"
else
  fail "no network: exit $RC, said: $OUT"
fi
fetch 200
if [[ $RC == 0 && "$(cat "$W/dest" 2>/dev/null)" == DMG ]] && grep -q 'example.invalid/App-1.0.dmg' "$W/calls"; then
  pass "a 200 downloads the release's DMG"
else
  fail "200: exit $RC, dest '$(cat "$W/dest" 2>/dev/null)', said: $OUT"
fi

# ── install_github_app passes the skip up, and cleans up after it ────────────

# shellcheck disable=SC2218  # the sourced install-apps defines it; a stub replaces it further down
OUT=$(CURL_CODE=404 install_github_app "$W/Applications/Example.app" sevmorris/example Example 2>&1); RC=$?
left=$(find "$W/tmp" -mindepth 1 -maxdepth 1 | tr '\n' ' ')
if [[ $RC == 3 ]] && ! grep -q 'failed to download' <<<"$OUT" && [[ -z "$left" ]] \
   && [[ ! -e "$W/Applications/Example.app" ]]; then
  pass "install_github_app returns the skip, warns nothing, and leaves no temporary file"
else
  fail "install_github_app on a 404: exit $RC, left in TMPDIR: '${left}', said: $OUT"
fi
# shellcheck disable=SC2218  # as above
OUT=$(CURL_CODE=403 install_github_app "$W/Applications/Example.app" sevmorris/example Example 2>&1); RC=$?
if [[ $RC == 1 ]] && grep -q 'failed to download' <<<"$OUT"; then
  pass "install_github_app on a 403 fails, as before"
else
  fail "install_github_app on a 403: exit $RC, said: $OUT"
fi

# ── install_companion_apps counts skips apart from failures ──────────────────

install_github_app() {
  case "$2" in
    */ok) return 0 ;; */private) return 3 ;; *) return 1 ;;
  esac
}
# shellcheck disable=SC2034  # read by install_companion_apps, from the sourced script
COMPANION_APPS=("A.app|x/ok|A" "B.app|x/private|B" "C.app|x/broken|C" "D.app|x/private|D")
install_companion_apps
if [[ $COMPANION_FAILED == 1 && $COMPANION_SKIPPED == 2 ]]; then
  pass "install_companion_apps: 1 failed, 2 skipped, and only failures reach post-install's count"
else
  fail "install_companion_apps: failed $COMPANION_FAILED, skipped $COMPANION_SKIPPED (want 1 and 2)"
fi

(( fails == 0 ))
