# Audit Module 1 — Call Graph
<!-- generated 2026-04-24, audit/static-pass branch -->

All paths are relative to repo root unless otherwise noted.
External commands are denoted as bare names (e.g. `defaults`, `brew`, `git`).
Go binaries built from `tools/` are listed as leaves.

---

## Target: `help`

```
help
  grep / awk (reads Makefile, prints target list — no side effects)
```

---

## Target: `all`

Depends on: `fix-exec`, `setup`, `brew`, `post-install`, `build-tools`.
See each sub-target below. After they complete, `all` prints completion
messages and optionally (with `ARGS=--adventure`) prints a "YOU HAVE WON"
banner.

```
all
  fix-exec  [see fix-exec target]
  setup     [see setup target]
  brew      [see brew target]
  post-install  [see post-install target]
  build-tools   [see build-tools target]
  printf (stdout messages only)
```

---

## Target: `adventure`

```
adventure
  scripts/adventure-prologue  (interactive text-adventure TUI — no filesystem side effects;
                               exits 0 on success, 1 if user quits)
  $(MAKE) all ARGS=--adventure-end  [see all target — full install with adventure banner]
```

---

## Target: `build-tools`

```
build-tools
  $(MAKE) picker       [see picker target]
  $(MAKE) bf           [see bf target]
  $(MAKE) mrk-status   [see mrk-status target]
```

---

## Target: `fix-exec`

Implemented inline in the Makefile — does NOT call `scripts/fix-exec`.

```
fix-exec
  find scripts/ -type f -maxdepth 1  (enumerates scripts)
    chmod +x (sets executable bits on scripts/*)
  find bin/ -type f -maxdepth 1      (enumerates bin files)
    chmod +x (sets executable bits on bin/*)
```

Note: `scripts/fix-exec` is a separate script that is linked into `~/bin`
via `make setup` but is never invoked by any Makefile target.

---

## Target: `install` / `setup`

`install` is an alias for `setup`. Both call `scripts/setup`.

```
install / setup
  scripts/setup
    [sources] scripts/lib.sh  (shared helpers — no side effects when sourced)
    check_macos               (uname -s — read-only)
    setup_logging             (mkdir -p ~/.mrk; rotates ~/.mrk/install.log if >10MB via mv)
    exec > >(tee -a ~/.mrk/install.log)  (redirects stdout to log — creates/appends file)

    phase_xcode
      xcode-select -p        (read — checks for CLT)
      xcode-select --install (triggers GUI installer; only if CLT absent)
      sudo xcodebuild -license accept  (accepts Xcode license; only if Xcode.app present)

    phase_link_tools
      mkdir -p ~/bin
      find scripts/ -maxdepth 1 -type f  (enumerate scripts)
      python3 -c os.path.realpath(...)   (resolve symlink targets — read-only)
      ln -sf <scripts/*> ~/bin/<name>    (creates symlinks; prefixed ones get "mrk-" prefix:
                                          brew→mrk-brew, install→mrk-install,
                                          setup→mrk-setup, post-install→mrk-post-install,
                                          defaults.sh→mrk-defaults, uninstall→mrk-uninstall)
      find bin/ -maxdepth 1 -type f      (enumerate bin files)
      ln -sf <bin/*> ~/bin/<name>        (creates symlinks for all bin/ executables)
      ln -sf bin/lib ~/bin/lib           (symlinks lib/ directory)

    phase_dotfiles
      mkdir -p ~/.mrk/backups/<timestamp>
      for each dotfiles/* (excluding *.example, README*, *.md):
        mv <existing-file> ~/.mrk/backups/<timestamp>/  (backup if non-symlink exists)
        ln -sfn dotfiles/<file> ~/<file>               (creates dotfile symlinks in $HOME)

    phase_defaults
      scripts/defaults.sh  [see defaults target]
      (optional) sudo defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText
                  (only if env MRK_LOGIN_MSG is set; appends rollback to ~/.mrk/defaults-rollback.sh)

    phase_shell
      dscl . -read "/Users/$USER" UserShell  (read current login shell)
      chsh -s <zsh-path>                     (changes login shell — only if not already zsh)
```

---

## Target: `setup-dry`

Calls `scripts/setup --dry-run`. No filesystem mutations occur (all writes
are suppressed by DRY_RUN=1 guards). Read-only traversal only.

---

## Target: `brew`

