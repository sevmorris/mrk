# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a collection of independent macOS-focused projects, not a monorepo. Each subdirectory is a standalone project.

## Projects

### macOS apps (Swift/SwiftUI, Xcode)
- **WaxOnWaxOff** — Podcast audio prep: WaxOn (raw recording prep) + WaxOff (delivery/mastering). `io.github.sevmorris.WaxOnWaxOff`, macOS 14.0+. Bundles a pinned LGPL FFmpeg fetched at build time.
- **ClipHack** — Prepares third-party audio clips (news, promos, broadcast) for use in a show. Logic lives in a `ClipHackKit` framework; bundles FFmpeg and yt-dlp. DMGs publish to a separate `ClipHack-releases` repo.
- **FilmStrip** — Extracts audio from video for an audio-only viewing workflow. Bundles a pinned LGPL FFmpeg fetched at build time.
- **DoublEnder** — Double-ended remote recording. Has a **private Cloud overlay** (`project.cloud.yml`, `DoublEnderCloud/`, `scripts/`) that is gitignored; the public tree builds without it. MIT.
- **WireHack** — **Retired on 2026-09-23.** ClipHack absorbed its yt-dlp downloading and supersedes it. The GitHub repo is archived (read-only); its README and its last release, v1.10.0, say so and point to ClipHack. Its local clone was deleted after archiving, so the audits no longer list it; there are no further features or releases. Its one unreleased fix (a corrected `--remote-components` value) stays unreleased. Anyone still running it is told v1.10.0 is current, because its in-app updater reads the archived releases.
- **JustLoop** — Drop an audio file and it loops. Menu bar integration.
- **Barkeep** — Homebrew Brewfile manager: browse and manage the Brewfile, adopt untracked packages.
- **Magic Backup Machine** — rsync-based backup/restore of application settings and presets. Xcode project lives in `BackupRestore/`.
- **Cypher** — Passphrase-based text encryption, with a matching web implementation under `web/`.
- **PasswordGen** — "Perfect Passwords Grabber", fetches random passwords from GRC.com. SwiftPM, not Xcode. **Its git remote is `sevmorris/ppg`.**
- **KeyVault** — SSH, GPG, Age, and API key manager, plus `Note` and `File` types for secrets it owns outright. `io.github.sevmorris.KeyVault`, macOS 15.0+. Being adapted as the store for personal secrets that NordPass isn't the right home for (it keeps passwords and passkeys), so `SecretStore` items are self-describing in the Keychain rather than indexed from UserDefaults. Backup and migration go through a passphrase-encrypted OpenPGP archive (`VaultExportService`, armored, AES-256) — readable by any `gpg` without KeyVault, which is the point; the restore drill has been run against a real export. **That archive covers what KeyVault stores — `KeyType.isStored`: notes and API keys (`SecretStore.ownedTypes`, `[.api, .note]`, in the Keychain) and files (`FileStore`: one AES-GCM-sealed, self-describing `<uuid>.kvfile` each in `~/Library/Application Support/KeyVault/Files`, never in the Keychain, stored only under a master passphrase, base64 inside the archive).** Nothing KeyVault stores may be read or written by a test against the real service or folder: `VaultCrypto.configure` deletes and rewrites the vault's salt, and `FileStore` takes its directory as a parameter so a harness can build one elsewhere. SSH and GPG keys are *indexed*, not owned: `SSHService` reads `~/.ssh` and `GPGService` reads `~/.gnupg`, the private material never enters the Keychain, and `GPGService` can export public keys only. So the vault export is half a machine transfer; the key files are the other half, and in mrk they are handled by `make snapshot-keys` / `make restore-keys`. `AgeService` is dormant: `age` is not installed and not in the Brewfile. Public repo, manual at `sevmorris.github.io/KeyVault`.

