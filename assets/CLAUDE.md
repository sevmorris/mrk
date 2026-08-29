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
- **WireHack** — **Superseded by ClipHack**, which absorbed its yt-dlp downloading. A GUI wrapper around yt-dlp; still public and still installed, but not the place to add features. It has one unreleased fix on `main` (a corrected `--remote-components` value); releasing it is probably not worth it.
- **JustLoop** — Drop an audio file and it loops. Menu bar integration.
- **Barkeep** — Homebrew Brewfile manager: browse and manage the Brewfile, adopt untracked packages.
- **Magic Backup Machine** — rsync-based backup/restore of application settings and presets. Xcode project lives in `BackupRestore/`.
- **Cypher** — Passphrase-based text encryption, with a matching web implementation under `web/`.
- **PasswordGen** — "Perfect Passwords Grabber", fetches random passwords from GRC.com. SwiftPM, not Xcode. **Its git remote is `sevmorris/ppg`.**
- **KeyVault** — SSH, GPG, Age, and API key manager, plus a `Note` type for secrets it owns outright. `io.github.sevmorris.KeyVault`, macOS 15.0+. Being adapted as the store for personal secrets that NordPass isn't the right home for (it keeps passwords and passkeys), so `SecretStore` items are self-describing in the Keychain rather than indexed from UserDefaults. Backup and migration go through a passphrase-encrypted OpenPGP archive (`VaultExportService`, armored, AES-256) — readable by any `gpg` without KeyVault, which is the point; the restore drill has been run against a real export. **That archive covers `SecretStore.ownedTypes` only — `[.api, .note]`.** SSH and GPG keys are *indexed*, not owned: `SSHService` reads `~/.ssh` and `GPGService` reads `~/.gnupg`, the private material never enters the Keychain, and `GPGService` can export public keys only. So the vault export is half a machine transfer; the key files are the other half, and in mrk they are handled by `make snapshot-keys` / `make restore-keys`. `AgeService` is dormant: `age` is not installed and not in the Brewfile. Public repo, manual at `sevmorris.github.io/KeyVault`.

### Sites and docs
- **sevmac** — macOS setup guide, published to Pages. Two pages: `docs/index.html` (SMAC-1, full reference) and `docs/daily.html` (SMAC-2, day-to-day commands), cross-linked. Hand-written HTML with `.nojekyll` — do not add Jekyll.
- **raspi-time-machine-guide** — Raspberry Pi Time Machine setup guide (RPTM-1). Single hand-written `docs/index.html` in the sevmac house style; Pages serves `/docs` on `master` with `.nojekyll` and no build step. Was MkDocs until 2026-08-27.
- **dead-city-sf** — Browser/terminal Python game published via Pages.
- **doublender-dashboard** — Cloudflare Worker dashboard for DoublEnder (Node, vitest).

### Cross-repo conventions
- **Shared files.** WaxOnWaxOff, ClipHack, DoublEnder, FilmStrip and KeyVault keep some files byte-identical (`tools/dmg/`, `scripts/check-shared.sh`, and `FFmpegProcess.swift` in the two that need it). Any file carrying the header comment "Shared verbatim across the sibling app repos" is compared by `scripts/check-shared.sh`, which runs in each release preflight and fails on drift. Registration is by that marker, not a manifest — except for the `SIBLINGS` array inside `check-shared.sh`, which names the repos to compare against and lives in a file that is itself shared verbatim. Adding a repo there means editing all five copies in one go; changing one alone makes that copy differ and fails every repo's preflight.
- **Vendored binaries** are fetched, not committed: a pinned GitHub release asset plus SHA-256s in `Vendor/ffmpeg-manifest.env`, fetched by `scripts/fetch-ffmpeg.sh`. Those deps releases must stay published and flagged as prereleases — an ordinary release becomes `/releases/latest` and breaks README download links.
- **release.sh prunes release pages, never git tags.** A page is a convenience; a tag is the record.
- **DoublEnder's private Cloud overlay is versioned separately.** `project.cloud.yml`, `scripts/` and `DoublEnderCloud/` are gitignored in the public repo and tracked in `sevmorris/DoublEnder-cloud` (private), via a bare repo at `~/DoublEnder-cloud.git` sharing the same working tree — the overlay is interleaved with the public tree, so a submodule can't span it. Use `decloud` (mrk's `bin/`, on PATH) instead of `git` for it. The GCS service-account key and `ingest.env` are **not** in that repo and never should be; a pre-commit hook refuses them.
- **Pages deployments accumulate.** Every push to a Pages repo creates a deployment that is never cleaned up. Run `prune-deployments` (mrk's `bin/`, on PATH) from inside the repo — it reads the repo from the origin remote, paginates, and always protects the deployment currently serving the site, so a failed deploy cannot make it delete the live one. `--dry-run` first, `--keep N` to retain more. Applies to sevmac, mrk, dead-city-sf, raspi-time-machine-guide and KeyVault. `mrk-push` already does this for mrk as part of pushing.

## Build Commands

### macOS apps
```bash
# From the project directory
xcodebuild -project <ProjectName>.xcodeproj -scheme <ProjectName> -configuration Release

# Repos with tests
xcodebuild -project <ProjectName>.xcodeproj -scheme <ProjectName> test
```

Distribution differs by project:
- `./release.sh <version>` — WaxOnWaxOff, ClipHack, FilmStrip, DoublEnder, WireHack, Barkeep, Magic Backup Machine, KeyVault. Builds, signs, notarizes, publishes, and rewrites version references in the docs.
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
- Deployment targets: 14.0 for WaxOnWaxOff, ClipHack, FilmStrip, WireHack and Barkeep; 13.0 for DoublEnder and JustLoop; 15.0 for KeyVault.
- MVVM with `@Observable` / `@MainActor`, actor-based services.
- `PBXFileSystemSynchronizedRootGroup` in WaxOnWaxOff, ClipHack, FilmStrip, JustLoop and KeyVault — new files in a synced folder are picked up with no project edit. Barkeep, WireHack and DoublEnder do **not** use it, so adding or removing a file there means editing `project.pbxproj` (or `project.yml`, for DoublEnder).
- A consequence of synced groups worth knowing: Xcode decides what to bundle when it *plans* the build, so a build-phase script that downloads a resource runs too late for the first build on a fresh clone. That is why `release.sh` fetches FFmpeg before invoking `xcodebuild` rather than relying on the phase alone.
- App sandbox disabled where system tool access is needed (KeyVault, WaxOnWaxOff, ClipHack).
- Build output lands in `build/Build/Products/Release/<AppName>.app`.

### Shell scripts
- `set -euo pipefail` for strict error handling.
- Validate with `shellcheck` before committing — but note the `release.sh` scripts are **zsh**, which shellcheck cannot analyse; use `zsh -n` for those.
- The user's gitconfig sets `color.grep = always`, so any script parsing git output must pass `--no-color`. `-c color.ui=false` does not override it.