```
brew
  scripts/brew
    [sources] scripts/lib.sh
    curl -sf --max-time 5 https://brew.sh   (network check — exits 1 if no connectivity)

    install_homebrew (if Homebrew absent)
      /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
                        (network — downloads and runs official Homebrew installer)
      eval "$(/opt/homebrew/bin/brew shellenv)"  (sets PATH/env for current shell)

    resolve_homebrew
      eval "$($HOMEBREW shellenv)"  (extends PATH in current shell)

    ensure_gum (if mrk-picker absent)
      $HOMEBREW install gum  (network — installs gum package)

    install_brewfile
      mktemp -t mrk                          (creates temp Brewfile)
      $HOMEBREW list --formula               (read — lists installed formulae)
      $HOMEBREW list --cask                  (read — lists installed casks)
      [interactive] bin/mrk-picker --brewfile Brewfile ...
                        (Go binary — TUI package selector; outputs selection to stdout)
        OR gum choose  (interactive TUI — selects packages)
      $HOMEBREW bundle --file=<TEMP_BREWFILE> --verbose
                        (network — installs selected packages from Brewfile)
      rm -f <TEMP_BREWFILE>  (cleanup on exit)
```

---

## Target: `post-install`

```
post-install
  scripts/post-install
    [sources] scripts/lib.sh

    # Topgrade config
    mkdir -p ~/.config
    ln -s assets/topgrade.toml ~/.config/topgrade.toml
       (symlink; backs up existing ~/.config/topgrade.toml → ~/.config/topgrade.toml.bak first)

    # Browser defaults
    bash assets/browsers/safari-defaults.sh   [see safari-defaults.sh leaf]
    bash assets/browsers/helium-defaults.sh   [see helium-defaults.sh leaf]

    open <url>  (opens extension URLs in default browser — for Safari/Chrome/Brave
                 if *-extensions.txt files exist; only if user consents interactively)

    # Browser policies
    mkdir -p "$HOME/Library/Application Support/Google/Chrome/policies/managed"
    cp assets/browsers/chrome-policy.json → above path
    mkdir -p "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/policies/managed"
    cp assets/browsers/brave-policy.json  → above path

    # GitHub app: Barkeep
    install_github_app "/Applications/Barkeep.app" "sevmorris/Barkeep"
      curl -sf "https://api.github.com/repos/sevmorris/Barkeep/releases/latest"
                        (network — GitHub API: fetch latest release JSON)
      jq -r (parses JSON — external command)
      mktemp -t mrk  (temp DMG, temp mountpoint)
      curl -L -sf -o <tmp_dmg> <dmg_url>
                        (network — downloads DMG)
      hdiutil attach <tmp_dmg> -mountpoint <tmp_mount> -quiet -nobrowse
                        (mounts DMG)
      find <tmp_mount> -maxdepth 2 -name "*.app"  (locates .app in DMG)
      cp -R <found.app> /Applications/
                        (copies Barkeep.app to /Applications/)
      hdiutil detach <tmp_mount> -quiet  (unmounts DMG)
      rm -f <tmp_dmg>; rm -rf <tmp_mount>  (cleanup)
      xattr -cr /Applications/Barkeep.app  (removes quarantine xattr)

    # Application preference defaults
    bash assets/preferences/audio-hijack-defaults.sh   [see audio-hijack-defaults.sh leaf]
    bash assets/preferences/fission-defaults.sh        [see fission-defaults.sh leaf]
    bash assets/preferences/rogue-amoeba-updates.sh    [see rogue-amoeba-updates.sh leaf]
    bash assets/preferences/aldente-defaults.sh        [see aldente-defaults.sh leaf]

    # SSH check for mrk remote URL switch
    ssh -T -o ConnectTimeout=5 git@github.com
                        (network — tests SSH auth to GitHub)
    git -C <mrk-dir> remote get-url origin  (read)
    git -C <mrk-dir> remote set-url origin <ssh-url>
                        (modifies git remote URL if currently HTTPS — only if SSH auth succeeds)

    # Preferences: pull from mrk-prefs
    bash scripts/pull-prefs  [see pull-prefs target — git clone or pull from mrk-prefs]
                        (only if SSH auth succeeds AND ~/.mrk/preferences/ absent)

    # Plist imports
    defaults import <bundle-id> <plist-file>
                        (imports each app's plist from ~/.mrk/preferences/ — per app)
      Apps: BetterSnapTool, Ice, iTerm2, Raycast, Stats, Loopback,
            SoundSource, Audio Hijack, Farrago, Piezo, Typora, Keka,
            TimeMachineEditor, MacWhisper

    # App support files
    mkdir -p "$HOME/Library/Application Support/<app>"
    cp <src> "$HOME/Library/Application Support/<app>/<file>"
      Apps/files: Loopback (Devices.plist, RecentApps.plist),
                  SoundSource (Presets.plist, CustomPresets.plist, Sources.plist, Models.plist)

    # Login items
    osascript -e "tell application \"System Events\" to get the name of every login item"
                        (read — checks existing login items)
    osascript -e "tell application \"System Events\" to make login item at end with properties ..."
                        (adds login item via System Events AppleScript)
      Apps added: AlDente, BetterSnapTool, Bitwarden, Chrono Plus, Dropbox,
                  Hammerspoon, Ice, NordPass, Raycast, SoundSource, Stats
```

