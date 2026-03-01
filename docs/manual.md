---
title: "mrk — macOS Bootstrap Manual"
subtitle: "Workflow guide for managing, maintaining, and migrating your Mac setup"
date: "2026"
---

# Overview

**mrk** is a three-phase macOS bootstrap system that automates the configuration of a Mac from a clean install. It manages the shell environment, dotfiles, macOS system preferences, Homebrew packages, app settings, login items, and personal app preferences.

**Key repositories:**

| Repo | Location | Purpose |
|---|---|---|
| `sevmorris/mrk` | `~/Projects/mrk-dev/` | Public bootstrap repo |
| `sevmorris/mrk-prefs` | `~/.mrk/preferences/` | Private app preferences |

The two-repo split keeps personal preference data (iTerm2 profiles, Raycast settings, etc.) out of the public repo while still making them fully portable across machines.

---

# How It Works — The Three Phases

## Phase 1 — Setup (`make setup`)

Script: `scripts/setup`

Sets up the foundational shell environment on a new or existing machine.

**What it does:**

- Installs Xcode Command Line Tools if not present
- Links everything in `dotfiles/` into `$HOME` as symlinks (with automatic backups of any existing files)
- Links `scripts/` and `bin/` into `~/bin` so tools are on your PATH
- Applies macOS system preferences via `scripts/defaults.sh`
- Sets Zsh as the login shell
- Generates a rollback script at `~/.mrk/defaults-rollback.sh`

**Options:**

```
make setup --only dotfiles    # Link dotfiles only
make setup --only tools       # Link scripts/bin only
make setup --only defaults    # Apply macOS defaults only
make setup --dry-run          # Preview changes without applying
make dotfiles                 # Shorthand for --only dotfiles
make tools                    # Shorthand for --only tools
make defaults                 # Shorthand for --only defaults
make trackpad                 # Apply defaults including trackpad settings
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
- **Plist imports** (15 apps): Imports personal preference plists; skips any app that already has a preferences file (non-destructive)
- **App Support restore:** Restores Loopback and SoundSource configuration files (non-destructive)
- **Login items:** Registers AlDente, Dropbox, Ice, Hot, Raycast, Stats, BetterSnapTool, Chrono Plus as login items

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
| Hot | ✓ |
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

## Keeping the Brewfile Current (`make sync`)

Whenever you install a new Homebrew package, run `make sync` to record it in the Brewfile.

```bash
make sync           # Interactive — opens mrk-picker TUI to select packages
make sync -n        # Dry run — show what would be added, make no changes
make sync -c        # Auto-commit the Brewfile after updating
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

## Keeping App Preferences Current (`make snapshot-prefs`)

After configuring an app, run `make snapshot-prefs` to capture and push the preferences.

```bash
make snapshot-prefs
```

**How snapshot-prefs works:**

1. Exports the preference plist for each of the 15 managed apps using `defaults export`
2. Copies Loopback and SoundSource Application Support files
3. Commits all changes to `~/.mrk/preferences/` with a timestamped message
4. Pushes to `sevmorris/mrk-prefs` on GitHub

Snapshots are idempotent — if nothing changed, it reports "No changes to push."

## Pulling App Preferences (`make pull-prefs`)

```bash
make pull-prefs
```

Clones `mrk-prefs` into `~/.mrk/preferences/` if it doesn't exist, or fast-forward pulls if it does.

> **Note:** `make post-install` does this automatically if `~/.mrk/preferences/` is absent and your SSH key is authenticated with GitHub.

## Updating This Manual (`make manual`)

The manual source lives in the repo at `docs/manual.md`. After editing it, regenerate the HTML and commit:

```bash
# Edit the source
$EDITOR ~/Projects/mrk-dev/docs/manual.md

# Regenerate the site HTML (requires pandoc)
make manual

# Commit and push both files
cd ~/Projects/mrk-dev
git add docs/manual.md docs/index.html
git commit -m "docs: update manual"
git push
```

GitHub Pages picks up the change automatically — the site at `sevmorris.github.io/mrk` updates within a minute of the push.

> **Note:** Only edit `docs/manual.md` — never edit `docs/index.html` directly, as it is overwritten by `make manual`.

---

# Before Migrating to a New Machine

Run these steps on the **old machine** before you transfer.

**1. Sync the Brewfile**

```bash
make sync --commit
# or from ~/
make sync -c
```

Captures any packages installed since the last sync and commits the updated Brewfile.

**2. Snapshot app preferences**

```bash
make snapshot-prefs
# or from ~/
make snapshot-prefs
```

Exports and pushes all 15 app preference plists plus Application Support files. Verify the push succeeded — you should see "Pushed to git@github.com:sevmorris/mrk-prefs.git" in the output.

**3. Push any pending mrk-dev changes**

```bash
cd ~/Projects/mrk-dev
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

- macOS 15 or later
- Active internet connection
- Your GitHub SSH key (or ability to create and add one)

## Step 1 — Clone mrk

**If SSH is already set up:**

```bash
mkdir -p ~/Projects
git clone git@github.com:sevmorris/mrk.git ~/Projects/mrk-dev
```

**If SSH is not yet configured** (fresh machine), clone over HTTPS first:

```bash
mkdir -p ~/Projects
git clone https://github.com/sevmorris/mrk.git ~/Projects/mrk-dev
```

Then generate and add your SSH key to GitHub before continuing, so mrk-prefs can be pulled automatically in Phase 3.

## Step 2 — Phase 1: Shell & Dotfiles

```bash
cd ~/Projects/mrk-dev
make setup
exec zsh        # Reload shell to pick up dotfiles and ~/bin
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
cd ~/Projects/mrk-dev
make all
exec zsh
```

---

# Command Reference

## Commands Available from Anywhere (`~/Makefile`)

| Command | Description |
|---|---|
| `make sync` | Sync installed Homebrew packages into the Brewfile |
| `make snapshot-prefs` | Export app preferences and push to mrk-prefs |
| `make pull-prefs` | Clone or pull app preferences from mrk-prefs |
| `make picker` | Build the mrk-picker TUI binary |
| `make help` | Show all available commands |

## Commands from `~/Projects/mrk-dev/`

| Command | Description |
|---|---|
| `make all` | Full install: setup + brew + post-install |
| `make setup` / `make install` | Phase 1: shell, dotfiles, macOS defaults |
| `make brew` | Phase 2: Homebrew packages and casks |
| `make post-install` | Phase 3: app configs and login items |
| `make dotfiles` | Link dotfiles only |
| `make tools` | Install CLI tools only |
| `make defaults` | Apply macOS defaults only |
| `make trackpad` | Apply macOS defaults including trackpad settings |
| `make harden` | Apply macOS security hardening |
| `make update` | Upgrade all packages (topgrade or brew upgrade) |
| `make updates` | Run macOS software updates (`softwareupdate -ia`) |
| `make uninstall` | Remove symlinks and undo setup |
| `make status` | Show installation status |
| `make doctor` | Run diagnostics |
| `make fix-exec` | Make all scripts and bin files executable |
| `make help` | Show all available commands |

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
| `~/bin` not on PATH | Add `export PATH="$HOME/bin:$PATH"` to `~/.zshrc`, or run `make doctor` |
| Brewfile entry shows ✗ (missing) | Package name may differ from formula name; check with `brew info <pkg>` |
| `make sync` exits with "nothing to add" | All installed packages are already in the Brewfile — nothing to do |
| `make snapshot-prefs` fails for an app | App is not installed or `defaults export` failed; check the app is running |
| post-install login item already exists | Safe to ignore — `add_login_item` checks before adding |
