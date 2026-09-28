#!/usr/bin/env bash
# setup-safety.sh — prove that setup and post-install link into ~ only from the
# checkout ~ is linked to, link only real dotfiles, change nothing in a dry
# run, and replace a dangling topgrade link. Audit 19, W-4, W-5, W-7, W-11.
#
# Until 2026-09-27:
# - W-5: run from any checkout, a worktree say, setup linked ~/bin and every
#   dotfile into it, and post-install four more paths. Removing the worktree
#   left them all dangling, and a new shell started without .zshrc.
# - W-11: post-install then failed on every run, because its topgrade step
#   could not replace a dangling link.
# - W-4: setup linked whatever sat in dotfiles/. The dotfiles/.claude/ Claude
#   Code creates moved the real ~/.claude, settings, sessions and memory, into
#   ~/.mrk/backups, and ~/.DS_Store became a link.
# - W-7: `setup --dry-run` opened the Command Line Tools installer, ran
#   `sudo xcodebuild -license accept`, registered a shell in /etc/shells, ran
#   chsh, and made ~/.mrk, ~/bin and install.log.
#
# Every run is on a copy of the repository, under a throwaway HOME, with
# `env -i` and PATH cut to stubs and the system directories. Every
# "/Applications/" in the copies points at a scratch folder. sudo, chsh, git,
# osascript, launchctl, open, topgrade, dscl, xcode-select, ssh and defaults are
# stubs that run nothing, /etc/shells is a scratch file (SHELLS_FILE), nvm is a
# stub with a default set, and scripts/install-apps is a no-op. Nothing reaches
# the real HOME, the network, the login shell, launchd or any preferences.
# setup and post-install run under /bin/bash and under the bash running this
# file. ci-check runs it.

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

[[ -x /usr/bin/jq ]] || { fail "/usr/bin/jq not found; post-install's session-hook step needs it"; exit 1; }

W=$(mrk_mktemp_d) || exit 1
W=$(cd "$W" && pwd -P)
trap 'rm -rf "$W"' EXIT
R="$W/repo"     # the copy of the repository
H="$W/home"     # the throwaway HOME
S="$W/stubs"    # first on PATH
APPS="$W/Applications"
mkdir -p "$R" "$S" "$APPS" "$W/tmp"

# ── The repository copy ──────────────────────────────────────────────────────

while IFS= read -r -d '' f; do
  [[ -f "$REPO_ROOT/$f" ]] || continue
  mkdir -p "$R/$(dirname "$f")"
  cp -p "$REPO_ROOT/$f" "$R/$f"
done < <(git -C "$REPO_ROOT" ls-files -z scripts bin dotfiles assets Makefile)
cat > "$R/scripts/install-apps" <<'EOF'
#!/usr/bin/env bash
install_companion_apps() { COMPANION_FAILED=0; }
EOF
for f in "$R/scripts/setup" "$R/scripts/post-install" "$R"/assets/*/*.sh; do
  sed "s#/Applications/#$APPS/#g" "$f" > "$W/rewrite" && cat "$W/rewrite" > "$f"
done
if grep -n '/Applications/' "$R/scripts/setup" "$R/scripts/post-install" "$R"/assets/*/*.sh | grep -vF "$APPS/"; then
  fail "a real /Applications path survived the rewrite — refusing to run"
  exit 1
fi

# The dotfiles setup should link: what the repository tracks, less its README
TRACKED=()
while IFS= read -r f; do
  case "$f" in README*|*.md|*.example) ;; *) TRACKED+=("$f") ;; esac