---

## Leaf: `assets/browsers/safari-defaults.sh`

```
assets/browsers/safari-defaults.sh
  [sources] scripts/lib.sh
  defaults write com.apple.Safari ShowFullURLInSmartSearchField -bool true
  defaults write com.apple.Safari ShowFavoritesBar-v2 -bool true
  defaults write com.apple.Safari ShowOverlayStatusBar -bool true
  defaults write com.apple.Safari SendDoNotTrackHTTPHeader -bool true
  defaults write com.apple.Safari BlockStoragePolicy -int 2
  defaults write com.apple.Safari AutoOpenSafeDownloads -bool false
  defaults write com.apple.Safari AutoFillCreditCardData -bool false
  defaults write com.apple.Safari IncludeDevelopMenu -bool true
  defaults write com.apple.Safari WebKitDeveloperExtrasEnabledPreferenceKey -bool true
  defaults write com.apple.Safari "com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled" -bool true
  defaults write com.apple.Safari ExtensionsEnabled -bool true
  defaults write com.apple.Safari InstallExtensionUpdatesAutomatically -bool true
```

---

## Leaf: `assets/browsers/helium-defaults.sh`

```
assets/browsers/helium-defaults.sh
  [sources] scripts/lib.sh
  defaults write net.imput.helium SUEnableAutomaticChecks -bool true
  defaults write net.imput.helium SUAutomaticallyUpdate -bool true
```

---

## Leaf: `assets/preferences/audio-hijack-defaults.sh`

```
assets/preferences/audio-hijack-defaults.sh
  [sources] scripts/lib.sh
  defaults write com.rogueamoeba.AudioHijack applicationTheme -int 2
  defaults write com.rogueamoeba.AudioHijack audioEditorBundleID -string "com.izotope.RXPro"
  defaults write com.rogueamoeba.AudioHijack bufferFrames -int 512
  defaults write com.rogueamoeba.AudioHijack allowExternalCommands -int 0
```

---

## Leaf: `assets/preferences/fission-defaults.sh`

```
assets/preferences/fission-defaults.sh
  [sources] scripts/lib.sh
  defaults write com.rogueamoeba.Fission applicationTheme -int 2
  defaults write com.rogueamoeba.Fission CustomFormatWAV -dict ...  (multi-key dict write)
  defaults write com.rogueamoeba.Fission CustomFormatMP3 -dict ...
  defaults write com.rogueamoeba.Fission CustomFormatAAC -dict ...
  defaults write com.rogueamoeba.Fission exportFormatType -int 5
  defaults write com.rogueamoeba.Fission showStartWindow -bool false
```

---

## Leaf: `assets/preferences/rogue-amoeba-updates.sh`

```
assets/preferences/rogue-amoeba-updates.sh
  [sources] scripts/lib.sh
  for bundle_id in com.rogueamoeba.{AudioHijack,Fission,Loopback,Piezo,soundsource,Farrago2}:
    defaults write <bundle_id> SUAllowsAutomaticUpdates -bool false
    defaults write <bundle_id> SUAutomaticallyUpdate -bool false
```

---

## Leaf: `assets/preferences/aldente-defaults.sh`

```
assets/preferences/aldente-defaults.sh
  [sources] scripts/lib.sh
  defaults write com.apphousekitchen.aldente-pro chargeVal -int 80
  defaults write com.apphousekitchen.aldente-pro calibrationBackupPercentage -int 80
  defaults write com.apphousekitchen.aldente-pro sailingMode -bool true
  defaults write com.apphousekitchen.aldente-pro sailingLevel -int 5
  defaults write com.apphousekitchen.aldente-pro automaticDischarge -bool true
  defaults write com.apphousekitchen.aldente-pro allowDischarge -bool false
  defaults write com.apphousekitchen.aldente-pro magsafeBlinkDischarge -bool true
  defaults write com.apphousekitchen.aldente-pro SUAutomaticallyUpdate -bool true
  defaults write com.apphousekitchen.aldente-pro SUEnableAutomaticChecks -bool true
```

---

## Target: `tools`

```
tools
  scripts/setup --only tools
    [sources] scripts/lib.sh
    phase_link_tools only  [see setup → phase_link_tools]
```

---

## Target: `dotfiles`

```
dotfiles
  scripts/setup --only dotfiles
    [sources] scripts/lib.sh
    phase_dotfiles only  [see setup → phase_dotfiles]
```

---

## Target: `defaults`

