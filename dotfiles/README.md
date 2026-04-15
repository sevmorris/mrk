# Dotfiles

Files in this directory are symlinked into `$HOME` by `make setup`.

- Files are linked as-is (`.zshrc` → `~/.zshrc`, etc.)
- Any existing file at the destination is backed up to `~/.mrk/backups/TIMESTAMP/` before being replaced
- Safe to re-run — already-correct symlinks are skipped
- `.example` and `README` files in this directory are not linked
