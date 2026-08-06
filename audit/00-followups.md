# Followups

This file indexes every deferred item, known limitation, and explicitly-out-of-scope
finding from the mrk audit (modules 1–12, five fix sessions, runtime verification).
It is not a punch list of unfixed bugs — most items here were explicitly chosen to defer,
accept as a known limitation, or scope out. The value of the file is that "what's still
open?" has a single answer without grepping the whole audit directory.

For each item: what it is, where it's documented, why it was deferred, what action
would close it.

**Last re-verified:** 2026-08-02 against `a17ba54`, in `12-fresh-audit-2026-08.md`.
That pass closed 9 items, reopened 2, and added new findings — including one HIGH
(`N-1`) that modules 1–11 did not catch. Line numbers below are current as of that
verification.

---

## Blocking

None. N-1 is fixed — see Closed below.

---

## Deferred decisions

Items that require a real choice before they can be closed in either direction.

**Tests 1C, 2, 3, and 4 in the test plan — BLOCKED: the plan does not exist.**
Idempotency (Test 2), order-independence (Test 3), and re-entry recovery (Test 4) were
not executed. Test 1C (combined `make defaults` + `make harden` rollback) was also not
run; static analysis predicts a PARTIAL verdict because ~40 browser and app-preference
keys have no rollback coverage. **`10-test-plan.md` was never committed at any path** —
`git log --all --diff-filter=A` over both `docs/audit/*` and `audit/*` shows modules
00–09, 11 and `syncall-removal` added, and no 10. The `docs/audit/` prefix is separately
stale: the tree moved to `audit/` in `b3ad0d0`. These tests cannot be run from the repo
as it stands. Documented in `12-fresh-audit-2026-08.md N-19`.
→ To close: write and commit `audit/10-test-plan.md`, or amend the three files that
reference it (this file, `11-test-results.md:3,264`, `syncall-removal.md:67-78`) and
fix the stale `docs/audit/` prefix at the same time. Then
`tart clone mrk-audit-clean-prepared mrk-test-N` and run.

**N-17 — `bash-completion@2` is back in the Brewfile (reopened B6).** B6 removed it in
`3fe44dd`; `43c4d55` reintroduced it and it has been present ever since, now at
`Brewfile:5`. The mechanism mattered more than the entry: `make sync` re-offers anything
installed but absent from the Brewfile, and **at audit time** the `~/.mrk/sync-ignore`
opt-out was not auto-created and did not exist on this machine. Any deliberate Brewfile
removal could be silently re-added on a later sync. Documented in
`12-fresh-audit-2026-08.md N-17`.
→ To close: decide whether `bash-completion@2` stays. If it stays, that is the answer. If
it goes, uninstall it or decline it once at the picker and accept the offer to ignore it.

**Scope note, rewritten 2026-08-05.** N-17 named one entry but described a class: a
deliberate untrack can be silently re-added by a later sync, because "installed but not
tracked" and "never tracked" are indistinguishable to the diff. The class had two halves,
and **both are now closed** (see Closed below). `sync-login-items` gained the ignore list
it never had, and both commands now offer the candidates you declined and write the ones
you select, creating the file if it is absent. Neither ignore file is hand-created-only
any more — which was the reason `~/.mrk/sync-ignore` had never existed here, and so the
reason the opt-out was never reached for.

What remains of N-17 is only the decision it opened with: whether `bash-completion@2`
stays in the Brewfile. That is a choice, not a defect. If it goes, the mechanism to keep
it gone now exists and takes one decline.

**N-9 — oh-my-zsh and zsh plugins are cloned unpinned.** `scripts/setup:612,626` clone
`ohmyzsh/ohmyzsh` and two `zsh-users` plugins at `--depth=1` from the default branch,
with no tag, commit pin, or verification. The result is sourced by every interactive
shell. The project pins its other network-installed dependency (nvm at `v0.40.4`), so
this is inconsistent with its own precedent. Not a live defect. Documented in
`12-fresh-audit-2026-08.md N-9`.
→ To close: pin to a tag or commit, or record the decision to track upstream.

