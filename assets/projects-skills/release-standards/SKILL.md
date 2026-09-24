---
name: release-standards
description: Keep the release machinery in ~/Projects consistent across the app repos, and cut releases the standard way. Each app has its own copy of release.sh, so a guard added in one repo — a preflight check, an atomic push, a curated-notes gate, a cleanup trap — reaches the others only by hand. Use this whenever releasing any of these apps (./release.sh), after changing one repo's release.sh, when a release fails part-way or leaves a stranded version bump, when asked to bring a project "up to standard" or check the release scripts, and when adding a new app that will publish DMGs. Also use it when a published release looks wrong — missing installer window, notes that are a bare commit list, a tag with no release behind it.
---

# Release standards (~/Projects)

These are separate repos, not a monorepo, and each carries its own
`release.sh`. Every guard in them was added after something went wrong once:
the scripts are the written-down form of that. The failure mode this skill
exists to prevent is a lesson staying in the repo where it was learned —
WaxOnWaxOff gaining a check in July that ClipHack still lacked in September,
and hitting the same wall.

`WaxOnWaxOff/release.sh` is the reference. When porting, take its comment too:
each one names the failure the guard prevents, and that is what stops the next
reader deleting it as noise.

## 1. Survey first

Read-only, a few seconds:

```bash
bash ~/Projects/.claude/skills/release-standards/scripts/audit.sh
bash ~/Projects/.claude/skills/release-standards/scripts/audit.sh -v   # plus per-repo tag and notes state
```

It finds every `release.sh` under `~/Projects` by searching, so a new app
appears without editing anything. It prints a guard-by-repo matrix, the
missing ones as a list, and the repo state a release would trip over.

## 2. The guards, and what each one is for

| Guard | Prevents | Applies to |
|---|---|---|
| `notes-gate` | Publishing a bare commit list where a written changelog entry exists. ClipHack 1.25.5 shipped that way. | every app |
| `notary` | Discovering a missing keychain profile after a clean build. A profile cannot be exported, so every new Mac hits this. | every app |
| `py3-subproc` | dmgbuild importing fine and then segfaulting on its first subprocess, shipping an unstyled DMG. | dmgbuild only |
| `remote-tags` | A clone that never saw a release passing a local-only tag check, then being refused after notarizing. | every app |
| `ancestry` | A remote branch ahead of HEAD failing the push *after* the build. | every app |
| `atomic-push` | A refused tag leaving the release commit on main with nothing tagging it. | every app |
| `dmg-verify` | Shipping a disk image with no installer window, undetected. | dmgbuild only |
| `dmg-signed` | A disk image that spctl reports as `no usable signature` despite a valid stapled ticket, because only the app inside it was ever signed. | every app |
| `app-stapled` | An app that loses its notarization the moment it is dragged out of the DMG, because only the image was stapled. Gatekeeper then has to ask Apple on first launch, which fails with no network. Also verifies the ticket on the shipped copy, not the build product. | every app |
| `generic-dest` | xcodebuild silently building one architecture. | every app |
| `v-tag-filter` | A dependency or checkpoint tag being read as the previous release and truncating the notes. | every app |
| `exit-trap` / `signal-trap` | A failed *or interrupted* release stranding a version bump in the working tree. zsh does not run an EXIT trap on a signal. | every app |
| `shared-files` | Byte-identical files drifting between repos. | repos with siblings |

`n/a` in the matrix means the guard has nothing to protect: a script building a
plain image with `hdiutil create` has no dmgbuild to crash and no installer
window to check. WireHack, retired and archived on 2026-09-23 with ClipHack
superseding it, has no clone here any more and so does not appear.

## 3. Cutting a release

0. **Check the vendored pins first**:
   `bash ~/.claude/skills/dependency-updates/scripts/check.sh`. A release is the
   only way a new yt-dlp or FFmpeg reaches anyone, and ClipHack 1.25.7 went out
   with a yt-dlp two releases old because nobody looked. If a pin is behind,
   update it first, following the `dependency-updates` skill.
1. **Write the changelog entry first**, then `release-notes/v<version>.md` with
   the same prose. The gate refuses to release without it. Reaching for
   `--generated-notes` should feel like a decision, because it is one.
2. Commit and push everything, and let CI go green. The scripts that check CI
   check `HEAD`.
3. Run it under `caffeinate`, because notarization is long and a sleeping Mac
   fails it:

   ```bash
   caffeinate -dis ./release.sh <version>
   ```

4. **Verify what was published, not what was built.** Download the DMG from the
   release page, mount it, and check the installer window (`.DS_Store` plus
   `.background.*`), the app's version, `spctl -a -vvv` on the app, the stapled
   ticket, and that any bundled binaries run. The 2026-09-16 releases passed
   every build-time check and were still broken.

## 4. After changing one repo's release.sh

Port it the same day. Re-run the audit; anything that turns from `yes` to `--`
in another repo is the work. If the change is to a file carrying the
"Shared verbatim across the sibling app repos" marker, every copy must move
together or the next release fails preflight in every repo.

Then update `~/Projects/CLAUDE.md` if the change is a new convention rather
than a new guard — the release-preflight bullet there is what a session reads
before it reaches this skill.

## 5. Things that are true here and surprise people

- **The scripts are zsh**, so `shellcheck` cannot analyse them. Use `zsh -n`.
- **Glob qualifiers** (`"$MOUNT"/.DS_Store(N)`) work in the scripts because
  non-interactive zsh has `bare_glob_qual` on by default. An interactive shell
  here has it off, so the same line pasted into a terminal fails with
  "no matches found". That is the shell, not the script.
- **The user's gitconfig sets `color.grep = always`**, so anything parsing git
  output needs `--no-color`. `-c color.ui=false` does not override it. Note
  that `git status --no-color` is not valid — `--porcelain` is already
  uncolored.
- **release.sh prunes release pages, never git tags.** A page is a convenience;
  a tag is the record.
- **Homebrew is not a distribution channel for these apps any more**, with one
  exception. The `doublender` and `waxonwaxoff` casks were deprecated on
  2026-09-17 because each app checks GitHub for its own updates and the cask's
  records went stale the moment an in-app update was installed. `fl2601`
  (Cypher) keeps its cask: it is sandboxed with no network entitlement and
  cannot check for itself, so `distribute.sh --bump-cask` still bumps it. Do
  not add a cask-bump step back to any other release script.
