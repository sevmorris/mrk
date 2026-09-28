#!/usr/bin/env bash
# new-mac.sh — prove that Phases 1 and 2 run on a Mac with no Homebrew: under
# the bash 3.2 that macOS ships, with no Homebrew bash to hand over to.
#
# From 2026-03-20 until 2026-09-27 scripts/setup and scripts/brew began by
# re-executing themselves with /opt/homebrew/bin/bash or /usr/local/bin/bash,
# and exited 1 when neither existed. On a new Mac neither does, so `make setup`
# and `make brew` both stopped at their first lines, and brew is the phase that
# installs Homebrew (audit 19, W-1). Nothing saw it: test installs keep
# Homebrew, CI installs bash before ci-check, and tests/install-all.sh stubs
# make. Both scripts are now bash-3.2-clean and never re-execute.
#
# Every run is on a copy of the repository, under a throwaway HOME, with
# `env -i` and PATH cut to stubs and the system directories, so no Homebrew is
# reachable by name. BASH_ENV records which bash runs each script. A re-exec
# into another bash shows up there even when that bash exists, as Homebrew's
# does on this Mac and on CI, where a missing-bash check would pass.
#
# brew runs with MRK_BREW naming a path in the sandbox. curl is a stub whose
# Homebrew "installer" puts a stub brew there, and `brew install gum` puts a
# stub gum beside it. sudo, chsh, dscl, xcode-select and git are stubs too.
# Nothing is installed, and the real HOME, ~/.mrk, ~/bin and /opt/homebrew are
# never touched. ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

command -v script >/dev/null 2>&1 || { fail "script(1) not found"; exit 1; }

# cd && pwd: the paths the scripts print are normalised that way, and macOS's
# TMPDIR ends in a slash.
W="$(mktemp -d "${TMPDIR:-/tmp}/new-mac.XXXXXX")" && W="$(cd "$W" && pwd)" || exit 1
trap 'rm -rf "$W"' EXIT
R="$W/repo"          # the copy of the repository
H="$W/home"          # the throwaway HOME
S="$W/stubs"         # first on PATH
P="$W/homebrew"      # where the stub installer puts Homebrew
TPL="$W/templates"   # the stub brew and gum, before anything "installs" them
mkdir -p "$R" "$S" "$TPL" "$W/tmp"

# The tracked files the two phases read, as the working tree has them
while IFS= read -r -d '' f; do
  [[ -f "$REPO_ROOT/$f" ]] || continue
  mkdir -p "$R/$(dirname "$f")"
  cp -p "$REPO_ROOT/$f" "$R/$f"
done < <(git -C "$REPO_ROOT" ls-files -z scripts bin dotfiles Brewfile Makefile tools/picker/main.go)

# Belt and braces: MRK_BREW keeps brew away from this Mac's Homebrew, and the
# copy's own Homebrew paths are pointed into the sandbox as well. A brew that
# stopped honouring MRK_BREW then finds nothing, rather than a real brew to run
# `brew bundle` with.
sed -i.orig -e "s#/opt/homebrew/bin/brew#$W/refused/bin/brew#g" \
  -e "s#/usr/local/bin/brew#$W/refused/bin/brew#g" "$R/scripts/brew"
rm -f "$R/scripts/brew.orig"

# Copies of both, beside lib.sh in a directory of their own, with an unbound
# variable planted after their traps are set, for the abort cases below
A="$W/abort"
mkdir -p "$A/scripts"
cp -p "$R/scripts/lib.sh" "$A/scripts/"
plant() {
  awk -v a="$2" 'index($0, a) == 1 && !done { print ": \"$mrk_planted_unbound\""; done = 1 } { print }' \
    "$R/scripts/$1" > "$A/scripts/$1"
  chmod +x "$A/scripts/$1"
  grep -q mrk_planted_unbound "$A/scripts/$1" || { fail "could not plant an abort in $1: no line begins '$2'"; exit 1; }
}
plant setup "# Run phases"
plant brew "# Run main installation"

