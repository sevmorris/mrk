# Module 12 — Fresh Audit (2026-08)

**Date:** 2026-08-02
**Scope:** read-only re-verification of the module 1–11 ledger, plus a first audit of
code added after the prior audit closed.
**Baseline:** the audit tree was committed at `b3ad0d0` (2026-05-29). Everything from
the `F-01`…`F-32` fix session (2026-06-12) forward post-dates the ledger in
`audit/00-followups.md`, including `bin/maintain`, the oh-my-zsh bootstrap, the Calibre
file-tree backup, the Brewfile sync feature, PR #1 and PR #2.

**Method:** every ledger claim was re-checked against current code. Line numbers below
are fresh as of `a17ba54`. Nothing was modified during the audit itself.

> **Status update — 2026-08-02.**
> Fix session 1 (branch `fix/audit-12-critical`) closed N-1, N-2, N-3 and N-4.
> Phase B (branch `docs/ste-phase-b`) closed N-6, N-7, N-8 and N-12, and rewrote the
> documentation prose in Simplified Technical English — see `docs/STE-CONVERSION.md`.
>
> Two sections at the end of this file record the outcomes: "Fix session outcomes"
> (commits, adversarial reproductions, and two further defects that surfaced while
> fixing N-2) and "Phase B outcomes".
>
> Line numbers in the finding bodies below are as-audited and now refer to pre-fix
> code. Everything else in this document still stands.

**Headline:** the ledger is in better shape than it reads — 9 of 15 open items are
resolved. But this pass found one HIGH defect that the prior audit missed entirely,
affecting 114 call sites across the two largest install-phase scripts.

---

## Severity summary

| ID | Severity | Title |
|---|---|---|
| N-1 | ~~**HIGH**~~ **FIXED** | `\|\| ((failed++))` under `set -e` aborts on the first failure (114 sites) |
| N-2 | ~~**HIGH**~~ **FIXED** | Secret-scan patterns miss every common API-key token format |
| N-3 | ~~MEDIUM~~ **FIXED** | `sync-login-items` empty-list path still only warns |
| N-4 | ~~MEDIUM~~ **FIXED** | Secret scan reads binary plists in `config/` and `app-support/` |
| N-5 | ~~MEDIUM~~ **FIXED** | Deleted config files are never staged, so they persist in `mrk-prefs` |
| N-6 | ~~MEDIUM~~ **FIXED** | Defaults reference renders 18 keys with a broken parse |
| N-7 | ~~MEDIUM~~ **FIXED** | BIN-1 nav index stops at 2.16; five `~/bin` commands undocumented |
| N-8 | ~~MEDIUM~~ **FIXED** | `manual.md` states a false relationship between `snapshot` and `post-install` |
| N-9 | ~~MEDIUM~~ **FIXED** | oh-my-zsh and plugin clones are unpinned |
| N-10 | ~~LOW~~ **FIXED** | `maintain` build-freshness ignores the shared `tools/theme` module |
| N-11 | ~~LOW~~ **FIXED** | Calibre restore sentinel is a single file; `cp -R` can overwrite siblings |
| N-12 | ~~LOW~~ **FIXED** | 24 dead `DEFAULT_DESCRIPTIONS` entries |
| N-13 | ~~LOW~~ **FIXED** | Latent Brewfile truncation in the `sync` python3 block |
| N-14 | ~~LOW~~ **FIXED** | `sync` does not restore file mode before the atomic replace |
| N-15 | ~~LOW~~ **FIXED** | `mrk-push` prunes deployments in every environment, not just Pages |
| N-16 | ~~LOW~~ **FIXED** | `maintain --keep=0` will delete the live Pages deployment |
| N-17 | INFO | `bash-completion@2` regression; ledger item B6 reopened |
| N-18 | INFO | F08 listed as Closed, but the dead variable is still present |
| N-19 | INFO | `10-test-plan.md` was never committed; `docs/audit/` paths are stale |

---

# TRACK 1 — Re-verification of open ledger items

| Ledger item | Verdict | Current evidence |
|---|---|---|
| Screensaver rollback writes `0` | **RESOLVED** | `scripts/hardening.sh:103-107,111-115` now emits `defaults delete …` when the key was absent pre-apply |
| M4 — sudo check tests PATH, not usability | **RESOLVED** | `scripts/hardening.sh:43` — `sudo -n true 2>/dev/null` gates the credential refresh |
| FM5 — stealth mode skipped when firewall on | **RESOLVED** | `scripts/hardening.sh:132-136` computes `need_firewall` from both states; `:156-167` handles stealth independently |
| `sync` python3 Brewfile write not atomic | **RESOLVED** | `scripts/sync:558` writes to `.Brewfile.XXXXXX` in the repo, `:649` `mv`s it over; prune path does the same at `:293-304`; `cleanup` trap at `:79-84` |
| F10 — dscl error discarded in mrk-status | **RESOLVED** | `tools/mrk-status/main.go:251-255` surfaces `dscl failed: %v` |
| B7 — coreutils gnubin not on PATH | **RESOLVED** | `dotfiles/.zprofile:15-24` prepends `$(brew --prefix coreutils)/libexec/gnubin` with a duplicate guard; `Brewfile:8` comment now matches reality |
| B4 — Python management strategy | **RESOLVED** | `python@3.12` removed in `43c4d55`; `Brewfile:52` documents pyenv + pipx + `.python-version` as canonical |
| nvm management direction | **RESOLVED (documented)** | `Brewfile:53` records post-install as the deliberate home |
| check-updates 1s blocking timeout | **RESOLVED (fully)** | `scripts/check-updates:55-84` — no blocking fetch remains; every refresh is `{ git fetch …; } & disown`. This went further than the ledger's deferred plan |
| fix-exec target vs binary divergence | **RESOLVED** | `Makefile:71-72` now calls `"$(SCRIPTS)/fix-exec"`; the binary repairs `~/bin` symlinks that point into the repo at `scripts/fix-exec:27-38` |
| ~40 browser/app-pref writes have no rollback | **STILL OPEN** | `scripts/post-install:157,173,189,203,356,363,369,373` — `apply_defaults` writes with no rollback capture. Unchanged |
| ARGS word-split for value-bearing flags | **STILL OPEN — line moved** | TODO now at `Makefile:145-146` (ledger said `:124`). No recipe quotes `$(ARGS)` |
| `make doctor --fix` bare form | **STILL OPEN (accepted); docs fixed** | The Make limitation stands. The doc regression at `docs/manual.md:531` was corrected in Phase B (`292485f`), and BIN-1 §2.2 now states it. See N-8 |
| snapshot-prefs API key scan | **PARTIALLY RESOLVED — material gaps** | `scan_for_secrets` exists (`scripts/lib.sh:82-102`) and is wired in, but misses the token formats the ledger explicitly asked for. See N-2, N-4 |
| Tests 1C, 2, 3, 4 | **STILL OPEN — plan is missing** | See N-19 |