```
defaults
  scripts/defaults.sh
    [sources] scripts/lib.sh
    mkdir -p ~/.mrk
    printf '#!/usr/bin/env bash\n' > ~/.mrk/defaults-rollback.sh  (truncates and rewrites rollback)
    chmod +x ~/.mrk/defaults-rollback.sh
    write_default <domain> <key> <type> <value>  (for each default — see side-effects doc)
      defaults read <domain> <key>               (read — check current value)
      defaults read-type <domain> <key>          (read — check type)
      defaults write <domain> <key> -<type> <value>  (write)
      echo "..." >> ~/.mrk/defaults-rollback.sh  (append rollback line)
    killall Finder      (restarts Finder to apply changes)
    killall Dock        (restarts Dock to apply changes)
    killall SystemUIServer  (restarts SystemUIServer for menu bar changes)
```

---

## Target: `trackpad`

```
trackpad
  scripts/defaults.sh --with-trackpad
    [identical to defaults target, plus:]
    for domain in {com.apple.AppleMultitouchTrackpad, com.apple.driver.AppleBluetoothMultitouch.trackpad}:
      defaults write <domain> Clicking -bool false
      defaults write <domain> ForceSuppressed -bool true
      defaults write <domain> TrackpadCornerSecondaryClick -int 2
      defaults write <domain> TrackpadFiveFingerPinchGesture -int 0
      ... (14 trackpad keys total per domain × 2 domains = 28 additional writes)
    killall Finder, Dock, SystemUIServer  (same as defaults)
```

---

## Target: `uninstall`

```
uninstall
  scripts/uninstall
    find ~/bin -maxdepth 1 -type l            (enumerate symlinks in ~/bin)
    readlink <link>                            (resolve each symlink target)
    rm -f <link>                               (removes symlinks pointing into repo scripts/ or bin/)
    find ~/.local/bin -maxdepth 1 -type l     (also cleans up legacy ~/.local/bin links)
    rm -f <link>                               (removes legacy links)
    offer_rollback:
      ~/.mrk/defaults-rollback.sh             (interactive — user decides; runs rollback if yes)
      ~/.mrk/hardening-rollback.sh            (interactive — user decides; runs rollback if yes)
        [rollback scripts written by defaults.sh / hardening.sh; content is dynamic]
```

---

## Target: `update`

```
update
  topgrade  (if installed — external; upgrades all package managers, apps, tools)
    OR
  brew update && brew upgrade  (if topgrade absent — updates Homebrew and all formulae/casks)
```

---

## Target: `updates`

```
updates
  softwareupdate -ia  (macOS Software Update — installs all available updates)
```

---

## Target: `harden`

```
harden
  scripts/hardening.sh
    mkdir -p ~/.mrk
    printf '#!/usr/bin/env bash\n' > ~/.mrk/hardening-rollback.sh  (rewrites rollback)
    chmod +x ~/.mrk/hardening-rollback.sh

    # Touch ID for sudo
    grep -q 'pam_tid.so' /etc/pam.d/sudo          (read — check if already enabled)
    sudo cp /etc/pam.d/sudo /etc/pam.d/sudo.backup.mrk  (backup existing PAM config)
    echo 'auth sufficient pam_tid.so' >> rollback
    mktemp -t mrk                                   (temp file for new PAM config)
    { echo 'auth       sufficient     pam_tid.so'; cat /etc/pam.d/sudo; } > <tmpfile>
    grep -q 'pam_tid\.so' <tmpfile>                 (validate — check pam_tid present)
    grep -qE 'pam_smartcard\.so|pam_opendirectory\.so' <tmpfile>  (validate — check auth chain)
    sudo cp <tmpfile> /etc/pam.d/sudo               (writes new PAM config)
    sudo mv /etc/pam.d/sudo.backup.mrk /etc/pam.d/sudo  (restore on failure)
    rm -f <tmpfile>

    # Screensaver password
    defaults read com.apple.screensaver askForPassword   (read — capture current value)
    defaults read com.apple.screensaver askForPasswordDelay  (read)
    echo "defaults write ..." >> ~/.mrk/hardening-rollback.sh  (rollback entries)
    defaults write com.apple.screensaver askForPassword -int 1
    defaults write com.apple.screensaver askForPasswordDelay -int 0

    # Firewall
    /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate  (read)
    echo "socketfilterfw --setglobalstate <prev>" >> rollback
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
```

---

## Target: `status`

```
status
  scripts/status
    [read-only: checks filesystem, brew, dscl, find — no side effects]
    dscl . -read "/Users/$USER" UserShell  (read)
    brew --version                         (read)
    brew list --formula                    (read)
    brew list --cask                       (read)
    find ~/bin -maxdepth 1 -type l         (read)
```

---

## Target: `doctor`

```
doctor
  scripts/doctor  [default: check mode]
    check mode:
      :$PATH: match  (read-only)
    --fix mode:
      mkdir -p ~/bin
      cat >> ~/.zshrc  (appends PATH entry for ~/bin — only if not already present)
```

---

## Target: `picker`

