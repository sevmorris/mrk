---
name: repo-standards
description: Keep every repository on the sevmorris account to the same standard. That covers the default-branch ruleset, deleting a branch when its pull request merges, secret push protection, Dependabot alerts, Pages that serve hand-written HTML (.nojekyll, HTTPS, homepage, pruned deployments), a licence and README, tests that actually run, current CI actions, and no committed executables. release-standards covers the release machinery inside the apps; this covers everything around it, for all repos, including mrk, sevmac, the guides and the private ones. Use this when asked to audit, tidy, standardize or "bring up to standard" the repos, when creating a new repository, when making one public or private, when adding tests, CI or a Pages site to a repo, and when a repo's GitHub settings or Pages look wrong.
---

# Repo standards (all repositories)

These are separate repositories with no shared tooling, so a setting fixed in one
stays fixed only there. The failure mode this skill exists to prevent is the
same one release-standards names, one level up. On 2026-09-18 an audit found:
- KeyVault, the one repo about secrets, was among three public repos without
  secret push protection.
- Eight of eleven Pages sites were served through Jekyll, which none of them use.
- Five repos had tests that nothing ever ran.
- Two CI workflows were on an action runtime GitHub had deprecated.

Each standard below exists to prevent a failure, not for tidiness. The audit
reads the state GitHub has published, so it covers repositories with no clone
on this Mac too.

## 1. Survey first

Read-only, about fifteen seconds for the whole account:

```bash
bash ~/Projects/.claude/skills/repo-standards/scripts/audit.sh          # every non-archived repo
bash ~/Projects/.claude/skills/repo-standards/scripts/audit.sh KeyVault # one or more by name
bash ~/Projects/.claude/skills/repo-standards/scripts/audit.sh -v       # plus why each n/a is n/a
```

It lists the repositories with `gh`, skipping archived repos and forks. It
matches local clones by their `origin` URL, not by folder name. It looks for
them in `~/Projects`, `~/mrk` and `~/.mrk` (mrk-prefs is `~/.mrk/preferences`),
and reads the bare `~/Projects/DoublEnder-cloud.git` through its working tree,
as `decloud` does. It prints:
- a standard-by-repo matrix
- the gaps as a list, each with its fix
- any clone with uncommitted or unpushed work

`yes` means met, `--` missing, and `n/a` means the standard has nothing to
protect there: a repo with no Pages site cannot need `.nojekyll`.

## 2. The standards, and what each one is for

| Standard | Prevents | Applies to | Fix |
|---|---|---|---|
| `branch-rules` | A force push or deletion wiping the default branch. Several Claude sessions push with the owner's credentials. | public repos | the ruleset in §3 |
| `auto-delete` | Merged branches piling up on GitHub. Every session's pull request leaves one, and on 2026-10-18 fourteen repos kept them: Barkeep had three after its PRs merged. With it on, GitHub deletes the branch when the PR merges, and `tidy-projects` then sees the local copy as gone upstream. | all repos | `gh repo edit sevmorris/R --delete-branch-on-merge` |
| `push-protect` | A pushed credential going public: GitHub refuses the push instead. | public repos | §3 |
| `vuln-alerts` | Shipping a dependency with a published vulnerability, unnoticed. Alerts only; no pull requests. | repos with a manifest GitHub reads (`go.mod`, `package-lock.json`, `*.csproj`, `Package.resolved`…) | `gh api -X PUT repos/sevmorris/R/vulnerability-alerts` |
| `no-binaries` | A committed executable no one can audit or reproduce. Vendored binaries are fetched from a pinned release and checked by SHA-256 (`Vendor/ffmpeg-manifest.env`). | repos cloned here | remove it, fetch it at build time |
| `nojekyll` | Jekyll processing a hand-written site: files and folders starting with `_` vanish, and `{{ }}` is read as Liquid. No site here uses Jekyll. | Pages sites | `touch docs/.nojekyll`, commit, push |
| `pages-https` | The site served over plain HTTP. | Pages sites | `gh api -X PUT repos/sevmorris/R/pages -F https_enforced=true` |
| `homepage` | A manual no one can find from the repository page. | Pages sites | `gh repo edit sevmorris/R --homepage <Pages URL>` |
| `deploys` | Pages deployments piling up forever. Every push adds one. Flagged above 20, pruned to 10. | Pages sites | `prune-deployments --repo sevmorris/R --keep 10 --dry-run`, then without `--dry-run` |
| `licence` | Public code nobody may legally reuse: no licence means all rights reserved. | public repos | the owner's choice; see §3 |
| `readme` | A repository that does not say what it is. | all, except exemptions | write one |
| `tests-in-ci` | Tests that exist and never run, so they rot. `release.sh` running them counts. | repos with tests | port WaxOnWaxOff's `build-and-test` job |
| `ci-matrix` | CI passing on images users have left, never compiling what ships, or never running a slice that ships. On 2026-10-04 four repos tested on macos-15 alone, none built with Xcode 27 (which every release uses), two universal apps had never run their Intel slice, and two jobs sat on macos-14, which GitHub fails in brownouts through October 2026 and retires on 2026-11-02. | repos whose CI runs Xcode or Swift tests | a leg per gap the note names: WaxOnWaxOff's `ci.yml` for the matrix, DoublEnder's for the Intel leg |
| `ci-current` | CI breaking when GitHub removes an action's runtime. The Node 20 warning was in every mrk run. | repos with workflows | bump each `uses:` to its current major, after reading its release notes |