## N-2 — Secret-scan pattern coverage — **HIGH**

`scripts/lib.sh:84-89` defines four patterns. Measured against the formats Raycast and
MacWhisper actually store, and against the ledger's own closing criteria:

**The ledger asked for `sk-`, `ghp_`, `gho_`, bearer, and common key field names. Only
bearer was implemented.** There is no pattern for any prefixed token:
`sk-`, `sk-proj-`, `sk-ant-`, `ghp_`, `gho_`, `github_pat_`, `xoxb-`, `AKIA`.

Two further gaps:

1. **Pattern 2 is anchored and only matches exact key names.**
   `'<(key)>(APIKey|apiKey|accessToken|…)</key>'` (`lib.sh:86`) requires the literal
   `<key>` to be immediately followed by one of the alternatives. A real Raycast or
   MacWhisper key such as `<key>openAIAPIKey</key>` does **not** match, because `<key>`
   is followed by `o`. Any vendor-prefixed name — `openAIAPIKey`, `groqAPIKey`,
   `elevenLabsToken` — passes clean.

2. **Pattern 3 cannot fire on plists at all.**
   `lib.sh:87` requires a `:` or `=` separator. XML plists use
   `<key>x</key><string>y</string>` — no separator. So for the 14 exported plists, only
   patterns 1, 2 and 4 are live, and pattern 2 is crippled by (1). Pattern 3 is
   effectively JSON-only, which is useful for Calibre but not for the plists.
   It also omits `password` and `token` as bare field names, so a Calibre
   `"password": "…"` in JSON is not caught either.

Net effect: a Raycast plist containing `<key>openAIAPIKey</key><string>sk-proj-…</string>`
is scanned, reported clean, staged, committed and pushed. The failure is silent.

**On the warn-vs-fatal seam** (the specific question asked): the per-file `warn`
(`scripts/snapshot-prefs:75-77, 118-120, 176-178`) and the final
`require_clean_secrets` (`:219`) call the *same* `scan_for_secrets` with the *same*
patterns, so there is no coverage difference between them — the per-file pass is purely
informational and redundant. The final gate is correctly fatal: `require_clean_secrets`
(`lib.sh:106-121`) aborts under `NONINTERACTIVE=1` and aborts when stdin is not a TTY,
and otherwise requires an explicit `y`. **The seam is not warn-vs-fatal. The seam is
that both ends share one under-powered pattern set**, plus the encoding problem in N-4.
A keyed file does not get through on a warning; it gets through because nothing
recognises the key.

---

# TRACK 2 — Code new or changed since the prior audit

## `bin/maintain` — never in module scope; audited fresh

Added `4f93046` (2026-06-12), after the audit tree was committed. It does not appear in
`01-callgraph.md` or `02-side-effects.md`. Audited here for the first time.

Overall it is the most careful script in the repo: correct `((n++)) || true` idiom
(`bin/maintain:120`), dry-run gating that covers API, git and make separately
(`:90-92, 97-98, 146-147, 165-166`), network auth checked only when calls will actually
happen (`:81-86`), and `--keep` validated (`:70-73`).

### N-10 — build-freshness ignores `tools/theme` — LOW

`bin/maintain:193` runs `find "$src_dir" -name '*.go' -newer "$bin_path"` where
`src_dir` is the tool's own directory only (`:188`). All four TUIs import the shared
`tools/theme` module — `997991c` moved `bf` onto it explicitly. Editing
`tools/theme/theme.go` and rebuilding nothing leaves every binary stale while Step 4
reports "up to date" for all four.

### N-16 — `--keep=0` deletes the live deployment — LOW

`bin/maintain:70` accepts `0` as valid (the usage text at `:49` says "non-negative").
With `KEEP=0`, `to_prune=("${ids[@]:0}")` at `:110` selects every deployment including
the active one, which takes the published Pages site down until the next push. There is
an interactive confirm at `:114-116`, so this needs an explicit user mistake.

## `scripts/setup` — oh-my-zsh and plugin bootstrap (`e7aa56f`)

`scripts/setup:604-631`. Idempotency, failure handling and dry-run are all correct:
directory-existence guards at `:608, 622`, `dry` branches at `:610, 624`, and clone
failures warn and continue rather than aborting setup (`:615, 629`) — consistent with
the stated intent at `:606`. Interaction with `.zshrc` is sound: the guard added in
`b75a6ee` tolerates OMZ being absent, and `a08082a` added `~/.oh-my-zsh` to the
`nuke-mrk` teardown.

### N-9 — clones are unpinned — MEDIUM

`:612` clones `ohmyzsh/ohmyzsh` and `:626` clones two `zsh-users` plugins, all at
`--depth=1` from the default branch, with no tag, commit pin or verification. This code
is then sourced by every interactive shell. The repo pins its other network-installed
dependency — nvm at `v0.40.4` via the upstream script (per ledger B3) — so the posture
here is inconsistent with the project's own precedent. Not a live defect; a
supply-chain surface worth a deliberate decision.