---

## Known limitations (documented, not blocking)

Items the audit identified that are real but classified as acceptable.

**Defaults-page prose split is outstanding.** `docs/defaults/script.js` is reconciled
(77/77 keys, 0 orphans) and the 18 newly authored entries are in Simplified Technical
English, but the 59 pre-existing descriptions still mix functional text and historical
material in one paragraph. The rendering support for the split is in place: an entry may
carry a `background` field, which renders in a block labelled as not-STE. Documented in
`docs/STE-CONVERSION.md`.
→ To close: per entry, move the historical and editorial material into `background` and
convert the functional sentence to STE. A per-entry authoring task, not a mechanical pass.

**~40 browser and app-preference writes have NO ROLLBACK FOUND.** Safari, Helium, Audio
Hijack, Fission, AlDente, and all six Rogue Amoeba update-suppression domains are written
by `assets/browsers/` and `assets/preferences/` scripts with no rollback entries
(`scripts/post-install:157,173,189,203,356,363,369,373`). The 14 plist imports
(`defaults import`, `:464-477`) and browser policy JSON files also have no rollback.
Documented in `02-side-effects.md` (macOS defaults tables) and `11-test-results.md §5`.
Re-verified unchanged 2026-08-02. Still the largest deferred item.
→ To close: extend the rollback mechanism to these paths. Significant work; lower
priority because plist imports are gated on the preferences file being absent (skip-if-
exists) and browser policies are additive, not destructive to existing user settings.

**ARGS word-split for value-bearing flags.** Make word-splits `$(ARGS)` before the
shell receives it. For single-token flags (`--dry-run`, `-c`) this is benign. For
flags with embedded spaces (`ARGS="--message hello world"`) the value is split into
three tokens. A TODO comment documents this at `Makefile:145-146` (was `:124`). No
current ARGS values trigger the problem. Documented in `04-makefile-audit.md L1`.
→ To close: quote the expansion in each recipe: `@"$(SCRIPTS)/sync" "$(ARGS)"`. For
multi-flag use, a proper argument-splitting approach or documented workaround would
also help.

**N-5 — deleted config files are never staged, so they persist in mrk-prefs.**
`scripts/snapshot-prefs:140-141` claims the dest is cleared "so files removed from the
source don't linger in the backup". `rm -rf` at `:154` clears the local tree, but staging
at `:194-210` collects only files that exist and runs `git add -- <paths>` — a tracked
file that vanished is never staged as a deletion, so it stays in `HEAD` and in the pushed
repo. Documented in `12-fresh-audit-2026-08.md N-5`.
→ To close: stage deletions (`git add -A -- <trees>` scoped to the snapshot outputs), or
correct the comment.

**make doctor --fix bare form (Make limitation).** `make doctor --fix` is interpreted
by Make as passing `--fix` as a Make option and produces `make: invalid option -- -`.
The documented canonical form is `make doctor ARGS=--fix` (Makefile has `$(ARGS)`
passthrough at `:121`). Fixing the bare form would require MAKEFLAGS manipulation or
`.RECIPEPREFIX` changes — marginal value. Documented in
`07-contract-verification.md CLAIM-06`.
The bare form had regressed into `docs/manual.md`; Phase B corrected it in `292485f`,
and BIN-1 §2.2 now states the limitation explicitly.
→ To close: no-op unless the bare-form UX is specifically desired.

**N-10 — maintain build-freshness ignores tools/theme.** `bin/maintain:193` compares each
binary only against its own `tools/<name>` directory (`:188`). All four TUIs import the
shared `tools/theme` module, so editing `tools/theme/theme.go` leaves every binary stale
while Step 4 reports all four "up to date". Documented in
`12-fresh-audit-2026-08.md N-10`.
→ To close: include `tools/theme/*.go` in the `-newer` comparison for every binary.

