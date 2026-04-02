# Dotfiles

This directory contains dotfiles that will be symlinked to your home directory.

## Usage

1. Add your dotfiles to this directory (e.g., `.zshrc`, `.gitconfig`, `.vimrc`)
2. Run `./scripts/install` or `make install`
3. Existing files will be backed up automatically

## Notes

- Files starting with `.` will be linked as-is (e.g., `.zshrc` → `~/.zshrc`)
- Backups are stored in `~/.mrk/backups/TIMESTAMP/`
- The installer is idempotent - safe to run multiple times

