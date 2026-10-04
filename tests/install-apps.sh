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
# And until 2026-09-28 a copy into /Applications cut short by Ctrl-C was left
# where it stopped: the traps detached the image and removed the temporary
# paths, but only a ditto that failed removed the partial app, and the next
# run's skip test took it for installed. Now the EXIT trap removes it, and
# `make apps` on its own exits on Ctrl-C as post-install does, so the trap runs.
#
# scripts/install-apps is sourced, which defines its functions and runs nothing.
# curl, gh, hdiutil, ditto, codesign and spctl are stubs first on PATH, so no
# request leaves the machine, nothing is mounted and nothing is verified for real. install_github_app runs against app paths in a scratch
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
BASH_UNDER_TEST="$2"

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
# hdiutil: `attach … -mountpoint DIR` puts $STUB_APP.app in DIR.
cat > "$S/hdiutil" <<'EOF'
#!/bin/bash
printf 'hdiutil %s\n' "$*" >> "$SANDBOX/calls"
if [[ "$1" == attach ]]; then
  mp=""; prev=""
  for a in "$@"; do [[ "$prev" == -mountpoint ]] && mp="$a"; prev="$a"; done
  mkdir -p "$mp/${STUB_APP:-Example}.app/Contents" && echo app > "$mp/${STUB_APP:-Example}.app/Contents/Info.plist"
fi
exit 0
EOF
# ditto SRC DEST: DITTO_MODE=ok copies; fail stops part-way; interrupt stops
# part-way and sends SIGINT to the shell that ran it, as Ctrl-C would.
cat > "$S/ditto" <<'EOF'
#!/bin/bash
printf 'ditto %s\n' "$*" >> "$SANDBOX/calls"
case "${DITTO_MODE:-ok}" in
  ok)        /bin/cp -R "$1" "$2" ;;
  fail)      mkdir -p "$2/Contents"; echo partial > "$2/Contents/partial"; exit 1 ;;
  interrupt) mkdir -p "$2/Contents"; echo partial > "$2/Contents/partial"
             kill -INT "$PPID"; sleep 1; exit 130 ;;
esac
EOF
# codesign and spctl pass everything, with the expected team.
cat > "$S/codesign" <<'EOF'
#!/bin/bash
[[ "$1" == -dv ]] && echo "TeamIdentifier=T9RLNAXPWU" >&2
exit 0
EOF
printf '#!/bin/bash\nexit 0\n' > "$S/spctl"
chmod +x "$S"/*
export PATH="$S:/usr/bin:/bin:/usr/sbin:/sbin" SANDBOX="$W" TMPDIR="$W/tmp"
for cmd in curl gh hdiutil ditto codesign spctl; do
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

OUT=$(CURL_CODE=404 install_github_app "$W/Applications/Example.app" sevmorris/example Example 2>&1); RC=$?
left=$(find "$W/tmp" -mindepth 1 -maxdepth 1 | tr '\n' ' ')
if [[ $RC == 3 ]] && ! grep -q 'failed to download' <<<"$OUT" && [[ -z "$left" ]] \
   && [[ ! -e "$W/Applications/Example.app" ]]; then
  pass "install_github_app returns the skip, warns nothing, and leaves no temporary file"
else
  fail "install_github_app on a 404: exit $RC, left in TMPDIR: '${left}', said: $OUT"
fi
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

# ── A copy into /Applications, whole, failed or cut short ────────────────────


# copy MODE — install_github_app with the release found and ditto in MODE, run
# from a script file carrying post-install's INT trap, as post-install runs it;
# sets RC, OUT and LEFT. A script file, not `bash -c` or a subshell: bash 3.2
# unwinds the function before the EXIT trap in those, so the trap cannot see
# install_github_app's locals. In a script file, as post-install and install-apps
# always run, it can.
cat > "$W/driver.sh" <<'EOF'
source "$1"
trap 'printf "interrupted\n"; exit 1' INT TERM
install_github_app "$2" sevmorris/example Example
EOF
copy() {
  rm -rf "$W/Applications/Example.app"; : > "$W/calls"
  OUT=$(CURL_CODE=200 DITTO_MODE="$1" "$BASH_UNDER_TEST" "$W/driver.sh" \
    "$REPO_ROOT/scripts/install-apps" "$W/Applications/Example.app" 2>&1); RC=$?
  LEFT=$(find "$W/tmp" -mindepth 1 -maxdepth 1 | tr '\n' ' ')
}
copy ok
if [[ $RC == 0 && -f "$W/Applications/Example.app/Contents/Info.plist" && -z "$LEFT" ]]; then
  pass "a whole copy is installed, and no temporary file is left"
else
  fail "whole copy: exit $RC, left '$LEFT', said: $OUT"
fi
copy fail
if [[ $RC == 1 && ! -e "$W/Applications/Example.app" && -z "$LEFT" ]] && grep -q 'failed to copy' <<<"$OUT"; then
  pass "a failed copy is removed and reported"
else
  fail "failed copy: exit $RC, app $([[ -e "$W/Applications/Example.app" ]] && echo left || echo gone), said: $OUT"
fi
copy interrupt
if [[ $RC == 1 && ! -e "$W/Applications/Example.app" && -z "$LEFT" ]] && grep -q interrupted <<<"$OUT" \
   && grep -q '^hdiutil detach' "$W/calls"; then
  pass "a copy cut short by Ctrl-C is removed, the image detached, no temporary file left"
else
  fail "interrupted copy: exit $RC, app $([[ -e "$W/Applications/Example.app" ]] && echo LEFT BEHIND || echo gone), left '$LEFT'"
fi

# `make apps` on its own: a copy of the script, its /Applications pointed into
# the sandbox, interrupted during its first app's copy.
C="$W/copy"; mkdir -p "$C"
cp "$REPO_ROOT/scripts/lib.sh" "$C/"
sed "s#/Applications/#$W/Applications/#g" "$REPO_ROOT/scripts/install-apps" > "$C/install-apps"
first=$(sed -n 's/^  "\([^"|]*\)\.app|.*/\1/p' "$C/install-apps" | head -1)
rm -rf "$W/Applications"/*; : > "$W/calls"
OUT=$(CURL_CODE=200 DITTO_MODE=interrupt STUB_APP="$first" "$BASH_UNDER_TEST" "$C/install-apps" 2>&1); RC=$?
if [[ -n "$first" && $RC == 1 && ! -e "$W/Applications/$first.app" ]] && grep -q 'interrupted' <<<"$OUT"; then
  pass "make apps, interrupted during $first's copy: exits 1 and removes the partial app"
else
  fail "make apps interrupted (first app '$first'): exit $RC, app $([[ -e "$W/Applications/$first.app" ]] && echo LEFT BEHIND || echo gone), said: $(tail -3 <<<"$OUT")"
fi

(( fails == 0 ))
