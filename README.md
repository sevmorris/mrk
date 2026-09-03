# mrk — personal macOS setup, maintenance and migration

This is my own machine, written down. mrk sets up a Mac from a clean install in three
idempotent phases, keeps it in that state, and carries it to the next one. It is not a
framework and not a starting point — it installs my apps, my login items, my defaults,
and it pulls my private preferences repo.

**Read it, fork it, take the parts you like.** Running it unmodified will configure your
Mac to be mine. See [Adapting it](#adapting-it) if that is not what you want.

**[Full workflow manual →](docs/manual.md)** · **[macOS defaults reference →](https://sevmorris.github.io/mrk/defaults/)** · **[~/bin command reference →](https://sevmorris.github.io/mrk/bin/mrk-usage.html)**

[sevmac](https://sevmorris.github.io/sevmac/) is the companion guide — the same ground written as procedure rather than reference: a new-machine walkthrough, a [migration checklist](https://sevmorris.github.io/sevmac/#mrk-migration) covering the key material `mrk-prefs` deliberately never carries, and a [day-to-day command card](https://sevmorris.github.io/sevmac/daily.html). Like this repo, it documents one machine rather than a general recipe.

## Quick Start

For my machine, on a clean install:

```bash
git clone https://github.com/sevmorris/mrk.git ~/mrk
make -C ~/mrk all
exec zsh
```

On anyone else's, that clones a `mrk-prefs` you cannot read, adds eight login items you
did not choose, rearranges the Dock, and installs two apps of mine. Fork first — see
[Adapting it](#adapting-it).

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
| `make harden` | Security settings (Touch ID sudo, sleep password, firewall) plus the quarantine-prompt opt-out |
| `make dock` | Populate the Dock with preferred apps |

**Maintenance**

| Target | Description |
|--------|-------------|
| `make sync` | Snapshot installed Homebrew packages into the Brewfile. Add names to `~/.mrk/sync-ignore` (one per line) to permanently skip them. |
| `make sync-login-items` | Sync system login items into post-install and docs |
| `make snapshot-prefs` | Export app preferences and push to mrk-prefs |
| `make pull-prefs` | Clone or pull app preferences from mrk-prefs |
| `make update` | Update via topgrade (or brew) |
| `make updates` | Install macOS software updates |

**Diagnostics & tools**

| Target | Description |
|--------|-------------|
| `mrk-menu` | Open the hierarchical tool launcher |
| `make status` | Open the mrk-status TUI health dashboard |
| `make doctor` | Check `~/bin` is on PATH; `make doctor ARGS=--fix` adds it to `.zshrc` |
| `make build-tools` | Build all Go TUI binaries (mrk-picker + mrk-status + mrk-menu) |
| `make picker` | Build mrk-picker only |
| `make mrk-status` | Build mrk-status TUI health dashboard |
| `make mrk-menu` | Build mrk-menu TUI launcher |
| `make uninstall` | Remove symlinks, optionally rollback defaults |
| `make fix-exec` | Fix executable permissions on scripts |

## Adapting it

Everything below is mine and will not suit you. The scripts are the interesting part; the
data in them is not.

| What | Where | Why it is personal |
|---|---|---|
| Preferences repo | `PREFS_REPO` in `scripts/snapshot-prefs` | Points at `sevmorris/mrk-prefs`, which is private. Nothing else works until you repoint it. |
| Packages | `Brewfile` | My formulae and casks, with `##` section headers the sync tooling relies on. |
| Login items | `add_login_item` block in `scripts/post-install` | AlDente, BetterSnapTool, Chrono Plus, Dropbox, Ice, Raycast, SoundSource, Stats. |
| Snapshotted apps | `scripts/snapshot-prefs` | The 14 plist domains and the Application Support trees I care about. |
| Dock | `DOCK_APPS` in `scripts/dock-setup` | Wipes the Dock before it rebuilds it. |
| macOS defaults | `scripts/defaults.sh` | ~77 keys, each one a preference of mine. Documented in the [defaults reference](https://sevmorris.github.io/mrk/defaults/). |
| Companion apps | `install_github_app` in `scripts/post-install` | Installs Barkeep and KeyVault, both mine. |
| Dotfiles | `dotfiles/` | My shell, aliases and git config. |

`make setup-dry`, `make sync ARGS=-n` and `make snapshot-keys ARGS=-n` all preview without
writing, which is the cheapest way to see what a phase would do before it does it.

## Philosophy

Setup is split into phases so you can:

- Run Phase 1 on a fresh Mac before Homebrew is even available
- Selectively install only the Homebrew packages you want (Phase 2 is interactive)
- Re-run any phase independently — `make defaults` restarts Finder, Dock, and SystemUIServer to apply changes, which is visible but harmless

mrk's bookkeeping (rollback scripts, backups) lives in `~/.mrk`. Configuration changes are written to their canonical macOS locations — system preferences via `defaults`, app symlinks in `~/bin`, and so on. Rollback scripts are generated automatically for defaults and hardening changes.

## Companion apps

Two native macOS apps ship alongside mrk. `make post-install` installs both from their latest GitHub release.

- **[Barkeep](https://github.com/sevmorris/Barkeep)** — visually manage your Homebrew Brewfile, and adopt packages the Brewfile doesn't track yet.
- **[KeyVault](https://github.com/sevmorris/KeyVault)** — manage SSH keys, GPG keys, API keys, and secure notes. API keys and notes are KeyVault's own: they live in the login Keychain and back up to a passphrase-encrypted OpenPGP archive that plain `gpg` can read. SSH and GPG keys stay in `~/.ssh` and `~/.gnupg` — KeyVault reads and generates them, but never copies the private keys into the Keychain or the archive.

Both installs are one-shot: post-install skips an app that is already in `/Applications`, so it never overwrites a newer copy. To update, use the app itself, or delete it and re-run the phase.

### Moving keys to a new machine

`make snapshot-keys` bundles `~/.ssh`, `~/.gnupg` and your code-signing identities into one passphrase-encrypted OpenPGP archive; `make restore-keys ARGS=<archive>` puts them back, fixes the permissions, and imports the identities. The Developer ID private key is the one item here with no recovery path — Apple reissues a certificate, but never the key. The archive goes to a path you choose (`~/Desktop` by default) and is pushed nowhere — `mrk-prefs` is a git repo and never carries private keys. `snapshot-keys` refuses to write inside `~/mrk` or `~/.mrk`, since `nuke-mrk` deletes both.

That covers the key *files*. KeyVault's own export covers the secrets KeyVault owns — its API keys and notes, which live in the login Keychain. You need both archives for a complete transfer; neither contains the other's contents.

## License

MIT — Seven Morris

---

*Merged from [mrk1](https://github.com/sevmorris/mrk1) + [mrk2](https://github.com/sevmorris/mrk2).*