## 3. Applying fixes

**Every fix changes a repository's settings or adds a commit to it.** List what
the audit found, say which you would fix, and apply them together once the
owner agrees. Do not fix as you go.

Every commit goes on a branch and into a pull request, in every repository,
and the owner merges it: `~/Projects/CLAUDE.md`, "Sessions work on a branch".
Push to `main` directly only when the owner says so in so many words. In mrk,
GitHub also holds the merge until CI is green.

Re-run the audit afterwards. Every line you fixed should now read `yes`.

The settings fixes are one call each:

```bash
R=KeyVault   # the repository

# branch-rules: no force push, no deletion, on whatever the default branch is
gh api -X POST repos/sevmorris/$R/rulesets --input - <<'JSON'
{"name":"main: no force push, no deletion","target":"branch","enforcement":"active",
 "conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},
 "rules":[{"type":"non_fast_forward"},{"type":"deletion"}],"bypass_actors":[]}
JSON

# push-protect
gh api -X PATCH repos/sevmorris/$R --input - <<'JSON'
{"security_and_analysis":{"secret_scanning":{"status":"enabled"},
 "secret_scanning_push_protection":{"status":"enabled"}}}
JSON
```

**Licences follow the family.** Most apps are GPL-3.0: WaxOnWaxOff, ClipHack
(and ClipHack-releases), FilmStrip, Barkeep and PasswordGen (`ppg`).
DoublEnder, DoublEnder-Windows, KeyVault and Dipstick are MIT. The
tools, guides and sites are MIT: mrk, sevmac, homebrew-tap, dead-city-sf,
wp-sim-93 and the Raspberry Pi guide. A new app has no one family to follow, so
ask: Dipstick went MIT to match mrk, which it is a front end for.
It is always the owner's decision, and a repository published without a licence
may be that way on purpose.

**Tests in CI.** WaxOnWaxOff's `.github/workflows/ci.yml` is the reference.
Its `build-and-test` job:
1. picks an Xcode
2. fetches the vendored binaries with the repo's own script
3. runs `xcodebuild … test` with a timeout

ClipHack's copy records why the timeout matters: a wedged GUI test host on the
runner. For SwiftPM it is `swift test`, and for Node `npm ci && npx vitest run`.
Public repos run on macOS runners for free. A private repo pays in Actions
minutes, ten per macOS minute, which is why a private repo whose `release.sh`
runs the tests is left alone.

## 4. Exemptions

