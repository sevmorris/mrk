# ==============================================================================
#  .zprofile — Sourced for LOGIN shells (before .zshrc)
#  Maintainer: Seven Morris
# ==============================================================================

# --- Homebrew Environment (Apple Silicon first, then Intel) ---
# NOTE: This block is also present in scripts/brew and scripts/setup.
# Keep them in sync if the Homebrew install paths change.
if [ -x /opt/homebrew/bin/brew ]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
elif [ -x /usr/local/bin/brew ]; then
  eval "$(/usr/local/bin/brew shellenv)"
fi

# GNU coreutils — prepend gnubin so ls/cat/sed use GNU names (see Brewfile coreutils comment)
if command -v brew >/dev/null 2>&1; then
  _coreutils_gnubin="$(brew --prefix coreutils 2>/dev/null)/libexec/gnubin"
  if [[ -d "$_coreutils_gnubin" ]]; then
    case ":${PATH}:" in
      *":${_coreutils_gnubin}:"*) ;;
      *) export PATH="${_coreutils_gnubin}:${PATH}" ;;
    esac
  fi
  unset _coreutils_gnubin
fi

# --- Ensure ~/.local/bin is on PATH (idempotent) ---
if [ -d "$HOME/.local/bin" ]; then
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac
fi
