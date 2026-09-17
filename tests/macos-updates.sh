#!/usr/bin/env bash
# macos-updates.sh — prove that bin/macos-updates installs the updates for the
# installed major version, and never a major upgrade.
#
# On 2026-09-15 update-full ran `softwareupdate -ia` on macOS 26.7, and the one
# update listed was macOS 27: softwareupdate started downloading it. That call
# is gone, and macos-updates replaced it. softwareupdate and sw_vers are stubs
# here, so nothing is installed and nothing touches the network. The stub
# answers --list from a fixture and records every label --install is given.
# The first fixture is the listing this Mac printed on 2026-09-16.
#
# It also guards the repository, once per run: no tracked script may call
# softwareupdate with --all, topgrade's "system" step — `softwareupdate
# --install --all`, and assume_yes means nobody is asked — must stay
# disabled, and both ways in (make updates, update-full) must go through
# macos-updates.
#
# Runs under /bin/bash as well as the bash running it, because macos-updates
# has no bash-4 guard. ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

# repo_guards — the static half: what no fixture can show.
repo_guards() {
  printf '  repository\n'
  local hits
  # Code lines only: a comment may quote the old call to say why it is gone.
  hits=$(git -C "$REPO_ROOT" ls-files -z -- Makefile bin scripts dotfiles assets tools \
    | xargs -0 grep -HnE 'softwareupdate' -- 2>/dev/null \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*(#|//)' \
    | grep -E "softwareupdate.*[[:space:]\"'](-[a-zA-Z]*a[a-zA-Z]*|--all)([^a-zA-Z-]|\$)" || true)
  if [[ -z "$hits" ]]; then
    pass "no tracked script calls softwareupdate with --all"
  else
    fail "a tracked script calls softwareupdate with --all, which installs a major upgrade:"
    printf '%s\n' "$hits" >&2
  fi

  if grep -Eq '^[[:space:]]*disable[[:space:]]*=[[:space:]]*\[[^]]*"system"' "$REPO_ROOT/assets/topgrade.toml"; then
    pass "topgrade's system step stays disabled"
  else
    fail "assets/topgrade.toml no longer disables \"system\" — topgrade would run softwareupdate --install --all"
  fi

  if make -n -C "$REPO_ROOT" updates 2>/dev/null | grep -q '/bin/macos-updates'; then
    pass "make updates runs macos-updates"
  else
    fail "make updates does not run bin/macos-updates"
  fi

  # shellcheck disable=SC2016  # the literal text of the call, not an expansion
  if grep -q '"$SCRIPT_DIR/macos-updates"' "$REPO_ROOT/bin/update-full"; then
    pass "update-full runs macos-updates"
  else
    fail "bin/update-full does not run macos-updates for its macOS step"
  fi
}

if [[ "${1:-}" != --inner ]]; then
  run_under() {
    # shellcheck disable=SC2016  # expanded by the inner bash, not this one
    printf '  under bash %s\n' "$("$1" -c 'echo "${BASH_VERSION%%(*}"')"
    "$1" "${BASH_SOURCE[0]}" --inner
  }
  rc=0
  run_under /bin/bash || rc=1
  if [[ ! "$BASH" -ef /bin/bash ]]; then run_under "$BASH" || rc=1; fi
  repo_guards
  (( fails == 0 )) || rc=1
  exit "$rc"
fi

ROOT=$(mrk_mktemp_d) || exit 1
trap 'rm -rf "$ROOT"' EXIT
BASH_UNDER_TEST=$BASH
S=$ROOT/state
mkdir -p "$ROOT/bin" "$S"

cat > "$ROOT/bin/softwareupdate" <<STUB
#!/bin/bash
S="$S"
printf '%s\n' "\$*" >> "\$S/calls"
case "\$1" in
  --list)
    cat "\$S/list"
    [[ -s "\$S/list_err" ]] && cat "\$S/list_err" >&2
    exit "\$(cat "\$S/list_rc" 2>/dev/null || echo 0)"
    ;;
  --install)
    shift
    for a in "\$@"; do printf '[%s]\n' "\$a" >> "\$S/installed"; done
    exit "\$(cat "\$S/install_rc" 2>/dev/null || echo 0)"
    ;;
  *)
    echo "stub softwareupdate: unexpected arguments: \$*" >&2
    exit 99
    ;;
esac
STUB
cat > "$ROOT/bin/sw_vers" <<STUB
#!/bin/bash
case "\$1" in
  -productVersion) cat "$S/version" ;;
  *) echo "stub sw_vers: unexpected arguments: \$*" >&2; exit 99 ;;
esac
STUB
chmod +x "$ROOT/bin/softwareupdate" "$ROOT/bin/sw_vers"

export PATH="$ROOT/bin:$PATH"
if [[ "$(command -v softwareupdate)" != "$ROOT/bin/softwareupdate" ]]; then
  err "the softwareupdate stub is not first on PATH — refusing to run against the real one"
  exit 1
fi

T=$'\t'
HEADER="Software Update Tool

Finding available software
Software Update found the following new or updated software:"
# Verbatim from `softwareupdate --list` on this Mac, 2026-09-16, macOS 26.7.
MAJOR27="* Label: macOS 27-26A428
${T}Title: macOS 27, Version: 27, Size: 11728377KiB, Recommended: YES, Action: restart, "
MINOR="* Label: macOS Tahoe 26.7.1-25H300
${T}Title: macOS Tahoe 26.7.1, Version: 26.7.1, Size: 1843200KiB, Recommended: YES, Action: restart, "
RSR="* Label: macOS Tahoe 26.7.1 (a)-25H300a
${T}Title: macOS Tahoe 26.7.1 (a), Version: 26.7.1 (a), Size: 90112KiB, Recommended: YES, Action: restart, "
SAFARI="* Label: Safari27.0TahoeAuto-27.0
${T}Title: Safari, Version: 27.0, Size: 190512KiB, Recommended: YES, "
CLT="* Label: Command Line Tools for Xcode 27.0-27.0
${T}Title: Command Line Tools for Xcode 27.0, Version: 27.0, Size: 903421KiB, Recommended: YES, "

