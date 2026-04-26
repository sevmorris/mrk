# mrk — macOS bootstrap

Personal, opinionated macOS bootstrap tailored to my workflow and toolset. Idempotent setup in three phases.

**[Full workflow manual →](docs/manual.md)** · **[macOS defaults reference →](https://sevmorris.github.io/mrk/defaults/)** · **[~/bin command reference →](https://sevmorris.github.io/mrk/bin/mrk-usage.html)**

## Quick Start

```bash
git clone https://github.com/sevmorris/mrk.git ~/mrk
make -C ~/mrk all
exec zsh
```

## Quick Start (fun version)

```bash
git clone https://github.com/sevmorris/mrk.git ~/mrk
make -C ~/mrk adventure
exec zsh
```

Boots a fictional 4.3BSD Unix workstation at UC Berkeley, 1989. Find the floppy, run the setup script, and the real install begins.

## Phases

| Phase | Command | What it does |
|-------|---------|--------------|
| **1 — Setup** | `make setup` | Xcode CLI tools, dotfile symlinks, tool linking, macOS defaults, login shell |
| **2 — Brew** | `make brew` | Installs Homebrew, then interactively selects formulae & casks from `Brewfile` |
| **3 — Post-install** | `make post-install` | App preferences, browser policies, login items |

Run `make all` to execute all three phases at once. On a fresh machine, run Phase 1 first — it installs Xcode CLI tools and the login shell that later phases depend on. After that, Phases 2 and 3 can run in either order or together. On an already-configured machine all phases can be re-run freely in any order.

## Make Targets

**Install**

| Target | Description |
|--------|-------------|
| `make all` | All three phases + build TUI binaries |
| `make adventure` | Same as `make all` but with a fictional 4.3BSD terminal prelude |
| `make install` / `make setup` | Phase 1 only |
| `make setup-dry` | Preview Phase 1 changes without applying |
| `make brew` | Phase 2 only |
| `make post-install` | Phase 3 only |

**Partial phases**

| Target | Description |
|--------|-------------|
| `make dotfiles` | Symlink dotfiles only |
| `make tools` | Link scripts into `~/bin` only |
| `make defaults` | Apply macOS defaults only |
| `make trackpad` | Apply defaults including trackpad gestures |
| `make harden` | Security hardening (Touch ID sudo, firewall) |
| `make dock` | Populate the Dock with preferred apps |

**Maintenance**

| Target | Description |
|--------|-------------|
| `make sync` | Snapshot installed Homebrew packages into the Brewfile |
| `make sync-login-items` | Sync system login items into post-install and docs |
| `make snapshot-prefs` | Export app preferences and push to mrk-prefs |
| `make pull-prefs` | Clone or pull app preferences from mrk-prefs |
| `make update` | Update via topgrade (or brew) |
| `make updates` | Install macOS software updates |

**Diagnostics & tools**

| Target | Description |
|--------|-------------|
| `make status` | Open the mrk-status TUI health dashboard |
| `make doctor` | Check `~/bin` is on PATH; `make doctor ARGS=--fix` adds it to `.zshrc` |
| `make build-tools` | Build all Go TUI binaries (picker + bf + mrk-status) |
| `make picker` | Build mrk-picker only |
| `make bf` | Build bf Brewfile manager only |
| `make mrk-status` | Build mrk-status TUI health dashboard |
| `make uninstall` | Remove symlinks, optionally rollback defaults |
| `make fix-exec` | Fix executable permissions on scripts |

## Philosophy

Setup is split into phases so you can:

- Run Phase 1 on a fresh Mac before Homebrew is even available
- Selectively install only the Homebrew packages you want (Phase 2 is interactive)
- Re-run any phase independently — `make defaults` restarts Finder, Dock, and SystemUIServer to apply changes, which is visible but harmless

mrk's bookkeeping (rollback scripts, backups) lives in `~/.mrk`. Configuration changes are written to their canonical macOS locations — system preferences via `defaults`, app symlinks in `~/bin`, and so on. Rollback scripts are generated automatically for defaults and hardening changes.

## Barkeep

**[Barkeep](https://github.com/sevmorris/Barkeep)** is a native macOS app for visually managing your Homebrew Brewfile. It's a companion app to mrk and is installed automatically by `make post-install`.

## License

MIT — Seven Morris

---

*Merged from [mrk1](https://github.com/sevmorris/mrk1) + [mrk2](https://github.com/sevmorris/mrk2).*