Some standards do not fit a repository by design. Each one sits in `EXEMPT` at
the top of the checks in `scripts/audit.sh`, with its reason, and the audit
shows it as `n/a` with that reason:
- **DoublEnder-cloud** has no README and no CI of its own. It is an overlay
  sharing DoublEnder's working tree, so a README would collide with
  DoublEnder's, and its code is only built and tested inside that tree.
- **mrk-prefs** has no README. It is a data store that `snapshot-prefs` writes.
- **DoublEnder-Windows** is exempt from `ci-matrix`. It ships for Windows and
  Linux only and builds nothing for the Mac, so its CI tests where it ships:
  Ubuntu 24.04 and Windows Server 2025.

Add an exemption rather than leave a gap standing, and write the reason. A gap
the owner has decided to keep is a decision, and the reason stops the next pass
from reopening it.

## 5. Things that are true here and surprise people

- **A private repository on this plan cannot have rulesets or push
  protection.** GitHub answers "Upgrade to GitHub Pro". `n/a` there is the
  plan, not a gap. Each private repo has a full-history clone here
  (`~/.mrk/preferences`, and three in `~/Projects`, one of them the bare
  `DoublEnder-cloud.git`).
- **Folder names are not repository names.** PasswordGen is `ppg`, and
  FloppyLetters/FloppyLetter2601 is `wp-sim-93`. Magic Backup Machine and
  the Pi guide use hyphenated lowercase names, and FloppyLetter2601 sits one
  folder down.
  The audit matches by `origin`.
- **Two default branches are `master`:** the Pi guide and
  doublender-dashboard. The ruleset targets `~DEFAULT_BRANCH`, so it follows
  whichever it is.
- **The ruleset stops the owner too.** To rewrite a branch on purpose (there is
  `git-filter-repo` in the Brewfile), turn it off first and back on after:
  `gh api -X PUT repos/sevmorris/R/rulesets/<id> -f enforcement=disabled`.
  `gh api repos/sevmorris/R/rulesets` lists the ids.
- **`prune-deployments` keeps ten deployments.** That is its default, and
  what `maintain` and `mrk-push` keep for mrk; until 2026-09-23 the default was
  one, which is why older notes pass `--keep 10`. The audit flags only more than twenty. Every push to a Pages
  site adds a deployment, and a threshold at ten made wp-sim-93 read as a gap
  after the push that added its licence. The gap between the two numbers keeps
  a routine push from looking like a pile-up. The tool always keeps the
  deployment serving the site, and with `--repo` it needs no clone. `mrk-push`
  already prunes mrk's; the other repos grow until someone runs it.
- **ci-matrix's runner lists are dated.** `CI_MACOS_LEGS`, `CI_TOOLCHAIN_LEG`,
  `CI_RETIRED` and `CI_INTEL_LEG` at the top of `scripts/audit.sh` name GitHub's
  images as of 2026-10-04. Each autumn a new macOS image arrives and the oldest
  is deprecated; update the lists and every workflow together, then re-run the
  audit. `xcode-27` is a public preview, so a red leg there can be GitHub's
  rather than the code's: re-run it before debugging.
- **In zsh, `path` is `$PATH`.** A loop that assigns `path=…` empties the
  command search path for the rest of the line. Name it anything else.
- **The user's gitconfig sets `color.grep = always`**, so anything parsing git
  output needs `--no-color` (or `--porcelain`).

## 6. A new repository

Run `audit.sh <name>` as soon as it exists on GitHub, and apply what applies:
- the ruleset and push protection, if it is public
- delete-branch-on-merge, whatever its visibility
- Dependabot alerts, if it has a dependency manifest GitHub reads
- a README, and a licence (§3)
- CI that runs its tests on the `ci-matrix` runners, if it has tests
- `.nojekyll`, HTTPS and the homepage, if it gets a Pages site

Then add it to the owner's `pushall` sweep by cloning it under `~/Projects`, so
`snapshot-prefs` records it in the repository manifest and `restore-repos`
brings it back on the next Mac.