```
picker
  (go-build macro)
    go mod tidy  (in tools/picker/ — may update go.sum)
    go build -o bin/mrk-picker .  (compiles Go source → bin/mrk-picker)
    chmod +x bin/mrk-picker
  ln -sf bin/mrk-picker ~/bin/mrk-picker  (symlink into ~/bin)

  bin/mrk-picker  [leaf — Go binary]
    Interactive Brewfile package selector TUI (Bubble Tea).
    Reads Brewfile sections and packages; outputs selected packages as
    "formula:<name>" or "cask:<name>" lines to stdout.
    No filesystem writes — caller (scripts/brew, scripts/sync) consumes output.
```

---

## Target: `bf`

```
bf
  (go-build macro)
    go mod tidy  (in tools/bf/)
    go build -o bin/bf .  (compiles Go source → bin/bf)
    chmod +x bin/bf
  ln -sf bin/bf ~/bin/bf

  bin/bf  [leaf — Go binary]
    Two-pane Bubble Tea TUI for interactively browsing and managing the
    repo Brewfile. Can directly read and write the Brewfile.
    NOTE: bin/bf is linked to ~/bin/bf but NOT invoked by any make target.
    It is intended for direct user invocation.
```

---

## Target: `mrk-status`

```
mrk-status
  (go-build macro)
    go mod tidy  (in tools/mrk-status/)
    go build -o bin/mrk-status .
    chmod +x bin/mrk-status
  ln -sf bin/mrk-status ~/bin/mrk-status
  ln -sf bin/mrk-status ~/bin/status

  bin/mrk-status  [leaf — Go binary]
    Interactive two-pane Bubble Tea TUI health dashboard.
    Reads and displays installation status (dotfiles, tools, defaults,
    hardening, Brewfile packages, shell config). Primarily read-only;
    runs system checks via exec (brew, dscl, find, etc.).
```

---

## Target: `sync`

```
sync
  scripts/sync
    [sources] scripts/lib.sh
    $HOMEBREW leaves          (read — top-level formulae)
    $HOMEBREW list --formula  (read — all installed formulae)
    $HOMEBREW list --cask     (read — all installed casks)

    [interactive selection via mrk-picker OR gum choose]
      bin/mrk-picker  (Go binary — TUI selector)
        OR
      gum choose  (interactive selection)
        OR
      gum input  (section name input)

    [if --prune selected]
      sed -i '' -e "/^brew \"<pkg>\"/d" Brewfile
          (in-place removal of stale lines from Brewfile)
      OR gum choose to select which stale entries to remove

    python3 inline script  (inserts new entries alphabetically into Brewfile)
      Reads: Brewfile, temp insertions file
      Writes: Brewfile (in-place rewrite)

    [if --commit flag]
      git add Brewfile
      git commit -m "sync: add <pkgs>; remove <pkgs>"
```

---

## Target: `sync-login-items`

```
sync-login-items
  scripts/sync-login-items
    [sources] scripts/lib.sh
    osascript -e "tell application \"System Events\" to get the name of every login item"
                    (read — queries System Events)
    osascript to get path of each login item  (read)

    [interactive selection via gum choose OR read]

    python3 inline script  (rewrites add_login_item block in scripts/post-install)
      Reads: scripts/post-install
      Writes: scripts/post-install (in-place rewrite)

    python3 inline script  (updates login items list in docs/manual.md)
      Reads: docs/manual.md
      Writes: docs/manual.md

    python3 inline script  (updates login items list in docs/index.html)
      Reads: docs/index.html
      Writes: docs/index.html

    [if --commit flag]
      git add scripts/post-install docs/manual.md docs/index.html
      git commit -m "login-items: add <names>; remove <names>"
```

---

## Target: `snapshot-prefs`

```
snapshot-prefs
  scripts/snapshot-prefs
    git -C ~/.mrk/preferences init          (if no .git dir; init new repo)
    git -C ~/.mrk/preferences remote add origin git@github.com:sevmorris/mrk-prefs.git
        (if newly initialized)
      OR
    git clone git@github.com:sevmorris/mrk-prefs.git ~/.mrk/preferences
        (network — clones mrk-prefs if ~/.mrk/preferences absent)

    for each app:
      defaults export <bundle_id> ~/.mrk/preferences/<AppName>.plist
          (writes plist to ~/.mrk/preferences/)
      Apps: BetterSnapTool, Ice, iTerm2, Raycast, Stats, Loopback,
            SoundSource, Audio Hijack, Farrago, Piezo, Typora, Keka,
            TimeMachineEditor, MacWhisper

    for app-support files:
      mkdir -p ~/.mrk/preferences/app-support/Loopback
      cp ~/Library/Application Support/Loopback/{Devices,RecentApps}.plist → above
      mkdir -p ~/.mrk/preferences/app-support/SoundSource
      cp ~/Library/Application Support/SoundSource/{Presets,CustomPresets,Sources,Models}.plist → above

    git -C ~/.mrk/preferences add .
    git -C ~/.mrk/preferences commit -m "snapshot: <date>"
    git -C ~/.mrk/preferences push        (network — pushes to mrk-prefs)
```