Minor: `:619` honours a caller's `ZSH_CUSTOM`, but `dotfiles/.zshrc` does not set it, so
a user with `ZSH_CUSTOM` exported elsewhere gets plugins installed where `.zshrc` will
not find them.

## Calibre file-tree backup and restore (`070916d`)

Backup: `scripts/snapshot-prefs:142-187`. Restore: `scripts/post-install:525-556`.

The design is right — this is a file tree, not a defaults domain, and the code says so
in both places. `snapshot_pref_dir` guards the empty-`dest_subdir` case before
`rm -rf` (`:147, 154`), which is the dangerous one, and scans every copied file
(`:174-179`). Restore is gated on the app being installed, the backup existing, and a
sentinel (`:529-540`).

### N-4 — binary plists are scanned as binary — MEDIUM

`snapshot_plist` converts each export to xml1 *before* scanning, and the comment at
`scripts/snapshot-prefs:69-70` states exactly why: "so the secret scan reads text, not
binary plist data."

Neither of the other two capture paths does this:

- `snapshot_app_support:117` — `cp` then scan. Loopback `Devices.plist`,
  SoundSource `Presets.plist`, `CustomPresets.plist`, `Sources.plist`, `Models.plist`.
- `snapshot_pref_dir:168` — `cp -R` then scan. Calibre's `*.plist` glob (`:187`).

`grep -Ein` on a binary plist does not reliably match, and where it does it prints
"Binary file … matches" rather than a line. The stated rationale for the conversion
applies identically to these paths.

### N-5 — deletions are never staged — MEDIUM

`scripts/snapshot-prefs:140-141` claims: "The dest is cleared first so files removed
from the source (e.g. uninstalled plugins) don't linger in the backup."

`rm -rf` at `:154` clears the local working tree. But staging at `:194-210` collects
only files that currently exist (`find "$tree" -type f`) and runs `git add -- <paths>`.
A tracked file that vanished from the working tree is never staged as a deletion, so it
stays in `HEAD` and stays in the pushed repo. The comment's promise holds locally and
fails for the backup it describes. A Calibre plugin removed after storing a token
remains in `mrk-prefs` indefinitely.

### N-11 — restore sentinel is one file — LOW

`scripts/post-install:537` skips only when `$dest_dir/gui.json` exists. If `gui.json` is
absent but the directory holds other files — a partially-initialised Calibre, or a
Calibre that created its directory before first configuration — `cp -R "$src_dir/."` at
`:544` overwrites every matching sibling. `docs/manual.md:210` states "Every restore is
non-destructive — it skips any app that's already configured", which is stronger than
what the single-file sentinel guarantees.

## `sync` / `sync-login-items` — PR #1 empty-list fix (`576b22e`)

**`scripts/sync`: fully closed.** `:148-151` and `:153-156` capture `brew list --formula`
and `--cask` into variables and `exit 1` on failure. An empty installed set can no
longer reach the `--prune` stale computation.

### N-3 — `sync-login-items` is NOT fully closed — MEDIUM

The root cause was fixed: `POSIX path of (path of li)` → `path of li`
(`scripts/sync-login-items:84`). The structural path was not.

`scripts/sync-login-items:92-94`:
```
if [[ -z "$raw_items" ]]; then
  warn "No login items returned from osascript (System Events may be unavailable)"
fi
```
It warns and continues. `system_items` stays empty, so the loop at `:118-120` marks
every tracked item stale and offers to delete all of them from `post-install` — exactly
the corruption PR #1 set out to stop, reached by a different route (System Events
unavailable, TCC denial, or any future per-item `try` failure at `:83-85`).

Two contributing details at `:78`: `osascript 2>/dev/null || true` discards the exit
status entirely, and the per-item `try` still swallows individual errors silently.

`sync` hard-aborts on the same class of failure. `sync-login-items` should mirror it.

### N-13 — latent Brewfile truncation — LOW

`scripts/sync:571-572`: when `raw` is empty the python block calls `sys.exit(0)`
**without writing `out_path`**. `:649` then unconditionally `mv`s the zero-byte mktemp
file over the Brewfile.

Currently unreachable — the guards at `:418-421` and `:495-498` exit before
`insertions_data` can be empty. It is one refactor away from truncating the Brewfile,
and it is the same class of defect as `F01`, which this file was already fixed for.

### N-14 — mode not restored before the atomic replace — LOW

`mktemp` creates 0600. `scripts/sync:304` and `:649` `mv` that file over the Brewfile,
leaving it 0600. `scripts/sync-login-items:367-370` does restore modes before its
`mv`, with a comment explaining why. `sync` does not. Git only tracks the exec bit so
this self-heals on the next checkout, which is why it has gone unnoticed.

### N-17 — `bash-completion@2` regression — INFO

Ledger B6 is listed under **Closed** — removed in `3fe44dd` (2026-04-25). It is back at
`Brewfile:5`, reintroduced by `43c4d55` (2026-05-27) and present in every Brewfile
commit since.

The mechanism matters more than the entry: `make sync` re-adds anything installed that
is not in the Brewfile, and the `~/.mrk/sync-ignore` opt-out (`scripts/sync:86-96`) is
not auto-created and does not exist on this machine. **Any deliberate Brewfile removal
will be re-offered and can be silently re-added on the next sync unless the package is
also uninstalled or manually added to `sync-ignore`.** B6 is reopened as a decision, not
a defect — keeping it may now be intentional.

## `assets/topgrade.toml` — `claude_code` step disabled (`bbfd802`)

Rationale holds and is self-documented at `assets/topgrade.toml:9-11`: the step runs
`claude plugin marketplace update`, which grabs the tty and gets SIGTTOU'd, suspending
the whole run. Disabling a background-hostile step in a non-interactive updater is the
correct call, the replacement behaviour (Claude Code self-updates) is stated, and the
entry sits in a `disable` list that already documents each of its members. No finding.

