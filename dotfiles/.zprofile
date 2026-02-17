# ==============================================================================
#  .zprofile — Sourced for LOGIN shells (before .zshrc)
#  Maintainer: Seven Morris
# ==============================================================================

# --- Homebrew Environment (Apple Silicon first, then Intel) ---
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# --- Ensure ~/.local/bin is on PATH (idempotent) ---
if [ -d "$HOME/.local/bin" ]; then
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac
fi