---

## Target: `pull-prefs`

```
pull-prefs
  scripts/pull-prefs
    if ~/.mrk/preferences/.git exists:
      git -C ~/.mrk/preferences pull --ff-only
          (network — pulls latest from git@github.com:sevmorris/mrk-prefs.git)
    else:
      mkdir -p ~/.mrk  (creates parent)
      git clone git@github.com:sevmorris/mrk-prefs.git ~/.mrk/preferences
          (network — clones mrk-prefs repo)
```

---

## Target: `syncall`

> **Removed** in commit `ba29d0c` (branch `audit/static-pass`). Section retained for audit history.

```
syncall
  scripts/syncall
    [sources] scripts/lib.sh
    python3 -c os.path.realpath(...)   (resolve paths — read)

    discover_repos:
      find $HOME -xdev -maxdepth 7 ...  (scans all of $HOME for .git directories)
      git -C <repo> rev-parse --show-toplevel  (read)

    for each discovered repo (with GitHub remote, not in skip list):
      git -C <repo> remote -v              (read — check for github.com)
      git -C <repo> rev-parse --abbrev-ref HEAD  (read)
      git -C <repo> status --porcelain    (read — check dirty)

      if dirty:
        git -C <repo> diff --stat         (read)
        git -C <repo> status --short      (read)
        git -C <repo> add -A              (stages ALL changes in repo)
        git -C <repo> commit -m "syncall: auto-commit <timestamp>"
                                          (creates commit in repo)

      GIT_TERMINAL_PROMPT=0 git -C <repo> push --dry-run  (read — test push access)
      git -C <repo> push origin HEAD:<branch>
                                          (NETWORK — pushes to GitHub remote)

    mkdir -p ~/.mrk
    echo "syncall ran on <date>" >> ~/.mrk/syncall.log
```

---

## Target: `dock`

```
dock
  scripts/dock-setup
    [sources] scripts/lib.sh
    command -v dockutil              (read)
    brew install dockutil            (network — only if dockutil absent)
    dockutil --remove all --no-restart   (removes all Dock items)
    for each app in DOCK_APPS:
      dockutil --add <app-path> --no-restart  (adds app to Dock)
    dockutil --add /Applications --view grid --display folder --no-restart
                                     (adds Applications folder to Dock)
    killall Dock                     (restarts Dock to apply changes)
```

---

## Shared Libraries (sourced, not executed as targets)

### `scripts/lib.sh`