**N-11 — Calibre restore sentinel is a single file.** `scripts/post-install:537` skips
only when `gui.json` exists. If `gui.json` is absent but the directory holds other files,
`cp -R "$src_dir/."` at `:544` overwrites matching siblings. Documented in
`12-fresh-audit-2026-08.md N-11`. The manual previously claimed "Every restore is
non-destructive"; Phase B narrowed that claim to what the guard provides (`292485f`), so
only the code side is open.
→ To close: widen the guard to "directory is empty or sentinel absent".

**N-13 / N-14 — sync write-path hardening.** `scripts/sync:571-572` calls `sys.exit(0)`
without writing `out_path` when the insertions payload is empty, and `:649` then `mv`s
the zero-byte temp file over the Brewfile. Currently unreachable (guards at `:418-421`
and `:495-498`) but the same class as the already-fixed `F01`. Separately, `mktemp`
creates 0600 and neither `:304` nor `:649` restores the mode before the replace;
`scripts/sync-login-items:367-370` does, with a comment explaining why. Documented in
`12-fresh-audit-2026-08.md N-13, N-14`.
→ To close: guard the `mv` on a non-empty temp file; `chmod 644` before the replace.

**N-15 / N-16 — deployment-pruning edges.** `bin/mrk-push:87` queries
`/repos/$repo/deployments` with no environment filter, so it would delete deployments in
any environment; `bin/maintain:101` correctly scopes to `?environment=github-pages`.
`bin/maintain:70` accepts `--keep=0`, which selects every deployment including the live
one at `:110` (interactive confirm at `:114-116` stands between). Documented in
`12-fresh-audit-2026-08.md N-15, N-16`.
→ To close: scope the `mrk-push` query; reject `--keep=0`.

---

## Out of scope

Items the audit considered and explicitly excluded.

**Multi-machine concurrent snapshot-prefs.** Audit module 9 traced the failure mode
(push rejected non-fast-forward when two machines snapshot without syncing). Requires
two real machines to reproduce and test. Standard git multi-writer behavior; the
failure path is clean (local commit preserved, user must pull and re-push).
→ To close: requires real-world testing if concurrent multi-machine use becomes common.

**Network-loss simulation for graceful degradation.** Verifying that `make brew`,
`make post-install`, and `scripts/check-updates` degrade gracefully on a disconnected
network would require Tart network manipulation (pfctl rules or VM network bridge
control) beyond what the test plan covered.

**adventure-prologue L1 — unbraced `$10`/`$11` positional parameters.** Two instances
at approximately lines 1211 and 1289 of `scripts/adventure-prologue`. In bash, `$10`
is `${1}` + literal `"0"`, not the tenth positional parameter. Causes wrong room or
item lookups on those branches. Game script only; no production impact.
Documented in `03-shell-hygiene.md L1`.

**adventure-prologue L2 — overlapping case patterns.** One game path is unreachable
due to a more-general pattern appearing before a more-specific one (approximately
lines 1597/1602). Dead code in the game logic only. Documented in `03-shell-hygiene.md L2`.

**adventure-prologue SC2015 patterns.** 33 instances of `A && B || C` used as
if-then-else. The footgun: if `B` fails, `C` also runs. All are in game-logic context;
no production risk. Documented in `03-shell-hygiene.md L3`.

---

## Closed (for reference)

Items that were on the punch list and have been closed. Pointers to commits only;
the audit artifacts have the full detail.

### Closed by the login-items ignore-list feature, branch `feat/login-items-ignore`, 2026-08-05