### Sites and docs
- **sevmac** — macOS setup guide, published to Pages. Two pages: `docs/index.html` (SMAC-1, full reference) and `docs/daily.html` (SMAC-2, day-to-day commands), cross-linked. Hand-written HTML with `.nojekyll` — do not add Jekyll. **It documents mrk and does not update itself** — see the cross-repo convention below.
- **raspi-time-machine-guide** — Raspberry Pi Time Machine setup guide (RPTM-1). Single hand-written `docs/index.html` in the sevmac house style; Pages serves `/docs` on `master` with `.nojekyll` and no build step. Was MkDocs until 2026-08-27.
- **dead-city-sf** — Browser/terminal Python game published via Pages.
- **doublender-dashboard** — Cloudflare Worker dashboard for DoublEnder (Node, vitest).

### Cross-repo conventions
- **Shared files.** WaxOnWaxOff, ClipHack, DoublEnder, FilmStrip, KeyVault and Magic Backup Machine keep some files byte-identical (`tools/dmg/`, `scripts/check-shared.sh`, and `FFmpegProcess.swift` in the two that need it). Any file carrying the header comment "Shared verbatim across the sibling app repos" is compared by `scripts/check-shared.sh`, which runs in each release preflight and fails on drift. Registration is by that marker, not a manifest — except for the `SIBLINGS` array inside `check-shared.sh`, which names the repos to compare against and lives in a file that is itself shared verbatim. Adding a repo there means editing all six copies in one go; changing one alone makes that copy differ and fails every repo's preflight.
- **Vendored binaries** are fetched, not committed: a pinned GitHub release asset plus SHA-256s in `Vendor/ffmpeg-manifest.env`, fetched by `scripts/fetch-ffmpeg.sh`. Those deps releases must stay published and flagged as prereleases — an ordinary release becomes `/releases/latest` and breaks README download links. Each FFmpeg repo builds (`scripts/build-ffmpeg.sh`) and hosts its own, and never deletes a superseded one: older tags pin them. The binaries must carry `LC_UUID` — dyld on macOS 26.7 refuses an executable without one — and reproducibility comes from `ZERO_AR_DATE=1`, not `-Wl,-no_uuid` (the r2 recipe, whose binaries abort there). The build script asserts both. **Only the `dependency-updates` skill watches these pins** — Dependabot cannot read the manifests — and a pin reaches users only with an app release. Its SessionStart hook, which mrk's post-install adds to `~/.claude/settings.json`, reports in every session any pin behind upstream (yt-dlp, FFmpeg, LAME) and any open Dependabot alert; the skill holds the update procedure. Check it before cutting a release: ClipHack 1.25.7 shipped a yt-dlp two releases old.
- **Release preflight.** Every `release.sh` notarizes with the keychain profile `notarytool` (`NOTARY_PROFILE` overrides it). A profile cannot be exported, so a new Mac needs `xcrun notarytool store-credentials notarytool --apple-id <email> --team-id T9RLNAXPWU` before its first release. The app scripts also check that profile, that `python3` can spawn a subprocess (dmgbuild shells out to hdiutil), and the remote's tags — fetched, not just the clone's — before building; they push branch and tag in one atomic push. There is deliberately no fallback to bare `hdiutil`: a DMG without its installer window fails the release, and verification checks the mounted image for its `.DS_Store` and background.
- **Release notes are curated, not generated.** Every app's `release.sh` takes `release-notes/v<version>.md` when it exists and **stops in preflight when it does not** — before anything is built, pushed or published, because failing at the GitHub step would strand a pushed tag with no release behind it. `--generated-notes` falls back to commit subjects, as a decision rather than a silent default. Write the CHANGELOG entry first and put the same prose in the notes file. ClipHack 1.25.5 is what this is for: it published two commit subjects while the changelog entry written for it sat in the repo unread.
- **release.sh prunes release pages, never git tags.** A page is a convenience; a tag is the record.
- **The release scripts are seven copies of one idea, so port a fix the same day.** A guard added in one repo reaches the others only by hand, and WaxOnWaxOff gaining a check in July that ClipHack still lacked in September is how the same wall gets hit twice. `WaxOnWaxOff/release.sh` is the reference. The `release-standards` skill (`~/Projects/.claude/skills/`, tracked in `mrk/assets/projects-skills/`) lists every guard, what each one prevents, and carries a read-only `scripts/audit.sh` printing which repos are missing which — run it after touching any `release.sh`. One subtlety it records: a zsh `EXIT` trap does **not** fire on a signal, so each script also traps `INT` and `TERM`, or Ctrl-C during the notarization wait strands a version bump in the working tree.
- **Homebrew is no longer a distribution channel for these apps, with one exception.** The `doublender` and `waxonwaxoff` casks were deprecated on 2026-09-17: both apps check GitHub for their own updates, so the cask was a second update path whose records went stale the moment an in-app update was installed — Homebrew had 2.12.0 and 2.5.0lr recorded against 2.12.4 and 2.5.4lr on disk, and nothing noticed. They are deprecated rather than deleted so an existing `brew upgrade` says where the app went. **`fl2601` (the Cypher repo) keeps its cask and must:** it is sandboxed with no network entitlement at all — deliberately, so it cannot phone anywhere even if compromised — so it cannot check for its own updates, and `distribute.sh --bump-cask` is still its publish path. Do not add a cask-bump step back to any other release script.
- **DoublEnder's private Cloud overlay is versioned separately.** `project.cloud.yml`, `scripts/` and `DoublEnderCloud/` are gitignored in the public repo and tracked in `sevmorris/DoublEnder-cloud` (private), via a bare repo at `~/DoublEnder-cloud.git` sharing the same working tree — the overlay is interleaved with the public tree, so a submodule can't span it. Use `decloud` (mrk's `bin/`, on PATH) instead of `git` for it. The GCS service-account key and `ingest.env` are **not** in that repo and never should be; a pre-commit hook refuses them.
- **sevmac lags mrk, and the lag is dangerous.** sevmac documents mrk from a separate repo, by hand, so every mrk change to a command, a Make target, an install phase, a LaunchAgent schedule, or anything affecting what moves between machines needs a matching sevmac edit. `mrk/CLAUDE.md` carries the table of which change maps to which section; check it in the same session, not later. The failure mode is not cosmetic: `snapshot-keys` landed in mrk on 2026-08-29 and SMAC-1's migration checklist did not mention it for two days, so following that checklist would have wiped a Mac while leaving the Developer ID signing key — which Apple cannot reissue — behind. Flags are the one thing sevmac must **not** restate: they live in BIN-1 (`mrk/docs/bin/mrk-usage.html`), which ships with the code, and SMAC-1 links into it by anchor.
- **Pages deployments accumulate.** Every push to a Pages repo creates a deployment that is never cleaned up. Run `prune-deployments` (mrk's `bin/`, on PATH) from inside the repo — it reads the repo from the origin remote, paginates, and always protects the deployment currently serving the site, so a failed deploy cannot make it delete the live one. `--dry-run` first. It keeps the ten newest by default, which is what repo-standards asks for and what `maintain` and `mrk-push` keep for mrk; `--keep N` changes that. Deletions can't be undone. Until 2026-09-23 the default was 1, and twice that day a run without `--keep` left a repo only its live deployment. Applies to sevmac, mrk, dead-city-sf, raspi-time-machine-guide, KeyVault, ClipHack (Pages enabled 2026-09-05, serving `/docs` on `main` — the manual) and FilmStrip (serving `/docs` on `main`; first pruned 2026-09-23). `mrk-push` already does this for mrk as part of pushing.
- **Every repository is held to one standard, and a skill checks it.** `release-standards` covers the release machinery inside the apps. `repo-standards` (`~/Projects/.claude/skills/`, tracked in `mrk/assets/projects-skills/`) covers everything around it, for every repository on the account, including mrk, sevmac and the private ones: the no-force-push ruleset, secret push protection, Dependabot alerts, `.nojekyll`/HTTPS/homepage/pruned deployments for Pages, a licence and README, tests that some CI or `release.sh` actually runs, current CI actions, and no committed executables. Its read-only `scripts/audit.sh` prints which repos miss which, from GitHub's published state. Run it when creating a repository, making one public, or adding tests, CI or Pages to one. Its fixes change settings or add commits, so they wait for the owner's go-ahead.

## Build Commands

### macOS apps
```bash
# From the project directory
xcodebuild -project <ProjectName>.xcodeproj -scheme <ProjectName> -configuration Release

# Repos with tests
xcodebuild -project <ProjectName>.xcodeproj -scheme <ProjectName> test
```

Distribution differs by project:
- `./release.sh <version>` — WaxOnWaxOff, ClipHack, FilmStrip, DoublEnder, Barkeep, Magic Backup Machine, KeyVault. Builds, signs, notarizes, publishes, and rewrites version references in the docs.
- `./build.sh` + `./distribute.sh` — JustLoop, PasswordGen, Cypher.

`DoublEnder` is generated by **xcodegen** from `project.yml`; edit that rather than the `.xcodeproj`. Its Cloud build additionally needs the private `project.cloud.yml` overlay.

### Static guide sites (sevmac, raspi-time-machine-guide)
Hand-written HTML, no build step. Open the file to preview:
```bash
open docs/index.html
```
Pages serves `/docs` directly with `.nojekyll`. Pushing publishes in under a minute.

### doublender-dashboard
```bash
npm ci && npx vitest run
```

## Architecture Notes

### Swift apps
- SwiftUI + AVFoundation for the audio apps; KeyVault uses the Security framework (Keychain).
- Deployment targets: 14.0 for WaxOnWaxOff, ClipHack, FilmStrip and Barkeep; 13.0 for DoublEnder and JustLoop; 15.0 for KeyVault.
- MVVM with `@Observable` / `@MainActor`, actor-based services.
- WaxOnWaxOff, ClipHack and FilmStrip build with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so a value type or pure helper reached from an actor, a function value or a default-argument closure needs `nonisolated` — Swift 6.4 (Xcode 27) warns on each one, and it is an error in Swift 6 mode.
- `PBXFileSystemSynchronizedRootGroup` in WaxOnWaxOff, ClipHack, FilmStrip, JustLoop and KeyVault — new files in a synced folder are picked up with no project edit. Barkeep and DoublEnder do **not** use it, so adding or removing a file there means editing `project.pbxproj` (or `project.yml`, for DoublEnder).
- A consequence of synced groups worth knowing: Xcode decides what to bundle when it *plans* the build, so a build-phase script that downloads a resource runs too late for the first build on a fresh clone. That is why `release.sh` fetches FFmpeg before invoking `xcodebuild` rather than relying on the phase alone.
- App sandbox disabled where system tool access is needed (KeyVault, WaxOnWaxOff, ClipHack).
- Build output lands in `build/Build/Products/Release/<AppName>.app`.

### Toolchain
- **An Xcode newer than macOS is a trap.** Xcode 27 ships only the macOS 27 SDK; on macOS 26 anything built against it can weak-link functions the running OS lacks. pyenv's Python did (`pipe2`, `dup3`) and segfaulted on every subprocess call, which is what broke dmgbuild — and ensurepip — on the 2026-09-15 migration. mrk's post-install now builds it with `CC=/usr/bin/clang SDKROOT=<CLT MacOSX26.sdk>`. Anything else compiled from source here deserves the same suspicion.
- Pass `-destination 'generic/platform=macOS'` to Release builds. Without it xcodebuild warns and builds only the first matching destination's arch; with it, `ARCHS` decides (arm64 for the FFmpeg apps, universal for DoublEnder).

### Shell scripts
- `set -euo pipefail` for strict error handling.
- Validate with `shellcheck` before committing — but note the `release.sh` scripts are **zsh**, which shellcheck cannot analyse; use `zsh -n` for those.
- The user's gitconfig sets `color.grep = always`, so any script parsing git output must pass `--no-color`. `-c color.ui=false` does not override it.