---

# TRACK 3 — Contract and documentation accuracy

## N-7 — BIN-1 drift — MEDIUM

**Confirmed: the nav index stops at 2.16.** `docs/bin/mrk-usage.html:461` is the last
nav entry (`2.16 mrk-uninstall`), but the body continues:

| Body section | Line | In nav? |
|---|---|---|
| 2.17 `bf` | `:811` | no |
| 2.18 `mrk-menu` | `:835` | no |
| 2.19 `mrk-picker` | `:855` | no |
| 2.20 `mrk-push` | `:866` | no |

**Commands with no section at all.** `scripts/setup:299-356` links every executable in
`scripts/` (minus `lib.sh` and `status`, per `_skip_link` at `:273-279`), and
`:358-400` links every executable in `bin/` with no exclusions. Five linked commands
have no BIN-1 entry:

`maintain`, `dock-setup`, `ci-check`, `check-picker-desc`, `adventure-prologue`.

`maintain` is the significant one — a user-facing housekeeping tool with four steps and
three flags, also surfaced in `mrk-menu` under Maintenance (`2bbb030`).

**Content drift within existing sections:**

- **§2.7 snapshot-prefs** (`:672-677`) omits the Calibre config tree added in
  `070916d`. It documents plists and App Support only.
- **§2.20 mrk-push** (`:875-879`) omits the pre-push secret scan at `bin/mrk-push:69` —
  a safety feature that can abort the push.
- **§2.17 bf** (`:818`) shows `bf` with no flags; the binary accepts `--help` and
  `--version`.

**Verified accurate — no change needed:**

- §1.4 `snapshot` app list (`:559`) matches `bin/snapshot:70-97` exactly — all 10 apps.
- §2.7 `snapshot-prefs` app list (`:675`) matches `scripts/snapshot-prefs:82-97` exactly
  — all 14 plists, and the "14 apps" count is right.
- §2.8 `status` (`:691-695`): nine checks, in the same order as
  `tools/mrk-status/main.go:384-392`; `f`, `r`, `tab`/`←→` all match `:492-540`.
- §2.17 `bf` key bindings (`:820-830`) all match `tools/bf/main.go:570-652`.
- §2.18 `mrk-menu` key bindings (`:844-850`) all match `tools/mrk-menu/update.go:83-167`,
  including the `1–9` jump (`digitJump`, `:263-265`).
- §2.9 `sync` and §2.10 `sync-login-items` flags match their scripts.

## N-8 — `docs/manual.md` factual errors — MEDIUM

**`:476` is false.** It states: "`snapshot` writes to the public mrk repo's
`assets/preferences/` (used by `make post-install` for first-run defaults)."

`bin/snapshot` writes plists to `assets/preferences/` (`bin/snapshot:15`). Those plists
are gitignored (`.gitignore`, final line). `scripts/post-install:352` sets
`PREFS_DIR="$REPO_ROOT/assets/preferences"` and uses it **only** for the four
`*-defaults.sh` scripts (`:356, 363, 369, 373`). Plist imports read
`LOCAL_PREFS_DIR="$HOME/.mrk/preferences"` (`:384`, used at `:464-477`). **Nothing reads
`assets/preferences/*.plist`.** BIN-1 §1.4 (`:557`) already gets this right — "Local
export only … No git integration (the exported plists are gitignored)" — so the two
documents contradict each other.

**`:531` reintroduces the bare `--fix` form**: "`make doctor` | Check `~/bin` is on
PATH; `--fix` adds it to `.zshrc`". That is the exact form CLAIM-06 corrected, and Make
rejects it with `make: invalid option -- -`. `:579` in Troubleshooting has the correct
`make doctor ARGS=--fix`.

**`:210` overclaims restore safety** — see N-11.

**Command Reference omissions** (`:490-532`). No entry for `make check`, `make ci`,
`make tidy`, `make bf`, `make build-tools`, `make mrk-status`, `make mrk-menu`, or
`make maintain`. `65f58df` documented `check`/`ci`/`tidy`/`pull` in BIN-1 but not here.

## N-6 / N-12 — Defaults reference

**Correction to the stated premise.** The page does **not** render from
`DEFAULT_DESCRIPTIONS` alone. It renders from **both**:

- `docs/defaults/script.js:502` fetches
  `https://raw.githubusercontent.com/sevmorris/mrk/main/scripts/defaults.sh` over the
  network and parses it (`:512-570`) for the section structure and the key list.
- `DEFAULT_DESCRIPTIONS` supplies prose, looked up by `${domain}.${key}` at `:630`.
- No entry → `generateGenericDescription` fallback (`:638`).
- Fetch failure → `loadDemoData()` (`:508`).

Two consequences worth recording: the published page reflects `main`, not whatever
branch a reader is looking at; and it needs network access to render real content.

### N-6 — 18 keys parse into lookup keys that can never match — MEDIUM

`parseWriteDefault` (`:615-627`) splits on whitespace and does no shell evaluation or
quote handling. Two constructs in `defaults.sh` defeat it:

**The trackpad `$domain` loop — 16 keys.** `scripts/defaults.sh:359` iterates two
domains, and `:361-379` call `write_default "$domain" …`. The parser produces literal
lookup keys `"$domain".TrackpadPinch`, `"$domain".Clicking`, `"$domain".ForceSuppressed`
and 13 more. None match. The entire opt-in trackpad section renders with auto-generated
generic prose, and the displayed `command` / `revertCommand` strings (`:643-644`) read
`defaults write "$domain" TrackpadPinch …` — not runnable as shown.

**Quoted multi-word keys — 2 keys.** `scripts/defaults.sh:328-329` use
`"Default Window Settings"` and `"Startup Window Settings"`. The split at `:618` yields
`com.apple.Terminal."Default` and `com.apple.Terminal."Startup`, with the rest of the
key absorbed into `type` and `value`. Both render with a mangled key and a wrong command.