- **Login-item silent return (the login-item half of the N-17 class)** — `6c0501a`.
  `sync-login-items` had no ignore mechanism, so an app that re-registers itself as a
  login item after a deliberate untrack came back as an add candidate on every run.
  NordPass, untracked in `673622b`, is the live case; `bash-completion@2` is the same
  class on the Brewfile side. `~/.mrk/login-items-ignore` now drops matching names
  before the up-to-date check and the select UI, so an ignored item is never offered
  (`scripts/sync-login-items:69-107` loader and match, `:177-201` filter stage).
  The file mirrors `~/.mrk/sync-ignore` in format, loader and match, with one recorded
  difference: `sync` strips all whitespace from a rule, which is right for Brewfile
  tokens but would turn `Chrono Plus` into `ChronoPlus` and never match, so the
  login-items loader strips only leading and trailing whitespace.
  Scope is deliberate: the filter is a new upstream stage and the stale set and the whole
  apply/generator path are unchanged. It stops a re-add; it does not retroactively untrack
  an already-tracked item, which stays a manual edit of the `add_login_item` block.
  Like `sync-ignore`, the file is not auto-created.
  Verified with a stubbed `osascript` and a throwaway `$HOME` and repo: an ignored,
  present, untracked NordPass is dropped and the run reports "up to date"; a non-ignored
  item is still offered; with no ignore file the output is byte-identical to the
  pre-change script; comments, blank lines, inline comments and surrounding whitespace
  parse per `sync`'s semantics; and ignoring a tracked-but-absent item still lists it as
  stale. The N-1 generator was re-checked in the same run — driving the write path through
  a pty produces `post-install` and `docs/manual.md` byte-identical to the pre-change
  script's output, adding one line in the safe `|| failed=$(( failed + 1 ))` form with
  column alignment, the `", "`-separated manual sentence and the 755/644 modes preserved.
- **Documentation** — `d7696cc`. `docs/manual.md` and `docs/bin/mrk-usage.html` §2.10
  document the file in STE. Both also gained the `~/.mrk/sync-ignore` line that neither
  had carried: the manual's state-files table listed no ignore file at all, and the usage
  page never mentioned `sync-ignore`. `docs/STE-CONVERSION.md` registers "drop" as the
  chosen term for the action.

### Closed by the self-populating ignore list, branch `feat/login-items-ignore-selfpopulate`, 2026-08-05

- **Ignore-list discoverability — the file was inert until hand-created** — `f4f2ab1`.
  The ignore mechanism above only helped someone who already knew the file existed, which
  is the same reason `~/.mrk/sync-ignore` has never existed on this machine (see N-17).
  `sync-login-items` now offers the candidates you declined and writes the ones you select
  to `~/.mrk/login-items-ignore`, creating the file with a documented header. The file
  populates itself at the exact moment the user expresses the intent.
  The offer runs before the "No changes selected" exit, because declining every candidate
  is the case it exists for. It touches only the ignore file. Appends are append-only and
  keep existing comments, blank lines and order; names go in verbatim so interior spaces
  survive the trim-ends-only loader; a file with no final newline gets one first;
  `--dry-run` asks but writes nothing.
  The same offer was then ported to `scripts/sync` — see below — so both commands behave
  the same way.
- **The Brewfile side of the same gap** — `7e526c9`. `scripts/sync` had the older, inert
  half of the pattern: `~/.mrk/sync-ignore` only helped someone who already knew it
  existed, and it had never existed on this machine. sync now offers the candidates you
  declined at the picker and writes the ones you select, mirroring section 5b of
  `sync-login-items` — before the "No packages selected" exit, touching only the ignore
  file and never the Brewfile, append-only, with the same `--dry-run` behavior.
  This closes the mechanism half of N-17 on both sides. Verified 10/10 with a stubbed
  brew: decline both at the picker and accept, and a re-run reports "Skipping 2 ignored
  package(s)"; on a partial selection only the declined package is offered while the
  selected one is added; the Brewfile is byte-identical to the pre-change script's output
  given the same picker input. Two test seams are disclosed in the commit message, because
  sync resolves Homebrew from hardcoded paths and has no non-TUI selection fallback.
