# Audit Module 2 — Side-Effect Inventory
<!-- generated 2026-04-24, audit/static-pass branch -->

Side effects are grouped by category. For each entry:
- **Command/operation** — the exact command or operation
- **Script:line** — source location (approximate where noted)
- **Make targets** — which top-level targets reach this
- **Reversible** — yes/no, with rollback location or "NO ROLLBACK FOUND"
- **Idempotent** — whether running twice produces identical state (I=yes, NI=no, COND=conditional)

---

## FILESYSTEM

### State directory and log file

| Operation | Script:line | Make targets | Reversible | Idempotent |
|---|---|---|---|---|
| `mkdir -p ~/.mrk` | scripts/setup:105, scripts/defaults.sh:22, scripts/hardening.sh:11 ~~, scripts/syncall:183~~ | setup, defaults, trackpad, harden, all | Yes — `rm -rf ~/.mrk` | I (mkdir -p) |
| `mkdir -p ~/.mrk/backups/<timestamp>` | scripts/setup:451 | setup, install, dotfiles, all | Yes — `rm -rf ~/.mrk/backups/<timestamp>` | NI (timestamp changes each run) |
| `exec > >(tee -a ~/.mrk/install.log)` (creates/appends log) | scripts/setup:126 | setup, install, tools, dotfiles, setup-dry, all | Yes — delete file | NI (appends) |
| `mv ~/.mrk/install.log → ~/.mrk/install.log.<epoch>.old` (log rotation if >10MB) | scripts/lib.sh:80 | any target sourcing lib.sh that calls setup_logging | Yes — `mv` back | COND (only if >10MB) |
| `touch ~/.mrk/defaults-rollback.sh` + `chmod +x` | scripts/setup:119 | setup, install, all | Yes — delete file | I |
| `printf '#!/usr/bin/env bash\n' > ~/.mrk/defaults-rollback.sh` (truncates) | scripts/defaults.sh:27 | defaults, trackpad, setup→phase_defaults, all | NO ROLLBACK FOUND | NI (truncates on each run) |
| `echo "<rollback-cmd>" >> ~/.mrk/defaults-rollback.sh` (many appends) | scripts/defaults.sh:44,88-94 | defaults, trackpad, setup, all | Yes — delete file | NI (appends) |
| `printf '#!/usr/bin/env bash\n' > ~/.mrk/hardening-rollback.sh` | scripts/hardening.sh:15 | harden | NO ROLLBACK FOUND | NI (truncates) |
| `echo "<rollback-cmd>" >> ~/.mrk/hardening-rollback.sh` | scripts/hardening.sh:35,66,74 | harden | Yes — delete file | NI (appends) |
| ~~`echo "syncall ran on <date>" >> ~/.mrk/syncall.log`~~ | ~~scripts/syncall:184~~ | ~~syncall~~ | — | — | <!-- syncall removed commit ba29d0c -->
| `mkdir -p ~/.cache/mrk` | scripts/check-updates:29 | none (invoked from .zshrc) | Yes — `rm -rf ~/.cache/mrk` | I |
| `date +%s > ~/.cache/mrk/last-update-check` | scripts/check-updates:69 | none | Yes — delete file | NI (overwrites timestamp) |

### Dotfile symlinks in $HOME

All entries created by `phase_dotfiles` in scripts/setup. Each file in `dotfiles/`
(excluding `*.example`, `README*`, `*.md`) gets a symlink in `$HOME`.

| Operation | Target path | Source | Make targets | Reversible | Idempotent |
|---|---|---|---|---|---|
| `ln -sfn dotfiles/.aliases ~/` | `~/.aliases` | `dotfiles/.aliases` | setup, install, dotfiles, all | Yes — `rm ~/.aliases` | COND (skips if already correct) |
| `ln -sfn dotfiles/.gitconfig ~/` | `~/.gitconfig` | `dotfiles/.gitconfig` | setup, install, dotfiles, all | Yes | COND |
| `ln -sfn dotfiles/.hushlogin ~/` | `~/.hushlogin` | `dotfiles/.hushlogin` | setup, install, dotfiles, all | Yes | COND |
| `ln -sfn dotfiles/.zprofile ~/` | `~/.zprofile` | `dotfiles/.zprofile` | setup, install, dotfiles, all | Yes | COND |
| `ln -sfn dotfiles/.zshenv ~/` | `~/.zshenv` | `dotfiles/.zshenv` | setup, install, dotfiles, all | Yes | COND |
| `ln -sfn dotfiles/.zshrc ~/` | `~/.zshrc` | `dotfiles/.zshrc` | setup, install, dotfiles, all | Yes | COND |
| `ln -sfn dotfiles/Makefile ~/` | `~/Makefile` | `dotfiles/Makefile` | setup, install, dotfiles, all | Yes | COND |
| `mv <existing-file> ~/.mrk/backups/<timestamp>/` | varies | any pre-existing non-symlink dotfile | setup, install, dotfiles, all | Yes — mv back from backup | NI (backs up then links) |

Note: `dotfiles/Makefile` (the `dotfiles/` sub-Makefile) would be linked to `~/Makefile`,
creating a `Makefile` in the user's home directory. This is an unusual side effect.

### ~/bin symlinks (tool linking)

Created by `phase_link_tools` in scripts/setup. Links every executable in `scripts/`
and `bin/` into `~/bin/`. Six scripts get an `mrk-` prefix:

| Operation | Target | Source | Make targets | Reversible | Idempotent |
|---|---|---|---|---|---|
| `ln -sf scripts/brew ~/bin/mrk-brew` | `~/bin/mrk-brew` | `scripts/brew` | setup, tools, all | Yes — `rm ~/bin/mrk-brew` | COND (skips if already correct) |
| `ln -sf scripts/install ~/bin/mrk-install` | `~/bin/mrk-install` | `scripts/install` | setup, tools, all | Yes | COND |
| `ln -sf scripts/setup ~/bin/mrk-setup` | `~/bin/mrk-setup` | `scripts/setup` | setup, tools, all | Yes | COND |
| `ln -sf scripts/post-install ~/bin/mrk-post-install` | `~/bin/mrk-post-install` | `scripts/post-install` | setup, tools, all | Yes | COND |
| `ln -sf scripts/defaults.sh ~/bin/mrk-defaults` | `~/bin/mrk-defaults` | `scripts/defaults.sh` | setup, tools, all | Yes | COND |
| `ln -sf scripts/uninstall ~/bin/mrk-uninstall` | `~/bin/mrk-uninstall` | `scripts/uninstall` | setup, tools, all | Yes | COND |
| `ln -sf scripts/<name> ~/bin/<name>` (non-prefixed) | `~/bin/<name>` | all other executable scripts | setup, tools, all | Yes | COND |
| `ln -sf bin/<name> ~/bin/<name>` | `~/bin/<name>` | all executable bin/ files | setup, tools, all | Yes | COND |
| `ln -sf bin/lib ~/bin/lib` | `~/bin/lib` | `bin/lib/` directory | setup, tools, all | Yes | COND |

