---
title: "mrk — macOS Bootstrap Manual"
subtitle: "Workflow guide for managing, maintaining, and migrating your Mac setup"
date: "[github.com/sevmorris/mrk](https://github.com/sevmorris/mrk)"
---

::: {.logo-banner}
![](assets/mrk_logo.png)
:::

# Overview

**mrk** is a personal, opinionated macOS bootstrap system tailored to my workflow and toolset. It automates the configuration of a Mac from a clean install, managing the shell environment, dotfiles, macOS system preferences, Homebrew packages, app settings, login items, and personal app preferences.

**Key repositories:**

| Repo | Location | Purpose |
|---|---|---|
| `sevmorris/mrk` | `~/mrk` | Public bootstrap repo |
| `sevmorris/mrk-prefs` | `~/.mrk/preferences/` | Private app preferences |

The two-repo split keeps personal preference data (iTerm2 profiles, Raycast settings, etc.) out of the public repo while still making them fully portable across machines.

As long as both repos are kept current, the entire setup can be fully restored on a new machine from scratch — nothing needs to be manually transferred. The repos are the source of truth.

> **Adapting for your own use:** This project is built around a specific setup. If you fork it, you'll need to replace `sevmorris/mrk-prefs` with your own private preferences repo, swap in your own dotfiles, and review the app lists in `scripts/post-install` and `scripts/snapshot-prefs` to match your environment.

---

# How It Works — The Three Phases

## Phase 1 — Setup (`make setup`)

Script: `scripts/setup`

Sets up the foundational shell environment on a new or existing machine.

**What it does:**

- Installs Xcode Command Line Tools if not present
- Links everything in `dotfiles/` into `$HOME` as symlinks (with automatic backups of any existing files)

**Managed dotfiles:**

| File | Purpose |
|---|---|
| `.aliases` | Shell aliases |
| `.gitconfig` | Git configuration |
| `.hushlogin` | Suppresses "Last login" terminal message |
| `.zprofile` | Zsh login shell profile |
| `.zshenv` | Zsh environment variables |
| `.zshrc` | Zsh interactive shell config |
| `Makefile` | mrk commands available from `~/` |
- Links `scripts/` and `bin/` into `~/bin` so tools are on your PATH
- Applies macOS system preferences via `scripts/defaults.sh`
- Sets Zsh as the login shell
- Generates a rollback script at `~/.mrk/defaults-rollback.sh`

**Options:**

```
make setup --only dotfiles      # Link dotfiles only
make setup --only tools         # Link scripts/bin only
make setup --only defaults      # Apply macOS defaults only
make setup --only ext           # Run external dotfiles repo hooks only
make setup --dry-run            # Preview changes without applying
make setup --validate           # Check prerequisites before running
make setup --continue-on-error  # Continue remaining phases if one fails
make dotfiles                   # Shorthand for --only dotfiles
make tools                      # Shorthand for --only tools
make defaults                   # Shorthand for --only defaults
make trackpad                   # Apply defaults including trackpad settings
```

## Phase 2 — Homebrew (`make brew`)

Script: `scripts/brew`

Installs Homebrew and all packages listed in the `Brewfile`.

**What it does:**

- Installs Homebrew if not present
- Runs `brew bundle install` from the Brewfile
- Presents interactive prompts for packages that are new (not previously installed)
- Uses the mrk-picker TUI or `gum` to let you select which packages to accept

## Phase 3 — Post-Install (`make post-install`)

Script: `scripts/post-install`

Configures installed apps. Must be run after Phase 2.

**What it does:**

- **Topgrade:** Links `assets/topgrade.toml` to `~/.config/topgrade.toml`
- **Browsers:** Applies Safari defaults, Chrome/Brave managed policies, Helium defaults; opens extension install URLs on request
- **App defaults:** Applies `defaults write` settings for Audio Hijack, Fission, AlDente, Rogue Amoeba update settings
- **Preferences auto-pull:** If `~/.mrk/preferences/` is absent and SSH is authenticated to GitHub, automatically clones `mrk-prefs`
- **Plist imports** (14 apps): Imports personal preference plists; skips any app that already has a preferences file (non-destructive)
- **Barkeep:** Downloads and installs Barkeep from the latest GitHub release. Skipped if `/Applications/Barkeep.app` already exists — to update, use Barkeep itself or remove the app first
- **App Support restore:** Restores Loopback and SoundSource configuration files (non-destructive)
- **Login items:** Registers AlDente,BetterSnapTool,Bitwarden,Chrono Plus,Dropbox,Hammerspoon,Ice,NordPass,Raycast,SoundSource,Stats as login items

