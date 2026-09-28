#!/usr/bin/env bash
# snapshot-brewfile.sh — prove that `snapshot --brewfile` strips the App Store
# lines a Brewfile dump writes back, and leaves the Brewfile as it should.
#
# snapshot --brewfile runs `brew bundle dump --force`, and on a Mac where mas is
# installed the dump writes `mas` lines, which mrk does not install and
# ci-check refuses. Until 2026-09-28 the strip called mrk_mktemp, a helper from
# scripts/lib.sh that bin/snapshot never sources, so it died with "command not
# found" and left the lines in (audit 19, W-21).
#
# It runs on a copy of the repository under a throwaway HOME. brew is a stub
# whose `bundle dump` writes a Brewfile with a tap, a formula, a cask and a mas
# line; defaults and plutil are stubs that refuse, and every "/Applications/" in
# the copy points at an empty folder, so no preference is read or exported. The
# confirmation is read from /dev/tty, so snapshot runs in a pseudo-terminal
# that answers it. Under /bin/bash and the bash running this file. ci-check
# runs it.

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

command -v python3 >/dev/null 2>&1 || { fail "python3 not found"; exit 1; }

W=$(mrk_mktemp_d) || exit 1
W=$(cd "$W" && pwd -P)
trap 'rm -rf "$W"' EXIT
R="$W/repo"; S="$W/stubs"
mkdir -p "$R/bin" "$R/assets/preferences" "$S" "$W/home" "$W/Applications" "$W/tmp"
sed "s#/Applications/#$W/Applications/#g" "$REPO_ROOT/bin/snapshot" > "$R/bin/snapshot"
chmod +x "$R/bin/snapshot"
if grep -n '/Applications/' "$R/bin/snapshot" | grep -vF "$W/"; then
  fail "a real /Applications path survived the rewrite — refusing to run"
  exit 1
fi
printf '# the Brewfile before the dump\nbrew "old"\n' > "$R/Brewfile"
chmod 644 "$R/Brewfile"
cp -p "$R/Brewfile" "$W/Brewfile.before"

cat > "$S/brew" <<'EOF'
#!/bin/bash
[[ "$1 $2" == "bundle dump" ]] || { echo "brew stub: unexpected: $*" >&2; exit 1; }
for a in "$@"; do [[ "$a" == --file=* ]] && f="${a#--file=}"; done
printf 'tap "homebrew/core"\nbrew "jq"\ncask "iterm2"\nmas "Xcode", id: 497799835\n' > "$f"
EOF
for cmd in defaults plutil; do printf '#!/bin/bash\necho "%s stub: refused: $*" >&2\nexit 1\n' "$cmd" > "$S/$cmd"; done
chmod +x "$S"/*

# ptyrun.py ANSWER CMD... — CMD in a pseudo-terminal, typing ANSWER at the
# first [y/N] prompt. Prints CMD's output and exits with its status.
cat > "$W/ptyrun.py" <<'EOF'
import os, pty, re, select, sys
answer = sys.argv[1]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(sys.argv[2], sys.argv[2:])
out, pending, sent = b"", b"", False
while True:
    try:
        ready, _, _ = select.select([fd], [], [], 30)
        if not ready:
            break
        data = os.read(fd, 4096)
    except OSError:
        break
    if not data:
        break
    out += data
    pending += data
    if not sent and re.search(rb"\[y/N\]:?\s*$", pending):
        os.write(fd, (answer + "\n").encode())
        sent = True
_, status = os.waitpid(pid, 0)
sys.stdout.buffer.write(out)
sys.exit(os.waitstatus_to_exitcode(status))
EOF

python3 "$W/ptyrun.py" y env -i HOME="$W/home" TMPDIR="$W/tmp" TERM=dumb \
  PATH="$S:/usr/bin:/bin:/usr/sbin:/sbin" "$BASH_UNDER_TEST" "$R/bin/snapshot" --brewfile \
  2>&1 | tr -d '\r' > "$W/out"
rc=${PIPESTATUS[0]}

if [[ $rc == 0 ]] && ! grep -q '^mas' "$R/Brewfile" \
   && [[ "$(cat "$R/Brewfile")" == "$(printf 'tap "homebrew/core"\nbrew "jq"\ncask "iterm2"')" ]] \
   && grep -q 'Dropped 1 Mac App Store' "$W/out" && ! grep -q 'command not found' "$W/out"; then
  pass "snapshot --brewfile strips the dump's mas line and keeps the rest"
else
  fail "snapshot --brewfile (exit $rc) left: $(tr '\n' '|' < "$R/Brewfile")"
  sed 's/^/      /' "$W/out" | tail -6 >&2
fi
if cmp -s "$R/Brewfile.bak" "$W/Brewfile.before" && [[ "$(/usr/bin/stat -f %Lp "$R/Brewfile")" == 644 ]] \
   && [[ -z "$(find "$R" -maxdepth 1 -name '.Brewfile.*')" ]]; then
  pass "  the old Brewfile is kept as Brewfile.bak, the mode stays 644, and no temp file is left"
else
  fail "  Brewfile.bak $(cmp -s "$R/Brewfile.bak" "$W/Brewfile.before" && echo matches || echo differs); mode $(/usr/bin/stat -f %Lp "$R/Brewfile"); temp: $(find "$R" -maxdepth 1 -name '.Brewfile.*' | tr '\n' ' ')"
fi

(( fails == 0 ))
