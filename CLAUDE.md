# CLAUDE.md

Guidance for Claude Code (claude.ai/code) when working in this repository.

This file exists for one thing: **three documents describe this repository, and none of
them update themselves.** Two live here — `docs/manual.md` and BIN-1 — and one lives in
`sevmorris/sevmac`. For the wider picture — the sibling app repos, the shared-file
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

## In-repo documentation: manual.md

`docs/manual.md` is this repository's own manual, and it is load-bearing in three ways
that make it easy to mistake for a stray duplicate and delete:

- It is the README's first link.
- `docs/index.html` — the Pages site at [sevmorris.github.io/mrk](https://sevmorris.github.io/mrk/)
  — is a redirect to it.
- **`scripts/sync-login-items` writes to it**, and exits 1 if it cannot find the sentence it
  templates. Deleting the file breaks a daily-driver command.

It covers the same ground as SMAC-1 — overview, the three phases, the migration checklist,
the new-machine walkthrough, troubleshooting — so a change that needs SMAC-1 almost always
needs manual.md too. That overlap is the reason this section exists: on 2026-09-10 three
sentences in manual.md were left stale in a single day, and two of them had been corrected
in BIN-1 or SMAC-1 the same afternoon.

| Change in mrk | What to update in manual.md |
|---|---|
| Anything in the table above that touches SMAC-1 | the matching section here |
| A change to what a phase does | §How It Works — The Three Phases |
| Anything affecting what moves between machines | §How to prepare for a new machine |
| A destructive command gaining or losing a safeguard | its section, and the Caution beside it |

**Do not re-document flags in sevmac.** Flags, exit codes and per-command behaviour live
in BIN-1 (`docs/bin/mrk-usage.html`), which ships from this repo and is updated in the
same commit as the code. SMAC-1 links into BIN-1 by anchor; every command in `bin/` and
`scripts/` has one. Keeping a second copy of a flag list is what produced the drift this
split was made to stop.

**The check runs both ways.** Where the two pages describe the same behaviour, correcting
one means reading the other in the same session. On 2026-09-10 SMAC-1's description of the
mrk-status dashboard was sharpened — eight checks, with Backups appearing fifth only when a
backup exists — and BIN-1, which documents the same panel from inside this repo, was left
saying "nine checks" with Backups as a permanent member. The downstream page was right and
the upstream one was wrong, which is the opposite of the direction this file was written to
guard, and is exactly why the check cannot be one-directional.

### Why this note exists

`snapshot-keys` and `restore-keys` landed here on 2026-08-29. sevmac's migration
checklist — the page whose whole job is to stop you wiping a Mac before you have saved
what cannot be recovered — did not mention them for two days. Following it would have
lost the Developer ID signing key, which Apple cannot reissue. The gap was found in the
2026-08-31 audit and closed; see `audit/13-audit-2026-08-31.md`.
