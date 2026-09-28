#!/usr/bin/env bash
# zshrc-nvm.sh — hold .zshrc's nvm block to what it promises. Audit 18.
#
# Until 2026-09-28 .zshrc sourced nvm.sh plainly, and nvm.sh's closing
# `nvm use default` took about 220 of the 250 ms it cost every shell. The block
# now loads nvm with --no-use and puts the newest installed Node matching the
# default alias on PATH itself, falling back to `nvm use` only when no installed
# version matches that way.
#
# The block is cut out of dotfiles/.zshrc between its "# --- NVM ---" and
# "# --- mrk Update Check" comments and run in `zsh -f` under a throwaway HOME,
# whose ~/.nvm holds empty version folders and a stub nvm.sh that records how
# it was sourced and each `nvm` call. The real ~/.nvm is never read. It runs
# under /bin/zsh and, when it is a different binary, the zsh on PATH. ci-check
# runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

W=$(mrk_mktemp_d) || exit 1
W=$(cd "$W" && pwd -P)
trap 'rm -rf "$W"' EXIT
H="$W/home"

sed -n '/^# --- NVM ---$/,/^# --- mrk Update Check/p' "$REPO_ROOT/dotfiles/.zshrc" \
  | sed '$d' > "$W/nvm-block.zsh"
if ! grep -q 'NVM_DIR' "$W/nvm-block.zsh"; then
  fail "could not cut the nvm block out of dotfiles/.zshrc"
  exit 1
fi

# nvm_home ALIAS VERSION... — a HOME whose ~/.nvm has those versions and that
# default alias. An empty ALIAS writes no alias file.
nvm_home() {
  local alias=$1 v; shift
  rm -rf "$H"; mkdir -p "$H/.nvm/versions/node" "$H/.nvm/alias"
  for v in "$@"; do mkdir -p "$H/.nvm/versions/node/$v/bin"; done
  [[ -n "$alias" ]] && printf '%s\n' "$alias" > "$H/.nvm/alias/default"
  cat > "$H/.nvm/nvm.sh" <<'EOF'
print -r -- "sourced $*" >> "$HOME/calls"
nvm() { print -r -- "nvm $*" >> "$HOME/calls"; }
EOF
  : > "$H/calls"
}
# run ZSH — the block in a bare zsh; prints PATH's first entry
run() {
  # shellcheck disable=SC2016  # expanded by zsh, not by this shell
  env -i HOME="$H" PATH=/usr/bin:/bin "$1" -f -c \
    'typeset -U path; source "$1"; print -r -- "${path[1]}"' zsh "$W/nvm-block.zsh" \
    > "$W/out" 2>&1
  RC=$?
  FIRST=$(tail -1 "$W/out")
}

ZSHES=(/bin/zsh)
other=$(command -v zsh 2>/dev/null || true)
[[ -n "$other" && ! "$other" -ef /bin/zsh ]] && ZSHES+=("$other")

for z in "${ZSHES[@]}"; do
  # shellcheck disable=SC2016  # expanded by zsh, not by this shell
  printf '  under %s %s\n' "$z" "$("$z" -f -c 'print -r -- $ZSH_VERSION')"

  nvm_home v24 v22.12.0 v24.9.0 v24.21.0
  touch "$H/.nvm/versions/node/v24.99.0"    # a file, not an installed version
  run "$z"
  if [[ $RC == 0 && "$FIRST" == "$H/.nvm/versions/node/v24.21.0/bin" ]] \
     && grep -qx 'sourced --no-use' "$H/calls" && ! grep -q '^nvm ' "$H/calls"; then
    pass "alias v24: nvm loaded with --no-use, v24.21.0 first on PATH, no nvm use"
  else
    fail "alias v24 (exit $RC): PATH starts '$FIRST'; calls: $(tr '\n' ';' < "$H/calls")"
  fi

  for alias in 'lts/*' ''; do
    nvm_home "$alias" v24.21.0
    run "$z"
    if [[ $RC == 0 && "$FIRST" == /usr/bin ]] && grep -qx 'sourced --no-use' "$H/calls" \
       && grep -qx 'nvm use default --silent' "$H/calls"; then
      pass "alias '${alias:-none}': falls back to nvm use default"
    else
      fail "alias '${alias:-none}' (exit $RC): PATH starts '$FIRST'; calls: $(tr '\n' ';' < "$H/calls")"
    fi
  done

  nvm_home v24 v24.21.0
  rm "$H/.nvm/nvm.sh"
  run "$z"
  if [[ $RC == 0 && "$FIRST" == /usr/bin && ! -s "$H/calls" && "$(wc -l < "$W/out")" -eq 1 ]]; then
    pass "no nvm.sh: nothing loaded, PATH unchanged, nothing printed"
  else
    fail "no nvm.sh (exit $RC): PATH starts '$FIRST'; output: $(tr '\n' ';' < "$W/out")"
  fi
done

(( fails == 0 ))
