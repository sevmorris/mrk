# ==============================================================================
#  .zshrc — Sourced for INTERACTIVE shells
#  Maintainer: Seven Morris
#  Rev: 2025-10-19
# ==============================================================================

# --- Oh My Zsh (OMZ) Configuration ---
export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="bira"
zstyle ':omz:update' mode auto
COMPLETION_WAITING_DOTS="true"
plugins=(git zsh-autosuggestions zsh-syntax-highlighting z colored-man-pages command-not-found gh)

# Load Oh My Zsh
source "$ZSH/oh-my-zsh.sh"

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
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# --- mrk Update Check (weekly) ---
[[ -x "$HOME/bin/check-updates" ]] && "$HOME/bin/check-updates" || true

# --- Shell Welcome ---
command -v fastfetch >/dev/null 2>&1 && fastfetch