# given VERSION LIST... — the installed version, and the entries --list prints
given() {
  printf '%s\n' "$1" > "$S/version"; shift
  { printf '%s\n' "$HEADER"; printf '%s\n' "$@"; } > "$S/list"
  rm -f "$S/list_err" "$S/list_rc" "$S/install_rc"
}

# run [ARGS...] — sets OUT and RC; clears the call record first
run() {
  : > "$S/calls"
  rm -f "$S/installed"
  OUT=$("$BASH_UNDER_TEST" "$REPO_ROOT/bin/macos-updates" "$@" 2>&1)
  RC=$?
}

installed() { cat "$S/installed" 2>/dev/null; }
install_called() { grep -q '^--install' "$S/calls"; }

# expect NAME RC INSTALLED — the exit status, and exactly the labels installed
# ("" for none: then --install must not have been called at all)
expect() {
  local name=$1 want_rc=$2 want=$3
  if [[ "$RC" != "$want_rc" ]]; then
    fail "$name: exit $RC, expected $want_rc"
    printf '%s\n' "$OUT" | sed 's/^/      /' >&2
  elif [[ -z "$want" ]] && install_called; then
    fail "$name: installed $(installed | tr '\n' ' ')— expected nothing"
  elif [[ "$(installed)" != "$want" ]]; then
    fail "$name: installed '$(installed | tr '\n' ' ')', expected '$(printf '%s' "$want" | tr '\n' ' ')'"
  else
    pass "$name"
  fi
}

says() {
  if [[ "$OUT" == *"$2"* ]]; then pass "$1"; else fail "$1 — output lacks '$2'"; printf '%s\n' "$OUT" | sed 's/^/      /' >&2; fi
}

given 26.7 "$MAJOR27"
run
expect "the 2026-09-16 listing — macOS 27 alone — installs nothing" 0 ""
says "and names the upgrade it left alone" "Not installing macOS 27 (27)"

given 26.7 "$MINOR" "$MAJOR27"
run
expect "a minor update beside the upgrade: only the minor one, its label in one piece" 0 "[macOS Tahoe 26.7.1-25H300]"

given 26.7 "$SAFARI" "$CLT" "$MAJOR27"
run
expect "Safari and the Command Line Tools at 27.0 install on macOS 26; macOS 27 does not" 0 \
  "[Safari27.0TahoeAuto-27.0]
[Command Line Tools for Xcode 27.0-27.0]"

given 26.7 "$RSR"
run
expect "a security response for the installed version installs" 0 "[macOS Tahoe 26.7.1 (a)-25H300a]"

given 27.0 "* Label: macOS 27.0.1-26A500
${T}Title: macOS 27.0.1, Version: 27.0.1, Size: 1843200KiB, Recommended: YES, Action: restart, " \
  "* Label: macOS 28-27A100
${T}Title: macOS 28, Version: 28, Size: 12000000KiB, Recommended: YES, Action: restart, "
run
expect "on macOS 27 the rule moves with it: 27.0.1 installs, 28 does not" 0 "[macOS 27.0.1-26A500]"

given 26.7
printf 'Software Update Tool\n\nFinding available software\n' > "$S/list"
printf 'No new software available.\n' > "$S/list_err"
run
expect "nothing listed: exit 0, nothing installed" 0 ""

given 26.7 "$MINOR" "$MAJOR27"
run --dry-run
expect "--dry-run installs nothing" 0 ""
says "and names what it would install" "Would install: macOS Tahoe 26.7.1-25H300"
run -n
expect "-n is --dry-run" 0 ""

given 26.7 "$MINOR"
printf 'Cannot connect to the Apple Software Update server.\n' > "$S/list"
echo 1 > "$S/list_rc"
run
expect "a failed --list installs nothing and exits 1" 1 ""

given 26.7 "* Label: macOS Next-27Z1" "$MINOR"
run
expect "an entry with no title line: nothing installed, not even the readable one" 1 ""

given 26.7 "$MINOR" "* Label: macOS Next-27Z1
${T}Title: macOS Next, Version: Next, Size: 1KiB, Recommended: YES, Action: restart, "
run
expect "a macOS entry whose version does not parse: nothing installed" 1 ""

given 26.7
printf 'Software Update Tool\n\nSomething Apple has not printed before\n' > "$S/list"
run
expect "output with no labels and no \"No new software\" is not \"up to date\"" 1 ""

given 26.7 "$MINOR"
echo 1 > "$S/install_rc"
run
expect "a failed install exits 1" 1 "[macOS Tahoe 26.7.1-25H300]"

given 26.7 "$MAJOR27"
run --help
if [[ "$RC" == 0 && ! -s "$S/calls" ]]; then pass "--help answers without calling softwareupdate"; else fail "--help: exit $RC, calls: $(tr '\n' ' ' < "$S/calls")"; fi
run --all
if [[ "$RC" == 2 && ! -s "$S/calls" ]]; then pass "an unknown option exits 2 without calling softwareupdate"; else fail "--all: exit $RC, calls: $(tr '\n' ' ' < "$S/calls")"; fi

given "" "$MINOR"
run
if [[ "$RC" == 1 && ! -s "$S/calls" ]]; then pass "an unreadable macOS version stops before softwareupdate runs"; else fail "no version: exit $RC, calls: $(tr '\n' ' ' < "$S/calls")"; fi

(( fails == 0 ))
