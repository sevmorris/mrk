# syncall Removal
**Branch:** `audit/static-pass` | **Date:** 2026-04-24 | **Commit:** `ba29d0c`

## Summary

`scripts/syncall` and its `make syncall` target were removed from mrk as a direct
consequence of Module 1 and Module 2 audit findings. The script auto-committed and pushed
every GitHub repository found under `$HOME` in a single command. Two independent audit
findings established that the risk profile is unacceptable for inclusion in a personal
bootstrap tool.

## Audit Findings Cited

### Module 1 — `02-side-effects.md` Hot Spot #1

`make syncall` was ranked **#1 by blast radius** across the entire project:

> Searches up to 7 directory levels deep under `$HOME` for any git repo with a GitHub
> remote. For each dirty repo, it runs `git add -A` (stages everything, including
> secrets/unintended files), creates a time-stamped commit, then pushes to GitHub origin.
> A single run can push to tens of repos the user hasn't reviewed. Auto-commit message is
> generic (`"syncall: auto-commit <timestamp>"`), making history noisy. Push cannot be
> recalled once complete.

### Module 2 — `03-shell-hygiene.md` H3

The only interactive safeguard (`[[ -t 0 ]]` TTY gate) was found to be bypassable:

> When stdin is not a TTY — cron, CI, a shell launched by a script, or any piped
> invocation — the TTY gate is skipped and every dirty repo is auto-committed and pushed
> with no user input and no diff review. `git add -A` is particularly risky: it stages
> all untracked files including environment files, credentials, or any other sensitive
> content that happened to be written into a tracked repo directory.

## Rationale

The script provided a convenience shortcut: commit and push multiple repos in one command.
The cost was a single mistaken invocation (from a non-TTY context, or while a sensitive
file was unintentionally present in a tracked directory) could silently push credentials
or unreviewed changes to multiple GitHub repositories with no recovery path for the pushes.

The benefit — saving a minute of typing across a few repos — does not justify the cost.
`git push` per repository is the correct replacement. It takes thirty seconds per repo,
keeps the history intentional, and has no blast radius.

## What Replaces It

Nothing. Per-repo `git push` is the replacement. For the common case of pushing the mrk
repo itself, `bin/mrk-push` remains available (no make target, direct invocation only).

## Files Changed

| File | Change |
|------|--------|
| `scripts/syncall` | Deleted (187 lines) |
| `Makefile` | Removed `syncall` target and `.PHONY` entry (3 lines) |
| `README.md` | Removed `make syncall` row from commands table |
| `docs/manual.md` | Removed `## Syncing All Repos` section, Maintenance table row, State Files table row |

## Audit Artifact Annotations (commit `5888b4d`+)

Audit artifacts retain the original findings as historical record. A removal note was
added at the top of each affected section:

| File | Location | Change |
|------|----------|--------|
| `docs/audit/01-callgraph.md` | `## Target: syncall` | Added removal note |
| `docs/audit/01-callgraph.md` | `scripts/lib.sh` sourcing list | Removed `scripts/syncall` |
| `docs/audit/01-callgraph.md` | Cross-reference index row | Struck through, noted removed |
| `docs/audit/02-side-effects.md` | `mkdir -p ~/.mrk` table row | Removed `scripts/syncall:183` caller |
| `docs/audit/02-side-effects.md` | `syncall.log` table row | Struck through |
| `docs/audit/02-side-effects.md` | NETWORK `git push` row | Struck through |
| `docs/audit/02-side-effects.md` | GIT REMOTES table rows (×2) | Struck through |
| `docs/audit/02-side-effects.md` | `syncall detail` block | Struck through |
| `docs/audit/02-side-effects.md` | Hot Spots §1 | Added removal note |
| `docs/audit/03-shell-hygiene.md` | Summary table HIGH row | Struck through `scripts/syncall` |
| `docs/audit/03-shell-hygiene.md` | H3 finding | Added removal note |
| `docs/audit/04-makefile-audit.md` | L1 ARGS code block | Removed `syncall` example line |
