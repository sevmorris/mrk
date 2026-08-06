# mrk — macOS Bootstrap Manual

_How to manage, maintain and migrate your Mac setup_

[github.com/sevmorris/mrk](https://github.com/sevmorris/mrk)

---

# Overview

**mrk** is a personal macOS bootstrap system. It configures a Mac from a clean installation. mrk manages these items: the shell environment, the dotfiles, the macOS system preferences, the Homebrew packages, the app settings, the login items, and the personal app preferences.

**Key repositories:**

| Repo | Location | Purpose |
|---|---|---|
| `sevmorris/mrk` | `~/mrk` | Public bootstrap repo |
| `sevmorris/mrk-prefs` | `~/.mrk/preferences/` | Private app preferences |

The two repositories keep the personal preference data out of the public repository. This data includes the iTerm2 profiles and the Raycast settings. The split keeps the data portable between machines.

Keep both repositories current. You can then restore the full setup on a new machine, and you transfer nothing by hand. The repositories are the source of truth.

> **How to adapt mrk for your own use:** This project fits one specific setup. If you fork it, do these four steps.
>
> 1. Replace `sevmorris/mrk-prefs` with your own private preferences repository.
> 2. Replace the dotfiles with your own.
> 3. Edit the app list in `scripts/post-install` to match your machine.
> 4. Edit the app list in `scripts/snapshot-prefs` to match your machine.

---

# How It Works — The Three Phases

## Phase 1 — Setup (`make setup`)

Script: `scripts/setup`

Phase 1 configures the shell environment. It runs on a new machine or on an existing machine.

**What it does:**

- Installs the Xcode Command Line Tools when they are absent.
- Symlinks every file in `dotfiles/` into `$HOME`. Phase 1 first backs up any file that it replaces.

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
- Symlinks `scripts/` and `bin/` into `~/bin`, which puts the tools on your PATH.
- Applies the macOS system preferences with `scripts/defaults.sh`.
- Sets zsh as the login shell.
- Clones oh-my-zsh and two zsh plugins: zsh-autosuggestions and zsh-syntax-highlighting. Phase 1 skips a clone when the directory exists. A failed clone gives a warning, and Phase 1 continues.
- Writes a rollback script to `~/.mrk/defaults-rollback.sh`.

> **Note:** `scripts/defaults.sh` continues when a write fails. It counts the failed writes and reports the total at the end. The rollback script covers the writes that succeeded.

**Options:**

```
make setup ARGS="--only dotfiles"      # Symlink the dotfiles only
make setup ARGS="--only tools"         # Symlink scripts/ and bin/ only
make setup ARGS="--only defaults"      # Apply the macOS defaults only
make setup ARGS="--only xcode"         # Install the Xcode Command Line Tools only
make setup ARGS="--only shell"         # Set the login shell and install oh-my-zsh only
make setup ARGS="--dry-run"            # Show the changes, but apply nothing
make setup-dry                         # Short form of --dry-run
make setup ARGS="--validate"           # Check the prerequisites first
make setup ARGS="--continue-on-error"  # Continue when a phase fails
make setup ARGS="--adventure"          # Use narrative mode for this phase
make setup ARGS="--yes"                # Skip every confirmation prompt
make dotfiles                          # Short form of --only dotfiles
make tools                             # Short form of --only tools
make defaults                          # Short form of --only defaults
make trackpad                          # Apply the defaults and the trackpad settings
```

## Phase 2 — Homebrew (`make brew`)

Script: `scripts/brew`

Phase 2 installs Homebrew and every package that the `Brewfile` lists.

**What it does:**

- Installs Homebrew when it is absent.
- Runs `brew bundle install` against the Brewfile.
- Asks you about each new package.
- Shows the mrk-picker TUI, so you can select the packages. If mrk-picker is absent, Phase 2 uses `gum`.

## Phase 3 — Post-Install (`make post-install`)

Script: `scripts/post-install`

Phase 3 configures the installed apps. Run Phase 2 first.

**What it does:**

- **Topgrade:** Symlinks `assets/topgrade.toml` to `~/.config/topgrade.toml`.
- **Browsers:** Applies the Safari defaults, the Chrome and Brave managed policies, and the Helium defaults. It opens the extension URLs when you ask for them.
- **App defaults:** Writes the settings for Audio Hijack, Fission, AlDente, and the Rogue Amoeba update options.
- **Preferences pull:** Clones `mrk-prefs` when `~/.mrk/preferences/` is absent and GitHub accepts your SSH key.
- **Plist imports (14 apps):** Imports your preference plists. Phase 3 skips an app that already has a preferences file, so it never overwrites a live configuration.
- **Barkeep:** Installs Barkeep from the most recent GitHub release. Phase 3 skips this step when `/Applications/Barkeep.app` exists. To update Barkeep, use Barkeep, or delete the app first.
- **Application Support restore:** Restores the Loopback and SoundSource configuration files. Phase 3 skips a file that exists.
- **Config directory restore:** Restores the Calibre configuration into `~/Library/Preferences/calibre/`. Phase 3 skips this step when `gui.json` exists.
- **Login items:** post-install adds these apps to the login items: AlDente, BetterSnapTool, Chrono Plus, Dropbox, Ice, Raycast, SoundSource, Stats

> **Note:** Phase 3 continues when a step fails. It counts the failed steps and reports the total at the end.

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

**Adventure mode** adds narrative room descriptions and a `>` prompt at each phase. The installation is the same:

```bash
make adventure  # Full install in narrative mode
```

To skip every confirmation prompt, pass `--yes` or set `NONINTERACTIVE=1`. This also works in adventure mode.

---

# Day-to-Day Workflow

## How to keep the Brewfile current

Two tools manage the Brewfile.

**`bf`** is a TUI. Use it to read, add, delete and move the Brewfile entries.

```bash
bf                    # Start the Brewfile manager TUI
bf --help             # Show the keys and the options
```

Keys: **a** add · **d** delete · **m** move · **g** greedy on or off · **p** delete uninstalled · **/** search · **w** write · **c** commit

**Prune mode** (`p`) runs `brew list` and shows every Brewfile entry that you no longer have installed. Press `space` to mark an entry, `a` to mark all of them, and `enter` to delete the marked entries.

**`sync`** reads the installed packages, compares them against the Brewfile, and adds the packages that are absent.

```bash
sync                  # Start the mrk-picker TUI, and select the packages
sync -n               # Show the additions, but change nothing
sync -c               # Commit the Brewfile after sync updates it
sync -p               # Delete the entries for the packages you uninstalled
```

**How sync works**

1. sync reads the Brewfile and builds the list of tracked packages.
2. sync runs `brew leaves --installed-on-request` and `brew list --cask` to read the installed packages. The `leaves` form returns the formulae that you asked for, and it drops the dependencies.
3. sync compares the two lists and finds the packages that the Brewfile does not have.
4. sync drops the names that `~/.mrk/sync-ignore` lists, so those packages never reach the picker.
5. sync starts the **mrk-picker** TUI. Press `space` to select a package, `enter` to confirm, and `q` to quit.
6. sync asks you, through `gum`, which Brewfile section each formula belongs to.
7. sync puts every cask in the existing cask section.
8. sync adds each entry to its section in alphabetical order.

If `brew list` fails, sync stops. An empty package list would make `-p` mark every Brewfile entry for deletion.

> **Note:** The mrk-picker binary is at `bin/mrk-picker`. It is platform-specific, and gitignore excludes it. If the binary is absent, build it with `make picker`.

**The ignore list (`~/.mrk/sync-ignore`)** holds one formula name or cask name per line. Do not add a `brew` or `cask` prefix. A `#` character starts a comment.

sync drops these names on every run, so a package that you keep installed but do not want in the Brewfile stops appearing. mrk does not create this file. To start one, run `touch ~/.mrk/sync-ignore`.

> **Note:** `make sync` can add back a package that you deleted from the Brewfile on purpose, because the package is still installed. To stop this, add the name to `~/.mrk/sync-ignore`, or uninstall the package.

## How to keep the app preferences current

Configure an app, and then run `snapshot-prefs`. This command exports the preferences and pushes them.

```bash
snapshot-prefs
```

**How snapshot-prefs works**

1. snapshot-prefs exports the preference plist for each managed app with `defaults export`.
2. snapshot-prefs copies the config directories that are not defaults domains into `config/`. Calibre is one example: its settings, conversion presets and plugins live in `~/Library/Preferences/calibre/`.
3. snapshot-prefs converts each binary plist to xml1, and then scans every file for secrets.
4. snapshot-prefs commits the changes in `~/.mrk/preferences/` with a timestamped message.
5. snapshot-prefs pushes to `sevmorris/mrk-prefs` on GitHub.

You can run snapshot-prefs more than once. When nothing changed, it reports "No changes to push."

> **Caution:** snapshot-prefs scans every staged file for API keys and tokens before it commits. If the scan finds a match, snapshot-prefs stops and asks you to confirm. It does not ask when `NONINTERACTIVE=1` is set or when there is no terminal — in those two cases it aborts. Read the reported lines before you answer. `mrk-push` applies the same gate to the mrk repository.

## How to pull the app preferences

```bash
pull-prefs
```

`pull-prefs` clones `mrk-prefs` into `~/.mrk/preferences/`. If the clone exists, `pull-prefs` fast-forwards it instead.

`pull-prefs` only fetches the data. `post-install` does the restore. It imports each defaults-domain plist with `defaults import`, restores the Application Support files, and copies the config directories back into `~/Library/Preferences/`.

`post-install` skips an app that it finds already configured, so it does not overwrite your live settings. It decides this from one file for each app: the preferences plist for a defaults domain, and `gui.json` for Calibre. If that one file is absent but other files exist, the restore overwrites them. Quit an app before you restore it.

> **Note:** `make post-install` runs `pull-prefs` for you when `~/.mrk/preferences/` is absent and GitHub accepts your SSH key.

## How to configure the Dock

> **Caution:** `dock-setup` deletes every item from the Dock before it adds the new items. It does not ask you to confirm, and it does not save your current layout.

**`dock-setup`** fills the Dock from a fixed app list.

```bash
make dock
```

To change the list or the order, edit `scripts/dock-setup`. The script needs `dockutil`, and it installs dockutil when dockutil is absent.

## How to keep the login items current

**`sync-login-items`** compares the system login items against `post-install`, and then updates the repository.

```bash
sync-login-items          # Select the items to add or delete
sync-login-items -n       # Show the changes, but write nothing
sync-login-items -c       # Commit the changes after the update
```

**How sync-login-items works**

1. sync-login-items reads the system login items with AppleScript.
2. sync-login-items reads the tracked `add_login_item` lines in `scripts/post-install`.
3. sync-login-items drops the new items that `~/.mrk/login-items-ignore` lists.
4. sync-login-items shows the differences in both directions.
5. sync-login-items starts a `gum` selector, so you can choose the items.
6. sync-login-items updates `scripts/post-install` and `docs/manual.md`.

> **Caution:** If System Events returns no login items, or if the AppleScript fails, sync-login-items stops and shows an error. It does not continue, because an empty list looks the same as a complete list of deletions, and sync-login-items would then offer to delete every tracked item. Give Automation access in System Settings → Privacy & Security → Automation, and then run the command again.

**The ignore list (`~/.mrk/login-items-ignore`)** holds one login-item name per line. Use the app name, and do not add the `.app` suffix. A `#` character starts a comment.

sync-login-items drops these names on every run. An app that you keep as a login item, but do not want in `post-install`, stops appearing. mrk does not create this file. To start one, run `touch ~/.mrk/login-items-ignore`.

> **Note:** Some apps add themselves back to the login items after an update. sync-login-items then offers the app again. A later sync can track it again. To stop this, add the name to `~/.mrk/login-items-ignore`.

> **Note:** sync-login-items drops the ignored names from the new items only. An item that `post-install` already tracks stays tracked. To delete it, edit the `add_login_item` block in `scripts/post-install`.

## How to check the installation health

**`mrk-status`** is a TUI. It shows the health of your mrk installation. The `status` command runs the same binary.

```bash
mrk-status                # Start the TUI dashboard
status                    # The same binary
```

The checks are in the left pane, and the details are in the right pane. Press `f` to run the suggested fix for the selected check. Press `r` to run all the checks again.

## mrk-menu

**`mrk-menu`** starts any mrk task. It groups the commands into categories: Brewfile, Login items, Preferences, System state, Diagnostics, Maintenance, and Nuclear options. It runs each command in the same terminal.

```bash
mrk-menu
```

**Layout**

mrk-menu first shows a splash screen with the version and the short git SHA. Press any key to continue. mrk-menu then shows two panes: the categories on the left, and the items on the right. The footer shows the command for the selected item, such as `$ make defaults`. It also shows the result of the last run, either `✓ ok` or `✗ exited N`.

**Key bindings**

| Key | Action |
|---|---|
| `j` `k` / `↑` `↓` | Move the cursor |
| `enter` / `→` / `l` | Open the category, then start the item |
| `esc` / `←` / `h` | Go back |
| `1`–`9` | Go to that entry in the active pane |
| `/` | Start filter mode, and search every item in every category |
| `?` | Show or hide the help panel |
| `q` / `ctrl-c` | Quit |

**Filter mode**

Press `/` anywhere in the menu. Type any part of an item name, a description or a category. mrk-menu shows each match as `Category › item`, and it updates the list as you type. Press `↑` or `↓` to move, `enter` to start the item, and `esc` to cancel.

**Nuclear options**

The `nuke-mrk` entry is under Nuclear options. To confirm it, type the word `nuke`. Press `esc` to cancel.

## Barkeep

**[Barkeep](https://github.com/sevmorris/Barkeep)** is a native macOS app. Use it to manage your Homebrew Brewfile. `make post-install` installs Barkeep for you. Barkeep has its own repository, and the link above has the releases.

## Standalone Utilities

These tools are in `~/bin/`, symlinked from `mrk/bin/`. They have no Make target, so run them directly.

| Command | Purpose |
|---|---|
| `audio-mode` | Pauses and resumes the sync clients for a recording session or a mixing session |
| `zoom-mode` | Keeps the Wi-Fi awake and stops sleep during a long Zoom session; `zoom-mode on \| off \| status` |
| `mrk-push` | Commits and pushes `~/mrk`, then deletes the old GitHub Pages deployments. Scans the staged files for secrets first |
| `hide_tm.sh` | Hides the Time Machine volumes from the Finder sidebar. The default name is `TimeMachine`. Give the volume names, or set `TM_VOLUMES` |
| `nuke-mrk` | Moves `~/mrk` and `~/.mrk` to the Trash, deletes the `~/bin` symlinks and the dotfile symlinks, and offers the rollbacks. It does NOT change Homebrew. `mrk-menu` lists it under Nuclear options |

> `nuke-mrk` deletes more than `make uninstall`. Use `make uninstall` to unlink mrk only. Use `nuke-mrk` to get a clean machine for a test installation.

## How to update the manual

This file is the manual. Edit it, and then push it.

```bash
$EDITOR ~/mrk/docs/manual.md
cd ~/mrk
git add docs/manual.md
git commit -m "docs: update manual"
git push
```

GitHub renders this file in the repository, so the [link in the README](../README.md) always shows the current text.

---

# How to prepare for a new machine

Do these five steps on the **old machine** before you transfer.

**1. Sync the Brewfile**

```bash
make sync ARGS=-c
```

This command adds the packages that you installed since the last sync. It then commits the Brewfile.

**2. Snapshot app preferences**

```bash
make snapshot-prefs
```

This command exports the 14 app preference plists, the Application Support files and the config directories. It then pushes them. Check that the push succeeded: the output ends with "Pushed to git@github.com:sevmorris/mrk-prefs.git".

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

The new machine needs your SSH key. `make post-install` uses it to pull mrk-prefs.

**5. Note anything not covered by mrk**

Write down the apps, the license keys and the settings that mrk does not manage:

- The App Store apps. Install them again from Purchases.
- The software licenses. Export them from your license manager.
- The system settings that `defaults write` does not cover.
- The VPN configurations and the certificates.

---

# How to set up a new machine

## Prerequisites

- macOS. mrk is developed and tested on macOS 15. It can work on macOS 13 and macOS 14.
- An internet connection.
- Your GitHub SSH key. You can also create a key and add it later.

## Step 1 — Clone mrk

**If SSH already works:**

```bash
git clone git@github.com:sevmorris/mrk.git ~/mrk
```

**If SSH does not work yet**, clone over HTTPS:

```bash
git clone https://github.com/sevmorris/mrk.git ~/mrk
```

Then create your SSH key and add it to GitHub. Phase 3 needs the key to pull mrk-prefs.

## Step 2 — Phase 1: the shell and the dotfiles

```bash
cd ~/mrk && make setup && exec zsh
```

This step configures the shell, symlinks the dotfiles, and applies the macOS system preferences.

## Step 3 — Add your SSH key to GitHub, if you need to

If you cloned over HTTPS, add your SSH key now. Do this before Phase 3.

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

This step installs Homebrew and every package in the Brewfile. It is the slowest step, and its duration depends on the number of packages.

## Step 5 — Phase 3: the app configuration

```bash
make post-install
```

This step configures the apps, imports your preferences, and adds the login items. If GitHub accepts your SSH key, this step also pulls your preferences from `mrk-prefs`.

If `~/.mrk/preferences/` is empty, your SSH key was not ready. Run these two commands:

```bash
make pull-prefs
make post-install   # Run it again to import the plists
```

## Step 6 — Check the installation

```bash
make status     # Check the dotfiles, tools, shell, Homebrew and Brewfile packages
make doctor     # Check that ~/bin is on the PATH
```

Read the output. Correct every item that has a ✗ mark or a ⚠ mark.

## How to install with one command

```bash
cd ~/mrk
make all
exec zsh
```

---

# Command Reference

## Commands you can run from anywhere (`~/Makefile`)

`make setup` symlinks `~/Makefile` from `dotfiles/`. Run `make help` from `~/` to see the commands in this file and in `mrk/`.

**Brewfile**

| Command | Description |
|---|---|
| `make sync` | Sync the installed packages into the Brewfile (`-c` commit · `-n` dry run · `-p` prune) |

**Preferences**

| Command | Description |
|---|---|
| `make snapshot-prefs` | Export the app preferences, and push them to mrk-prefs |
| `make pull-prefs` | Clone or pull the app preferences from mrk-prefs |

> `snapshot` and `snapshot-prefs` are not the same command.
>
> `snapshot` writes plists into `assets/preferences/` in the public mrk repository. gitignore excludes those plists, and no other script reads them. `snapshot` is a local export only, and it does not scan for secrets.
>
> `snapshot-prefs` writes to the private mrk-prefs repository, and it pushes. `pull-prefs` and `post-install` use that data to restore your preferences on a new machine.

**Build Tools**

| Command | Description |
|---|---|
| `make picker` | Build the mrk-picker TUI binary |
| `make bf` | Build the bf TUI binary |
| `make mrk-status` | Build the mrk-status TUI binary |
| `make mrk-menu` | Build the mrk-menu TUI binary |
| `make build-tools` | Build all four TUI binaries |

**General**

| Command | Description |
|---|---|
| `make help` | Show the commands in `~/` and in `mrk/` |

## Commands from `~/mrk/`

**Bootstrap**

| Command | Description |
|---|---|
| `make all` | Run the full installation: setup, brew, post-install and the TUI binaries |
| `make adventure` | Run the full installation in narrative mode |
| `make setup` / `make install` | Phase 1: the shell, the dotfiles and the macOS defaults |
| `make setup-dry` | Show the Phase 1 changes, but apply nothing |
| `make brew` | Phase 2: the Homebrew formulae and casks |
| `make post-install` | Phase 3: the app configuration and the login items |

To use narrative mode for one phase, pass `ARGS=--adventure` to that target. To skip the confirmation prompts, pass `ARGS=--yes`.

**Partial Phases**

| Command | Description |
|---|---|
| `make dotfiles` | Symlink the dotfiles only |
| `make tools` | Symlink `scripts/` and `bin/` into `~/bin` only |
| `make defaults` | Apply the macOS defaults only |
| `make trackpad` | Apply the macOS defaults and the trackpad settings |
| `make harden` | Apply the optional macOS security settings |
| `make dock` | Replace the Dock contents with the preferred apps |

**Maintenance**

| Command | Description |
|---|---|
| `make sync` | Sync the installed packages into the Brewfile |
| `make sync-login-items` | Sync the system login items into post-install and the manual |
| `make update` | Upgrade every package, with topgrade or with brew upgrade |
| `make updates` | Run the macOS software updates (`softwareupdate -ia`) |
| `make uninstall` | Delete the symlinks, and offer the rollbacks |
| `make maintain` | Run the periodic housekeeping (see `maintain` in BIN-1) |
| `make pull` | Fast-forward the mrk repository to origin |
| `make check` | Run the local validation: picker descriptions, shellcheck and go test |
| `make ci` | Run the local validation, and build the TUI binaries |
| `make tidy` | Run `go mod tidy` in every Go tool directory |

**Diagnostics & Launchers**

| Command | Description |
|---|---|
| `mrk-menu` | Start the TUI launcher (see [mrk-menu](#mrk-menu) above for the keys) |
| `make status` | Start the mrk-status TUI health dashboard |
| `make doctor` | Check that `~/bin` is on the PATH. `make doctor ARGS=--fix` adds it to `.zshrc` |
| `make fix-exec` | Set the executable bit on the scripts and the `~/bin` symlinks |

---

# What `make status` checks

`make status` checks the whole installation and shows nine results:

- **Dotfiles** — The files that mrk symlinked into `~/`, and the files that are absent.
- **Tools** — The `~/bin` symlinks that work, and the symlinks that are broken.
- **macOS Defaults** — Whether mrk applied the defaults. The rollback script is the evidence.
- **Security Hardening** — Whether mrk applied the hardening.
- **Backups** — The number of dotfile backups in `~/.mrk/backups/`.
- **Shell** — Your login shell. It must be zsh.
- **PATH** — Whether `~/bin` is on the PATH.
- **Homebrew** — The installed version.
- **Brewfile packages** — Each formula and cask, marked ✓ installed or ✗ absent.

---

# State Files

mrk writes its state to `~/.mrk/`. gitignore excludes this directory.

| File / Directory | Purpose |
|---|---|
| `~/.mrk/preferences/` | The clone of `sevmorris/mrk-prefs`. Holds the app plists, the Application Support files and the config directories |
| `~/.mrk/backups/` | The timestamped backups of the dotfiles that setup replaced |
| `~/.mrk/defaults-rollback.sh` | Undoes the macOS system defaults that `make defaults` wrote, and the app plists that post-install imported. It does **not** cover the app-preference scripts that Phase 3 runs for Safari, Helium, AlDente, Audio Hijack, Fission and Rogue Amoeba. Those scripts write their defaults directly |
| `~/.mrk/hardening-rollback.sh` | Undoes the security hardening |
| `~/.mrk/sync-ignore` | The formula names and cask names that `sync` does not offer. One name per line. mrk does not create this file |
| `~/.mrk/login-items-ignore` | The login-item names that `sync-login-items` does not offer. One name per line. mrk does not create this file |

To undo the macOS defaults that mrk applied, run this command:

```bash
bash ~/.mrk/defaults-rollback.sh
```

---

# Troubleshooting

| Problem | Solution |
|---|---|
| `make setup` fails at the Xcode Command Line Tools | 1. Run `xcode-select --install`. 2. Wait for the installation dialog to close. 3. Run `make setup` again |
| A dotfile conflict gives a "file exists" warning | 1. Find the backup in `~/.mrk/backups/`. 2. Correct the conflict by hand. 3. Run the command again |
| post-install skips the plist imports | GitHub does not accept your SSH key. 1. Add the key to GitHub. 2. Run `make pull-prefs`. 3. Run `make post-install` again |
| mrk-picker does not appear | Build the binary again with `make picker` |
| `~/bin` is not on the PATH | Run `make doctor ARGS=--fix`. This adds `~/bin` to the PATH in `.zshrc` |
| A Brewfile entry shows ✗ | The package name can differ from the formula name. Check it with `brew info <pkg>` |
| `make sync` reports "nothing to add" | The Brewfile already has every installed package. Do nothing |
| `make snapshot-prefs` skips an app | The app is not installed, or `defaults export` failed. snapshot-prefs lists the skipped apps when it exits |
| post-install reports that a login item exists | Ignore this message. `add_login_item` checks before it adds an item |
| `sync-login-items` stops with "System Events returned no login items" | macOS denied Automation access, or System Events did not answer. 1. Open System Settings → Privacy & Security → Automation. 2. Give your terminal access to System Events. 3. Run the command again |
| `make defaults` reports "N default(s) failed to apply" | A managed or locked key rejected the write. The other defaults did apply, and the rollback script covers them. Read the log for the key names |
