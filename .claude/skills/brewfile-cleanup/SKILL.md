---
name: brewfile-cleanup
description: Clean up the Brewfile in the mrk repo (~/mrk) and everything that depends on it. Reconcile it with what Homebrew actually has installed, keep the mrk-picker descriptions in step (check-picker-desc), drop redundant dependency pins, retire packages nothing uses (with the owner's say-so), and fix the scripts and docs that still name removed packages or apps that are gone from this Mac. Use this whenever the user asks to clean up, tidy, prune, audit, reconcile or sort out the Brewfile or their Homebrew formulae and casks. Also use it when check-picker-desc or make check fails on picker descriptions, after `sync` has added or removed packages, or when they want to drop brew packages they don't use, even if they never say "cleanup".
---

# Brewfile cleanup (mrk)

The Brewfile is one list with many readers. mrk-picker describes every entry,
`sync` and `mrk-status` parse it, and Phase 3 configures, snapshots and
cache-clears the apps it installs. The docs count those apps too. A cleanup
that edits only the Brewfile leaves the readers behind, and the drift surfaces
later as a red `make check`, a status line that is wrong forever, or a setting
that points at an app that is gone. So a cleanup here has two halves: decide
what the list should hold, then follow every change to what depends on it.

## 1. Before touching anything

- Work in `~/mrk`, on a branch rather than `main`.
- Read `git status`. Uncommitted changes may belong to the owner or to another
  Claude session sharing the checkout (check `ListAgents` if it is available).
  A Brewfile diff you did not make is usually the owner's own `sync` output. It
  is where the cleanup starts, not noise. Leave any other foreign change alone,
  and stage only your own paths later.
- Run the survey. It is read-only and takes about ten seconds:

  ```bash
  bash .claude/skills/brewfile-cleanup/scripts/report.sh                  # the findings
  bash .claude/skills/brewfile-cleanup/scripts/report.sh --descriptions   # plus picker vs Homebrew descriptions
  ```

  It takes the repo as an argument (`report.sh /path/to/checkout`), and
  `PROJECTS` and `SEVMAC` override where it looks for the other repos.

## 2. Decide what each finding means

| Report section | Usual action | Owner's call? |
|---|---|---|
| check-picker-desc: missing | Write a description in `tools/picker/main.go` | no |
| check-picker-desc: orphaned | Delete the description | no |
| `--descriptions` | Fix a description that describes a different product | no |
| Installed, not in the Brewfile | Add it, ignore it (`~/.mrk/sync-ignore`), or uninstall it | yes |
| In the Brewfile, not installed | Fix a name Homebrew lists differently; otherwise ask | if not a name |
| Dependency pins | Remove library and build-dependency pins; keep tools | usually no |
| No code names it | A hint only; look for evidence of disuse | yes |
| Missing /Applications paths | Remove the app from the per-app lists | yes |
| Missing cache folders | Remove the block if the app is not installed | yes |
| Bundle IDs with no app | Point the setting at the installed app | no |
| Doc counts | Correct every count that disagrees | no |

The reasoning behind the rows:

- **Descriptions.** `tools/picker/main.go` holds the only description table.
  `scripts/brew`'s gum fallback reads it too, and on a new Mac that fallback is
  the picker, because Phase 2 runs before `make build-tools`. Never add a
  second copy. Write a short noun phrase, starting from Homebrew's `desc`. When
  mrk is the reason a package is there, say so: `dockutil` is "used by make
  dock". Run `gofmt -w tools/picker/main.go` afterwards. With `--descriptions`,
  fix only real mismatches, not wording: on 2026-09-17 `helium-browser`
  described a floating-window app, and the cask is imput's Chromium browser.
- **Names.** `brew list` prints canonical names, and `brew install` accepts
  aliases. `whisper-cpp` installed fine but was reported missing on every run
  until 2026-09-15, because the canonical name is `whisper.cpp`. `brew info
  <name>` gives the canonical name.
- **Dependency pins.** A formula other installed formulae depend on
  (`libpng`, `autoconf`, or `python@3.14` while the Brewfile says pyenv is
  canonical) is installed anyway through its dependents. Removing its line
  changes nothing on a new Mac. Keep what the owner runs directly: bash, gnupg,
  ffmpeg, openjdk, deno. Read the "last Brewfile change" line. `3fcad99` removed
  such pins in May 2026, and a `sync` on the old Mac re-added them in August. An
  earlier removal is precedent, not a new decision.
- **"No code names it."** Most of this list is tools run by hand (htop, ncdu,
  ripgrep), so leave them alone. Look for positive evidence of disuse:
  - the project that needed it moved on (mkdocs, after the Raspberry Pi guide
    left MkDocs);
  - its service never ran and its config is the default (`brew services list`,
    `ls $(brew --prefix)/etc/<name>`);
  - it was a dependency that `sync` adopted.

  Something the owner picked recently stays: look for a commit such as
  "sync: add …". Put real candidates to the owner with that evidence.
- **Retiring a package** means uninstalling it. `sync` offers any installed
  leaf again, so removing the Brewfile line alone does not last. Run `brew
  uninstall` only after the owner says yes in this conversation, and only after
  `brew uses --installed <name>` shows no dependents. Homebrew then autoremoves
  the dependencies nothing else needs. Report which it removed.
- **Apps that are gone.** Removing an app from `scripts/snapshot-prefs`,
  `scripts/post-install` and `bin/snapshot` leaves its saved plist in
  mrk-prefs, which is what the owner usually wants, so say so when asking.
- **Cache folders.** A missing folder means the app is not installed, or has
  never been opened. Slack on a fresh Mac is the second case, so leave those
  alone. When you remove a block, keep any comment that records a hard-won
  lesson, such as Spotify's offline-storage warning.
- **Bundle IDs.** Audio Hijack's external editor was `com.izotope.RXPro`, and
  the RX installed on this Mac is `com.izotope.RX12`. Reading the ID from the
  installed app lasts longer than a new hard-coded one.

Ask the owner once, with all the decisions together: one multi-select
question per kind, with the evidence in each option. That beats a string of
single questions.

## 3. Follow each change to what depends on it

- `tools/picker/main.go` holds the descriptions, and `check-picker-desc` holds
  them to the Brewfile in both directions. `scripts/brew` reads them.
- `scripts/sync`, `scripts/brew`, `scripts/status`, `tools/picker` and
  `tools/mrk-status` all parse the Brewfile, each in its own way. Keep every
  line in the strict shape: `brew "name"` or
  `cask "name", greedy: true`. `check-picker-desc` refuses anything else. Keep
  entries alphabetical within their `##` section, as `sync` inserts them, and
  keep the section comments true: the Languages section says there are no
  Homebrew python@ pins.
- `scripts/snapshot-prefs`, `scripts/post-install` (`import_plist`,
  `add_login_item`) and `bin/snapshot` hold the per-app lists.
- `bin/clear-app-caches`, `scripts/trim-services` (launchd labels such as
  Samsung Magician's and Google's updater) and `scripts/dock-setup`
  (`DOCK_APPS`) each name apps.
- `assets/preferences/*.sh` and `assets/browsers/*.sh` hold settings that name
  other apps.
- `dotfiles/.zprofile` depends on the `coreutils` entry, which puts gnubin
  first on PATH.
- Docs, as `~/mrk/CLAUDE.md` requires:
  - BIN-1 (`docs/bin/mrk-usage.html`), for any command whose behaviour
    changed, in the same commit;
  - `docs/manual.md` (the Phase 2 and Phase 3 sections, the app tables, the
    counts) and `README.md` (the counts);
  - sevmac in `~/Projects/sevmac`: SMAC-1's Phase 3 text and counts, and
    Tables 2.7-1 and 2.7-2 if a command or target changed. SMAC-2 changes only
    for a daily-driver command.

  Never edit the history in `audit/`.

## 4. Verify

- `scripts/check-picker-desc` passes, with the new package count.
- `gofmt -l tools/` prints nothing, and `shellcheck -x` passes on every changed
  script.
- A second `report.sh` run finds nothing to add, nothing missing, no stale
  paths or IDs, and counts that agree.
- `make status` shows every package installed.
- `make check` passes. If the working tree holds anyone else's changes, run it
  in a scratch copy instead:
  `rsync -a ~/mrk/ <scratch>/ && cd <scratch> && git add -A && scripts/ci-check`.
  `make build-tools` is safe there: it builds, and links into `~/bin` only when
  run in `~/mrk`.
- If you edited HTML docs, check that they parse with balanced tags. BIN-1 once
  rendered two entries inside a third.
- Do not run `make brew`, `brew bundle` or `sync` as a check. The first two
  install, and `sync` prompts on the terminal.

## 5. Hand back

- Summarize what was removed, added, described, uninstalled (with the
  dependencies autoremoved) and changed in the docs, and what is left for the
  owner.
- Commit and push only when asked. Match the repo's style: a short subject that
  names the file or command ("Brewfile: …"), a body that says why, and the
  session's co-author trailer. Stage only your own paths. sevmac is a separate
  repository, and pushing it publishes the site.
- After the merge, run `make build-tools` if `tools/` changed (the picker
  binary embeds the descriptions), and `make tools` if a script was added.