- **Ignored-but-tracked was invisible** — `94e2ed9`. A name both tracked in `post-install`
  and present in the ignore list appeared in neither the new set nor the stale set, so
  `post-install` kept adding the app at install time while the ignore rule did nothing.
  These are now shown under their own heading, "Ignored, but still tracked", and offered
  for deletion through the existing remove path. Deliberately not folded into the stale
  set: the apps are on the system, so "not on system" would be false. Scoped to tracked
  AND ignored AND present, so a tracked, ignored, absent item stays stale-only and is
  never listed twice.
- **Documentation** — `318b787`. Corrects the two statements this work made false: "mrk
  does not create this file", and the note that an already-tracked item stays tracked and
  needs a hand edit. `docs/STE-CONVERSION.md` registers "decline", the only new term.
- **Verification.** 13/13 across the core, offer and ignored-but-tracked cases, with a
  stubbed `osascript`, a throwaway `$HOME` and repo, gum hidden to force the deterministic
  path, and the write path driven through a pty. The end-to-end proof is one loop: an item
  is offered, the add is declined, the offer is accepted, the name is appended, and a fresh
  re-run drops it without a prompt. The generator was re-checked in its strongest form — a
  run where the offer fires and writes while the generator also deletes a stale entry
  produces `post-install` and `docs/manual.md` byte-identical to the pre-change script's
  output, with the safe `|| failed=$(( failed + 1 ))` form, the column alignment and the
  `", "` separated manual sentence all preserved.

### Closed by Phase B (documentation), branch `docs/ste-phase-b`, 2026-08-02

- **N-7 — BIN-1 drift** — `89fd1af`. The nav index now runs to 2.25. Added 2.17-2.20
  (bf, mrk-menu, mrk-picker, mrk-push), which existed in the body but not the index, and
  five commands that had no section at all: `maintain`, `dock-setup`, `ci-check`,
  `check-picker-desc` and `adventure-prologue`. Also corrected §2.7 (Calibre config
  tree), §2.17 (`bf` takes an optional path, `--help`/`-h` and `--version`) and §2.19
  (`mrk-picker` has five real flags, not a placeholder). Rendered check: 31 nav links,
  29 sections, no broken anchors.
- **N-8 — `docs/manual.md` factual errors** — `292485f`. Deleted the false claim that
  `make post-install` reads `assets/preferences/` "for first-run defaults"; nothing reads
  those gitignored plists. Corrected `make doctor` from "Run full diagnostics" to what it
  does, and replaced the bare `--fix` form with `make doctor ARGS=--fix`. Documented the
  five `--only` phases instead of three, added the ten missing Make targets, added the
  Calibre restore, and narrowed the "Every restore is non-destructive" claim to what the
  single-sentinel guard actually provides.
- **N-6 — defaults reference parse failures** — `7f3d8de`. The parser now resolves the
  `for domain in ...` loop and tokenizes quoted multi-word keys. All 16 trackpad keys and
  both Terminal profile keys render runnable commands; previously they displayed
  `defaults write "$domain" TrackpadPinch ...` and a mangled `com.apple.Terminal."Default`.
  Fixed in the parser, not in `defaults.sh`, so it works against the `defaults.sh` already
  on main.
- **N-12 — 24 dead `DEFAULT_DESCRIPTIONS` entries** — `7f3d8de`. Deleted. None could be
  rewired; their key names no longer appear anywhere in `defaults.sh`. The 18 keys that
  had no description gained one. Acceptance verified against the branch's `defaults.sh`
  with the fetch URL temporarily repointed and then reverted: 77 parsed keys, 77
  descriptions, 0 without a description, 0 orphans, 0 commands with an unexpanded
  variable.
- **Session-1 behaviour deltas absorbed into the docs** — `89fd1af`, `292485f`. The
  `sync-login-items` abort on an empty or failed read; the secret-scan gate, documented
  only on the two commands that call `require_clean_secrets`
  (`scripts/snapshot-prefs:219` and `bin/mrk-push:69`) and explicitly disclaimed on
  `bin/snapshot`, which has no gate; and `make defaults` / `make post-install` continuing
  past a failed step to report a count.