### N-12 — 24 dead description entries — LOW

`DEFAULT_DESCRIPTIONS` holds 83 entries; `defaults.sh` yields 77 parsed keys. 24 entries
describe keys no longer written by `defaults.sh` and are therefore never rendered:

`com.apple.dock.autohide`, `autohide-time-modifier`,
`enable-spring-load-actions-on-all-items`, `show-process-indicators`;
`com.apple.finder.AppleShowAllFiles`, `_FXShowPosixPathInTitle`, `FXDefaultSearchScope`,
`FXEnableExtensionChangeWarning`, `FXPreferredViewStyle`, `NewWindowTarget`,
`ShowExternalHardDrivesOnDesktop`, `ShowHardDrivesOnDesktop`,
`ShowMountedServersOnDesktop`, `ShowPathbar`, `ShowRemovableMediaOnDesktop`,
`ShowStatusBar`, `WarnOnEmptyTrash`;
`com.apple.LaunchServices.LSQuarantine`; `com.apple.screencapture.type`;
`com.apple.AddressBook.ABShowDebugMenu`;
`com.apple.DiskUtility.advanced-image-options`, `DUDebugMenuEnabled`;
`NSGlobalDomain.com.apple.sound.beep.feedback`,
`NSGlobalDomain.NSDisableAutomaticTermination`.

Harmless, but they are the reason the entry count exceeds the key count, and they hide
genuine coverage gaps in a raw count comparison.

## CI coverage — verified

**`scripts/ci-check` does run `go test`.** `:38-41` iterates `picker bf mrk-status
mrk-menu theme` and runs `go test ./...` in each — five modules, including the shared
`theme` package.

**shellcheck covers both `bin/` and `scripts/`.** `:25-29` takes
`git ls-files 'scripts/*' 'bin/*'`, filters to files whose first line matches
`^#!.*bash`, and excludes only `scripts/adventure-prologue`. `bin/maintain` is covered.
The committed Go binaries in `bin/` are excluded automatically by the shebang filter.

`.github/workflows/ci.yml` runs `scripts/ci-check` then `make build-tools` on
`macos-latest`, with shellcheck installed first — so CI cannot hit the silent-skip
branch at `ci-check:34-35` that a local run can.

Gap: `go vet` is not part of `ci-check`. Run manually during this audit across all five
modules — clean.

## N-19 — the missing test plan — INFO

Two separate problems, both confirmed against git history:

1. **The path prefix is stale.** The audit tree lived at `docs/audit/` and was moved to
   `audit/` in `b3ad0d0`. Three files still reference the old prefix:
   `audit/00-followups.md:23`, `audit/11-test-results.md:3` and `:264`, and
   `audit/syncall-removal.md:67-78` (12 rows).
2. **`10-test-plan.md` was never committed at either path.** `git log --all
   --diff-filter=A` over `docs/audit/*` and `audit/*` shows modules
   00–09, 11 and `syncall-removal` added; 10 appears in neither list, and no deletion
   exists.

So the answer is: **misreferenced *and* missing.** The plan was written during the audit
and never committed. Tests 1C, 2, 3 and 4 cannot be run from the repo as it stands —
their procedures do not exist. This also means the ledger's top deferred item points at
nothing.

## N-18 — F08 is not fully closed — INFO

Ledger lists "F08/F09 — mrk-status dead indicator variable, repoRoot via MRK_ROOT env
var" as Closed. The `MRK_ROOT` half landed. The dead variable did not:
`tools/mrk-status/main.go:766-771` still computes `indicator`, discards it with
`_ = indicator`, and carries the stale comment "we'll embed it in the header instead".
The real scroll display is `scrollInfo` at `:775`.

## Standard sweeps

**Shell hygiene.** `set -euo pipefail` is present in every bash file under `scripts/`
and `bin/` except `scripts/lib.sh`, `bin/lib/common.sh` (sourced libraries — correct to
omit) and `scripts/adventure-prologue` (game, excluded from shellcheck by design).
Portable `mrk_mktemp` (`lib.sh:56-57`) is used consistently. Atomic writes are now the
norm — see N-14 for the one remaining inconsistency.

**Go.** `go vet` clean across all five modules. Only two discarded errors remain in the
tree: `tools/mrk-status/main.go:260` (`exec.LookPath("zsh")` — the empty-string result
is handled) and `:771` (N-18).

**Side effects / rollback.** No change since module 2: the ~40 browser and app-preference
writes still have no rollback coverage.

### N-1 — `|| ((failed++))` under `set -e` — **HIGH**

The prior audit did not catch this. It is the most consequential finding in this pass.

Both scripts set `set -euo pipefail` and initialise `failed=0`
(`scripts/defaults.sh:2,132`; `scripts/post-install:2,31`). Every guarded call then uses:

```
write_default NSGlobalDomain AppleInterfaceStyle string Dark || ((failed++))
```

`((failed++))` is post-increment: it evaluates to the **old** value. When `failed` is
`0`, the arithmetic command's exit status is **1**. It is the last command in the `||`
list, so the list's status is 1, and `set -e` terminates the script.

Verified directly:

```
set -euo pipefail; failed=0
false || ((failed++))
echo "REACHED"          # never printed; script exits 1
```

**Blast radius:**

| File | Sites | Counter init | Summary that never runs |
|---|---|---|---|
| `scripts/defaults.sh` | 77 | `:132` | `:387-388` `warn "$failed default(s) failed to apply"` |
| `scripts/post-install` | 37 | `:31` | `:607` `log "Warning: $failed post-install step(s) failed"` |

The first failed `write_default` — a managed or sandboxed domain, an MDM-locked key, a
missing app — aborts `defaults.sh` mid-run. Defaults are left partially applied, the
rollback file at `~/.mrk/defaults-rollback.sh` is left partially written, and the
"N defaults failed" summary the design depends on is unreachable. `scripts/setup:562`
then reports only "defaults.sh returned non-zero". The same holds for `post-install`
across browser policies, plist imports, app-support restores and login items.

