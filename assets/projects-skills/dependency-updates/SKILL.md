---
name: dependency-updates
description: Keep the third-party code the apps ship current. That means the binaries vendored through <repo>/Vendor/*-manifest.env — yt-dlp in ClipHack; FFmpeg and LAME in WaxOnWaxOff, ClipHack and FilmStrip — and the npm dependencies Dependabot flags in doublender-dashboard. A SessionStart hook runs the check in every session and reports what is behind. Use this when that notice appears, when asked whether yt-dlp, FFmpeg, LAME or any dependency is up to date, when updating one, and before cutting an app release, so the release does not ship a stale tool.
---

# Dependency updates

Nothing else watches the vendored binaries. Dependabot cannot read the
`Vendor/*-manifest.env` files, and each pin reaches users only inside an app
release, so a pin drifts until someone looks. On 2026-09-23:
- ClipHack 1.25.7 shipped yt-dlp 2026.06.09, two releases behind and already
  warning that it was more than 90 days old.
- FFmpeg had sat at 8.0 for thirteen months, across three point releases on its
  own branch.
- LAME 4.0 had been out for ten weeks while the docs called 3.100 current.

That is what this skill is for. It watches the pins and holds the update
procedure. Releasing still goes through `release-standards`.

## 1. Check

```bash
S=~/.claude/skills/dependency-updates/scripts
bash $S/check.sh               # check now: pins vs upstream, open Dependabot alerts
bash $S/check.sh --list        # the cached findings, with their ids
bash $S/check.sh --ack ID|all  # stop the session notice repeating these
```

| What | Pinned in | Compared with |
|---|---|---|
| yt-dlp | `ClipHack/Vendor/ytdlp-manifest.env` | yt-dlp's latest GitHub release |
| FFmpeg | `Vendor/ffmpeg-manifest.env` (`FFMPEG_SOURCE_RELEASE`) in the three FFmpeg repos | FFmpeg's release tags: the newest point release on the pinned branch, and the newest line |
| LAME | the same manifest (`LAME_VERSION`, or the version in `LAME_SOURCE_URL`) | SourceForge's current release |
| npm and other manifests GitHub reads | `package-lock.json` and the like | open Dependabot alerts, on every non-archived repository the account owns |
| any other `*_VERSION` in a Vendor manifest | wherever it is | nothing yet: it is reported as unchecked, so a new vendored tool is not silently ignored. Teach `check.sh` about it. |

Manifests are found by searching `~/Projects`, so a new app with a `Vendor/`
folder is covered without editing anything.

**The session notice.** `~/.claude/settings.json` runs `check.sh --session` at
the start of every session. It reads a cache and prints only when something
needs attention. When the cache is more than 12 hours old, it refreshes it in
the background for the next session, so it never slows a start. The notice
tells Claude to mention the findings once and to update nothing without the
owner's go-ahead.

A finding's id names the upstream version it was raised for. `--ack` therefore
silences a finding only until upstream moves again. Each alert id carries the
newest alert's number, so a new alert raises it again.

The cache and acknowledgements live in `~/Library/Caches/dependency-updates`;
deleting that folder resets both. mrk's `post-install` links this skill to
`~/.claude/skills/dependency-updates` and installs the hook. The tracked copy
lives in `mrk/assets/projects-skills/`.

## 2. Update yt-dlp (ClipHack)

1. **Verify before pinning.** `verify-ytdlp.sh [TAG]` (the latest by default)
   requires three things: a good signature on `SHA2-256SUMS` from yt-dlp's key,
   by the fingerprint pinned in the script; the asset's SHA-256 in that file;
   and the same SHA-256 in GitHub's digest. It prints the manifest lines. If it
   refuses because the key changed, stop and ask the owner. Do not edit the
   fingerprint to make it pass.
2. **Read the release notes** between the old pin and the new tag
   (`gh release view TAG -R yt-dlp/yt-dlp`). For each security advisory, check
   whether ClipHack passes the affected option. Its whole argument list is
   `YtDlpService.buildArguments`.
3. **Update `Vendor/ytdlp-manifest.env`, then grep the repo for the old version
   string.** The README's third-party section names it, and so do comments and
   tests of the form "verified against <version>". Re-check each claim against
   the new binary before renaming it.
4. **Compare old and new the way the app runs them:**
   - ClipHack's exact arguments;
   - the bundled FFmpeg (`ClipHackKit/`);
   - a Finder-launch environment. A Terminal `PATH` includes Homebrew's deno,
     which the app never sees.

   ```bash
   env -i HOME="$HOME" PATH=/usr/bin:/bin:/usr/sbin:/sbin "$BIN" \
     -f 'ba/b' -x --ffmpeg-location ClipHackKit -P "$OUT" -o '%(title)s.%(ext)s' \
     --print 'after_move:CLIPHACK_OUT|%(filepath)s' --no-quiet --no-playlist --newline \
     --restrict-filenames --retries 10 --fragment-retries 10 -N 4 \
     --remote-components ejs:github --no-cache-dir 'https://www.youtube.com/watch?v=jNQXAC9IVRw'
   ```

   Run it once per binary, then once more per binary with a custom stem
   (`-o 'Lit Text two.%(ext)s'`). Compare the exit status, the `CLIPHACK_OUT|`
   path and `ffprobe` of the file. Use "Me at the zoo" (19 s) as the test
   video; yt-dlp's usual test video, BaW_jenozKc, has been removed.
5. `./scripts/fetch-ytdlp.sh`, run the tests, and write the CHANGELOG entry and
   `release-notes/v<version>.md`. Push, wait for CI, then release through
   `release-standards`. In the published DMG, run
   `ClipHack.app/Contents/Frameworks/ClipHackKit.framework/Versions/A/Resources/yt-dlp --version`.

## 3. Update FFmpeg or LAME (WaxOnWaxOff, ClipHack, FilmStrip)

This is heavier than yt-dlp. Each repo builds its own binaries from a committed
recipe and hosts them as its own deps release. A **point release on the pinned
branch** carries bug and security fixes and is the routine update. A **new
line** (8.0 to 9.0), or a new LAME major version, changes behaviour. It is a
separate decision for the owner, so present it rather than doing it.
`WaxOnWaxOff/Vendor/README.md` ("Updating the bundled binary build") is the
reference. The three `build-ffmpeg.sh` copies differ only in project name and
work directory, so repin all three the same day.

1. **Verify the sources.**
   - FFmpeg: check the tarball's `.asc` against FFmpeg's release signing key,
     not only a SHA-256 copied from the same page. The key is
     `FCF986EA15E6E293A5644F10B4322F04D67658D8` (from
     `https://ffmpeg.org/ffmpeg-devel.asc`; keyserver.ubuntu.com serves the
     same one), and it also signed the 8.0 tarball the old pin trusts. Verify
     the old tarball with it too: that continuity is the strongest evidence.
   - LAME: it publishes no signatures. Confirm the SHA-256 from an independent
     source, such as the checksum in Homebrew's `lame` formula.
2. **Re-read the licences** at the new version: FFmpeg's `LICENSE.md`, and the
   header of LAME's `include/lame.h`. Update the licence table and source links
   in each `Vendor/README.md`. The LGPL source obligation described there
   depends on them.
3. **Repin and build.** Edit the pins in `scripts/build-ffmpeg.sh`
   (`FFMPEG_VERSION`/`FFMPEG_SHA`, `LAME_VERSION`/`LAME_SHA`) and run it. It
   asserts:
   - no `--enable-gpl`, `--enable-nonfree` or `--enable-version3`;
   - `libmp3lame` is linked;
   - the deployment target;
   - `LC_UUID` is present (dyld on macOS 26.7 aborts without it);
   - no non-system dylibs.

   Pass an **absolute** output directory: the script `cd`s into its work
   directory before copying out, so a relative one fails at the very end.
   Build twice and compare SHA-256s. The recipe is reproducible, and a
   difference means something changed. The script does not check for weak
   imports, the failure CLAUDE.md warns about when the SDK is newer than the
   OS, so check by hand: `nm -m ffmpeg | grep undefined | grep -c weak`
   must be 0, as it is for every build so far. Build with the same SDK as
   the binary being replaced (`otool -l` shows `sdk`), so that parity
   measures FFmpeg's changes and nothing else.
4. **Run parity, old binary against new.** All three repos have
   `scripts/parity-corpus-gen.sh` and `scripts/parity-check.sh`. Their
   thresholds are frozen: never edit one after seeing results; take failing
   data to the owner. Validate a harness before trusting it: the old binary
   against itself must pass everything, and against Homebrew's FFmpeg it must
   fail. WaxOnWaxOff encodes MP3, so a LAME change must pre-register its
   bitstream divergence *before* the run. Its harness always skips the MP3 null
   gate. When LAME is unchanged, compare the decoded MP3s separately: in the
   8.0 → 8.0.3 move the audio was identical and the files differed by one byte,
   the `Lavf` encoder string in the ID3 tag.
   FilmStrip's harness was added after its 8.0.3 move, which an ad-hoc script
   checked. It compiles the app's own `FilterGraphBuilder.swift`, so the
   graphs are not retyped. It gates every stage at a −inf null, and also gates
   the loudnorm JSON and the `ffprobe` fields TrackInspector reads. It needs
   video fixtures, so its corpus comes from Homebrew's full FFmpeg.
   `FilmStrip/Vendor/README.md` ("Parity") has the commands and the 2026-09-23
   results: 8.0 → 8.0.3 changed only a `vendor_id` tag the app does not read,
   and 9.0.2 fails on every fixture. Also diff every `ffprobe` call the other
   apps make.
5. **Publish the binaries** as `ffmpeg-deps-<version>-audio-arm64-r<N>`, in the
   repo named by `FFMPEG_DEPS_REPO` (ClipHack's is `ClipHack-releases`).
   `r<N>` is the **recipe** revision, shared by all three repos: 8.0.3 went
   out as `-r4` because only its pins changed. Commit and push the repinned
   `build-ffmpeg.sh` alone first, and tag the deps release at that commit
   (`gh release create --target <sha> --prerelease --latest=false`). Only then
   push the manifest, because CI fetches whatever the manifest names. Publish
   the release:
   - as a **prerelease**. A normal release becomes `/releases/latest` and
     breaks the README download links;
   - with assets named `ffmpeg` and `ffprobe`, and the source directions in the
     description;
   - **without deleting the superseded one.** Older tags pin it. Add it to the
     previous-pins table in `Vendor/README.md`.
6. **Update `Vendor/ffmpeg-manifest.env`**: version, deps tag, both SHA-256s,
   and the `FFMPEG_SOURCE_*` and `LAME_*` fields. Then `./scripts/fetch-ffmpeg.sh`,
   test, and release each app.

## 4. Update npm dependencies (Dependabot)

- **doublender-dashboard.** Every dependency is a devDependency (wrangler,
  vitest, TypeScript), so its alerts never reach the deployed Worker. Run
  `npm ci`, then `npm audit fix`. Never pass `--force` without reading what it
  would change. Run `npx vitest run` and commit the lockfile. Redeploy
  (`npm run deploy`) only if a runtime dependency changed.
- Dependabot closes fixed alerts once the lockfile is pushed. Re-run `check.sh`
  afterwards; that also clears the session notice.

## 5. Things that are true here and surprise people

- **An updated pin reaches nobody until the app is released.** None of the
  apps update a bundled tool themselves; ClipHack's Help says so for yt-dlp.
- **ClipHack's yt-dlp runs with no JavaScript runtime**, because a
  Finder-launched app's `PATH` has no deno. yt-dlp warns about it on every
  YouTube download. That is how the app has always run, so compare old and new
  binaries in that same environment rather than from Terminal.
- **The check reads a cache at session start**, and that cache can be up to 12
  hours old. After updating something, run `check.sh` so the notice catches up.
- **Dependabot alerts are off in the app repos**, and turning them on would not
  help: GitHub reads no manifest there, and the vendored pins are custom `.env`
  files. That gap is why this check exists.
