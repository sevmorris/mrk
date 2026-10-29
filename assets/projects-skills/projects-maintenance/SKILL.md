---
name: projects-maintenance
description: Check and clean up every git clone under ~/Projects and ~/mrk in one pass — merged branches the clones kept after GitHub deleted them, finished Claude worktrees, stale remote-tracking refs, Pages deployments past ten, build output and DerivedData, clones behind origin, and repos with no backup (no remote, or a remote off GitHub) — with the repo-standards, release-standards and dependency-updates audits in the same report. Use this whenever asked to check, tidy, clean up, maintain or sweep all the repos or ~/Projects, to free disk space taken by builds, to clear out old branches or worktrees, after a run of merged pull requests, or before a round of releases or a move to a new Mac. Not for the code in one repository, and not for GitHub settings alone, which repo-standards covers.
---

# Projects maintenance (all clones)

Every session here works on a branch that becomes a pull request, and GitHub deletes the branch
when the PR merges, but the clone keeps its copy. Desktop sessions leave worktrees behind, and
every build leaves output. Nothing else sweeps any of it. On 2026-10-13 the first pass found:
- 14 merged branches in 9 repos, and a finished worktree in DoublEnder
- 9 stale remote-tracking refs in 4 repos
- 1.1 GB of build output and DerivedData

`tidy-projects` (mrk's `bin/`, on the PATH) does the work and holds every safety rule. This skill
adds the three standards audits and the owner's say-so.

## 1. Survey

All four are read-only, so run them together, in the background:

```bash
tidy-projects                                              # every clone: clutter, and what needs the owner
bash ~/.claude/skills/repo-standards/scripts/audit.sh      # GitHub settings, every repo (~15 s)
bash ~/.claude/skills/release-standards/scripts/audit.sh   # the release.sh guards (~1 s)
bash ~/.claude/skills/dependency-updates/scripts/check.sh  # vendored pins and Dependabot (~5 s)
```

`tidy-projects` fetches each clone first, which changes only remote-tracking refs, and takes about
15 seconds; `--no-fetch` skips the fetch. Its report has five parts: a table of every clone,
**Needs you**, **Cleanups available**, **Kept, and why**, and **What to run**. Each item under
Needs you and Kept has a `→` command that shows or settles it, and each cleanup has its
`--apply` command, so the report can be read without this skill. Piped, it has no colors.

## 2. Report, in one message

In this order, because the top is what only the owner can settle:

1. **Needs you.** No remote, a remote off GitHub, a clone on a branch other than its default,
   uncommitted changes, unpushed commits, stashes, branches never pushed that hold commits of
   their own (one whose tip is already in the default branch is a cleanup). Each is a decision, and
   nothing here acts on it. Say what the obvious next step would be: for a repo with no remote,
   a private GitHub repo and a push, which only the owner can choose.
2. **Cleanups available.** Counts per category and per repo, and how much disk the build cleanup
   frees. Name individual lines only where the owner needs them to decide.
3. **Kept, and why.** So nothing looks silently skipped. A branch with commits its PR did not merge
   is work, not clutter: say where it is, and ask.
4. **Standards gaps**, from the three audits, each with the skill that fixes it. Their fixes need
   their own go-ahead, as those skills say.

## 3. Apply what the owner agrees to

Ask once which categories to apply, with the counts beside each. Then:

```bash
tidy-projects --apply worktrees,branches,refs,ff,build,deploys   # only the ones agreed
```

It surveys again and checks every rule at that moment, so a branch that gained a commit since the
report stays. Re-run `tidy-projects` afterwards: what was applied should be gone. Report any `✗`
line it printed, with its reason.

| Category | What goes | The rule | Undo |
|---|---|---|---|
| `ff` | nothing: the default branch moves forward | checked out, clean, nothing unpushed | `git reset --hard ORIG_HEAD` |
| `refs` | stale `origin/*` refs | origin no longer has the branch | nothing to undo: a fetch would not bring them back |
| `worktrees` | the worktree directory | no uncommitted or untracked file, no process in it, HEAD merged | its commits stay in the repo |
| `branches` | the local branch | upstream gone, tip in the default branch or at or behind a merged PR's head | `git branch <name> <sha>`, from the reflog |
| `deploys` | Pages deployments past the newest 10 | `prune-deployments` keeps the live one | **none: permanent** |
| `build` | `build/`, `.build/` to the Trash; DerivedData cleared | gitignored, nothing tracked, no `xcodebuild` running | the Trash, or the next build |

Never delete a stash, run `pushall` or `mrk-push`, commit, push, change a repository's settings,
touch an archived repository, or remove a worktree with `--force`. Those belong to the owner or to
the standards skills, with their own go-ahead.

## 4. Things that are true here and surprise people

- **Squash merges are not ancestors of `main`**, so a branch counts as merged when its tip is in
  the default branch, or is a merged PR's head or behind it. Behind is common: on 2026-10-13 four of
  five `claude/macos-15` branches sat behind their PR, whose last commits came from a worktree.
  `tidy-projects` fetches `pull/N/head` to see that head.
- **A branch can go past its merged PR and still be merged.** DoublEnder's
  `claude/zealous-darwin-46fcb0` carried five commits after PR #4, and all five reached `main`
  without a PR of their own. The first version of the rule checked only the PR, and kept it as
  unmerged work. A branch kept now has commits in neither its PR nor the default branch: those may
  exist nowhere else, so ask the owner, and do not delete it by hand.
- **`fetch.prune` is off here**, so a plain fetch keeps the refs of deleted branches and git still
  calls those branches in step. `tidy-projects` asks origin itself (`git remote prune --dry-run`).
- **Desktop worktrees** sit in `<repo>/.claude/worktrees/<name>`, on a branch `claude/<name>`. One
  that a running session works in stays: the check is every process's working directory.
- **DerivedData is shared by every Xcode project**, so clearing it slows the next build of each
  app. A LaunchAgent (`com.user.clear_derived_data`) also clears it on a schedule.
- **`build/` holds the last release build** (`build/Build/Products/Release/<App>.app`). Once that
  release is published and checked, it is only disk space.
- **A remote's URL can carry an access token**, so `tidy-projects` never prints one, and neither
  should a report.
- **WaxOnWaxOff was checked out on `dev`** on 2026-10-13. A release must come from `main`
  (release-standards' `main-only` guard), so mention it before a release round.
- **mrk's own `maintain`** covers mrk's deployments, validation and tool builds. `tidy-projects`
  covers mrk too, for its branches and worktrees.