The counters are dead code in both files: `failed` can only ever be read while it is
still `0`.

**This is self-propagating.** `scripts/sync-login-items:320` is a Python line generator
that emits new `add_login_item …  || ((failed++))` lines into `post-install`:

```python
return f'{entry}{" " * padding}|| ((failed++))\n'
```

Hand-fixing `post-install` without fixing the generator means the next
`make sync-login-items` reintroduces the pattern.

**The correct idiom is already used elsewhere in the repo** — `|| true` after the
arithmetic: `bin/maintain:120`, `scripts/sync:409,414`, `scripts/setup:311,317,337`.
The fix is `|| { ((failed++)) || true; }` or `|| ((++failed))` (pre-increment, which
returns the new non-zero value) at all 114 sites plus the generator.

---

# Ranked recommended fixes

Highest value first. **None applied — Phase A is read-only.**

1. **N-1 — repair the `((failed++))` abort.** 114 sites plus the `sync-login-items`
   generator. Restores the intended soft-failure behaviour of both install phases and
   makes two "N failed" summaries reachable for the first time. Fix the generator in the
   same commit or it regresses. Highest value by a wide margin.
2. **N-2 — extend the secret-scan patterns.** Add prefixed-token patterns
   (`sk-`, `sk-ant-`, `ghp_`, `gho_`, `github_pat_`, `xox[baprs]-`, `AKIA`), unanchor
   pattern 2 so vendor-prefixed key names match, and add `password`/`token` to the JSON
   field list. Closes the ledger item on its own stated terms. Add fixture-based tests.
3. **N-4 — convert to xml1 before scanning in all three capture paths.** Small change;
   the rationale is already written at `snapshot-prefs:69-70`. Pairs naturally with 2.
4. **N-3 — make `sync-login-items` abort on an empty login-item list**, mirroring
   `sync:148-156`. Closes the PR #1 failure mode structurally, not just at its root cause.
5. **N-7 / N-8 — documentation corrections.** BIN-1 nav 2.17–2.20; new sections for
   `maintain` and the four other unlisted commands; Calibre in §2.7; the secret scan in
   §2.20. In `manual.md`: delete the false `snapshot`→`post-install` claim at `:476`,
   fix `:531` to `ARGS=--fix`, soften `:210`, add the missing Make targets.
   **These are Phase B inputs — fix the facts before applying STE.**
6. **N-6 — fix the defaults-reference parser** for `$domain` loop entries and quoted
   multi-word keys, or restructure `defaults.sh:359-379` to emit literal domains. 18 of
   77 keys currently render with generic prose and non-runnable commands.
7. **N-5 — stage deletions in `snapshot-prefs`**, or correct the comment at `:140-141`.
8. **N-9 — pin the oh-my-zsh and plugin clones**, matching the nvm precedent.
9. **N-10 — include `tools/theme` in the `maintain` freshness check.**
10. **N-11 — widen the Calibre restore guard** beyond a single sentinel file.
11. **N-12 — delete the 24 dead `DEFAULT_DESCRIPTIONS` entries** (Phase B will touch
    this file anyway — worth doing in the same pass).
12. **N-13 / N-14 — `sync` hardening.** Guard the `mv` on a non-empty temp file; restore
    the file mode before the replace, as `sync-login-items:367-370` does.
13. **N-19 — resolve the test-plan reference.** Either write and commit
    `audit/10-test-plan.md`, or amend `00-followups.md:23`, `11-test-results.md:3,264`
    and `syncall-removal.md:67-78` to stop pointing at a file that never existed. Fix the
    stale `docs/audit/` prefix in the same commit.
14. **N-15 / N-16 / N-18 — small cleanups.** Scope `mrk-push`'s deployment query to
    `?environment=github-pages`; reject `--keep=0` in `maintain`; delete the dead
    `indicator` block in `mrk-status`.
15. **N-17 — decide on `bash-completion@2`.** A choice, not a fix. If it stays, add it to
    `~/.mrk/sync-ignore` documentation so the sync round-trip is understood.

## Ledger items requiring a decision, not a fix

- **ARGS word-split** (`Makefile:145-146`) — unchanged, still benign for every current
  ARGS value.
- **~40 unrolled-back preference writes** — unchanged, still the largest deferred item.
- **Tests 1C/2/3/4** — blocked on N-19 until the plan exists.

---

# Fix session outcomes — 2026-08-02, branch `fix/audit-12-critical`

First of two approved fix sessions. Code only; the STE documentation rewrite is separate.
Four commits, each verified against `scripts/ci-check` (shellcheck + `go test` across five
modules) and `make build-tools` before the next was started.

No shell test harness exists in this repo, so each fix is backed by an adversarial
reproduction run during the session — the pre-fix code was reconstructed from git and run
against the same stub to confirm the reproduction actually reproduces.

| Finding | Commit | Result |
|---|---|---|
| N-1 | `7e21605` | 114 sites + generator + parser regex |
| N-4 | `92655df` | binary plists scanned as xml1 |
| N-2 | `601ced6` | 15/15 fixtures, 0 false positives |
| N-3 | `6dea188` | empty and failed reads both abort |

## N-1 — `7e21605`

All 114 sites replaced with `|| failed=$(( failed + 1 ))`, which always exits 0.

The generator was the load-bearing part. `scripts/sync-login-items` emits the
`add_login_item` block into `post-install`, and it had **two** couplings to the old form,
not the one the audit noted: `make_line()` wrote `|| ((failed++))`, and `LOGIN_ITEM_RE`
matched only that spelling. Fixing the emitter alone would have left the regex matching
nothing, so the block-not-found guard would have fired and the next
`make sync-login-items` would have exited 1. Both were changed together, and a
parse-and-regenerate round-trip over `post-install` is byte-identical.

