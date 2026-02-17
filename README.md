# mrk — macOS bootstrap

Opinionated, idempotent macOS setup in three phases.

## Quick Start

```bash
git clone https://github.com/sevmorris/mrk.git ~/mrk
cd ~/mrk
make install
make brew
make post-install
exec zsh
```

## Phases

| Phase | Command | What it does |
|-------|---------|--------------|
| **1 — Setup** | `make install` | Xcode CLI tools, dotfile symlinks, tool linking, macOS defaults, login shell |
| **2 — Brew** | `make brew` | Installs Homebrew, then interactively selects formulae & casks from `Brewfile` |
| **3 — Post-install** | `make post-install` | App preferences, browser policies, login items |

Run `make all` to execute all three phases at once. Phases are independent — run any subset, in any order, as many times as you want.

## Make Targets

| Target | Description |
|--------|-------------|
| `make install` / `make setup` | Phase 1 (setup) |
| `make brew` | Phase 2 (Homebrew) |
| `make post-install` | Phase 3 (app config) |
| `make all` | All three phases |
| `make tools` | Link scripts into `~/bin` only |
| `make dotfiles` | Symlink dotfiles only |
| `make defaults` | Apply macOS defaults only |
| `make trackpad` | Apply defaults including trackpad gestures |
| `make harden` | Security hardening (Touch ID sudo, firewall) |
| `make status` | Show installation status |
| `make doctor` | Run `brew doctor` |
| `make update` | Update via topgrade (or brew) |
| `make updates` | Install macOS software updates |
| `make uninstall` | Remove symlinks, optionally rollback defaults |
| `make fix-exec` | Fix executable permissions on scripts |

## Philosophy

Setup is split into phases so you can:

- Run Phase 1 on a fresh Mac before Homebrew is even available
- Selectively install only the Homebrew packages you want (Phase 2 is interactive)
- Re-run any phase independently without side effects

State lives in `~/.mrk`. Rollback scripts are generated automatically for defaults changes.

## Structure

```
mrk/
├── Makefile          # All targets
├── Brewfile          # Homebrew packages
├── dotfiles/         # Symlinked to ~/
├── bin/              # Extra scripts linked to ~/bin
├── assets/           # App configs, browser policies
│   ├── browsers/
│   ├── preferences/
│   └── topgrade.toml
└── scripts/
    ├── lib.sh        # Shared helpers
    ├── install       # Unified entrypoint (dispatches to phases)
    ├── setup         # Phase 1
    ├── brew          # Phase 2
    ├── post-install  # Phase 3
    ├── status        # Installation status
    ├── defaults.sh   # macOS defaults
    ├── hardening.sh  # Security hardening
    ├── uninstall     # Conservative uninstaller
    └── ...           # doctor, syncall, check-updates, etc.
```

## License

MIT — Seven Morris

---

*Merged from [mrk1](https://github.com/sevmorris/mrk1) + [mrk2](https://github.com/sevmorris/mrk2).*