# ── Stubs ────────────────────────────────────────────────────────────────────

# Each records its command line in $SANDBOX/calls.
cat > "$S/record" <<'EOF'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >> "$SANDBOX/calls"
EOF
chmod +x "$S/record"
for cmd in sudo chsh git; do cp -p "$S/record" "$S/$cmd"; done

cat > "$S/xcode-select" <<'EOF'
#!/bin/bash
printf 'xcode-select %s\n' "$*" >> "$SANDBOX/calls"
[[ "${1:-}" == -p ]] && echo /Library/Developer/CommandLineTools
exit 0
EOF
# A new Mac's login shell
cat > "$S/dscl" <<'EOF'
#!/bin/bash
printf 'dscl %s\n' "$*" >> "$SANDBOX/calls"
echo "UserShell: /bin/zsh"
EOF
# The network check reaches brew.sh; the Homebrew installer, run by
# `/bin/bash -c "$(curl …)"`, puts the stub brew where MRK_BREW says.
cat > "$S/curl" <<'EOF'
#!/bin/bash
printf 'curl %s\n' "$*" >> "$SANDBOX/calls"
case "$*" in
  *Homebrew/install*)
    printf 'mkdir -p %q && cp %q %q\n' "$(dirname "$MRK_BREW")" "$SANDBOX/templates/brew" "$MRK_BREW" ;;
esac
exit 0
EOF
cat > "$TPL/brew" <<'EOF'
#!/bin/bash
printf 'brew %s\n' "$*" >> "$SANDBOX/calls"
prefix="$(cd "$(dirname "$0")/.." && pwd)"
case "$1" in
  shellenv) printf 'export HOMEBREW_PREFIX=%q; export PATH=%q:"$PATH";\n' "$prefix" "$prefix/bin" ;;
  list)     if [[ "${2:-}" == --cask ]]; then cat "$SANDBOX/installed-casks"; else cat "$SANDBOX/installed-formulae"; fi ;;
  install)  if [[ "${2:-}" == gum ]]; then cp "$SANDBOX/templates/gum" "$prefix/bin/gum"; else exit 1; fi ;;
  bundle)   for a in "$@"; do [[ "$a" == --file=* ]] && cp "${a#--file=}" "$SANDBOX/bundled"; done; exit 0 ;;
  *)        echo "brew stub: unexpected: $*" >&2; exit 1 ;;
esac
EOF
# `gum choose [flags] LABEL...`: records every label, and chooses those whose
# package name is in GUM_PICK.
cat > "$TPL/gum" <<'EOF'
#!/bin/bash
printf 'gum %s\n' "${1:-}" >> "$SANDBOX/calls"
[[ "${1:-}" == choose ]] || exit 0
shift
for a in "$@"; do
  [[ "$a" == --* ]] && continue
  printf '%s\n' "$a" >> "$SANDBOX/gum-labels"
  [[ " $GUM_PICK " == *" ${a%% — *} "* ]] && printf '%s\n' "$a"