**Reproduction.** The real `scripts/defaults.sh` was run end-to-end against a stubbed
`defaults` and `killall`, with `HOME` and `ROLLBACK` redirected into a sandbox — nothing
touched the host preference store. Two writes were forced to fail: the first tracked call
(`NSGlobalDomain AppleInterfaceStyle`, pre-existing value) and a later one
(`com.apple.dock tilesize`, key absent).

| | pre-fix (`a17ba54`) | post-fix |
|---|---|---|
| exit code | 1 | 0 |
| reached the end | no | yes |
| writes applied | **0 of 59** | 59 |
| failures counted | — | 2 |
| summary printed | none | `2 default(s) failed to apply` |
| rollback file | 2 lines (shebang + 1) | 65 lines, `bash -n` clean |

The practical impact is larger than a dead counter: one refused key discarded the entire
`make defaults` run and left a near-empty rollback file.

### Related finding, NOT fixed — rollback entries precede the write

`write_default` appends the rollback entry (`scripts/defaults.sh:75-87` for an existing
key, `:117` for an absent one) **before** performing the write at `:120-126`. A failed
write therefore leaves a rollback entry for a change that never applied. Both failed keys
in the reproduction did exactly that.

**Both spurious entries are benign**, which is why this is reported rather than fixed:

- key existed, write failed → `defaults write … -string Light` restores the value that is
  still current. No-op.
- key absent, write failed → `defaults delete …` on an absent key, already suffixed
  `>/dev/null 2>&1 || true`. No-op.

The ordering is also deliberate — the comment at `:72` explains that the entry is written
before the idempotency check so re-runs preserve first-run originals, and the
idempotent-skip path returns at `:113-115` before the write. Moving the append after the
write would break that. Not trivial, not in scope for this session.

→ Follow-up: record the entry only after a successful write, while keeping the
idempotent-skip path recording. Cosmetic fidelity only.

## N-4 — `92655df`

Fixed inside `scan_for_secrets` rather than at each call site, so `snapshot_plist`,
`snapshot_app_support`, `snapshot_pref_dir` and `bin/mrk-push` all benefit. Detection is
on the `bplist00` magic; the scan runs against a temporary xml1 copy and the stored file
is left untouched, so nothing changes about what is backed up or restored.

**Correction to the finding as written.** The audit said `grep -Ein` on a binary plist
"does not reliably match". The mechanism is narrower and worth stating precisely: bplist
stores string data as plain ASCII, so **value** patterns such as `Bearer …` do match the
raw bytes. What can never match is the `<key>…</key>` **structure**, because that markup
does not exist in a binary plist at all. The exposure is therefore a credential under a
recognised key name whose value has no recognisable shape.

**Reproduction.** Identical content in both encodings — `<key>apiKey</key>` with the value
`0f3a9c21bb47de08`, which carries no vendor prefix, so only the structural pattern can
catch it. Used the pre-existing exact-name whitelist, isolating N-4 from N-2.

| | xml1 | binary |
|---|---|---|
| pre-fix | FLAG | **CLEAN** |
| post-fix | FLAG | FLAG |

Measured on this machine: 4 of the 6 Application Support files `snapshot_app_support`
copies are `bplist00` — Loopback `Devices.plist` and `RecentApps.plist`, SoundSource
`CustomPresets.plist` and `Sources.plist`.

## N-2 — `601ced6`

**Baseline first.** Fixtures for Raycast/MacWhisper-style OpenAI keys, GitHub classic and
fine-grained PATs, AWS, Slack, Google and Anthropic keys, and a Calibre JSON password —
**all 10 scanned CLEAN** and would have been committed and pushed.

### Two latent defects found while fixing, beyond the finding as scoped

Both are in the original pattern set and both meant a pattern silently did nothing:

1. **The private-key pattern has never worked on macOS.**
   `-----BEGIN (RSA |OPENSSH |EC |)PRIVATE KEY-----` contains an empty alternative.
   `/usr/bin/grep` — BSD grep 2.6.0-FreeBSD, which is what a script resolves to here —
   rejects it with `empty (sub)expression` and rc=2. The pattern also begins with `-`, so
   grep parsed it as options. `|| true` swallowed both. Private-key detection was dead.
2. **The key/value pattern could not fire on JSON.** It required the field name to be
   followed directly by `:` or `=`, but JSON always has a closing quote in between:
   `"smtp_password": "…"`.

### Changes

- Fixed the private-key pattern; every pattern is now passed with `-e`.
- Added vendor value shapes, independent of field name: `sk-`/`sk-proj-`/`sk-ant-`,
  `gh[pousr]_`, `github_pat_`, `AKIA`, `xox[baprs]-`, `AIza`.
- **Split into case-insensitive and case-sensitive passes.** Vendor prefixes are defined
  by their casing, and folding them is actively harmful: `AIza…` matched case-insensitively
  against a base64 `<data>` blob in a real `BetterSnapTool.plist`. Case-sensitive, the
  vendor patterns produce zero hits across all 14 exported plists.
- Allowed a quote before the `:`/`=` separator; added `password`, `passphrase`, `token`.
- **Paired suggestive plist key names with a substantial `<string>` value**
  (`_scan_plist_key_values`). Name-only matching flagged Keka's `ExportPassword`
  (`<false/>`), `RetryPassword`, `ReusePassword`, `AlwaysAskCompressionPassword`, and
  iTerm2's `AiMaxTokens` and `AiResponseMaxTokens` (`<integer>`). Six false positives
  across two of fourteen files is the rate at which a user learns to wave the gate through.
- **`grep` rc>1 is now a scan failure and a hit.** A pattern that does not compile
  previously reported "clean" — precisely how defect 1 above survived. For a gate that
  blocks a push, failing closed is the only safe reading.

### Verification