**Managed app preferences:**

| App | Plist imported |
|---|---|
| BetterSnapTool | ✓ |
| Ice | ✓ |
| iTerm2 | ✓ |
| Raycast | ✓ |
| Stats | ✓ |
| Loopback | ✓ + App Support files |
| SoundSource | ✓ + App Support files |
| Audio Hijack | ✓ |
| Farrago | ✓ |
| Piezo | ✓ |
| Typora | ✓ |
| Keka | ✓ |
| TimeMachineEditor | ✓ |
| MacWhisper | ✓ |

## Full Install

```bash
make all        # Runs setup + brew + post-install in sequence
exec zsh        # Reload shell after setup
```

---

# Day-to-Day Workflow

## Keeping the Brewfile Current

Two tools cover day-to-day Brewfile management:

**`bf`** — interactive TUI for browsing, adding, deleting, moving, and pruning Brewfile entries:

```bash
bf                    # Open the Brewfile manager TUI
bf --help             # Show keys and options
```

Key operations: **a** add · **d** delete · **m** move · **g** toggle greedy · **p** prune uninstalled · **/** search · **w** write · **c** commit

**Prune mode** (`p`) — fetches `brew list`, shows all Brewfile entries not currently installed. Space to mark, `a` to toggle all, `enter` to delete marked entries.

**`sync`** — scan installed packages, diff against the Brewfile, and add anything missing:

```bash
sync                  # Interactive — opens mrk-picker TUI to select packages
sync -n               # Dry run — show what would be added, make no changes
sync -c               # Auto-commit the Brewfile after updating
sync -p               # Prune — remove Brewfile entries for packages no longer installed
```

**How sync works:**

1. Reads the Brewfile to build a list of already-tracked packages
2. Runs `brew leaves` (top-level formulae) and `brew list --cask` to see what's installed
3. Computes the diff — packages installed but not yet in the Brewfile
4. Opens **mrk-picker** TUI: use `Space` to select packages, `Enter` to confirm, `q` to quit
5. For each selected formula, prompts via `gum` to choose which Brewfile section to add it to
6. Casks are auto-assigned to the existing cask section
7. Inserts each entry alphabetically within its section

> **Note:** The mrk-picker binary lives at `bin/mrk-picker` (gitignored, platform-specific).
> If it's missing, rebuild it first with `make picker`.

## Keeping App Preferences Current

After configuring an app, run `snapshot-prefs` to capture and push the preferences.

```bash
snapshot-prefs
```

**How snapshot-prefs works:**

1. Exports the preference plist for each managed app using `defaults export`
2. Commits all changes to `~/.mrk/preferences/` with a timestamped message
3. Pushes to `sevmorris/mrk-prefs` on GitHub

Snapshots are idempotent — if nothing changed, it reports "No changes to push."

## Pulling App Preferences

```bash
pull-prefs
```

Clones `mrk-prefs` into `~/.mrk/preferences/` if it doesn't exist, or fast-forward pulls if it does.

> **Note:** `make post-install` does this automatically if `~/.mrk/preferences/` is absent and your SSH key is authenticated with GitHub.

## Keeping Login Items Current

**`sync-login-items`** — diff system login items against `post-install` and update the repo:

```bash
sync-login-items          # Interactive — select items to add/remove
sync-login-items -n       # Dry run — show what would change
sync-login-items -c       # Auto-commit changes after updating
```

**How it works:**

1. Reads the current system login items via AppleScript
2. Parses `scripts/post-install` for tracked `add_login_item` calls
3. Shows the diff: items on the system but not tracked, and vice versa
4. Opens a TUI selector (via `gum`) to choose which items to add or remove
5. Updates `scripts/post-install`, `docs/manual.md`, and `docs/index.html`

## Installation Health Dashboard

**`mrk-status`** (also aliased as `status`) — interactive TUI showing the health of your mrk installation:

```bash
mrk-status                # Open the TUI dashboard
status                    # Same thing (alias)
```

Two-pane TUI: checks on the left, details on the right. Press `f` to run the suggested fix for any failing check, `r` to refresh.

## Barkeep

**[Barkeep](https://github.com/sevmorris/Barkeep)** is a native macOS companion app for visually managing your Homebrew Brewfile. It now lives in its own repository — see the link above for build instructions and releases.

## Updating the Manual

The manual is maintained in two places:

- `docs/manual.md` — Markdown source (this file)
- `docs/index.html` — hand-authored AFTO-style HTML document (the canonical published version)

The HTML document is the authoritative version served by GitHub Pages. Edit `docs/index.html` directly for the published site. This Markdown file serves as a reference and may lag behind the HTML.

```bash
# Edit the published manual directly
$EDITOR ~/mrk/docs/index.html

# Commit and push
cd ~/mrk
git add docs/index.html
git commit -m "docs: update manual"
git push
```

GitHub Pages picks up the change automatically — the site at `sevmorris.github.io/mrk` updates within a minute of the push.

---

# Before Migrating to a New Machine

Run these steps on the **old machine** before you transfer.

**1. Sync the Brewfile**

```bash
make sync ARGS=-c
```

Captures any packages installed since the last sync and commits the updated Brewfile.

**2. Snapshot app preferences**

```bash
make snapshot-prefs
```

Exports and pushes all 15 app preference plists plus Application Support files. Verify the push succeeded — you should see "Pushed to git@github.com:sevmorris/mrk-prefs.git" in the output.

**3. Push any pending mrk changes**

```bash
cd ~/mrk
git status
git push
```

**4. Verify SSH authentication**

```bash
ssh -T git@github.com
# Expected: Hi sevmorris! You've successfully authenticated...
```

The new machine needs your SSH key to auto-pull mrk-prefs during `make post-install`.

**5. Note anything not covered by mrk**

Write down any apps, license keys, or configurations not yet automated:

- App Store apps (manually reinstall from Purchases)
- Software licenses (export from your license manager)
- Any manual system settings not captured by `defaults write`
- VPN configurations, certificates, etc.

---

# Setting Up a New Machine

## Prerequisites

- macOS (developed and confirmed on 15; may work on 13/14)
- Active internet connection
- Your GitHub SSH key (or ability to create and add one)

## Step 1 — Clone mrk

**If SSH is already set up:**

```bash
git clone git@github.com:sevmorris/mrk.git ~/mrk
```

**If SSH is not yet configured** (fresh machine), clone over HTTPS first:

```bash
git clone https://github.com/sevmorris/mrk.git ~/mrk
```

Then generate and add your SSH key to GitHub before continuing, so mrk-prefs can be pulled automatically in Phase 3.

## Step 2 — Phase 1: Shell & Dotfiles

```bash
cd ~/mrk && make setup && exec zsh
```

After this step, the shell is configured, dotfiles are linked, and macOS system preferences are applied.

## Step 3 — (If needed) Add SSH Key to GitHub

If you cloned over HTTPS, add your SSH key now before running Phase 3:

```bash
# Generate a new key
ssh-keygen -t ed25519 -C "your-email@example.com"

# Copy the public key
cat ~/.ssh/id_ed25519.pub | pbcopy

# Add to GitHub: github.com → Settings → SSH and GPG keys → New SSH key
# Then verify:
ssh -T git@github.com
```

## Step 4 — Phase 2: Homebrew

```bash
make brew
```

Installs Homebrew (if needed) and all packages from the Brewfile. This step takes the most time depending on how many packages are in the Brewfile.

## Step 5 — Phase 3: App Configuration

```bash
make post-install
```

This configures apps, imports your personal preferences, and sets up login items. If SSH is authenticated, it automatically pulls your preferences from `mrk-prefs`.

If `~/.mrk/preferences/` is not populated (SSH wasn't ready), run manually:

```bash
make pull-prefs
make post-install   # Re-run to import plists
```

## Step 6 — Verify the Installation

```bash
make status     # Check dotfiles, tools, shell, Homebrew, Brewfile packages
make doctor     # Run full diagnostics
```

Review the output and address any items marked ✗ or ⚠.

## Full One-Command Install

```bash
cd ~/mrk
make all
exec zsh
```

---

# Command Reference

## Commands Available from Anywhere (`~/Makefile`)

`~/Makefile` is deployed automatically by `make setup` via `dotfiles/`. Running `make help` from `~/` shows all commands from both this file and `mrk/`.

**Brewfile**

| Command | Description |
|---|---|
| `make sync` | Sync installed packages into Brewfile (`-c` commit · `-n` dry run · `-p` prune) |
| `make sync-login-items` | Diff and sync system login items against post-install |

**Preferences**

| Command | Description |
|---|---|
| `make snapshot-prefs` | Export app preferences and push to mrk-prefs |
| `make pull-prefs` | Clone or pull app preferences from mrk-prefs |

**Build Tools**

| Command | Description |
|---|---|
| `make picker` | Build the mrk-picker TUI binary |
| `make bf` | Build the bf Brewfile manager TUI binary |
| `make mrk-status` | Build the mrk-status TUI health dashboard binary |
| `make build-tools` | Build all Go TUI binaries (picker + bf + mrk-status) |

**General**

| Command | Description |
|---|---|
| `make help` | Show all available commands from `~/` and `mrk/` |

## Commands from `~/mrk/`

**Bootstrap**

| Command | Description |
|---|---|
| `make all` | Full install: setup + brew + post-install + TUI binaries |
| `make setup` / `make install` | Phase 1: shell, dotfiles, macOS defaults |
| `make brew` | Phase 2: Homebrew packages and casks |
| `make post-install` | Phase 3: app configs and login items |

**Partial Phases**

| Command | Description |
|---|---|
| `make dotfiles` | Link dotfiles only |
| `make tools` | Link scripts and bin into ~/bin only |
| `make defaults` | Apply macOS defaults only |
| `make trackpad` | Apply macOS defaults including trackpad settings |
| `make harden` | Apply macOS security hardening |

**Maintenance**

| Command | Description |
|---|---|
| `make update` | Upgrade all packages (topgrade or brew upgrade) |
| `make updates` | Run macOS software updates (`softwareupdate -ia`) |
| `make uninstall` | Remove symlinks and undo setup |

**Diagnostics**

| Command | Description |
|---|---|
| `make status` | Open the mrk-status TUI health dashboard |
| `make doctor` | Check `~/bin` is on PATH; `--fix` adds it to `.zshrc` |
| `make fix-exec` | Make all scripts and bin files executable |

---

# What `make status` Checks

Running `make status` gives a quick health check of the entire installation:

- **Dotfiles** — Which files are symlinked into `~/` and which are missing
- **Tools** — Which scripts/bin symlinks are live in `~/bin` and which are broken
- **macOS Defaults** — Whether defaults have been applied (rollback script present)
- **Security Hardening** — Whether hardening has been applied
- **Backups** — Number of dotfile backups in `~/.mrk/backups/`
- **Shell** — Current login shell (should be Zsh)
- **PATH** — Whether `~/bin` is on the PATH
- **Homebrew** — Version installed
- **Brewfile packages** — Each formula and cask: ✓ installed or ✗ missing

---

# State Files

mrk writes runtime state to `~/.mrk/` (gitignored):

| File / Directory | Purpose |
|---|---|
| `~/.mrk/preferences/` | Cloned from `sevmorris/mrk-prefs`; app plists + App Support files |
| `~/.mrk/backups/` | Timestamped backups of dotfiles that were replaced during setup |
| `~/.mrk/defaults-rollback.sh` | Shell script to undo all `defaults write` changes |
| `~/.mrk/hardening-rollback.sh` | Shell script to undo security hardening |

To undo macOS defaults applied by mrk:

```bash
bash ~/.mrk/defaults-rollback.sh
```

---

# Troubleshooting

| Problem | Solution |
|---|---|
| `make setup` fails at Xcode CLT | Run `xcode-select --install`, wait for the GUI install dialog to complete, then re-run |
| Dotfile conflict ("file exists" warning) | Backup auto-created in `~/.mrk/backups/`; resolve manually then re-run |
| post-install skips plist imports | SSH key not authenticated; run `make pull-prefs` after adding key to GitHub |
| mrk-picker not rendering | Rebuild the binary: `make picker` |
| `~/bin` not on PATH | Run `make doctor --fix` — automatically adds `~/bin` to PATH in `.zshrc` |
| Brewfile entry shows ✗ (missing) | Package name may differ from formula name; check with `brew info <pkg>` |
| `make sync` exits with "nothing to add" | All installed packages are already in the Brewfile — nothing to do |
| `make snapshot-prefs` fails for an app | App is not installed or `defaults export` failed; check the app is running |
| post-install login item already exists | Safe to ignore — `add_login_item` checks before adding |
