# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

For the wider picture — the sibling app repos, the shared-file conventions, the release
scripts — see `assets/CLAUDE.md`, which is symlinked to `~/Projects/CLAUDE.md` and loads
when you work there. This file covers what matters inside `~/mrk`.

## Downstream documentation: sevmac

**`sevmorris/sevmac` documents this repository, and it does not update itself.** It is a
separate public repo publishing two hand-written pages to
[sevmorris.github.io/sevmac](https://sevmorris.github.io/sevmac/):

- **SMAC-1** (`docs/index.html`) — the narrative guide: new-machine walkthrough, Brewfile
  and preferences workflows, the migration checklist, troubleshooting. Also covers
  Barkeep and Magic Backup Machine, which this repo does not own.
- **SMAC-2** (`docs/daily.html`) — the day-to-day command card.

Hand-written HTML, `.nojekyll`, no build step. Pushing publishes in under a minute.

### When a change here needs a sevmac change

Check sevmac in the same session as any of these:

| Change in mrk | What to update in sevmac |
|---|---|
| A command added to or removed from `bin/` or `scripts/` | Table 2.7-2 in SMAC-1 |
| A Make target added or removed | Table 2.7-1 in SMAC-1 |
| A change to the install phases, or their order | SMAC-1 §2.2 New Machine Setup |
| Anything affecting what moves between machines | SMAC-1 §2.6 Migration Checklist |
| A change to a daily-driver command (`sync`, `snapshot-prefs`, `pushall`, `update-full`, `status`, `mrk-menu`) | SMAC-2 |
| A LaunchAgent schedule change | SMAC-2 Table B-1 |
| A change to what `mrk-status` checks | SMAC-2 §E, and SMAC-1 §2.8 |

**Do not re-document flags in sevmac.** Flags, exit codes and per-command behaviour live
in BIN-1 (`docs/bin/mrk-usage.html`), which ships from this repo and is updated in the
same commit as the code. SMAC-1 links into BIN-1 by anchor; every command in `bin/` and
`scripts/` has one. Keeping a second copy of a flag list is what produced the drift this
split was made to stop.

### Why this note exists

`snapshot-keys` and `restore-keys` landed here on 2026-08-29. sevmac's migration
checklist — the page whose whole job is to stop you wiping a Mac before you have saved
what cannot be recovered — did not mention them for two days. Following it would have
lost the Developer ID signing key, which Apple cannot reissue. The gap was found in the
2026-08-31 audit and closed; see `audit/13-audit-2026-08-31.md`.

## House style for documentation

`docs/manual.md`, `docs/bin/mrk-usage.html` and `docs/defaults/script.js` are written in
Simplified Technical English: short declarative sentences, active voice, present tense,
no perfect or progressive constructions, one idea per sentence, nothing over 25 words.
`docs/STE-CONVERSION.md` records the term choices and the deviations. sevmac follows the
same style. Match it rather than the surrounding prose of whatever you are editing.

## Verification

- `make check` runs the full local gate: `shellcheck -x` over every bash script,
  `check-picker-desc`, and `go test` in all four modules. `make ci` adds the TUI builds.
- Do not trust a green gate as proof a change is correct. The 2026-08-31 audit found 14
  defects with every tool passing, three of them HIGH. In particular:
  - `shellcheck` cannot see that a pipeline's exit status is semantically wrong.
    `if ! cmd | grep …` under `set -o pipefail` takes its status from `cmd`, not the
    match — check this shape by hand.
  - `bash -n` and `shellcheck` both pass on `mapfile` and `${x,,}`, which fail at
    *runtime* under the bash 3.2 macOS ships. Any script using bash-4 syntax needs the
    `BASH_VERSINFO[0] < 4` re-exec guard that ten scripts already carry. `scripts/lib.sh`
    is deliberately exempt and stays bash-3.2 clean, because nine of its callers have no
    guard.
- Reproduce a suspected defect before fixing it, and keep the reproduction in the commit
  message. That is the repository's convention and it is why the audit trail is useful.