Sourced by: scripts/setup, scripts/brew, scripts/post-install, scripts/defaults.sh,
scripts/sync, scripts/sync-login-items, scripts/status (inline helpers only),
scripts/dock-setup, and all assets/browsers/*.sh,
assets/preferences/*.sh.

Provides: logging helpers (log, ok, warn, err, info, dry, logskip, section),
confirm(), sudo_refresh(), check_macos(), setup_logging(), resolve_path().
No side effects when sourced.

### `bin/lib/common.sh`

Sourced by: bin/audio-mode, bin/zoom-mode.
Provides: logging helpers (ok, warn, err, info, debug), confirm(),
is_running(), require_cmd(), human_bytes(), du_bytes(), safe_rm(), resolve_path().
No side effects when sourced.

---

## Scripts Not Invoked by Any Make Target

The following scripts are linked into `~/bin` via `make setup`
(phase_link_tools) but are NOT invoked by any make target.
Some are invoked by other non-make scripts; noted where applicable.

### `scripts/check-updates`

```
scripts/check-updates
  mkdir -p ~/.cache/mrk
  git -C <repo> fetch --quiet &    (background fetch — NETWORK)
  date +%s > ~/.cache/mrk/last-update-check  (writes timestamp)
  git -C <repo> rev-parse          (read)
  git -C <repo> merge-base         (read)
  [if updates available and user says yes]:
    make -C <repo> update          (recursive make — see update target)
```

Invocation: called from `dotfiles/.zshrc` line 54 via `$HOME/bin/check-updates`
on every interactive shell startup (after the dotfile symlink is live).

### `scripts/generate-install-manifest`

```
scripts/generate-install-manifest
  find ~/bin -maxdepth 1 -type l  (read)
  python3 -c os.path.realpath(...) (read)
  find dotfiles/ (read)
  Writes: $REPO_ROOT/.install-manifest  (manifest file inside the repo)
```

Invocation: No make target and no script calls this. Standalone utility.

### `scripts/fix-exec`

```
scripts/fix-exec
  find scripts/ -maxdepth 1 -type f  (read)
  find bin/ -maxdepth 1 -type f      (read)
  chmod +x <files>                    (sets executable bits)
  find ~/bin -maxdepth 1 -type l      (read)
  chmod +x <mrk-symlinks in ~/bin>
```

Invocation: No make target invokes this script. The Makefile `fix-exec`
target uses inline `find | chmod` commands instead. This script is a
user-facing duplicate linked into `~/bin`.

### `bin/audio-mode`

```
bin/audio-mode
  [sources] bin/lib/common.sh
  touch ~/.audio_mode_active           (creates flag file)
  mktemp; mv (atomic state write)      (writes ~/.audio_mode_state.json)
  jq (reads/writes JSON state)
  osascript: "tell application Dropbox to pause/resume syncing"
                                       (AppleScript — controls Dropbox)
  launchctl bootout "gui/$UID" com.apple.bird
  launchctl bootout "gui/$UID" com.apple.cloudd
                                       (stops iCloud sync daemons)
  launchctl bootstrap "gui/$UID" <plist>
                                       (restarts iCloud sync daemons)
  open -gj -a <app>                    (relaunches Dropbox or Google Drive)
  rm -f ~/.audio_mode_active
  echo "..." >> ~/Library/Logs/audio-mode.log
```

Invocation: Called by `bin/zoom-mode`. No make target.

### `bin/zoom-mode`

```
bin/zoom-mode
  [sources] bin/lib/common.sh
  touch ~/.zoom_mode_active
  echo $! >> ~/.zoom_mode_pids
  route -n get default                 (read — get gateway IP)
  ping -c 1 <gateway> (loop, background)  (sends ICMP pings)
  caffeinate -d &                      (prevents display sleep)
  tmutil status                        (read)
  tmutil stopbackup                    (stops active Time Machine backup)
  audio-mode on --all                  [see bin/audio-mode]
  kill <pids>                          (kills background ping + caffeinate)
  rm -f ~/.zoom_mode_active ~/.zoom_mode_pids
  audio-mode off                       [see bin/audio-mode]
  echo "..." >> ~/Library/Logs/zoom-mode.log
```

Invocation: No make target. Standalone user tool.

### `bin/mrk-push`

```
bin/mrk-push
  git add -A
  git diff --cached --quiet            (read)
  git commit -m "<message>"
  git push                             (NETWORK — pushes to origin)
  gh api --paginate "/repos/<repo>/deployments" --jq '.[].id'
                                       (NETWORK — GitHub API: list deployments)
  gh api -X POST "/repos/<repo>/deployments/<id>/statuses" -f state=inactive
                                       (NETWORK — GitHub API: mark inactive)
  gh api -X DELETE "/repos/<repo>/deployments/<id>"
                                       (NETWORK — GitHub API: delete deployment)
```

Invocation: No make target. Standalone user tool (run from any git repo).

### `bin/nuke-mrk`

```
bin/nuke-mrk
  [interactive prompts throughout]

  # Pre-nuke snapshot (optional)
  make -C ~/mrk sync ARGS=-c           [see sync target with --commit]
  make -C ~/mrk snapshot-prefs         [see snapshot-prefs target]

  # Remove symlinks
  find ~/bin -maxdepth 1 -type l       (read)
  rm -f <mrk-symlinks in ~/bin>
  rm -f <mrk-dotfile-symlinks in ~/>
  rm -f ~/.config/topgrade.toml        (if symlink into mrk)

  # Optional rollbacks
  bash ~/.mrk/defaults-rollback.sh     (runs defaults rollback — dynamic content)
  bash ~/.mrk/hardening-rollback.sh    (runs hardening rollback — dynamic content)

  # Trash items
  mv ~/.mrk → ~/.Trash/               (moves state dir to Trash)
  mv ~/mrk  → ~/.Trash/               (moves repo to Trash)
  brew uninstall --cask barkeep        (optional)
    OR mv /Applications/Barkeep.app → ~/.Trash/
  mv ~/mrk-install.log* → ~/.Trash/
```

Invocation: No make target. Standalone dev/test reset tool.

### `bin/snapshot`

```
bin/snapshot
  defaults export <bundle_id> assets/preferences/<name>.plist
                               (writes plist exports into repo)
  plutil -convert xml1 <plist> (converts to XML plist format)
  Apps: BetterSnapTool, Ice, iTerm2, AlDente, Amphetamine, Descript,
        Fission, HandBrake, Helium, ScreenFlow
  [optional: --brewfile]
    brew bundle dump --force --file=Brewfile
                               (OVERWRITES Brewfile with current state)
    cp Brewfile Brewfile.bak   (backup before overwrite)
  git status / git add / git commit  (optional commit)
```

Invocation: No make target. Distinct from `make snapshot-prefs`
(which exports to `~/.mrk/preferences/` for the mrk-prefs repo).
This writes directly into `assets/preferences/` within the mrk repo.

### `bin/hide_tm.sh`

```
bin/hide_tm.sh
  osascript: tell Finder to set visible of disk <name> to false
                               (hides named Time Machine volume from Finder sidebar)
```

Invocation: No make target. Standalone utility (configurable via
`TM_VOLUMES` env var or first argument).

---

## Cross-Reference Index

Alphabetical list of every script/binary in the repo with the make targets
that transitively invoke it. "Linked only" means `make setup` creates a
`~/bin` symlink but no target runs the script.

| Script / Binary | Invoked by Make Targets |
|---|---|
| `assets/browsers/helium-defaults.sh` | `post-install`, `all` |
| `assets/browsers/safari-defaults.sh` | `post-install`, `all` |
| `assets/preferences/aldente-defaults.sh` | `post-install`, `all` |
| `assets/preferences/audio-hijack-defaults.sh` | `post-install`, `all` |
| `assets/preferences/fission-defaults.sh` | `post-install`, `all` |
| `assets/preferences/rogue-amoeba-updates.sh` | `post-install`, `all` |
| `bin/audio-mode` | linked only (`setup`, `all`) |
| `bin/bf` | linked only (`setup`, `all`); built by `bf`, `build-tools`, `all` |
| `bin/hide_tm.sh` | linked only (`setup`, `all`) |
| `bin/lib/common.sh` | sourced by `bin/audio-mode`, `bin/zoom-mode` — transitively linked only |
| `bin/mrk-picker` | `brew`, `sync` (via path lookup); built by `picker`, `build-tools`, `all` |
| `bin/mrk-push` | linked only (`setup`, `all`) |
| `bin/mrk-status` | linked only (`setup`, `all`); built by `mrk-status`, `build-tools`, `all` |
| `bin/nuke-mrk` | linked only (`setup`, `all`) |
| `bin/snapshot` | linked only (`setup`, `all`) |
| `bin/zoom-mode` | linked only (`setup`, `all`) |
| `scripts/adventure-prologue` | `adventure` |
| `scripts/brew` | `brew`, `all` |
| `scripts/check-updates` | linked only (`setup`, `all`); invoked from `dotfiles/.zshrc` |
| `scripts/defaults.sh` | `defaults`, `trackpad`, `setup`→phase_defaults, `all` |
| `scripts/dock-setup` | `dock` |
| `scripts/doctor` | `doctor` |
| `scripts/fix-exec` | linked only (`setup`, `all`) |
| `scripts/generate-install-manifest` | **none** |
| `scripts/hardening.sh` | `harden` |
| `scripts/install` | linked only as `mrk-install` (`setup`, `all`) |
| `scripts/lib.sh` | sourced by most scripts; transitively: `setup`, `brew`, `post-install`, `defaults`, `trackpad`, `sync`, `sync-login-items`, `dock`, `all`, and all assets/*.sh via `post-install` |
| `scripts/post-install` | `post-install`, `all` |
| `scripts/pull-prefs` | `pull-prefs`; also `post-install`→`all` (conditional) |
| `scripts/setup` | `setup`, `install`, `tools`, `dotfiles`, `setup-dry`, `all` |
| `scripts/snapshot-prefs` | `snapshot-prefs`; also `bin/nuke-mrk` (not a make target) |
| `scripts/status` | `status` |
| `scripts/sync` | `sync`; also `bin/nuke-mrk` (not a make target) |
| `scripts/sync-login-items` | `sync-login-items` |
| `scripts/syncall` | ~~`syncall`~~ — **removed** commit `ba29d0c` |
| `scripts/uninstall` | `uninstall` |

### DEAD CODE CANDIDATES

Scripts that **no make target invokes**, and are not invoked by any other
script that IS reached by a make target:

| Script / Binary | Notes |
|---|---|
| `scripts/generate-install-manifest` | No caller found anywhere in the codebase. Writes `.install-manifest` in the repo root. |
| `scripts/fix-exec` | Duplicates the inline `chmod` in the Makefile `fix-exec` target. Never called by any target or script. |
| `bin/nuke-mrk` | Dev-only reset tool. No make target; no script caller. |
| `bin/snapshot` | Distinct from `make snapshot-prefs`; exports to repo `assets/preferences/` not `~/.mrk/preferences/`. No make target; no script caller. |
| `bin/hide_tm.sh` | Standalone utility. No make target; no script caller. |
| `bin/mrk-push` | Standalone git push + GitHub deployment pruner. No make target; no script caller. |
| `bin/zoom-mode` | Calls `bin/audio-mode` but is itself unreachable from any make target. |
| `bin/audio-mode` | Called by `bin/zoom-mode` (itself a dead-code candidate). No make target. |

Note: `scripts/check-updates` is **not** listed here because it is invoked
at shell startup via `dotfiles/.zshrc` line 54. It is outside the make
dependency graph but has a real runtime invocation path once dotfiles are
linked.
