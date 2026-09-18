#!/usr/bin/env bash
# pinned-downloads.sh — prove that git_clone_pinned installs a tag only while
# it names its pinned commit, and that no script runs downloaded code unchecked.
#
# Until 2026-09-18 post-install piped nvm's install script from a release tag
# into bash, and the zsh plugins were cloned by tag alone. Both now go through
# git_clone_pinned (scripts/lib.sh). Here it clones from repositories built on
# the spot, over file:// so --depth applies, and nothing touches the network.
# One of them has its tag moved, which is the case the pin exists for.
#
# It also guards the repository: no tracked script may pipe a download into a
# shell. The one exception is Homebrew's official installer in scripts/brew;
# the reason it is not pinned is in audit/17-audit-2026-09-18.md.
#
# Runs under /bin/bash as well as the bash running it, because lib.sh is
# sourced by scripts that must work before Homebrew's bash exists. ci-check
# runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/pinned.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

# ── Fixtures: a repository with two commits, tagged ────────────────────────────

g() { git -c user.name=test -c user.email=test@test.invalid -c commit.gpgsign=false "$@"; }
SRC="$WORK/src"
g init -q "$SRC"
echo one > "$SRC/nvm.sh"; g -C "$SRC" add .; g -C "$SRC" commit -qm one
FIRST="$(git -C "$SRC" rev-parse HEAD)"
g -C "$SRC" tag v1                          # lightweight, like zsh-autosuggestions
g -C "$SRC" tag -a v1-annotated -m v1       # annotated, like nvm
echo two > "$SRC/nvm.sh"; g -C "$SRC" commit -qam two
SECOND="$(git -C "$SRC" rev-parse HEAD)"
URL="file://$SRC"

# leftovers DIR — temporary clones git_clone_pinned left beside a destination
leftovers() { find "$1" -maxdepth 1 -name '.*.??????' 2>/dev/null; }

# The pinned-clone cases run in a child bash so the helper is tested under
# /bin/bash 3.2 too; the child sources lib.sh and reports through its exit status.
clone() { # SHELL URL TAG COMMIT DEST
  local sh="$1"
  shift
  # shellcheck disable=SC2016  # expanded by the inner bash, not this one
  "$sh" -c 'source "$1/scripts/lib.sh"; shift; git_clone_pinned "$@"' _ "$REPO_ROOT" "$@" \
    >"$WORK/out" 2>&1
}

cases() {
  local sh="$1" d
  d="$(mktemp -d "$WORK/run.XXXX")"

  if clone "$sh" "$URL" v1 "$FIRST" "$d/ok" && [[ "$(git -C "$d/ok" rev-parse HEAD)" == "$FIRST" ]]; then
    pass "a tag that names its pinned commit is installed"
  else
    fail "the pinned clone of v1 failed: $(tail -1 "$WORK/out")"
  fi

  if clone "$sh" "$URL" v1-annotated "$FIRST" "$d/annotated"; then
    pass "an annotated tag is compared by the commit it names"
  else
    fail "the annotated tag was refused: $(tail -1 "$WORK/out")"
  fi

  if clone "$sh" "$URL" v1 "$SECOND" "$d/wrong"; then
    fail "a clone whose tag names another commit was installed"
  elif [[ -e "$d/wrong" ]]; then
    fail "a refused clone left $d/wrong in place"
  elif grep -q 'refused' "$WORK/out"; then
    pass "a tag that names another commit is refused, and nothing is left in place"
  else
    fail "the refusal did not say why: $(cat "$WORK/out")"
  fi

  if clone "$sh" "$URL" no-such-tag "$FIRST" "$d/missing" || [[ -e "$d/missing" ]]; then
    fail "a tag that does not exist was not refused cleanly"
  else
    pass "a tag that does not exist is refused"
  fi

  mkdir -p "$d/taken"; echo keep > "$d/taken/file"
  if clone "$sh" "$URL" v1 "$FIRST" "$d/taken" || [[ "$(cat "$d/taken/file")" != keep ]]; then
    fail "an existing destination was cloned over"
  else
    pass "an existing destination is left alone"
  fi

  if [[ -z "$(leftovers "$d")" ]]; then
    pass "no temporary clone is left beside any destination"
  else
    fail "temporary clones left behind: $(leftovers "$d" | tr '\n' ' ')"
  fi
}

# shellcheck disable=SC2016  # expanded by the inner bash, not this one
printf '  under bash %s\n' "$(/bin/bash -c 'echo "${BASH_VERSION%%(*}"')"
cases /bin/bash
if [[ ! "$BASH" -ef /bin/bash ]]; then
  # shellcheck disable=SC2016  # expanded by the inner bash, not this one
  printf '  under bash %s\n' "$("$BASH" -c 'echo "${BASH_VERSION%%(*}"')"
  cases "$BASH"
fi

# The pin's whole point: the upstream tag moves. Same pin, same URL, new target.
printf '  a moved tag\n'
g -C "$SRC" tag -f v1 "$SECOND" >/dev/null
if clone "$BASH" "$URL" v1 "$FIRST" "$WORK/moved"; then
  fail "v1 was moved to another commit and still installed"
else
  pass "once v1 is moved to another commit, the same pin refuses it"
fi

# ── The repository ────────────────────────────────────────────────────────────

printf '  repository\n'
# Code lines that fetch with curl or wget and hand the result to a shell. Comment
# lines may quote the old call to say why it is gone. The grep runs inside the
# repository: ls-files prints paths relative to it, and from anywhere else grep
# would find nothing, stay quiet, and let the check pass.
piped=$(cd "$REPO_ROOT" && git ls-files -z -- Makefile bin scripts dotfiles assets \
  | xargs -0 grep -HnE '(curl|wget)' -- 2>/dev/null \
  | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' \
  | grep -E '\|[[:space:]]*(ba|z)?sh([[:space:]]|$)|(ba|z)?sh[[:space:]]+<\(|(ba|z)?sh[[:space:]]+-c[[:space:]]+"?\$\((curl|wget)' \
  | grep -v '^scripts/brew:' || true)
if [[ -z "$piped" ]]; then
  pass "no script pipes a download into a shell, except Homebrew's installer"
else
  fail "a script runs downloaded code unchecked:"
  printf '%s\n' "$piped" >&2
fi

# Every pin is a full commit id, next to the tag it belongs to.
bad=$(grep -hoE 'NVM_COMMIT="[^"]*"|zsh-[a-z-]+:[^:"]+:[^"]*"' \
        "$REPO_ROOT/scripts/post-install" "$REPO_ROOT/scripts/setup" \
      | grep -vE '(NVM_COMMIT="|:)[0-9a-f]{40}"$' || true)
count=$(grep -hoE 'NVM_COMMIT="[0-9a-f]{40}"|zsh-[a-z-]+:[^:"]+:[0-9a-f]{40}"' \
          "$REPO_ROOT/scripts/post-install" "$REPO_ROOT/scripts/setup" | wc -l | tr -d ' ')
if [[ -z "$bad" && "$count" -eq 3 ]]; then
  pass "nvm and both zsh plugins are pinned to full commit ids"
else
  fail "expected 3 full commit pins, found $count${bad:+; malformed: $bad}"
fi

(( fails == 0 ))