| Check | Result |
|---|---|
| positive fixtures (10) | all FLAG |
| negative fixtures (5: UUID, sha256, `tokenizerEnabled`, base64/`<data>` blobs, ordinary JSON) | all CLEAN |
| 14 real exported plists | **0 flagged** |
| 19 real Application Support + Calibre files | **0 flagged** |
| fail-closed on an injected non-compiling pattern | reported `secret scan FAILED`, rc non-zero |
| `require_clean_secrets` under `NONINTERACTIVE=1` | still aborts |
| `require_clean_secrets` on a non-TTY | still aborts |
| `require_clean_secrets` on a clean file | still allows |

The fatal gate was not weakened.

## N-3 — `6dea188`

Both an empty read and a non-zero `osascript` exit now abort before the diff, matching
`scripts/sync`. An ambiguous empty read is treated as a failure: "you have zero login
items" and "the read failed" are indistinguishable here, and only one of the two readings
is destructive. `osascript`'s stderr and exit status are now captured, so a denied
Automation permission is reported instead of silently yielding an empty list.

**Reproduction**, with a stubbed `osascript` and `--dry-run`:

| Scenario | pre-fix (`a17ba54`) | post-fix |
|---|---|---|
| read returns empty | lists all 8 tracked items as stale, prompts `Remove all 8 stale item(s)? [y/N]` | aborts, no diff |
| read exits 1 | same destructive prompt | aborts, reports osascript's stderr |
| normal 8-item read | — | `Login items are up to date` |
| read with 1 new item | — | offers the add |

A `y` at that pre-fix prompt deletes the entire `add_login_item` block from
`scripts/post-install`.

### Residual, NOT fixed — the per-item `try` still swallows errors

The AppleScript loop wraps each item in `try … end try` so one bad login item does not
kill the enumeration. A *partial* failure therefore still yields a short list, and the
items that failed to enumerate are marked stale. The abort added here only covers a
*fully* empty or failed read.

→ Follow-up: have the AppleScript count per-item failures and surface the count, so a
partial read can be distinguished from a complete one. Out of scope for this session.

## Documented behaviour for Phase B to absorb

None of these were edited — the docs freeze held. Phase B should reflect:

1. **`sync-login-items` now aborts on an empty or failed login-item read.** BIN-1 §2.10
   (`docs/bin/mrk-usage.html:717-731`) describes the AppleScript read as automatic and
   silent — "Login items are read from System Events via AppleScript. Paths are resolved
   automatically." It should note the abort and the Automation-permission cause.
2. **The secret scan is a real gate with teeth.** BIN-1 §2.20 already omits
   `require_clean_secrets` in `mrk-push` (finding N-7); §2.7 `snapshot-prefs` likewise
   never mentions that a push can be blocked by the scan. Both matter more now that the
   scan actually detects common key formats.
3. **`make defaults` and `make post-install` now continue past a failed step and report a
   count at the end.** Previously they aborted. Any doc describing their failure behaviour
   should say so.


---

# Phase B outcomes — 2026-08-02, branch `docs/ste-phase-b`

Documentation accuracy fixes plus a Simplified Technical English rewrite. Facts first
per file, then prose. Branched from `bff9fe5` so the docs describe the Session-1 code.

| Finding | Commit | Result |
|---|---|---|
| N-7 | `89fd1af` | BIN-1 index runs to 2.25; 5 undocumented commands added |
| N-8 | `292485f` | manual.md false claims corrected; 10 missing targets added |
| N-6, N-12 | `7f3d8de` | 77/77 keys resolve, 0 orphans, every command runnable |
| — | `5b8064a` | `docs/STE-CONVERSION.md`: ruleset, glossary, scope, deviations |

## Secret-scan gate — verified before documenting

The instruction was to document the gate only on commands that enforce it. Checked in
code first: `require_clean_secrets` is called at `scripts/snapshot-prefs:219` and
`bin/mrk-push:69` only. `bin/snapshot` has no gate, so BIN-1 §1.4 now says so explicitly
rather than leaving a reader to assume otherwise.

## Generator round trip

`scripts/sync-login-items` templates the Login items line in `docs/manual.md`, and its
`re.subn` pattern anchored on the old wording. An STE rewrite of that sentence alone
would have made the next run fail its drift guard and exit 1. The sentence, the template
and the regex changed together in `292485f`.

Verified by driving the real script through a pty with a stubbed `osascript` reporting
one extra app:

- `docs/manual.md` — only the item list changed. The STE sentence survived, and the new
  name was inserted alphabetically with `, ` separators.
- `scripts/post-install` — exactly one new `add_login_item` line, in the Session-1 safe
  `|| failed=$(( failed + 1 ))` form, with correct alignment padding. The code emitter is
  undisturbed.

Also fixed there: `IFS=', '` joins on the first IFS character only, so the manual had
rendered a run-on `A,B,C` list with no spaces.

## Defaults-page reconcile — verification record

The page fetches `scripts/defaults.sh` from `main` at runtime, so the reconcile was
verified locally by temporarily pointing `loadScript` at the branch file, loading the
page, and then reverting the URL. The committed file points at `main`.

| Check | Result |
|---|---|
| parsed keys | 77 |
| descriptions | 77 |
| keys with no description | 0 |
| orphan descriptions | 0 |
| commands rendered | 77 |
| commands with an unexpanded `$domain` | 0 |
| multi-domain notices | 16 |

Sample resolved commands, previously non-runnable:

```
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool false
defaults write com.apple.Terminal "Default Window Settings" -string "Pro"
```

The parser was fixed rather than `defaults.sh`, so the page works against the
`defaults.sh` already on `main`. The one command that still contains a `$` is
`defaults write com.apple.screencapture location -string "$HOME/Desktop"`, which is a
real shell variable and expands correctly when pasted.

## Not done

The STE prose split across the **59 pre-existing** `DEFAULT_DESCRIPTIONS` entries. Each
mixes functional text with historical material in one paragraph, so it is a per-entry
authoring task. The rendering support is in place (`background` field, labelled
not-STE), and the 18 entries authored during the reconcile are the worked example.
Tracked in `00-followups.md` under Known limitations.