### Compiled Go binaries

| Operation | Target | Make targets | Reversible | Idempotent |
|---|---|---|---|---|
| `go build -o bin/mrk-picker` | `bin/mrk-picker` | picker, build-tools, all | Yes — delete file | I (overwrites) |
| `go build -o bin/bf` | `bin/bf` | bf, build-tools, all | Yes — delete file | I (overwrites) |
| `go build -o bin/mrk-status` | `bin/mrk-status` | mrk-status, build-tools, all | Yes — delete file | I (overwrites) |
| `go mod tidy` (may update go.sum) | `tools/*/go.sum` | picker, bf, mrk-status, build-tools, all | Yes — `git checkout tools/*/go.sum` | COND |
| `chmod +x bin/<binary>` | permissions on bin/* | picker, bf, mrk-status, build-tools, all | Yes — chmod back | I |
| `ln -sf bin/mrk-picker ~/bin/mrk-picker` | `~/bin/mrk-picker` | picker, build-tools, all | Yes | I |
| `ln -sf bin/bf ~/bin/bf` | `~/bin/bf` | bf, build-tools, all | Yes | I |
| `ln -sf bin/mrk-status ~/bin/mrk-status` | `~/bin/mrk-status` | mrk-status, build-tools, all | Yes | I |
| `ln -sf bin/mrk-status ~/bin/status` | `~/bin/status` | mrk-status, build-tools, all | Yes | I |

### Topgrade config

| Operation | Target | Script:line | Make targets | Reversible | Idempotent |
|---|---|---|---|---|---|
| `mv ~/.config/topgrade.toml → ~/.config/topgrade.toml.bak` | backup | scripts/post-install:97 | post-install, all | Yes — `mv` back | COND (only if non-symlink exists) |
| `ln -s assets/topgrade.toml ~/.config/topgrade.toml` | `~/.config/topgrade.toml` | scripts/post-install:98 | post-install, all | Yes — `rm ~/.config/topgrade.toml` | COND (skips if already correct) |

### Browser policy files

| Operation | Target | Script:line | Make targets | Reversible | Idempotent |
|---|---|---|---|---|---|
| `mkdir -p "$HOME/Library/Application Support/Google/Chrome/policies/managed"` | directory | scripts/post-install:136 | post-install, all | Yes — rmdir | I |
| `cp assets/browsers/chrome-policy.json → above/mrk-policy.json` | `~/Library/Application Support/Google/Chrome/policies/managed/mrk-policy.json` | scripts/post-install:136 | post-install, all | Yes — delete file | COND (skips if identical) |
| `mkdir -p "$HOME/Library/Application Support/BraveSoftware/Brave-Browser/policies/managed"` | directory | scripts/post-install:155 | post-install, all | Yes — rmdir | I |
| `cp assets/browsers/brave-policy.json → above/mrk-policy.json` | `~/Library/Application Support/BraveSoftware/Brave-Browser/policies/managed/mrk-policy.json` | scripts/post-install:155 | post-install, all | Yes — delete file | COND (skips if identical) |

### Application installation (from GitHub)

| Operation | Target | Script:line | Make targets | Reversible | Idempotent |
|---|---|---|---|---|---|
| `cp -R <Barkeep.app> /Applications/` | `/Applications/Barkeep.app` | scripts/post-install:215 | post-install, all | Yes — `rm -rf /Applications/Barkeep.app` | COND (skips if already installed) |
| `xattr -cr /Applications/Barkeep.app` | removes quarantine xattr | scripts/post-install:221 | post-install, all | NO ROLLBACK FOUND | COND |

### App support files (plist imports)

| Operation | Target | Script:line | Make targets | Reversible | Idempotent |
|---|---|---|---|---|---|
| `mkdir -p "$HOME/Library/Application Support/Loopback"` | directory | scripts/post-install:349 | post-install, all | Yes — rmdir | I |
| `cp ~/.mrk/preferences/app-support/Loopback/Devices.plist → ~/Library/Application Support/Loopback/` | file | scripts/post-install:359 | post-install, all | Yes — delete file | COND (skips if exists) |
| `cp ~/.mrk/preferences/app-support/Loopback/RecentApps.plist → ~/Library/Application Support/Loopback/` | file | scripts/post-install:359 | post-install, all | Yes — delete file | COND (skips if exists) |
| `mkdir -p "$HOME/Library/Application Support/SoundSource"` | directory | scripts/post-install:368 | post-install, all | Yes — rmdir | I |
| `cp ~/.mrk/preferences/app-support/SoundSource/{Presets,CustomPresets,Sources,Models}.plist` | 4 files | scripts/post-install:368 | post-install, all | Yes — delete files | COND (skips if exists) |

### ~/.mrk/preferences (mrk-prefs repo)

| Operation | Target | Script:line | Make targets | Reversible | Idempotent |
|---|---|---|---|---|---|
| `git clone git@github.com:sevmorris/mrk-prefs.git ~/.mrk/preferences` | `~/.mrk/preferences/` | scripts/pull-prefs:18, scripts/snapshot-prefs:21 | pull-prefs; post-install (conditional); snapshot-prefs | Yes — `rm -rf ~/.mrk/preferences` | COND (only if absent) |
| `defaults export <bundle_id> ~/.mrk/preferences/<name>.plist` (×14 apps) | plist files in `~/.mrk/preferences/` | scripts/snapshot-prefs:33 | snapshot-prefs | Yes — delete files | NI (overwrites on each run) |
| `mkdir -p ~/.mrk/preferences/app-support/{Loopback,SoundSource}` | directories | scripts/snapshot-prefs:65 | snapshot-prefs | Yes — rmdir | I |
| `cp ~/Library/Application Support/Loopback/*.plist → ~/.mrk/preferences/app-support/Loopback/` | 2 files | scripts/snapshot-prefs:84 | snapshot-prefs | Yes — delete | NI (overwrites) |
| `cp ~/Library/Application Support/SoundSource/*.plist → ~/.mrk/preferences/app-support/SoundSource/` | 4 files | scripts/snapshot-prefs:88 | snapshot-prefs | Yes — delete | NI (overwrites) |

### Repo file modifications (sync targets)

| Operation | Target | Script:line | Make targets | Reversible | Idempotent |
|---|---|---|---|---|---|
| `python3 <inline> Brewfile <insertions>` — in-place Brewfile update | `Brewfile` | scripts/sync:490 | sync | Yes — `git checkout Brewfile` | COND (only adds missing entries) |
| `sed -i '' -e "/^brew|cask \"<pkg>\"/d" Brewfile` — prune stale entries | `Brewfile` | scripts/sync:241 | sync (with --prune) | Yes — `git checkout Brewfile` | COND (interactive, user-selected) |
| `python3 <inline> scripts/post-install ...` — rewrites add_login_item block | `scripts/post-install` | scripts/sync-login-items:247 | sync-login-items | Yes — `git checkout scripts/post-install` | COND (reflects system state) |
| `python3 <inline> docs/manual.md ...` — updates login items list | `docs/manual.md` | scripts/sync-login-items:335 | sync-login-items | Yes — `git checkout docs/manual.md` | COND |
| `python3 <inline> docs/index.html ...` — updates login items list | `docs/index.html` | scripts/sync-login-items:349 | sync-login-items | Yes — `git checkout docs/index.html` | COND |
| `python3 <inline>` writes `$REPO_ROOT/.install-manifest` | `.install-manifest` | scripts/generate-install-manifest:41 | none (dead code) | Yes — delete file | NI (overwrites) |

### audio-mode state files (not reachable from make)

| Operation | Target | Script:line | Make targets | Reversible | Idempotent |
|---|---|---|---|---|---|
| `touch ~/.audio_mode_active` | flag file | bin/audio-mode:183 | none | Yes — `rm` | NI |
| atomic write to `~/.audio_mode_state.json` | state file | bin/audio-mode:53-58 | none | Yes — `rm` | NI |
| `rm -f ~/.audio_mode_active` | removes flag | bin/audio-mode:228 | none | Yes | I |
| `echo "..." >> ~/Library/Logs/audio-mode.log` | log append | bin/audio-mode:183,224 | none | Yes — delete file | NI |

### zoom-mode state files (not reachable from make)

| Operation | Target | Script:line | Make targets | Reversible | Idempotent |
|---|---|---|---|---|---|
| `touch ~/.zoom_mode_active` | flag file | bin/zoom-mode:52 | none | Yes | NI |
| `echo $! >> ~/.zoom_mode_pids` | PID file | bin/zoom-mode:59 | none | Yes | NI |
| `rm -f ~/.zoom_mode_active ~/.zoom_mode_pids` | removes files | bin/zoom-mode:86-87 | none | Yes | I |
| `echo "..." >> ~/Library/Logs/zoom-mode.log` | log | bin/zoom-mode:50,85 | none | Yes | NI |

### doctor --fix (PATH patch)

| Operation | Target | Script:line | Make targets | Reversible | Idempotent |
|---|---|---|---|---|---|
| `cat >> ~/.zshrc` (appends `~/bin` PATH entry) | `~/.zshrc` | scripts/doctor:27 | doctor (--fix mode only) | Yes — edit ~/.zshrc | COND (checks for existing entry first) |

---

## MACOS DEFAULTS

All entries written by `scripts/defaults.sh` (via `write_default` helper).
The helper is idempotent — it reads the current value and skips the write
if already set. It generates a rollback entry before each write.

**Rollback location:** `~/.mrk/defaults-rollback.sh` (truncated and rebuilt each run).

### NSGlobalDomain (system-wide)

| Domain | Key | Type | Value | Make targets |
|---|---|---|---|---|
| NSGlobalDomain | AppleInterfaceStyle | string | Dark | defaults, trackpad, setup, all |
| NSGlobalDomain | AppleShowScrollBars | string | Always | defaults, trackpad, setup, all |
| NSGlobalDomain | AppleShowAllExtensions | bool | true | defaults, trackpad, setup, all |
| NSGlobalDomain | NSAutomaticWindowAnimationsEnabled | bool | false | defaults, trackpad, setup, all |
| NSGlobalDomain | NSWindowResizeTime | float | 0.001 | defaults, trackpad, setup, all |
| NSGlobalDomain | NSQuitAlwaysKeepsWindows | bool | false | defaults, trackpad, setup, all |
| NSGlobalDomain | NSNavPanelExpandedStateForSaveMode | bool | true | defaults, trackpad, setup, all |
| NSGlobalDomain | NSNavPanelExpandedStateForSaveMode2 | bool | true | defaults, trackpad, setup, all |
| NSGlobalDomain | PMPrintingExpandedStateForPrint | bool | true | defaults, trackpad, setup, all |
| NSGlobalDomain | PMPrintingExpandedStateForPrint2 | bool | true | defaults, trackpad, setup, all |
| NSGlobalDomain | NSDocumentSaveNewDocumentsToCloud | bool | false | defaults, trackpad, setup, all |
| NSGlobalDomain | QLPanelAnimationDuration | float | 0 | defaults, trackpad, setup, all |
| NSGlobalDomain | com.apple.sound.beep.volume | float | 0 | defaults, trackpad, setup, all |
| NSGlobalDomain | com.apple.sound.uiaudio.enabled | bool | false | defaults, trackpad, setup, all |
| NSGlobalDomain | KeyRepeat | int | 2 | defaults, trackpad, setup, all |
| NSGlobalDomain | InitialKeyRepeat | int | 15 | defaults, trackpad, setup, all |
| NSGlobalDomain | ApplePressAndHoldEnabled | bool | false | defaults, trackpad, setup, all |
| NSGlobalDomain | AppleKeyboardUIMode | int | 2 | defaults, trackpad, setup, all |
| NSGlobalDomain | NSAutomaticCapitalizationEnabled | bool | false | defaults, trackpad, setup, all |
| NSGlobalDomain | NSAutomaticDashSubstitutionEnabled | bool | false | defaults, trackpad, setup, all |
| NSGlobalDomain | NSAutomaticPeriodSubstitutionEnabled | bool | false | defaults, trackpad, setup, all |
| NSGlobalDomain | NSAutomaticQuoteSubstitutionEnabled | bool | false | defaults, trackpad, setup, all |
| NSGlobalDomain | NSAutomaticSpellingCorrectionEnabled | bool | false | defaults, trackpad, setup, all |

### com.apple.dock

| Domain | Key | Type | Value | Make targets |
|---|---|---|---|---|
| com.apple.dock | orientation | string | left | defaults, trackpad, setup, all |
| com.apple.dock | tilesize | int | 36 | defaults, trackpad, setup, all |
| com.apple.dock | mineffect | string | scale | defaults, trackpad, setup, all |
| com.apple.dock | minimize-to-application | bool | true | defaults, trackpad, setup, all |
| com.apple.dock | no-bouncing | bool | true | defaults, trackpad, setup, all |
| com.apple.dock | show-recents | bool | false | defaults, trackpad, setup, all |
| com.apple.dock | autohide-delay | float | 0 | defaults, trackpad, setup, all |

### com.apple.finder

| Domain | Key | Type | Value | Make targets |
|---|---|---|---|---|
| com.apple.finder | DisableAllAnimations | bool | true | defaults, trackpad, setup, all |

### com.apple.screencapture

| Domain | Key | Type | Value | Make targets |
|---|---|---|---|---|
| com.apple.screencapture | disable-shadow | bool | true | defaults, trackpad, setup, all |
| com.apple.screencapture | show-thumbnail | bool | false | defaults, trackpad, setup, all |
| com.apple.screencapture | include-date | bool | false | defaults, trackpad, setup, all |
| com.apple.screencapture | location | string | `$HOME/Desktop` | defaults, trackpad, setup, all |

### com.apple.desktopservices

| Domain | Key | Type | Value | Make targets |
|---|---|---|---|---|
| com.apple.desktopservices | DSDontWriteNetworkStores | bool | true | defaults, trackpad, setup, all |
| com.apple.desktopservices | DSDontWriteUSBStores | bool | true | defaults, trackpad, setup, all |

### com.apple.frameworks.diskimages

| Domain | Key | Type | Value | Make targets |
|---|---|---|---|---|
| com.apple.frameworks.diskimages | skip-verify | bool | true | defaults, trackpad, setup, all |
| com.apple.frameworks.diskimages | skip-verify-locked | bool | true | defaults, trackpad, setup, all |
| com.apple.frameworks.diskimages | skip-verify-remote | bool | true | defaults, trackpad, setup, all |

### com.apple.TimeMachine

| Domain | Key | Type | Value | Make targets |
|---|---|---|---|---|
| com.apple.TimeMachine | DoNotOfferNewDisksForBackup | bool | true | defaults, trackpad, setup, all |

### com.apple.SoftwareUpdate

| Domain | Key | Type | Value | Make targets |
|---|---|---|---|---|
| com.apple.SoftwareUpdate | AutomaticCheckEnabled | bool | true | defaults, trackpad, setup, all |
| com.apple.SoftwareUpdate | AutomaticDownload | bool | true | defaults, trackpad, setup, all |
| com.apple.SoftwareUpdate | ConfigDataInstall | bool | true | defaults, trackpad, setup, all |
| com.apple.SoftwareUpdate | CriticalUpdateInstall | bool | true | defaults, trackpad, setup, all |

### com.apple.commerce

| Domain | Key | Type | Value | Make targets |
|---|---|---|---|---|
| com.apple.commerce | AutoUpdate | bool | true | defaults, trackpad, setup, all |

### com.apple.ActivityMonitor

| Domain | Key | Type | Value | Make targets |
|---|---|---|---|---|
| com.apple.ActivityMonitor | IconType | int | 2 | defaults, trackpad, setup, all |
| com.apple.ActivityMonitor | ShowCategory | int | 100 | defaults, trackpad, setup, all |
| com.apple.ActivityMonitor | SortColumn | string | CPUUsage | defaults, trackpad, setup, all |
| com.apple.ActivityMonitor | SortDirection | int | 0 | defaults, trackpad, setup, all |
| com.apple.ActivityMonitor | UpdatePeriod | int | 1 | defaults, trackpad, setup, all |

### com.apple.TextEdit

| Domain | Key | Type | Value | Make targets |
|---|---|---|---|---|
| com.apple.TextEdit | RichText | int | 0 | defaults, trackpad, setup, all |

### com.apple.Terminal

| Domain | Key | Type | Value | Make targets |
|---|---|---|---|---|
| com.apple.Terminal | Default Window Settings | string | Pro | defaults, trackpad, setup, all |
| com.apple.Terminal | Startup Window Settings | string | Pro | defaults, trackpad, setup, all |
| com.apple.Terminal | FocusFollowsMouse | bool | true | defaults, trackpad, setup, all |
| com.apple.Terminal | SecureKeyboardEntry | bool | true | defaults, trackpad, setup, all |
| com.apple.Terminal | ShowLineMarks | bool | false | defaults, trackpad, setup, all |

### com.apple.menuextra.clock

| Domain | Key | Type | Value | Make targets |
|---|---|---|---|---|
| com.apple.menuextra.clock | IsAnalog | bool | false | defaults, trackpad, setup, all |
| com.apple.menuextra.clock | ShowAMPM | bool | true | defaults, trackpad, setup, all |
| com.apple.menuextra.clock | ShowDayOfWeek | bool | true | defaults, trackpad, setup, all |
| com.apple.menuextra.clock | ShowDate | int | 0 | defaults, trackpad, setup, all |

### Trackpad domains (trackpad target only)

Written for BOTH `com.apple.AppleMultitouchTrackpad` AND
`com.apple.driver.AppleBluetoothMultitouch.trackpad` (28 writes total).

| Key | Type | Value |
|---|---|---|
| Clicking | bool | false |
| ForceSuppressed | bool | true |
| TrackpadCornerSecondaryClick | int | 2 |
| TrackpadFiveFingerPinchGesture | int | 0 |
| TrackpadFourFingerHorizSwipeGesture | int | 0 |
| TrackpadFourFingerPinchGesture | int | 0 |
| TrackpadFourFingerVertSwipeGesture | int | 0 |
| TrackpadPinch | bool | false |
| TrackpadRightClick | bool | false |
| TrackpadRotate | bool | false |
| TrackpadThreeFingerDrag | bool | false |
| TrackpadThreeFingerHorizSwipeGesture | int | 0 |
| TrackpadThreeFingerTapGesture | int | 0 |
| TrackpadThreeFingerVertSwipeGesture | int | 0 |
| TrackpadTwoFingerDoubleTapGesture | int | 0 |
| TrackpadTwoFingerFromRightEdgeSwipeGesture | int | 0 |

Make targets: `trackpad`.

### Hardening defaults (scripts/hardening.sh)

| Domain | Key | Type | Value | Make targets | Reversible |
|---|---|---|---|---|---|
| com.apple.screensaver | askForPassword | int | 1 | harden | Yes — `~/.mrk/hardening-rollback.sh` |
| com.apple.screensaver | askForPasswordDelay | int | 0 | harden | Yes — rollback script |

### Browser defaults (assets/browsers/)

| Domain | Key | Type | Value | Make targets | Reversible |
|---|---|---|---|---|---|
| com.apple.Safari | ShowFullURLInSmartSearchField | bool | true | post-install, all | NO ROLLBACK FOUND |
| com.apple.Safari | ShowFavoritesBar-v2 | bool | true | post-install, all | NO ROLLBACK FOUND |
| com.apple.Safari | ShowOverlayStatusBar | bool | true | post-install, all | NO ROLLBACK FOUND |
| com.apple.Safari | SendDoNotTrackHTTPHeader | bool | true | post-install, all | NO ROLLBACK FOUND |
| com.apple.Safari | BlockStoragePolicy | int | 2 | post-install, all | NO ROLLBACK FOUND |
| com.apple.Safari | AutoOpenSafeDownloads | bool | false | post-install, all | NO ROLLBACK FOUND |
| com.apple.Safari | AutoFillCreditCardData | bool | false | post-install, all | NO ROLLBACK FOUND |
| com.apple.Safari | IncludeDevelopMenu | bool | true | post-install, all | NO ROLLBACK FOUND |
| com.apple.Safari | WebKitDeveloperExtrasEnabledPreferenceKey | bool | true | post-install, all | NO ROLLBACK FOUND |
| com.apple.Safari | com.apple.Safari.ContentPageGroupIdentifier.WebKit2DeveloperExtrasEnabled | bool | true | post-install, all | NO ROLLBACK FOUND |
| com.apple.Safari | ExtensionsEnabled | bool | true | post-install, all | NO ROLLBACK FOUND |
| com.apple.Safari | InstallExtensionUpdatesAutomatically | bool | true | post-install, all | NO ROLLBACK FOUND |
| net.imput.helium | SUEnableAutomaticChecks | bool | true | post-install, all | NO ROLLBACK FOUND |
| net.imput.helium | SUAutomaticallyUpdate | bool | true | post-install, all | NO ROLLBACK FOUND |

### Application preference defaults (assets/preferences/)

| Domain | Key | Type | Value | Make targets | Reversible |
|---|---|---|---|---|---|
| com.rogueamoeba.AudioHijack | applicationTheme | int | 2 | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.AudioHijack | audioEditorBundleID | string | com.izotope.RXPro | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.AudioHijack | bufferFrames | int | 512 | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.AudioHijack | allowExternalCommands | int | 0 | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.Fission | applicationTheme | int | 2 | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.Fission | CustomFormatWAV | dict | `{BitRate:0, ChannelCount:1, Dithering:1, SampleSize:24, SamplingRate:44100, Type:5, TypeExtra:0, UseSDM:0, UseVBR:1}` | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.Fission | CustomFormatMP3 | dict | `{BitRate:160000, ChannelCount:2, Dithering:0, SampleSize:16, SamplingRate:44100, Type:3, TypeExtra:0, UseSDM:0, UseVBR:1}` | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.Fission | CustomFormatAAC | dict | `{BitRate:160000, ChannelCount:2, Dithering:0, SampleSize:16, SamplingRate:44100, Type:2, TypeExtra:0, UseSDM:0, UseVBR:1}` | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.Fission | exportFormatType | int | 5 | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.Fission | showStartWindow | bool | false | post-install, all | NO ROLLBACK FOUND |
| com.apphousekitchen.aldente-pro | chargeVal | int | 80 | post-install, all | NO ROLLBACK FOUND |
| com.apphousekitchen.aldente-pro | calibrationBackupPercentage | int | 80 | post-install, all | NO ROLLBACK FOUND |
| com.apphousekitchen.aldente-pro | sailingMode | bool | true | post-install, all | NO ROLLBACK FOUND |
| com.apphousekitchen.aldente-pro | sailingLevel | int | 5 | post-install, all | NO ROLLBACK FOUND |
| com.apphousekitchen.aldente-pro | automaticDischarge | bool | true | post-install, all | NO ROLLBACK FOUND |
| com.apphousekitchen.aldente-pro | allowDischarge | bool | false | post-install, all | NO ROLLBACK FOUND |
| com.apphousekitchen.aldente-pro | magsafeBlinkDischarge | bool | true | post-install, all | NO ROLLBACK FOUND |
| com.apphousekitchen.aldente-pro | SUAutomaticallyUpdate | bool | true | post-install, all | NO ROLLBACK FOUND |
| com.apphousekitchen.aldente-pro | SUEnableAutomaticChecks | bool | true | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.AudioHijack | SUAllowsAutomaticUpdates | bool | false | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.AudioHijack | SUAutomaticallyUpdate | bool | false | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.Fission | SUAllowsAutomaticUpdates | bool | false | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.Fission | SUAutomaticallyUpdate | bool | false | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.Loopback | SUAllowsAutomaticUpdates | bool | false | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.Loopback | SUAutomaticallyUpdate | bool | false | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.Piezo | SUAllowsAutomaticUpdates | bool | false | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.Piezo | SUAutomaticallyUpdate | bool | false | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.soundsource | SUAllowsAutomaticUpdates | bool | false | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.soundsource | SUAutomaticallyUpdate | bool | false | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.Farrago2 | SUAllowsAutomaticUpdates | bool | false | post-install, all | NO ROLLBACK FOUND |
| com.rogueamoeba.Farrago2 | SUAutomaticallyUpdate | bool | false | post-install, all | NO ROLLBACK FOUND |

### Plist imports (defaults import)

| App | Bundle ID | Source file | Make targets | Reversible | Idempotent |
|---|---|---|---|---|---|
| BetterSnapTool | com.hegenberg.BetterSnapTool | `~/.mrk/preferences/BetterSnapTool.plist` | post-install, all | NO ROLLBACK FOUND | COND (skips if `~/Library/Preferences/<bundle>.plist` exists) |
| Ice | com.jordanbaird.Ice | `~/.mrk/preferences/Ice.plist` | post-install, all | NO ROLLBACK FOUND | COND |
| iTerm2 | com.googlecode.iterm2 | `~/.mrk/preferences/iTerm2.plist` | post-install, all | NO ROLLBACK FOUND | COND |
| Raycast | com.raycast.macos | `~/.mrk/preferences/Raycast.plist` | post-install, all | NO ROLLBACK FOUND | COND |
| Stats | eu.exelban.Stats | `~/.mrk/preferences/Stats.plist` | post-install, all | NO ROLLBACK FOUND | COND |
| Loopback | com.rogueamoeba.Loopback | `~/.mrk/preferences/Loopback.plist` | post-install, all | NO ROLLBACK FOUND | COND |
| SoundSource | com.rogueamoeba.soundsource | `~/.mrk/preferences/SoundSource.plist` | post-install, all | NO ROLLBACK FOUND | COND |
| Audio Hijack | com.rogueamoeba.audiohijack | `~/.mrk/preferences/AudioHijack.plist` | post-install, all | NO ROLLBACK FOUND | COND |
| Farrago | com.rogueamoeba.farrago | `~/.mrk/preferences/Farrago.plist` | post-install, all | NO ROLLBACK FOUND | COND |
| Piezo | com.rogueamoeba.Piezo | `~/.mrk/preferences/Piezo.plist` | post-install, all | NO ROLLBACK FOUND | COND |
| Typora | abnerworks.Typora | `~/.mrk/preferences/Typora.plist` | post-install, all | NO ROLLBACK FOUND | COND |
| Keka | com.aone.keka | `~/.mrk/preferences/Keka.plist` | post-install, all | NO ROLLBACK FOUND | COND |
| TimeMachineEditor | com.tclementdev.timemachineeditor.application | `~/.mrk/preferences/TimeMachineEditor.plist` | post-install, all | NO ROLLBACK FOUND | COND |
| MacWhisper | com.goodsnooze.MacWhisper | `~/.mrk/preferences/MacWhisper.plist` | post-install, all | NO ROLLBACK FOUND | COND |

### Login window message (optional / privileged)

| Operation | Domain | Key | Type | Value | Make targets | Reversible |
|---|---|---|---|---|---|---|
| `sudo defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText "$MRK_LOGIN_MSG"` | /Library/Preferences/com.apple.loginwindow | LoginwindowText | string | `<dynamic: $MRK_LOGIN_MSG env var>` | setup, install, all (only if MRK_LOGIN_MSG is set) | Yes — rollback appended to `~/.mrk/defaults-rollback.sh` |

---

## SECURITY / PRIVILEGED

| Operation | Script:line | Make targets | Reversible | Idempotent |
|---|---|---|---|---|
| `sudo cp /etc/pam.d/sudo → /etc/pam.d/sudo.backup.mrk` | scripts/hardening.sh:34 | harden | Yes — `sudo mv /etc/pam.d/sudo.backup.mrk /etc/pam.d/sudo` (in rollback) | COND (only if pam_tid not already present) |
| Write new `/etc/pam.d/sudo` with `auth sufficient pam_tid.so` prepended | scripts/hardening.sh:43 | harden | Yes — rollback script runs `sudo mv /etc/pam.d/sudo.backup.mrk /etc/pam.d/sudo` | COND |
| `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on` | scripts/hardening.sh:79 | harden | Yes — rollback runs `socketfilterfw --setglobalstate <prev>` | COND (only if was off) |
| `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on` | scripts/hardening.sh:80 | harden | NO ROLLBACK FOUND (setstealthmode not rolled back) | COND |
| `sudo xcodebuild -license accept` | scripts/setup:239 | setup, install, all (only if Xcode.app present) | NO ROLLBACK FOUND | COND |
| `sudo defaults write /Library/Preferences/com.apple.loginwindow LoginwindowText ...` | scripts/setup:576 | setup (MRK_LOGIN_MSG env only) | Yes — rollback script | COND |
| `xattr -cr /Applications/Barkeep.app` (removes quarantine) | scripts/post-install:221 | post-install, all | NO ROLLBACK FOUND | COND |

**Note on PAM validation:** `hardening.sh` validates the generated PAM config before writing —
it checks for `pam_tid.so` and at least one of `pam_smartcard.so` or `pam_opendirectory.so`.
If validation fails, it restores the backup and aborts. This is a meaningful safety guard.

---

## NETWORK

| Operation | Script:line | Make targets | Notes |
|---|---|---|---|
| `curl -sf --max-time 5 https://brew.sh` | scripts/brew:647 | brew, all | Pre-flight connectivity check; exits 1 if unreachable |
| Homebrew installer: `/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"` | scripts/brew:164 | brew, all | Only if Homebrew absent; downloads and executes remote script |
| `$HOMEBREW install gum` | scripts/brew:266 | brew, all | Only if mrk-picker absent; installs TUI toolkit |
| `$HOMEBREW bundle --file=<TEMP_BREWFILE> --verbose` | scripts/brew:625 | brew, all | Installs selected packages from Brewfile; may download many packages |
| `curl -sf https://api.github.com/repos/sevmorris/Barkeep/releases/latest` | scripts/post-install:194 | post-install, all | GitHub API: fetch latest Barkeep release; skipped if already installed |
| `curl -L -sf -o <tmp_dmg> <dmg_url>` | scripts/post-install:205 | post-install, all | Downloads Barkeep DMG; skipped if already installed |
| `ssh -T -o ConnectTimeout=5 git@github.com` | scripts/post-install:267 | post-install, all | Tests SSH auth; gate for remote-URL switch and pull-prefs |
| `git clone git@github.com:sevmorris/mrk-prefs.git ~/.mrk/preferences` | scripts/pull-prefs:18, scripts/snapshot-prefs:21 | pull-prefs; snapshot-prefs; post-install (conditional) | Clones private preferences repo |
| `git -C ~/.mrk/preferences pull --ff-only` | scripts/pull-prefs:14 | pull-prefs; post-install (if prefs already cloned) | Pulls latest from mrk-prefs |
| `git -C ~/.mrk/preferences push` | scripts/snapshot-prefs:99 | snapshot-prefs | Pushes preference exports to mrk-prefs |
| ~~`git -C <repo> push origin HEAD:<branch>`~~ | ~~scripts/syncall:88~~ | ~~syncall~~ | Pushes each discovered GitHub repo | <!-- syncall removed commit ba29d0c -->
| `git -C <repo> fetch --quiet &` | scripts/check-updates:47 | none (shell startup) | Background fetch to check for mrk updates |
| `topgrade` | Makefile:88 | update | If installed: upgrades all package managers including brew, pip, npm, etc. |
| `brew update && brew upgrade` | Makefile:88 | update | If topgrade absent |
| `softwareupdate -ia` | Makefile:91 | updates | macOS Software Update — installs all pending updates |
| `brew install dockutil` | scripts/dock-setup:26 | dock | Only if dockutil absent |
| `gh api ...` (deployment list/delete) | bin/mrk-push:82-111 | none | GitHub API calls; not reachable from any make target |

---

## PACKAGE MANAGER

| Operation | Script:line | Make targets | Reversible | Idempotent |
|---|---|---|---|---|
| Homebrew installation | scripts/brew:164 | brew, all | Manual: `/bin/bash -c "$(curl ... uninstall.sh)"` | COND (only if absent) |
| `$HOMEBREW install gum` | scripts/brew:266 | brew, all | Yes — `brew uninstall gum` | COND |
| `$HOMEBREW bundle --file=<TEMP_BREWFILE>` | scripts/brew:625 | brew, all | Partially — `brew uninstall <pkg>` per package | COND (skips already-installed) |
| `brew install dockutil` (in dock-setup) | scripts/dock-setup:26 | dock | Yes — `brew uninstall dockutil` | COND |
| `brew update && brew upgrade` | Makefile:88 | update | NO ROLLBACK FOUND | NI |
| `topgrade` | Makefile:88 | update | NO ROLLBACK FOUND | NI |
| `softwareupdate -ia` | Makefile:91 | updates | NO ROLLBACK FOUND (OS updates generally irreversible) | NI |
| `brew uninstall --cask barkeep` | bin/nuke-mrk:162 | none | Yes — reinstall | COND |

---

## LOGIN ITEMS / DOCK / FINDER

### Login items

| Operation | Script:line | Make targets | Reversible | Idempotent |
|---|---|---|---|---|
| `osascript: make login item at end with properties {path:"...", hidden:false}` | scripts/post-install:391 | post-install, all | Yes — System Preferences > General > Login Items | COND (checks before adding) |
| Apps added: AlDente, BetterSnapTool, Bitwarden, Chrono Plus, Dropbox, Hammerspoon, Ice, NordPass, Raycast, SoundSource, Stats | | | | |

### Dock

| Operation | Script:line | Make targets | Reversible | Idempotent |
|---|---|---|---|---|
| `dockutil --remove all --no-restart` | scripts/dock-setup:45 | dock | NO ROLLBACK FOUND (existing Dock layout is lost) | I (after first run) |
| `dockutil --add <app> --no-restart` | scripts/dock-setup:53 | dock | Yes — `dockutil --remove <app>` | I (position determined by order) |
| `dockutil --add /Applications --view grid --display folder --no-restart` | scripts/dock-setup:63 | dock | Yes | COND |
| `killall Dock` | scripts/dock-setup:66, scripts/defaults.sh:374 | dock, defaults, trackpad, setup, all | N/A (transient) | I |

### Finder / SystemUIServer

| Operation | Script:line | Make targets | Reversible | Idempotent |
|---|---|---|---|---|
| `killall Finder` | scripts/defaults.sh:374 | defaults, trackpad, setup, all | N/A (Finder relaunches) | I |
| `killall SystemUIServer` | scripts/defaults.sh:375 | defaults, trackpad, setup, all | N/A (relaunches) | I |
| `osascript: set visible of disk <name> to false` | bin/hide_tm.sh:13 | none | Yes — set visible to true | COND |

### Open (browser extension URLs)

| Operation | Script:line | Make targets | Reversible | Idempotent |
|---|---|---|---|---|
| `open <url>` (extension install URLs, once per extension per browser) | scripts/post-install:79 | post-install, all (interactive prompt) | NO ROLLBACK FOUND | NI (opens URLs again if re-run) |

---

## LOGIN SHELL / SHELL ENV

| Operation | Script:line | Make targets | Reversible | Idempotent |
|---|---|---|---|---|
| `chsh -s <zsh-path>` | scripts/setup:595 | setup, install, all | Yes — `chsh -s <previous-shell>` | COND (skips if already zsh) |
| `git -C <mrk-dir> remote set-url origin <ssh-url>` | scripts/post-install:277 | post-install, all | Yes — re-run to switch back to HTTPS | COND (only if HTTPS and SSH auth ok) |
| `cat >> ~/.zshrc` (adds `~/bin` to PATH) | scripts/doctor:27 | doctor (--fix mode) | Yes — edit ~/.zshrc | COND (checks for existing entry) |

---

## PREFS SYNC

| Operation | Script:line | Make targets | Reversible | Idempotent |
|---|---|---|---|---|
| `git clone git@github.com:sevmorris/mrk-prefs.git ~/.mrk/preferences` | scripts/pull-prefs:18 | pull-prefs; post-install (conditional) | Yes — `rm -rf ~/.mrk/preferences` | COND |
| `git -C ~/.mrk/preferences pull --ff-only` | scripts/pull-prefs:14 | pull-prefs | Partially — `git -C ... reset --hard HEAD~N` | COND |
| `defaults export <bundle_id> ~/.mrk/preferences/<name>.plist` (×14 apps) | scripts/snapshot-prefs:33 | snapshot-prefs | Yes — `git -C ~/.mrk/preferences checkout -- <file>` | NI (overwrites) |
| `cp ~/Library/Application Support/<app>/<file> ~/.mrk/preferences/app-support/...` | scripts/snapshot-prefs:76 | snapshot-prefs | Yes | NI |
| `git -C ~/.mrk/preferences add .` | scripts/snapshot-prefs:94 | snapshot-prefs | Yes — `git -C ... reset HEAD` | NI |
| `git -C ~/.mrk/preferences commit -m "snapshot: <date>"` | scripts/snapshot-prefs:98 | snapshot-prefs | Yes — `git -C ... revert HEAD` or `git reset HEAD~1` | NI |
| `git -C ~/.mrk/preferences push` | scripts/snapshot-prefs:99 | snapshot-prefs | Partially — `git push --force` (dangerous) | NI |

---

## GIT REMOTES

| Operation | Script:line | Make targets | Notes | Reversible |
|---|---|---|---|---|
| ~~`git -C <repo> push origin HEAD:<branch>`~~ | ~~scripts/syncall:88~~ | ~~syncall~~ | Pushes every discovered GitHub repo under $HOME with local changes. Finds repos up to 7 levels deep. Auto-commits with message `"syncall: auto-commit <timestamp>"` before pushing. | Partially — cannot un-push; `git revert` per repo | <!-- syncall removed commit ba29d0c -->
| `git -C ~/.mrk/preferences push` | scripts/snapshot-prefs:99 | snapshot-prefs | Pushes to `git@github.com:sevmorris/mrk-prefs.git` | Partially |
| `git add Brewfile && git commit` | scripts/sync:620-621 | sync (with -c flag) | Commits Brewfile update to mrk repo | Yes — `git revert HEAD` |
| `git add ... && git commit` | scripts/sync-login-items:397-398 | sync-login-items (with -c flag) | Commits post-install + docs updates | Yes — `git revert HEAD` |
| `git -C <mrk-dir> remote set-url origin <ssh-url>` | scripts/post-install:277 | post-install, all | Mutates git remote URL in mrk repo (HTTPS→SSH) | Yes — re-set to HTTPS URL |
| `git add -A && git commit && git push` | bin/mrk-push (not a make target) | none | Commits and pushes current repo; also prunes GitHub Deployments via API | Partially |
| `git add -- assets/preferences/ && git commit` | bin/snapshot (not a make target) | none | Commits pref exports to mrk repo | Yes |
| ~~`git -C <repo> add -A && git commit`~~ | ~~scripts/syncall:72-73~~ | ~~syncall~~ | Auto-commit in each dirty repo (interactive confirmation in TTY mode) | Yes — `git revert HEAD` in each repo | <!-- syncall removed commit ba29d0c -->

~~**syncall detail:** By default searches `$HOME` at depth ≤7, skipping:
`$HOME/Library`, `$HOME/.Trash`, `$HOME/.venvs`, `$HOME/.cache`, `$HOME/.cargo`,
`$HOME/.npm`, `_build`, `node_modules`, `.git/modules`, `$HOME/mrk` (the mrk repo itself).
Only syncs repos with a `github.com` remote. Confirm prompt shown when terminal is a TTY.~~
<!-- syncall removed commit ba29d0c -->

---

## PROCESS SIGNALS

| Operation | Script:line | Make targets | Notes |
|---|---|---|---|
| `killall Finder` | scripts/defaults.sh:374 | defaults, trackpad, setup, all | Restarts Finder to apply settings |
| `killall Dock` | scripts/defaults.sh:374, scripts/dock-setup:66 | defaults, trackpad, setup, all, dock | Restarts Dock |
| `killall SystemUIServer` | scripts/defaults.sh:375 | defaults, trackpad, setup, all | Restarts menu bar |
| `caffeinate -d &` | bin/zoom-mode:63 | none | Prevents display sleep; killed by zoom-mode off |
| `kill <pids>` | bin/zoom-mode:37 | none | Kills tracked PIDs (ping loop + caffeinate) |
| `tmutil stopbackup` | bin/zoom-mode:68 | none | Stops active Time Machine backup |
| `launchctl bootout "gui/$UID" com.apple.bird` | bin/audio-mode:158 | none | Stops iCloud Drive sync daemon |
| `launchctl bootout "gui/$UID" com.apple.cloudd` | bin/audio-mode:159 | none | Stops iCloud Drive sync daemon |
| `launchctl bootstrap "gui/$UID" <plist>` | bin/audio-mode:163 | none | Restarts iCloud Drive sync daemons |

---

## XCODE / DEVELOPER TOOLS

| Operation | Script:line | Make targets | Reversible | Idempotent |
|---|---|---|---|---|
| `xcode-select --install` | scripts/setup:233 | setup, install, all | Yes — `sudo rm -rf /Library/Developer/CommandLineTools` | COND (only if CLT absent) |
| `sudo xcodebuild -license accept` | scripts/setup:239 | setup, install, all | NO ROLLBACK FOUND | COND (only if Xcode.app present) |

---

## Hot Spots

Ranked by blast radius: irreversible, privileged, touches user data outside mrk's own state,
or pushes to a remote.

### 1. `make syncall` — Auto-commit and push ALL GitHub repos under $HOME

> **Removed** in commit `ba29d0c` (branch `audit/static-pass`). Section retained for audit history.

**Blast radius: CRITICAL.**
Searches up to 7 directory levels deep under `$HOME` for any git repo with a
GitHub remote. For each dirty repo (with interactive confirmation in TTY mode),
it runs `git add -A` (stages everything, including secrets/unintended files),
creates a time-stamped commit, then pushes to GitHub origin. A single run can
push to tens of repos the user hasn't reviewed. The skip list is short and
env-configurable (`SYNCALL_SKIP_PATHS`). The mrk repo itself is excluded by
default, but all other repos under `$HOME` are candidates. Auto-commit message is
generic (`"syncall: auto-commit <timestamp>"`), making history noisy. Push cannot
be recalled once complete.

### 2. `make harden` — Edits /etc/pam.d/sudo

**Blast radius: HIGH (privileged, system-wide, affects all sudo sessions).**
Rewrites `/etc/pam.d/sudo` to add Touch ID authentication. If the PAM config
is malformed or incompatible with a future macOS update, all `sudo` access on
the machine could break until manually recovered from single-user mode or a
backup. Rollback (`sudo mv /etc/pam.d/sudo.backup.mrk /etc/pam.d/sudo`) is in
`~/.mrk/hardening-rollback.sh`. Stealth mode (`socketfilterfw --setstealthmode on`)
has NO rollback entry in the hardening script.

### 3. `make snapshot-prefs` — Pushes private app preferences to GitHub

**Blast radius: HIGH (network, user data, remote git push).**
Exports full application preferences (including potentially sensitive config for
audio routing, iTerm2, Raycast, Bitwarden-adjacent apps) and pushes them to
`git@github.com:sevmorris/mrk-prefs.git`. If the repo becomes public or is
compromised, exported preferences could expose configuration details. Each run
overwrites the previous export (NI). Cannot un-push.

### 4. `make all` / `make post-install` — Bulk defaults import from mrk-prefs

**Blast radius: HIGH (user data, irreversible for existing config).**
Imports full application plists for 14 apps. The skip logic (`if [[ -f "$existing" ]]`)
prevents overwriting existing configs, but on a fresh machine this overwrites
the default app state with potentially stale data from the prefs repo. No rollback.
Each import atomically replaces the app's preference domain.

### 5. `make all` / `make brew` — Homebrew bulk installation

**Blast radius: HIGH (network, package manager, disk).**
Installs all user-selected packages from the Brewfile. Includes a `curl | bash`
Homebrew installer if Homebrew is absent (executes remote code). No rollback for
installed packages; `brew uninstall` must be done manually per package.

### 6. `make defaults` / `make setup` — Kills Finder, Dock, SystemUIServer

**Blast radius: MEDIUM (visible, disruptive, reversible but jarring).**
`killall Finder/Dock/SystemUIServer` is run unconditionally at the end of
defaults application. On a machine with open work, this forces Finder windows to
close and may interrupt window-manager state. Recovers immediately (processes relaunch).

### 7. `make dock` — Clears and rebuilds the Dock

**Blast radius: MEDIUM (irreversible layout, privileged via dockutil).**
`dockutil --remove all` wipes the entire Dock layout before rebuilding. Existing
custom layout is permanently lost (no backup). `killall Dock` restarts it.

### 8. `make updates` — macOS Software Updates

**Blast radius: MEDIUM (irreversible, system-wide).**
`softwareupdate -ia` installs ALL pending macOS updates including OS version
upgrades. These cannot be rolled back. May require reboots.

### 9. `make post-install` — Copies Barkeep from GitHub to /Applications

**Blast radius: MEDIUM (network, arbitrary DMG execution, quarantine removal).**
Downloads a DMG from a GitHub release URL, mounts it, copies the `.app` to
`/Applications/`, then runs `xattr -cr` to remove the quarantine flag. The URL
is resolved at runtime via GitHub API. If the release is compromised or the
download is intercepted, a malicious app could be installed with quarantine removed.

### 10. `make post-install` — Rewrites mrk git remote URL from HTTPS to SSH

**Blast radius: LOW-MEDIUM (git config mutation, one-way for this session).**
If SSH auth succeeds, `git remote set-url origin` permanently changes the mrk
repo's remote from `https://github.com/...` to `git@github.com:...`. Reversible
manually but not by any automated rollback.
