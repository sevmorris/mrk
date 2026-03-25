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
# Add user-specific and Python paths. Homebrew path is set in .zprofile.

path=(
  "$HOME/bin"
  "$HOME/.local/bin"
  $path
)

# Add latest python.org version to PATH, if present
PYTHON_FRAMEWORK_DIR="/Library/Frameworks/Python.framework/Versions"
if [[ -d "$PYTHON_FRAMEWORK_DIR" ]]; then
  LATEST_PYTHON_VERSION=$(ls "$PYTHON_FRAMEWORK_DIR" | sort -V | tail -n 1)
  LATEST_PYTHON_PATH="$PYTHON_FRAMEWORK_DIR/$LATEST_PYTHON_VERSION"
  if [[ -d "$LATEST_PYTHON_PATH/bin" ]]; then
    path=("$LATEST_PYTHON_PATH/bin" $path)
  fi
fi

# Remove duplicate path entries
typeset -U path

# --- Source Personal Aliases ---
[[ -f "$HOME/.aliases" ]] && source "$HOME/.aliases"

# --- NVM (prefers Homebrew) ---
export NVM_DIR="$HOME/.nvm"

if [ -s "/opt/homebrew/opt/nvm/nvm.sh" ]; then
  . "/opt/homebrew/opt/nvm/nvm.sh"
  [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && . "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"
elif [ -s "$NVM_DIR/nvm.sh" ]; then
  . "$NVM_DIR/nvm.sh"
  [ -s "$NVM_DIR/bash_completion" ] && . "$NVM_DIR/bash_completion"
fi

# --- mrk Update Check (weekly) ---
[[ -x "$HOME/bin/check-updates" ]] && "$HOME/bin/check-updates"

# --- Shell Welcome ---
command -v fastfetch >/dev/null 2>&1 && fastfetch

# OpenClaw Completion
source "$HOME/.openclaw/completions/openclaw.zsh"