done
exit 0
EOF
# mrk-picker, when a case puts it in the repository's bin/: records its
# arguments and prints PICKER_OUT, one word per line.
cat > "$TPL/mrk-picker" <<'EOF'
#!/bin/bash
printf '%s\n' "$@" > "$SANDBOX/picker-args"
tr ' ' '\n' <<< "$PICKER_OUT"
EOF
chmod +x "$S"/* "$TPL"/*

# BASH_ENV: every non-interactive bash reads it first, the scripts under test
# included, and again after any re-exec. It logs the bash's version and the
# process's own argv, read with ps: bash 3.2 has not yet set $0 to the script
# when it reads BASH_ENV, and a re-exec keeps the PID but not the argv.
# shellcheck disable=SC2016  # expanded by the bash that reads the file
printf '%s\n' '[ -n "${SANDBOX:-}" ] && printf "%s %s\n" "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}" "$(ps -o args= -p $$)" >> "$SANDBOX/interp"' > "$W/bash-env"

# ── The Brewfile, as the cases below use it ──────────────────────────────────

FORMULAE=()
CASKS=()
while IFS= read -r n; do FORMULAE+=("$n"); done < <(sed -nE 's/^brew "([^"]+)".*/\1/p' "$R/Brewfile")
while IFS= read -r n; do CASKS+=("$n"); done < <(sed -nE 's/^cask "([^"]+)".*/\1/p' "$R/Brewfile")
if (( ${#FORMULAE[@]} < 2 || ${#CASKS[@]} < 2 )); then
  fail "the Brewfile lists ${#FORMULAE[@]} formulae and ${#CASKS[@]} casks; the cases need two of each"
  exit 1
fi
F1="${FORMULAE[0]}"; F2="${FORMULAE[${#FORMULAE[@]}-1]}"
C1="${CASKS[0]}";    C2="${CASKS[${#CASKS[@]}-1]}"

# line_of NAME — NAME's line in the Brewfile
line_of() { awk -F'"' -v n="$1" '($1 == "brew " || $1 == "cask ") && $2 == n { print; exit }' "$R/Brewfile"; }
# desc_of NAME — NAME's description in main.go, as written there
desc_of() {
  awk -v n="$1" 'index($0, "\t\"" n "\":") == 1 { sub(/^[^:]*:[[:space:]]*"/, ""); sub(/",$/, ""); print; exit }' \
    "$R/tools/picker/main.go"
}
# bundled_ok NAME... — `brew bundle` was handed the Brewfile's taps, comments
# and blank lines, in order, and the lines of exactly NAME..., in any order.
bundled_ok() {
  [[ -f "$W/bundled" ]] || return 1
  [[ "$(grep -vE '^(brew|cask) "' "$W/bundled")" == "$(grep -vE '^(brew|cask) "|^mas[[:space:]]' "$R/Brewfile")" ]] || return 1
  local want="" n
  for n in "$@"; do want+="$(line_of "$n")"$'\n'; done
  [[ "$(grep -E '^(brew|cask) "' "$W/bundled" | sort)" == "$(printf '%s' "$want" | sort)" ]]
}

# ── Running a phase ──────────────────────────────────────────────────────────

# fresh_mac — no Homebrew, nothing installed, an empty HOME
fresh_mac() {
  rm -rf "$P" "$H" "$R/bin/mrk-picker"
  mkdir -p "$H"
  : > "$W/installed-formulae"
  : > "$W/installed-casks"
  : > "$W/shells"
}
# with_homebrew — Homebrew already installed, and a clean HOME
with_homebrew() {
  fresh_mac
  mkdir -p "$P/bin"
  cp -p "$TPL/brew" "$P/bin/brew"
}

# run BASHDIR [--tty] CMD ARGS... — run CMD with a new Mac's PATH: the stubs,
# then BASHDIR, then the system directories. BASHDIR holds a `bash` for env to
# find first, or is empty, and then the #! line finds /bin/bash. --tty runs it
# in a pseudo-terminal, which brew's picker path needs. Output in $W/out, exit
# status in RC.
RC=0
run() {
  local bashdir=$1 tty=0
  shift
  [[ "$1" == --tty ]] && { tty=1; shift; }
  : > "$W/calls"; : > "$W/interp"
  rm -f "$W/bundled" "$W/picker-args" "$W/gum-labels"
  local cmd=(env -i HOME="$H" USER="${USER:-$(id -un)}" LOGNAME="${USER:-$(id -un)}"
             TMPDIR="$W/tmp" TERM=dumb PATH="$S:$bashdir:/usr/bin:/bin:/usr/sbin:/sbin"
             BASH_ENV="$W/bash-env" SANDBOX="$W" MRK_BREW="$P/bin/brew" SHELLS_FILE="$W/shells"
             GUM_PICK="${GUM_PICK:-}" PICKER_OUT="${PICKER_OUT:-}" "$@")
  if (( tty )); then
    script -q /dev/null "${cmd[@]}" </dev/null 2>&1 | tr -d '\r' > "$W/out"
    RC=${PIPESTATUS[0]}
  else
    "${cmd[@]}" </dev/null >"$W/out" 2>&1
    RC=$?
  fi
}

# ran_under SCRIPT — the bash versions that ran scripts/SCRIPT, as "3.2 ". A
# log line is "VERSION BASH SCRIPT ARGS...", so the script is the third field;
# make's `/bin/bash -c "…/scripts/brew" …` has -c there, and is not counted.
ran_under() {
  awk -v s="/scripts/$1" 'substr($3, length($3) - length(s) + 1) == s { print $1 }' "$W/interp" \
    | sort -u | tr '\n' ' '
}
has() { grep -qF -- "$1" "$W/out"; }
show() { sed 's/^/      /' "$W/out" | tail -"${1:-15}" >&2; }

# expect WHAT SCRIPT — a run of scripts/SCRIPT exited 0, under $WANT alone
expect() {
  local got
  got="$(ran_under "$2")"
  if [[ $RC -eq 0 && "$got" == "$WANT " ]]; then
    pass "$1"
  elif [[ -z "$got" ]]; then
    fail "$1: scripts/$2 never ran (exit $RC)"; show
  elif [[ "$got" != "$WANT " ]]; then
    fail "$1: scripts/$2 ran under bash $got— wanted $WANT alone, with no re-exec (exit $RC)"; show
  else
    fail "$1: exit $RC"; show
  fi
}

# ── The cases ────────────────────────────────────────────────────────────────

cases() {
  local b=$1

  # Phase 1
  fresh_mac
  run "$b" "$R/scripts/setup" --dry-run
  expect "setup --dry-run runs every phase" setup
  has "Dry run complete" || { fail "setup --dry-run did not finish"; show; }

  fresh_mac
  run "$b" "$R/scripts/setup" --only tools
  expect "setup --only tools" setup
  if [[ "$(readlink "$H/bin/mrk-brew")" == "$R/scripts/brew" && "$(readlink "$H/bin/harden")" == "$R/scripts/hardening.sh" ]]; then
    pass "  and links the tools into ~/bin"
  else
    fail "  ~/bin/mrk-brew is '$(readlink "$H/bin/mrk-brew")', ~/bin/harden '$(readlink "$H/bin/harden")'"
  fi

  # bin/ with nothing to link leaves an array empty, which bash 3.2 calls
  # unbound under set -u
  fresh_mac
  mv "$R/bin" "$W/bin.saved" && mkdir -p "$R/bin"
  run "$b" "$R/scripts/setup" --only tools
  rm -rf "${R:?}/bin" && mv "$W/bin.saved" "$R/bin"
  expect "setup --only tools with nothing in bin/" setup
  if [[ "$(readlink "$H/bin/mrk-setup")" == "$R/scripts/setup" ]] && has "Setup complete."; then
    pass "  still links scripts/, and finishes"
  else
    fail "  ~/bin/mrk-setup is '$(readlink "$H/bin/mrk-setup")'"; show 4
  fi

  fresh_mac
  run "$b" "$R/scripts/setup" --only dotfiles
  expect "setup --only dotfiles" setup
  if [[ "$(readlink "$H/.zshrc")" == "$R/dotfiles/.zshrc" ]]; then
    pass "  and links the dotfiles into HOME"
  else
    fail "  ~/.zshrc is '$(readlink "$H/.zshrc")'"
  fi

  # Phase 2, on a new Mac
  fresh_mac
  run "$b" "$R/scripts/brew" --dry-run
  expect "brew --dry-run with no Homebrew" brew
  if has "Would run: /bin/bash -c" && has "Formulae: ${#FORMULAE[@]}" && [[ ! -e "$P/bin/brew" ]] \
     && ! grep -q '^brew ' "$W/calls"; then
    pass "  says it would install Homebrew, counts the Brewfile, and installs nothing"
  else
    fail "  the dry run:"; show
  fi

  fresh_mac
  run "$b" "$R/scripts/brew" --yes
  expect "brew --yes with no Homebrew" brew
  if grep -q 'Homebrew/install' "$W/calls" && [[ -x "$P/bin/brew" ]] && cmp -s "$W/bundled" "$R/Brewfile" \
     && grep -qxF "brew bundle --file=$R/Brewfile --no-upgrade --verbose" "$W/calls"; then
    pass "  installs Homebrew, then hands brew bundle the whole Brewfile"
  else
    fail "  calls:"; sed 's/^/      /' "$W/calls" >&2; show
  fi

  # The picker a new Mac has: gum, which Phase 2 installs itself, because
  # build-tools has not made mrk-picker yet.
  fresh_mac
  GUM_PICK="$F1 $F2 $C1" run "$b" --tty "$R/scripts/brew"
  expect "brew with no Homebrew, choosing with gum" brew
  if grep -qxF 'brew install gum' "$W/calls" && bundled_ok "$F1" "$F2" "$C1"; then
    pass "  installs gum, and bundles the Brewfile's taps and the three packages chosen"
  else
    fail "  bundled:"; sed 's/^/      /' "$W/bundled" 2>/dev/null | grep -E '^ *(brew|cask) ' >&2; show
  fi
  local labels desc
  labels="$(wc -l < "$W/gum-labels" 2>/dev/null | tr -d ' ')"
  desc="$(desc_of "$F1")"
  if [[ "$labels" == "$(( ${#FORMULAE[@]} + ${#CASKS[@]} ))" ]] && [[ -n "$desc" ]] \
     && grep -qxF "$F1 — $desc" "$W/gum-labels"; then
    pass "  offers every package, each with its description from main.go"
  else
    fail "  gum was offered $labels labels; $F1's: $(grep -F "$F1" "$W/gum-labels" 2>/dev/null | head -1)"
  fi

  # Phase 2 on a Mac with Homebrew, with mrk-picker built
  with_homebrew
  cp -p "$TPL/mrk-picker" "$R/bin/mrk-picker"
  printf '%s\n' "$F1" > "$W/installed-formulae"
  printf '%s\n' "$C2" > "$W/installed-casks"
  PICKER_OUT="formula:$F1 formula:$F2 cask:$C1" run "$b" --tty "$R/scripts/brew"
  expect "brew with Homebrew, choosing with mrk-picker" brew
  if bundled_ok "$F2" "$C1" && has "Formula '$F1' is already installed, skipping installation" \
     && ! grep -q 'Homebrew/install' "$W/calls"; then
    pass "  bundles what was chosen, less what is installed"
  else
    fail "  bundled:"; grep -E '^(brew|cask) ' "$W/bundled" 2>/dev/null | sed 's/^/      /' >&2; show
  fi
  if [[ "$(grep -A1 -x -- --installed-formulae "$W/picker-args" | tail -1)" == "$F1" \
        && "$(grep -A1 -x -- --installed-casks "$W/picker-args" | tail -1)" == "$C2" ]]; then
    pass "  tells mrk-picker what is installed"
  else
    fail "  mrk-picker was given: $(tr '\n' ' ' < "$W/picker-args" 2>/dev/null)"
  fi

  # --no-formulae leaves the formulae empty, which bash 3.2 calls unbound
  with_homebrew
  cp -p "$TPL/mrk-picker" "$R/bin/mrk-picker"
  PICKER_OUT="cask:$C1" run "$b" --tty "$R/scripts/brew" --no-formulae
  expect "brew --no-formulae, choosing with mrk-picker" brew
  if bundled_ok "$C1" && grep -qx -- --skip-formulae "$W/picker-args"; then
    pass "  bundles the one cask chosen"
  else
    fail "  --no-formulae:"; show
  fi

  # Everything installed: no picker at all
  with_homebrew
  cp -p "$TPL/mrk-picker" "$R/bin/mrk-picker"
  printf '%s\n' "${FORMULAE[@]}" > "$W/installed-formulae"
  printf '%s\n' "${CASKS[@]}" > "$W/installed-casks"
  run "$b" --tty "$R/scripts/brew"
  expect "brew with everything installed" brew
  if has "All packages already installed" && [[ ! -e "$W/picker-args" ]] && bundled_ok; then
    pass "  skips the picker, and bundles no package"
  else
    fail "  everything installed:"; show
  fi

  # An abort must fail the run. Under bash 3.2 a `set -u` abort runs the EXIT
  # trap with $? at 0, and the script exits 0 unless its trap corrects that, so
  # make all would carry on as though the phase had succeeded.
  local s
  for s in setup brew; do
    fresh_mac
    run "$b" "$A/scripts/$s" --dry-run
    if [[ $RC -ne 0 ]] && has "mrk_planted_unbound: unbound variable"; then
      pass "$s, aborted by an unbound variable, exits $RC"
    else
      fail "$s, aborted by an unbound variable, exits $RC"; show 4
    fi
  done

  # The audit's reproduction: through make, as the README and the manual run it
  fresh_mac
  run "$b" make --no-print-directory -C "$R" setup ARGS=--dry-run
  expect "make setup ARGS=--dry-run with no Homebrew" setup
  fresh_mac
  run "$b" make --no-print-directory -C "$R" brew ARGS=--dry-run
  expect "make brew ARGS=--dry-run with no Homebrew" brew
}

# Under /bin/bash, as on a new Mac, and then under the bash running this test
# when that is another one, as on a Mac with Homebrew's bash on its PATH.
EMPTY="$W/no-bash"
mkdir -p "$EMPTY"
WANT="$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"')"
printf '  under /bin/bash %s, no Homebrew bash on PATH\n' "$WANT"
cases "$EMPTY"
if [[ ! "$BASH" -ef /bin/bash ]]; then
  mkdir -p "$W/bash-newer"
  ln -s "$BASH" "$W/bash-newer/bash"
  WANT="${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"
  printf '  under %s %s\n' "$BASH" "$WANT"
  cases "$W/bash-newer"
fi

# A static guard for the scripts a new Mac runs before Homebrew's bash can be
# on PATH: make all's phases, what they source, and what post-install runs with
# `bash`. The runs above cover setup and brew; this covers the rest, and the
# paths through setup and brew no case reaches. Not every bash-4 construct:
# the ones this repository has used, and the commonest others.
bash4='(declare|local|typeset)[[:space:]]+-[a-zA-Z]*[An]|\$\{[A-Za-z_][A-Za-z0-9_]*(\[[^]]*\])?(,|\^)|(^|[^A-Za-z0-9_-])(mapfile|readarray|coproc)([^A-Za-z0-9_-]|$)|\[-[0-9]+\]\}|;;&|&>>|\$\{[^}]*@[QEPAaKk]\}'
# From the repository root, so the relative names resolve there (audit 17,
# V-2a), and a file that cannot be read fails the guard rather than passing it.
hits="$(cd "$REPO_ROOT" && grep -nE "$bash4" scripts/setup scripts/brew scripts/lib.sh scripts/fix-exec \
          scripts/defaults.sh scripts/post-install scripts/install scripts/install-apps scripts/pull-prefs \
          assets/preferences/*.sh assets/browsers/*.sh)"
rc=$?
hits="$(printf '%s\n' "$hits" | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | grep -v '^$')"
if (( rc > 1 )); then
  fail "the bash-4 guard could not read every script it names (grep exit $rc)"
elif [[ -z "$hits" ]]; then
  pass "no bash-4 syntax in the scripts a new Mac runs under /bin/bash"
else
  fail "bash-4 syntax in a script a new Mac runs under /bin/bash:"
  printf '%s\n' "$hits" | sed 's/^/      /' >&2
fi

(( fails == 0 ))