### Closed by the fix session on branch `fix/audit-12-critical`, 2026-08-02

- **N-1 — `|| ((failed++))` aborted the script under `set -e`** — `7e21605`.
  All 114 sites in `scripts/defaults.sh` and `scripts/post-install` now use
  `|| failed=$(( failed + 1 ))`, which always exits 0. The generator in
  `scripts/sync-login-items` (`make_line`) and its matching `LOGIN_ITEM_RE` were fixed
  in the same commit, so the next `make sync-login-items` cannot reintroduce the
  pattern; a parse-and-regenerate round-trip over `post-install` is byte-identical.
  Reproduced against a stubbed `defaults`: before, one refused write aborted the run
  with 0 of 59 writes applied, no summary and a 2-line rollback stub; after, the run
  completes, applies 59 writes, counts 2 failures, prints the summary and leaves a
  well-formed 65-line rollback file.
- **N-4 — binary plists were scanned as binary** — `92655df`. `scan_for_secrets`
  detects `bplist00` and scans a temporary xml1 copy, so `snapshot_plist`,
  `snapshot_app_support`, `snapshot_pref_dir` and `mrk-push` are all covered; the
  stored file is untouched. Verified with identical content in both encodings:
  `<key>apiKey</key>` with an unremarkable value was FLAG as xml1 and CLEAN as binary
  before, FLAG in both after.
- **N-2 — the scanner missed every common API-key format** — `601ced6`. Added vendor
  value shapes (`sk-`/`sk-proj-`/`sk-ant-`, `gh[pousr]_`, `github_pat_`, `AKIA`,
  `xox[baprs]-`, `AIza`) in a case-sensitive pass, loosened the plist key-name match and
  paired it with a substantial `<string>` value, allowed a quote before the `:`/`=`
  separator, and made `grep` rc>1 a scan failure instead of "clean". 15/15 fixtures pass
  with 0 false positives across the 14 exported plists and 19 Application Support and
  Calibre files on this machine. The fatal gate is unchanged.
  **Two latent defects surfaced while fixing this** — the private-key pattern contained
  an empty alternative that BSD grep rejects outright, and it began with `-` so grep
  parsed it as options. Private-key detection had never worked on macOS. Both fixed.
- **N-3 — `sync-login-items` only warned on an empty login-item read** — `6dea188`.
  Both an empty read and a non-zero `osascript` exit now abort before the diff, matching
  `scripts/sync`. Reproduced with a stubbed `osascript`: before, an empty read printed
  all 8 tracked items as stale and prompted "Remove all 8 stale item(s)? [y/N]"; after,
  both failure modes abort with no removal diff, while a normal 8-item read still reports
  "up to date" and a read with a new item still offers the add.

### Closed by re-verification, 2026-08-02

Nine items carried as open in this file were already fixed in code. Verified against
`a17ba54`; full detail in `12-fresh-audit-2026-08.md` Track 1.

- **Screensaver rollback wrote `0` instead of deleting** — `scripts/hardening.sh:103-107`
  and `:111-115` now emit `defaults delete …` when the key was absent pre-apply.
- **M4 — sudo check tested PATH, not usability** — `scripts/hardening.sh:43` uses
  `sudo -n true 2>/dev/null` to gate the credential refresh, as the close criteria asked.
- **FM5 — `make harden` skipped stealth mode when the firewall was already on** —
  `scripts/hardening.sh:132-136` computes `need_firewall` from the global *and* stealth
  states; `:156-167` evaluates stealth independently.
- **`scripts/sync` python3 Brewfile write was not atomic** — `:558` writes to
  `.Brewfile.XXXXXX` in the repo and `:649` `mv`s it into place; the prune path does the
  same at `:293-304`, with a `cleanup` trap at `:79-84`. (Two residual edges remain — see
  N-13/N-14 above.)
- **F10 — dscl error discarded in mrk-status** — `tools/mrk-status/main.go:251-255`
  surfaces `dscl failed: %v`.
