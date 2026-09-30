# ==============================================================================
#  .zshrc — Sourced for INTERACTIVE shells
#  Maintainer: Seven Morris
# ==============================================================================

# --- Oh My Zsh (OMZ) Configuration ---
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="bira"
zstyle ':omz:update' mode auto
COMPLETION_WAITING_DOTS="true"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting z colored-man-pages command-not-found gh)

# Load Oh My Zsh (guarded: a hard failure here would abort the rest of .zshrc)
if [[ -f "$ZSH/oh-my-zsh.sh" ]]; then
  source "$ZSH/oh-my-zsh.sh"
else
  echo "mrk: oh-my-zsh not found at $ZSH — install it before sourcing .zshrc" >&2
fi

# --- PATH Customization ---
# Add user-specific paths. Homebrew and GNU coreutils gnubin are set in .zprofile.

path=(
  "$HOME/bin"
  "$HOME/.local/bin"
  $path
)

# Remove duplicate path entries
typeset -U path

# --- pyenv (Python version manager; pin in ~/mrk/.python-version) ---
export PYENV_ROOT="${PYENV_ROOT:-$HOME/.pyenv}"
[[ -d "$PYENV_ROOT/bin" ]] && path=("$PYENV_ROOT/bin" $path)
if command -v pyenv >/dev/null 2>&1; then
  eval "$(pyenv init - zsh)"
fi

# --- Source Personal Aliases ---
[[ -f "$HOME/.aliases" ]] && source "$HOME/.aliases"

# --- NVM ---
# nvm.sh ends with `nvm use default`, which took about 220 of the 250 ms it cost
# every shell (measured 2026-09-28; 29 ms with --no-use). So nvm loads with
# --no-use, and the newest installed Node that matches the default alias goes on
# PATH directly: v24 finds v24.21.0 before v24.9.0. An alias no installed
# version matches this way (lts/*, node, a bare number) falls back to nvm's own
# `nvm use`. Lazy-loading was the other option, and it keeps node off PATH for
# anything a shell starts until node is first typed.
export NVM_DIR="$HOME/.nvm"
if [ -s "$NVM_DIR/nvm.sh" ]; then
  \. "$NVM_DIR/nvm.sh" --no-use
  _nvm_node=()
  [[ -r "$NVM_DIR/alias/default" ]] \
    && _nvm_node=( "$NVM_DIR/versions/node/$(<"$NVM_DIR/alias/default")"*(N/nOn) )
  if (( ${#_nvm_node} )); then
    path=("${_nvm_node[1]}/bin" $path)
  else
    nvm use default --silent >/dev/null 2>&1
  fi
  unset _nvm_node
fi
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# --- mrk Update Check (every shell; fetches at most daily) ---
[[ -x "$HOME/bin/check-updates" ]] && "$HOME/bin/check-updates" || true

# --- Shell Welcome ---
command -v fastfetch >/dev/null 2>&1 && fastfetch