done < <(git -C "$REPO_ROOT" ls-files dotfiles | sed 's#^dotfiles/##' | grep -v /)
(( ${#TRACKED[@]} >= 3 )) || { fail "found ${#TRACKED[@]} tracked dotfiles; expected more"; exit 1; }

# ── Stubs ────────────────────────────────────────────────────────────────────

# Each records its command line in $SANDBOX/calls and does nothing else.
cat > "$S/record" <<'EOF'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >> "$SANDBOX/calls"
EOF
chmod +x "$S/record"
for cmd in sudo chsh git osascript launchctl open topgrade; do cp -p "$S/record" "$S/$cmd"; done
cat > "$S/defaults" <<'EOF'
#!/bin/bash
printf 'defaults %s\n' "$*" >> "$SANDBOX/calls"
exit 1
EOF
cat > "$S/ssh" <<'EOF'
#!/bin/bash
exit 255
EOF
cat > "$S/dscl" <<'EOF'
#!/bin/bash
echo "UserShell: ${LOGIN_SHELL:-/bin/zsh}"
EOF
cat > "$S/xcode-select" <<'EOF'
#!/bin/bash
printf 'xcode-select %s\n' "$*" >> "$SANDBOX/calls"
if [[ "${1:-}" == -p ]]; then
  [[ "${CLT_MISSING:-0}" == 1 ]] && exit 2
  echo /Library/Developer/CommandLineTools
fi
exit 0
EOF
chmod +x "$S"/*
ln -s "$BASH_UNDER_TEST" "$S/bash"

# ── Running a phase ──────────────────────────────────────────────────────────

# fresh_home — an empty HOME, no calls recorded, an empty /etc/shells
fresh_home() {
  rm -rf "$H" "${APPS:?}"/*
  mkdir -p "$H"
  : > "$W/calls"
  : > "$W/shells"
}
# for_post_install — what post-install's link steps need to find in HOME
for_post_install() {
  mkdir -p "$H/Projects" "$H/.claude" "$H/.nvm"
  # shellcheck disable=SC2016  # for nvm.sh to expand, not this shell
  printf 'nvm() { [[ "$1" == version ]] && echo v24.0.0; }\n' > "$H/.nvm/nvm.sh"
}

# run CMD ARGS... — CMD in a new Mac's environment. HOME_ROOT, when set, becomes
# MRK_ROOT. Output in $W/out, exit status in RC.
RC=0
run() {
  local env=(HOME="$H" USER="${USER:-$(id -un)}" LOGNAME="${USER:-$(id -un)}" TMPDIR="$W/tmp" TERM=dumb
             PATH="$S:/usr/bin:/bin:/usr/sbin:/sbin" SANDBOX="$W" SHELLS_FILE="$W/shells"
             LOGIN_SHELL="${LOGIN_SHELL:-/bin/zsh}" CLT_MISSING="${CLT_MISSING:-0}")
  [[ -n "${HOME_ROOT:-}" ]] && env+=(MRK_ROOT="$HOME_ROOT")
  env -i "${env[@]}" "$S/bash" "$@" </dev/null > "$W/out" 2>&1
  RC=$?
}
has()   { grep -qF -- "$1" "$W/out"; }
show()  { sed 's/^/      /' "$W/out" | tail -"${1:-12}" >&2; }
# links_into_repo — every symlink under HOME that points into the copy
links_into_repo() {
  local l
  find "$H" -type l 2>/dev/null | while IFS= read -r l; do
    [[ "$(readlink "$l")" == "$R"/* ]] && printf '%s\n' "${l#"$H"/}"
  done
}
POST_LINKS=(".config/topgrade.toml" "Projects/CLAUDE.md" "Projects/.claude/skills" ".claude/skills/dependency-updates")
POST_SRCS=("assets/topgrade.toml" "assets/CLAUDE.md" "assets/projects-skills" "assets/projects-skills/dependency-updates")

# ── W-5: setup from a checkout ~ is not linked to ────────────────────────────

fresh_home
run "$R/scripts/setup" --only tools;    rc_tools=$RC
has "not linked: ~ is linked to $H/mrk, not this checkout"; said_tools=$?
run "$R/scripts/setup" --only dotfiles; rc_dots=$RC
has "not linked: ~ is linked to $H/mrk, not this checkout"; said_dots=$?
run "$R/scripts/setup" --dry-run;       rc_dry=$RC
leaked="$(links_into_repo | tr '\n' ' ')"
if [[ -z "$leaked" && $rc_tools$rc_dots$rc_dry == 000 && $said_tools$said_dots == 00 ]] && ! has "Would link"; then
  pass "setup from another checkout: links nothing into ~, says why, and exits 0"
else
  fail "setup from another checkout (exits $rc_tools $rc_dots $rc_dry): linked ${leaked:-nothing}"; show
fi

# ── W-5: setup from the checkout ~ is linked to ──────────────────────────────

fresh_home
HOME_ROOT="$R" run "$R/scripts/setup" --only tools; rc_tools=$RC
HOME_ROOT="$R" run "$R/scripts/setup" --only dotfiles; rc_dots=$RC
if [[ $rc_tools$rc_dots == 00 && "$(readlink "$H/bin/mrk-setup")" == "$R/scripts/setup" \
      && "$(readlink "$H/.zshrc")" == "$R/dotfiles/.zshrc" ]]; then
  pass "setup with MRK_ROOT naming the checkout: links ~/bin and the dotfiles"
else
  fail "setup with MRK_ROOT: ~/bin/mrk-setup is '$(readlink "$H/bin/mrk-setup")', ~/.zshrc '$(readlink "$H/.zshrc")'"; show
fi

fresh_home
ln -s "$R" "$H/mrk"
run "$R/scripts/setup" --only dotfiles
if [[ $RC == 0 && "$(readlink "$H/.zshrc")" == "$R/dotfiles/.zshrc" ]]; then
  pass "setup with ~/mrk a symlink to the checkout: links the dotfiles"
else
  fail "setup with ~/mrk a symlink: ~/.zshrc is '$(readlink "$H/.zshrc")' (exit $RC)"; show
fi

# ── W-4: only real dotfiles are linked ───────────────────────────────────────

fresh_home
mkdir -p "$R/dotfiles/.claude" "$H/.claude/projects"
echo '{"local": true}' > "$R/dotfiles/.claude/settings.local.json"
echo x > "$R/dotfiles/.DS_Store"
echo '{"real": true}' > "$H/.claude/settings.json"
HOME_ROOT="$R" run "$R/scripts/setup" --only dotfiles
missing=""
for n in "${TRACKED[@]}"; do
  [[ "$(readlink "$H/$n")" == "$R/dotfiles/$n" ]] || missing="$missing $n"
done
if [[ $RC == 0 && -z "$missing" && ! -L "$H/.claude" && -f "$H/.claude/settings.json" \
      && ! -e "$H/.DS_Store" && ! -L "$H/.DS_Store" && ! -e "$H/.mrk/backups" ]]; then
  pass "dotfiles/.claude/ and .DS_Store: not linked, ~/.claude untouched, the ${#TRACKED[@]} tracked dotfiles linked"
else
  fail "dotfiles: unlinked:${missing:- none}; ~/.claude is $(/usr/bin/stat -f %HT "$H/.claude" 2>/dev/null); ~/.DS_Store $([[ -e "$H/.DS_Store" || -L "$H/.DS_Store" ]] && echo exists || echo absent)"
  show
fi

# status reads the same rule: the planted two are neither linked nor missing
HOME_ROOT="$R" run "$R/scripts/status"
dots_section="$(sed -n '/^Dotfiles:/,/^$/p' "$W/out")"
if grep -q "All dotfiles linked" <<<"$dots_section" && ! grep -qE '\.claude|\.DS_Store' <<<"$dots_section"; then
  pass "status agrees: all dotfiles linked, neither .claude nor .DS_Store reported"
else
  fail "status's Dotfiles section:"; printf '      %s\n' "$dots_section" >&2
fi
rm -rf "$R/dotfiles/.claude" "$R/dotfiles/.DS_Store"

# ── W-7: a dry run changes nothing ───────────────────────────────────────────

# A new Mac: no Command Line Tools, Xcode.app present, and a login shell that
# is not the zsh on PATH, so every phase has something it would do.
fresh_home
mkdir -p "$APPS/Xcode.app"
HOME_ROOT="$R" LOGIN_SHELL=/opt/homebrew/bin/zsh CLT_MISSING=1 run "$R/scripts/setup" --dry-run
made="$(cd "$H" && find . -mindepth 1 | head -5 | tr '\n' ' ')"
acted="$(grep -vE '^xcode-select -p' "$W/calls" | tr '\n' ';')"
if [[ $RC == 0 && -z "$made" && -z "$acted" && ! -s "$W/shells" ]]; then
  pass "setup --dry-run on a new Mac: no file, no sudo, no chsh, no installer, no /etc/shells line"
else
  fail "setup --dry-run (exit $RC) made: ${made:-nothing}; ran: ${acted:-nothing}; /etc/shells: $(tr '\n' ' ' < "$W/shells")"
  show
fi
said=""
for m in "Would open the Xcode Command Line Tools installer" "Would accept the Xcode licence" \
         "Would set login shell to" "Would link ${#TRACKED[@]} dotfile(s)" "tool(s) into $H/bin"; do
  has "$m" || said="$said; $m"
done
if [[ -z "$said" ]] && ! grep -qE 'Linked [0-9]+ (tool|dotfile)' "$W/out"; then
  pass "  and says what it would do, never \"Linked\""
else
  fail "  the dry run's report is missing:${said#;}"; show 20
fi

# ── W-5: post-install from a checkout ~ is not linked to ─────────────────────

fresh_home
for_post_install
run "$R/scripts/post-install" --yes
made=""
for l in "${POST_LINKS[@]}"; do
  [[ -e "$H/$l" || -L "$H/$l" ]] && made="$made $l"
done
if [[ $RC == 0 && -z "$made" ]] && has "Links into ~ skipped"; then
  pass "post-install from another checkout: none of its ${#POST_LINKS[@]} links made, and exits 0"
else
  fail "post-install from another checkout (exit $RC) made:${made:- nothing}"; show
fi

# ── W-11 and W-5: post-install from the checkout ~ is linked to ──────────────

fresh_home
for_post_install
mkdir -p "$H/.config"
ln -s "$W/removed-worktree/assets/topgrade.toml" "$H/.config/topgrade.toml"
HOME_ROOT="$R" run "$R/scripts/post-install" --yes
wrong=""
for i in "${!POST_LINKS[@]}"; do
  [[ "$(readlink "$H/${POST_LINKS[$i]}")" == "$R/${POST_SRCS[$i]}" ]] || wrong="$wrong ${POST_LINKS[$i]}"
done
if [[ $RC == 0 && -z "$wrong" ]]; then
  pass "post-install with MRK_ROOT: all ${#POST_LINKS[@]} links made, the dangling topgrade link replaced, exit 0"
else
  fail "post-install with MRK_ROOT (exit $RC): wrong or missing:${wrong:- none}"; show
fi

rm -f "$H/.config/topgrade.toml"
echo "mine" > "$H/.config/topgrade.toml"
HOME_ROOT="$R" run "$R/scripts/post-install" --yes
if [[ $RC == 0 && "$(readlink "$H/.config/topgrade.toml")" == "$R/assets/topgrade.toml" \
      && "$(cat "$H/.config/topgrade.toml.bak" 2>/dev/null)" == mine ]]; then
  pass "  and a real topgrade.toml is kept as .bak before the link replaces it"
else
  fail "  a real topgrade.toml (exit $RC): link '$(readlink "$H/.config/topgrade.toml")', .bak '$(cat "$H/.config/topgrade.toml.bak" 2>/dev/null)'"
  show
fi

(( fails == 0 ))
