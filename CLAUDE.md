# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

This file exists for one thing: **`sevmorris/sevmac` documents this repository, and it
does not update itself.** For the wider picture — the sibling app repos, the shared-file
conventions, the release scripts — see `assets/CLAUDE.md`, which is symlinked to
`~/Projects/CLAUDE.md` and loads when you work there.

## Downstream documentation: sevmac

sevmac is a separate public repo publishing two hand-written pages to
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
