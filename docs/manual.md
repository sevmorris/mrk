# mrk — macOS Bootstrap Manual

_How I set up, maintain and migrate my Mac_

[github.com/sevmorris/mrk](https://github.com/sevmorris/mrk)

---

# Overview

**mrk** is a personal macOS bootstrap system. It configures a Mac from a clean installation. mrk manages these items: the shell environment, the dotfiles, the macOS system preferences, the Homebrew packages, the app settings, the login items, and the personal app preferences.

This manual describes one machine: mine. The scripts are general. Every list inside them is a personal choice. This applies to the packages, the login items, the Dock, the preference domains, and the private repository that holds the preference data. Read the manual for the method. Do not run the commands on a different machine before you change those lists. The steps below say "you" because they are the steps I follow.

**Key repositories:**

| Repo | Location | Purpose |
|---|---|---|
| `sevmorris/mrk` | `~/mrk` | Public bootstrap repo |
| `sevmorris/mrk-prefs` | `~/.mrk/preferences/` | Private app preferences |

The two repositories keep the personal preference data out of the public repository. This data includes the iTerm2 profiles and the Raycast settings. The split keeps the data portable between machines.

Keep both repositories current. You can then restore the full setup on a new machine, and you transfer nothing by hand. The repositories are the source of truth.

> **How to adapt mrk for your own use:** This project fits one specific setup — mine. Nothing below is a recommendation for your machine. If you fork it, change each of these. The first one blocks everything else.
>
> 1. Set `PREFS_REPO` in `scripts/snapshot-prefs` to your own private preferences repository. It points at `sevmorris/mrk-prefs`, which you cannot read.
> 2. Replace the dotfiles in `dotfiles/` with your own.
> 3. Edit the `Brewfile`. Keep the `##` section headers, because the sync tools read them.
> 4. Edit the `add_login_item` list in `scripts/post-install`. It adds eight applications.
> 5. Edit the domain list in `scripts/snapshot-prefs`. It exports 18 named plist domains, plus every `io.github.sevmorris.*` domain as a group.
> 6. Edit `DOCK_APPS` in `scripts/dock-setup`. The script clears the Dock before it adds the applications.
> 7. Read `scripts/defaults.sh` before you run it. It writes 143 preference keys, and each key is a personal choice.
> 8. Remove the `install_github_app` calls in `scripts/post-install` if you do not want Barkeep and KeyVault. To install your own apps that way instead, set `GITHUB_APP_TEAM_ID` to your Developer ID team: it refuses any app not signed by that team.
>
> Use `make setup-dry` and `make sync ARGS=-n` to see the result of a phase before you apply it.

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
- Sets zsh as the login shell, registering it in `/etc/shells` first, with sudo. `chsh` refuses a shell that is not listed there and Homebrew does not register its own zsh, so without this the `chsh` failed and the login shell silently stayed `/bin/zsh`.
- Clones oh-my-zsh and two zsh plugins: zsh-autosuggestions and zsh-syntax-highlighting. Phase 1 skips a clone when the directory exists. A failed clone gives a warning, and Phase 1 continues.
- The two plugins are pinned to release tags, because `omz update` does not update a custom plugin. To move to a newer plugin release, change the tag in `scripts/setup` and delete the plugin directory. oh-my-zsh itself is not pinned: it publishes no tags, and `.zshrc` sets it to update itself.
- Writes a rollback script to `~/.mrk/defaults-rollback.sh`.

> **Note:** `scripts/defaults.sh` continues when a write fails. It counts the failed writes and reports the total at the end. The rollback script covers the writes that succeeded, and puts back each key's previous value exactly, with its type. Until 2026-09-11 it restored what `defaults read` prints instead, which turned lists, dictionaries, dates and data into text and garbled non-ASCII text.

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
- **Browsers:** Applies the Safari defaults and the Helium defaults. It opens the extension URLs when you ask for them. It no longer installs Chrome and Brave managed policies: those were JSON files in `policies/managed/`, which is the Linux policy mechanism, and Chrome on macOS never read them.
- **App defaults:** Writes the settings for Audio Hijack, Fission, AlDente, and the Rogue Amoeba update options.
- **Preferences pull:** Clones `mrk-prefs` when `~/.mrk/preferences/` is absent and GitHub accepts your SSH key.
- **Plist imports (18 apps):** Imports your preference plists. Phase 3 skips an app that already has preferences — in `~/Library/Preferences`, or in its sandbox container for a sandboxed app such as Keka — so it never overwrites a live configuration. It also skips an app that is not installed yet.
- **My own applications:** Imports every `io.github.sevmorris.*` plist that `snapshot-prefs` captured. This one does not check that the application is installed: several are tools with no bundle in `/Applications`, and on a new machine the preferences usually arrive before the application does, so an early import means the app finds its settings on first launch.
- **Barkeep:** Installs Barkeep from the most recent GitHub release, and only when the app in the release's DMG verifies, is signed by my Developer ID team, and is accepted by Gatekeeper as notarized; anything else is refused and counted as a failed step. Phase 3 skips this step when `/Applications/Barkeep.app` exists. To update Barkeep, use Barkeep, or delete the app first.
- **KeyVault:** Installs KeyVault from the most recent GitHub release, with the same signature checks as Barkeep. Phase 3 skips this step when `/Applications/KeyVault.app` exists. To update KeyVault, use KeyVault, or delete the app first.
- **Application Support restore:** Restores the Loopback and SoundSource configuration files. Phase 3 skips a file that exists.
- **Fonts:** Restores the fonts captured by `snapshot-prefs` into `~/Library/Fonts`. Phase 3 skips a font that is already installed.
- **GPG pinentry:** Points `gpg-agent` at `pinentry-mac`, so gpg asks for a passphrase in a window. Phase 3 adds one line to `~/.gnupg/gpg-agent.conf`, and it skips this step when the file already sets `pinentry-program`.
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

To skip every confirmation prompt, pass `--yes` or set `NONINTERACTIVE=1`.

`make all` does not install the App Store apps. Afterwards, sign in to App Store.app, run the command `make brew` printed, and then run `make post-install` again — it restores preferences and login items only for apps that are installed.

---

# Day-to-Day Workflow

## How to keep the Brewfile current

Two tools manage the Brewfile: `sync` on the command line, and Barkeep in a window.

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
5. sync starts the **mrk-picker** TUI. Each candidate takes one of three answers:

| Key | Answer |
|---|---|
| `space` | Add the package to the Brewfile |
| `i` | Add the package to `~/.mrk/sync-ignore`, so sync stops offering it |
| neither | Decide later. sync offers the package again on the next run |

   Press `a` to select every package in the category, `enter` to confirm and `q` to quit. The header counts both answers.
6. sync offers to add the packages you declined to `~/.mrk/sync-ignore`.
7. sync asks you, through `gum`, which Brewfile section each formula belongs to.
8. sync puts every cask in the existing cask section.
9. sync adds each entry to its section in alphabetical order.

If `brew list` fails, sync stops. An empty package list would make `-p` mark every Brewfile entry for deletion.

> **Note:** The mrk-picker binary is at `bin/mrk-picker`. It is platform-specific, and gitignore excludes it. If the binary is absent, build it with `make picker`.

**The ignore list (`~/.mrk/sync-ignore`)** holds one formula name or cask name per line. Do not add a `brew` or `cask` prefix. A `#` character starts a comment.

sync drops these names on every run, so a package that you keep installed but do not want in the Brewfile stops appearing.

**How the file is created.** sync creates the file when you accept the offer described below. You can also write the file yourself. To start an empty one, run `touch ~/.mrk/sync-ignore`.

**The offer to ignore a declined package.** sync shows the new packages in the picker, and you select the ones to add. It then offers the packages you declined, and you select the ones to ignore. sync adds each name you select to `~/.mrk/sync-ignore`, and shows the name it added.

The offer changes only the ignore list. It does not change the Brewfile. If you decline the offer, sync writes nothing, and it offers the same packages again on the next run. With `--dry-run`, sync shows the names but writes no file.

sync only adds to the file. It keeps your comments, your blank lines and your order, and it adds each new name at the end.

> **Note:** `make sync` can add back a package that you deleted from the Brewfile on purpose, because the package is still installed. To stop this, accept the offer to ignore the package, add the name to `~/.mrk/sync-ignore` yourself, or uninstall the package.

## How to keep the app preferences current

Configure an app, and then run `snapshot-prefs`. This command exports the preferences and pushes them.

```bash
snapshot-prefs
```

**How snapshot-prefs works**

1. snapshot-prefs exports the preference plist for each managed app with `defaults export`. It reads the copy the app uses: `~/Library/Preferences/<id>.plist` when that file exists, and the app's sandbox container otherwise. It skips an app with no preferences yet and keeps the copy it saved before. It does not quit any app, because `defaults export` already sees an open app's changes.
2. snapshot-prefs copies the config directories that are not defaults domains into `config/`. Calibre is one example: its settings and conversion presets live in `~/Library/Preferences/calibre/`. It does not copy the plugin code, which reinstalls from Calibre's plugin manager. It copies only `plugins/*.json` (the per-plugin settings) and `plugins/*/account` (the DeACSM Adobe activation, which cannot be recreated without a re-authorization).
3. snapshot-prefs converts each binary plist to xml1, and then scans every file for secrets.
4. snapshot-prefs commits the changes in `~/.mrk/preferences/` with a timestamped message.
5. snapshot-prefs pushes to `sevmorris/mrk-prefs` on GitHub.

You can run snapshot-prefs more than once. When nothing changed, it reports "No changes to push."

> **Caution:** `config/calibre/plugins/DeACSM/account/` holds real key material. It is kept deliberately — it cannot be
> regenerated without a re-authorization — and the secret scanner does not flag it, because its XML element names match none
> of the scanner's patterns. Nothing else will warn you it is there. This is why `sevmorris/mrk-prefs` must stay private.

> **Caution:** snapshot-prefs scans every staged file for API keys and tokens before it commits. If the scan finds a match, snapshot-prefs stops and asks you to confirm. It does not ask when `NONINTERACTIVE=1` is set or when there is no terminal — in those two cases it aborts. Read the reported lines before you answer. `mrk-push` applies the same gate to the mrk repository, and `pushall` applies it to every repository it commits. snapshot-prefs also refuses to start while a merge or rebase in `~/.mrk/preferences` is unfinished, and it checks before it exports anything.

## How to pull the app preferences

```bash
pull-prefs
```

`pull-prefs` clones `mrk-prefs` into `~/.mrk/preferences/`. If the clone exists, `pull-prefs` fast-forwards it instead.

`pull-prefs` only fetches the data. `post-install` does the restore. It imports each defaults-domain plist with `defaults import`, restores the Application Support files, and copies the config directories back into `~/Library/Preferences/`.

`post-install` skips an app that it finds already configured, so it does not overwrite your live settings. For a defaults domain, it skips when the domain holds any settings — in `~/Library/Preferences`, or in the app's sandbox container, where a sandboxed app such as Keka keeps them. It restores the preferences of an app, and registers its login item, only if the app is installed when it runs, so run it again after you install the App Store apps. For a config directory such as Calibre, it skips when `gui.json` exists, and it also skips when the directory holds any other file. To restore into a directory that already has files, delete the directory first. Quit an app before you restore it.

> **Note:** `make post-install` runs `pull-prefs` for you when `~/.mrk/preferences/` is absent and GitHub accepts your SSH key.

## How to configure the Dock

> **Caution:** `dock-setup` deletes every item from the Dock before it adds the new items, and it does not ask you to confirm. It does save the layout first: it exports `com.apple.dock` to `~/.mrk/plist-backups/com.apple.dock.plist` and appends a `defaults import` line to `~/.mrk/defaults-rollback.sh`. The snapshot is written once and never refreshed, so a second `make dock` cannot overwrite the original with the layout it just applied.

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
6. sync-login-items offers to add the new items you declined to `~/.mrk/login-items-ignore`.
7. sync-login-items updates `scripts/post-install` and `docs/manual.md`.

> **Caution:** If System Events returns no login items, or if the AppleScript fails, sync-login-items stops and shows an error. It does not continue, because an empty list looks the same as a complete list of deletions, and sync-login-items would then offer to delete every tracked item. Give Automation access in System Settings → Privacy & Security → Automation, and then run the command again.

**The ignore list (`~/.mrk/login-items-ignore`)** holds one login-item name per line. Use the app name, and do not add the `.app` suffix. A `#` character starts a comment.

sync-login-items drops these names on every run. An app that you keep as a login item, but do not want in `post-install`, stops appearing.

**How the file is created.** sync-login-items creates the file when you accept the offer described below. You can also write the file yourself. To start an empty one, run `touch ~/.mrk/login-items-ignore`.

**The offer to ignore a declined item.** sync-login-items shows the new items, and you select the ones to add. It then offers the items you declined, and you select the ones to ignore. sync-login-items adds each name you select to `~/.mrk/login-items-ignore`, and shows the name it added.

The offer changes only the ignore list. It does not add, delete or track anything in `scripts/post-install`. If you decline the offer, sync-login-items writes nothing, and it offers the same items again on the next run. With `--dry-run`, sync-login-items shows the names but writes no file.

sync-login-items only adds to the file. It keeps your comments, your blank lines and your order, and it adds each new name at the end.

> **Note:** Some apps add themselves back to the login items after an update. sync-login-items then offers the app again. A later sync can track it again. To stop this, accept the offer to ignore the app, or add the name to `~/.mrk/login-items-ignore` yourself.

> **Note:** sync-login-items drops the ignored names from the new items only. A name in the ignore list does not delete an item that `post-install` already tracks. If an app is both tracked and in the ignore list, `post-install` still adds the app at install time. sync-login-items shows these apps under "Ignored, but still tracked", and it offers to delete them from `scripts/post-install`.

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

## Companion apps

Two native macOS apps come with mrk. `make post-install` installs both apps. Each app has its own repository, and the links below have the releases.

**[Barkeep](https://github.com/sevmorris/Barkeep)** manages your Homebrew Brewfile in a window.

**[KeyVault](https://github.com/sevmorris/KeyVault)** manages your SSH keys, your GPG keys, your API keys and your secure notes. KeyVault does not hold all four the same way, and the difference decides how each one moves to a new machine.

- **API keys and notes.** KeyVault owns these. It keeps each one in the login Keychain, and nothing else holds a copy.
- **SSH and GPG keys.** KeyVault reads the key material in `~/.ssh` and `~/.gnupg`. It shows the keys and it generates new ones, but it never copies the private keys into the Keychain.

A KeyVault backup goes out as one passphrase-encrypted OpenPGP archive. Any `gpg` reads that archive, so the backup does not need KeyVault.

> **Caution:** The KeyVault archive holds the API keys and the notes only. It does not hold your SSH keys, and it does not hold your GPG keys. Use `make snapshot-keys` for those. See "How to prepare for a new machine".

> **Caution:** `snapshot-prefs` does not export the KeyVault preferences, and it must not. Use the KeyVault export for the API keys and the notes, and `make snapshot-keys` for the key files.

## Standalone Utilities

These tools are in `~/bin/`, symlinked from `mrk/bin/`. They have no Make target, so run them directly.

| Command | Purpose |
|---|---|
| `clear-app-caches` | Clears cache directories for common apps (Helium, Slack, Discord, VS Code, Spotify, Chrome — every Chrome profile). It never touches profile data or Spotify's offline downloads |
| `clear-derived-data` | Clears the Xcode DerivedData directory |
| `mrk-push` | Commits and pushes `~/mrk`, then deletes the old GitHub Pages deployments. Scans every file the commit carries for secrets first, from whichever directory you run it in. Refuses to run while a merge or rebase in `~/mrk` is unfinished |
| `prune-deployments` | Deletes the old GitHub Pages deployments and keeps the newest. It finds the repository from the origin remote, or use `--repo OWNER/NAME`. It always protects the deployment that serves the site, so a failed deploy cannot cause it to delete the live one. Use `--dry-run` first |
| `pushall` | Commits and pushes each repository in `~/Projects`, and then syncs `~/mrk`. Scans the staged files for secrets before each commit. It stages only the tracked files. It leaves a repository alone, and reports it as failed, while a merge, rebase or cherry-pick in it is unfinished. Use `pushall --dry-run` to run the scan and change nothing |
| `update-full` | Full update pass: pulls mrk, quits the applications, runs the macOS and package updates, builds the Go tools again, runs `clean-ds` and `brew doctor`, and then offers a reboot. It stops with an error when there is no terminal, unless you give `--yes`. The `update --full` command is the same command |
| `clean-ds` | Removes the `.DS_Store` files from the local disk. It does not examine `~/Library`, `~/Desktop`, the network volumes, or the external volumes. Use `clean-ds --dry-run` to see the files first |
| `hide_tm.sh` | Hides the Time Machine volumes from the Finder sidebar. The default name is `TimeMachine`. Give the volume names, or set `TM_VOLUMES` |
| `nuke-mrk` | Moves `~/mrk` and `~/.mrk` to the Trash, deletes the `~/bin` symlinks, the dotfile symlinks and the `~/Projects/CLAUDE.md` link, and offers the rollbacks. It does NOT change Homebrew. `mrk-menu` lists it under Nuclear options |

> `nuke-mrk` deletes more than `make uninstall`. Use `make uninstall` to unlink mrk only. Use `nuke-mrk` to get a clean machine for a test installation.
>
> **Caution:** before it deletes anything, `nuke-mrk` lists any uncommitted change, unpushed commit or stash in `~/mrk` or `~/.mrk/preferences` and stops unless you answer `y`. The fresh clone it tells you to make cannot contain them. Until 2026-09-11 it trashed them without a word — including the Brewfile commit its own pre-nuke `sync -c` had just made, because `sync -c` commits and does not push. That commit is now pushed when it is the only one waiting. If you decline to run the rollback scripts, `nuke-mrk` keeps them, with `~/.mrk/plist-backups/`, in `~/.mrk` — the settings they undo are still in force, and a reinstall adds to them rather than recording mrk's own values as the originals. Until 2026-09-11 they went to the Trash with the rest.

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

Do these ten steps on the **old machine** before you transfer. They run in the same order as the migration checklist in SMAC-1, and the first one is first for a reason: it is the only step with no second chance.

**1. Bundle your SSH and GPG keys**

> **Caution:** `snapshot-prefs` carries no private key, and it must not. `mrk-prefs` is a git repository. Keys go into their own encrypted archive instead.

```bash
make snapshot-keys
```

`snapshot-keys` bundles `~/.ssh`, `~/.gnupg` and your code-signing identities into one passphrase-encrypted OpenPGP archive. It writes the archive to `~/Desktop` and pushes it nowhere. Use `ARGS="-o PATH"` to write it somewhere else, and `ARGS=-n` to see what it would bundle first.

> **Caution:** The identities need two passphrases. macOS asks for a `.p12` passphrase of its own, on top of the archive passphrase. Store both in your password manager. Apple reissues a lost certificate, but the private key is generated once — no archive, no key, no signing.

`snapshot-keys` does not carry notarytool credentials, because a keychain profile has no export. Note which profile names your release scripts use — grep for `--keychain-profile`, and check every script, not only `release.sh` — and recreate each one with `xcrun notarytool store-credentials` on the new machine.

The script refuses to write inside `~/mrk` or `~/.mrk`, because `nuke-mrk` deletes both. Copy the archive to an encrypted external disk, and keep the passphrase in your password manager.

**2. Export the KeyVault vault**

`snapshot-keys` covers the key files. It does not cover the secrets KeyVault owns.

Start KeyVault, and export the vault. KeyVault writes its own passphrase-encrypted OpenPGP archive, which holds the API keys and the notes. Put that archive on the transfer disk too.

> **Note:** The two archives hold different things, and you need both. `snapshot-keys` holds the files in `~/.ssh` and `~/.gnupg`. The KeyVault export holds the API keys and the notes from the login Keychain. Neither one holds the other's contents.

**3. Sync the Brewfile**

```bash
make sync ARGS=-c
```

This command adds the packages that you installed since the last sync. It then commits the Brewfile.

**4. Snapshot app preferences**

```bash
make snapshot-prefs
```

This command exports the 18 app preference plists, the Application Support files, the config directories, your installed fonts and a manifest of your git repositories. It then pushes them. Check that the push succeeded: the output ends with "Pushed to git@github.com:sevmorris/mrk-prefs.git".

**5. Capture the login items**

```bash
make sync-login-items ARGS=-c
```

Login items live in the system's LaunchServices database, and `scripts/post-install` knows only the ones captured the last time this ran. Anything added since exists on this machine and nowhere else, and Phase 3 on the new machine would restore the stale list.

**6. Push any pending mrk changes**

```bash
cd ~/mrk
git status
git push
```

**7. Push the project repositories**

```bash
pushall
```

mrk brings `~/Projects` back to the new machine only from GitHub: `restore-repos` clones what the manifest records, and Magic Backup Machine does not back up `~/Projects`. Time Machine may hold a copy, but nothing in mrk restores from it — anything that is not on GitHub when you wipe comes back only if you dig it out of a Time Machine backup by hand, and only as it was at the last backup. `pushall` commits and pushes the branch each repository is on, including a repository kept one folder down, such as `JustIn/JustIn`, and then names what it leaves behind — commits on other branches that are on no remote, stashes, and folders in `~/Projects` that are not repositories. Deal with each one: push the branch, apply or drop the stash, copy the folder to the transfer disk.

Files a repository ignores are not pushed either. Copy any you need by hand, such as a credential file that `.gitignore` keeps out of the repository.

`pushall` does not push DoublEnder's Cloud overlay, `~/DoublEnder-cloud.git`: its files are versioned beside the public repository, which ignores them. `pushall` names the overlay's unpushed commits and uncommitted changes with the rest of what it leaves behind. Commit and push them with `decloud commit` and `decloud push`.

**8. Run a Magic Backup Machine backup**

Open Magic Backup Machine and run a full backup to the local and external destinations. It copies the Logic Pro projects, the audio presets, the browser profiles and the other data that mrk does not manage. It does not copy `~/Projects`; step 7 covers that.

**9. Verify SSH authentication**

```bash
ssh -T git@github.com
# Expected: Hi sevmorris! You've successfully authenticated...
```

The new machine needs your SSH key. `make post-install` uses it to pull mrk-prefs.

**10. Note anything not covered by mrk**

Write down the apps, the license keys and the settings that mrk does not manage:

- The App Store apps are listed in the Brewfile as `mas` entries, but `make brew` does not install them — `mas install` needs root, and `brew bundle` never runs as root. On the new machine, sign in to App Store.app by hand (`mas` has had no `signin` command since macOS 12), then run the command `make brew` prints at the end: `grep '^mas ' ~/mrk/Brewfile | sed 's/.*id: //' | xargs sudo mas install`. Then run `make post-install` again: it restores preferences and login items only for apps that are installed, and BetterSnapTool and Chrono Plus come from the App Store.
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

This step installs Homebrew and every formula and cask in the Brewfile. It is the slowest step, and its duration depends on the number of packages.

It does not install the Mac App Store apps the Brewfile lists — `mas install` needs root, and `brew bundle` never runs as root. It ends by printing the command that does. Sign in to App Store.app by hand, then run that command:

```bash
grep '^mas ' ~/mrk/Brewfile | sed 's/.*id: //' | xargs sudo mas install
```

Run it before Step 5. `post-install` restores the preferences and login item of an app only if the app is installed, and BetterSnapTool and Chrono Plus are App Store apps. If you install them later, run `make post-install` again.

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

## Step 6 — Restore your secrets

Phase 3 installs KeyVault. Your secrets are not on the new machine yet, because `mrk-prefs` carries none of them. You made two archives on the old machine, and each one restores by its own route. Skip either one that you do not use.

**SSH and GPG keys**

```bash
make restore-keys ARGS=~/Desktop/mrk-keys-<timestamp>.asc
```

`restore-keys` decrypts the archive, puts `~/.ssh` and `~/.gnupg` back, corrects the permissions that SSH and GPG demand, and imports your code-signing identities into the login Keychain. macOS asks for the `.p12` passphrase during the import — that is the second passphrase, not the archive one. To see the contents first, add `-l`:

```bash
make restore-keys ARGS="-l ~/Desktop/mrk-keys-<timestamp>.asc"
```

`restore-keys` never overwrites in place. It moves an existing `~/.ssh` or `~/.gnupg` aside with a timestamp first, and it puts them back if the restore fails.

**API keys and notes**

1. Copy the KeyVault archive from the transfer disk.
2. Start KeyVault.
3. Import the archive, and give it the passphrase.

KeyVault writes each item back into the login Keychain. KeyVault reads `~/.ssh` and `~/.gnupg` directly, so your SSH and GPG keys show in KeyVault as soon as `restore-keys` puts the files in place.

Check the result:

```bash
ssh -T git@github.com                      # GitHub authentication
gpg --list-secret-keys                     # GPG secret keys
security find-identity -v -p codesigning   # signing identities
```

**Your repositories**

`snapshot-prefs` recorded which repositories this machine had, and `pull-prefs` brought that manifest down in Phase 3. Clone them all back:

```bash
make restore-repos          # ARGS=-n to see what it would clone first
```

`restore-repos` skips any repository already on disk. It lists bare repositories but never clones one: a bare overlay shares its working tree with another repository, so a plain clone puts the files in the wrong shape. Set those up by hand.

## Step 7 — Check the installation

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

Then install the App Store apps with the command `make brew` printed, and run `make post-install` again to restore the preferences and login items it skipped for them.

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

**Keys**

| Command | Description |
|---|---|
| `make snapshot-keys` | Bundle `~/.ssh`, `~/.gnupg` and the code-signing identities into a passphrase-encrypted OpenPGP archive (`ARGS="-o PATH"` · `ARGS=-n` dry run · `ARGS=-f` overwrite · `ARGS=--no-signing` skip the identities) |
| `make restore-keys ARGS=<archive>` | Restore `~/.ssh`, `~/.gnupg` and the identities from that archive (`ARGS="-l <archive>"` lists the contents) |
| `make restore-repos` | Clone the repositories listed in the mrk-prefs manifest (`ARGS=-n` dry run) |

> No preferences command touches a private key.
>
> `snapshot-prefs` pushes to a git repository, so a private key must never reach it. `snapshot-keys` writes one encrypted file to a path you choose, and it pushes nowhere. The two share no destination, on purpose.
>
> `snapshot-keys` refuses to write inside `~/mrk` or `~/.mrk`. `nuke-mrk` moves both directories to the Trash, and an archive that a wipe deletes is not a backup. (`make uninstall` deletes neither.)
>
> The archive is ordinary OpenPGP. `gpg -d <archive> | tar -tvf -` reads it on any machine, with no mrk installed.
>
> **The signing identity has two passphrases.** The archive has one. The `.p12` inside it has a second, which macOS asks for in its own dialog. Store both. A good archive with a forgotten `.p12` passphrase does not give the identity back.
>
> `snapshot-keys` does not carry notarytool credentials, and cannot. A keychain profile has no export, and no tool but notarytool can read one — `security` cannot even confirm that a working profile exists. Recreate each profile your release scripts name with `xcrun notarytool store-credentials`, and check one with `xcrun notarytool history --keychain-profile <name>`.
>
> **An Apple ID password reset revokes every app-specific password**, so it silently invalidates every notarytool profile you own. The profiles still exist; they just return HTTP 401. Recreate each one after a reset.

**Build Tools**

| Command | Description |
|---|---|
| `make picker` | Build the mrk-picker TUI binary |
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
| `make setup` / `make install` | Phase 1: the shell, the dotfiles and the macOS defaults |
| `make setup-dry` | Show the Phase 1 changes, but apply nothing |
| `make brew` | Phase 2: the Homebrew formulae and casks |
| `make post-install` | Phase 3: the app configuration and the login items |

To skip the confirmation prompts, pass `ARGS=--yes`.

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
| `make check` | Run the local validation: picker and defaults descriptions, a secret scan over every tracked file, the commit-gate check, the `cleanempties` test, round trips through the defaults and harden undo scripts, shellcheck and go test |
| `make ci` | Run the local validation, and build the TUI binaries |
| `make tidy` | Run `go mod tidy` in every Go tool directory |

**Diagnostics & Launchers**

| Command | Description |
|---|---|
| `mrk-menu` | Start the TUI launcher (see [mrk-menu](#mrk-menu) above for the keys) |
| `make status` | Print the installation checks as a plain-text report. The `status` command is the mrk-status TUI dashboard, a separate program |
| `make doctor` | Check that `~/bin` is on the PATH. `make doctor ARGS=--fix` adds it to `.zshrc` |
| `make fix-exec` | Set the executable bit on the scripts and the `~/bin` symlinks, and remove a `~/bin` symlink whose script is gone from the repository |

---

# What `make status` checks

`make status` checks the whole installation and shows eight results, plus Backups when there is a backup to report. It prints them as text. The `status` command runs the same checks in the mrk-status dashboard, where **f** runs the suggested fix; the two are separate programs:

- **Dotfiles** — The files that mrk symlinked into `~/`, and the files that are absent.
- **Tools** — The `~/bin` symlinks that work, and the symlinks that are broken.
- **macOS Defaults** — Whether mrk applied the defaults. The rollback script is the evidence.
- **Security Hardening** — Whether mrk applied the hardening.
- **Backups** — Shown *only when backups exist*: how many, where, and the most recent. This is a report, not a health check — it can neither fail nor be fixed — so with nothing to report it is omitted rather than shown empty. See [What the backups are](#what-the-backups-are).
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
| `~/Projects/CLAUDE.md` | Symlink to `assets/CLAUDE.md`. Guidance Claude Code reads for the whole `~/Projects` tree; linked by `make post-install` |
| `~/.mrk/defaults-rollback.sh` | Undoes the macOS system defaults that `make defaults` wrote, and the app plists that post-install imported. It does **not** cover the app-preference scripts that Phase 3 runs for Safari, Helium, AlDente, Audio Hijack, Fission and Rogue Amoeba. Those scripts write their defaults directly |
| `~/.mrk/hardening-rollback.sh` | Undoes the security hardening |
| `~/.mrk/sync-ignore` | The formula names and cask names that `sync` does not offer. One name per line. sync creates this file when you accept its offer to ignore a declined package |
| `~/.mrk/login-items-ignore` | The login-item names that `sync-login-items` does not offer. One name per line. sync-login-items creates this file when you accept its offer to ignore a declined item |

### What the backups are

When `make setup` links a dotfile into `~`, it checks the destination first. If
a file is already there and it is **not** a symlink — a `.zshrc` you wrote
before mrk existed — setup **moves** it into `~/.mrk/backups/<timestamp>/`
rather than deleting it. If the destination is already the correct symlink,
setup skips the file and no backup is made.

So the directory holds the machine's *pre-mrk* dotfiles. The repository is the
source of truth for mrk's dotfiles; the backup is the one copy of what those
files replaced, which the repository never had.

Two consequences:

1. **On a clean install the directory does not exist at all.** It is created
   only at the moment setup actually displaces a file, so its absence means
   setup never found one. That is not a fault, and running `make install`
   again will not create it: setup skips destinations that are already correct
   symlinks.

2. **Nothing restores them.** No script reads a backup back into place —
   `make uninstall` does not, and neither does anything else. They are an inert
   archive you would copy from by hand. `nuke-mrk` moves the whole `~/.mrk`
   directory to the Trash, backups included.

Once a new machine is working, the backups have served their purpose. Keep them
only if you still want the option of reading what a dotfile looked like before
mrk replaced it.


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