- **B7 — coreutils gnubin not on PATH** — `dotfiles/.zprofile:15-24` prepends
  `$(brew --prefix coreutils)/libexec/gnubin` with a duplicate guard; the `Brewfile:8`
  comment now matches behaviour.
- **B4 — Python management strategy** — `python@3.12` removed in `43c4d55`; `Brewfile:52`
  records pyenv + pipx + `.python-version` as canonical.
- **nvm management direction** — `Brewfile:53` documents post-install as the deliberate
  long-term home.
- **check-updates 1-second blocking timeout** — closed beyond the deferred plan.
  `scripts/check-updates:55-84` performs no blocking fetch at all; it compares against the
  last-fetched remote ref and refreshes via `{ git fetch …; } & disown`.
- **fix-exec target vs binary divergence** — `Makefile:71-72` calls
  `"$(SCRIPTS)/fix-exec"`; the binary repairs `~/bin` symlinks pointing into the repo at
  `scripts/fix-exec:27-38`.

**Correction to an earlier Closed entry.** F08 ("mrk-status dead indicator variable") is
listed below as closed. The `MRK_ROOT` half (F09) landed; the dead variable did not.
`tools/mrk-status/main.go:766-771` still computes `indicator`, discards it with
`_ = indicator`, and carries the stale comment "we'll embed it in the header instead".
The live scroll display is `scrollInfo` at `:775`. Documented in
`12-fresh-audit-2026-08.md N-18`.

### Closed by the original fix sessions

- `make syncall` removed (Hot Spot #1, H3) — commits `ba29d0c`, `f9ac419`
- Rollback truncation and re-run decay (M2) — `fix/rollback-fidelity` branch
- Keys-with-spaces quoting and dedup guards (M2 extension) — same branch
- Empty backup dir created on every re-run (M1) — `ec3836c`
- H1 — `local` outside function crashes `--prune` path in scripts/sync — `fix/correctness` branch
- H2 — DMG mount leak on SIGINT in install_github_app — `fix/correctness` branch
- F01 — non-atomic Brewfile write in `bf` — `fix/correctness` branch
- F07 — mrk-status `f` key fires fix without confirmation — `fix/correctness` + `2820d0a`
- CLAIM-06 — `make doctor --fix` → `make doctor ARGS=--fix`; README corrected — `fix/correctness` branch
- F02–F04 — bf duplicate-add, greedy regexp, dirty-flag timing — `0a4853e`
- F05 — picker rune-vs-byte truncation — `477c3b8`
- F06 — moved truncate helper to shared theme package — `174c94e`
- F08/F09 — mrk-status dead indicator variable, repoRoot via MRK_ROOT env var — `fix/final-cleanup` branch
- M3 partial — check-updates timeout 5s → 1s — `031499c`
- M5 — sync-login-items partial-write via temp-and-rename — `c7d3582`
- L3 (nuke-mrk) — SC2015 `&&/||` footguns in cleanup sequences — `25e461d`
- L4 — `make help` sort order removed — `3361c77`
- Makefile M1 — `go mod tidy` removed from go-build macro; added `make tidy` — `472375b`
- Makefile L3 — `make snapshot` target added — `dbe7bf7`
- B3 — nvm migrated from Homebrew to official install script — `fix/nvm-migration` branch
- B5 — openjdk system symlink added to post-install — `1367782`
- B6 — `bash-completion@2` removed from Brewfile — `3fe44dd`
- B2 — `claudebar` cask removed (greedy inconsistency + Barkeep overlap) — `ffb3325`
- B8 — README claims corrected for phase independence and state locations — `fix/quality-drift` branch
- CLAIM-01 through CLAIM-07 README accuracy — `fix/quality-drift` branch
- Test 1A rollback fidelity (make defaults) — PASS — `17e45a2`
- Test 1B rollback fidelity (make harden) — PASS after fix — fixes `f17c991`, `178b191`; merged `efe3fd6`
