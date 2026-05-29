# Followups

This file indexes every deferred item, known limitation, and explicitly-out-of-scope
finding from the mrk audit (modules 1–11, five fix sessions, runtime verification).
It is not a punch list of unfixed bugs — every item here was explicitly chosen to defer,
accept as a known limitation, or scope out. Nothing here is blocking. The value of the
file is that "what's still open?" has a single answer without grepping the whole audit
directory.

For each item: what it is, where it's documented, why it was deferred, what action
would close it.

---

## Deferred decisions

Items that require a real choice before they can be closed in either direction.

**Tests 1C, 2, 3, and 4 in the test plan.** Idempotency (Test 2), order-independence
(Test 3), and re-entry recovery (Test 4) were not executed. Test 1C (combined
`make defaults` + `make harden` rollback) was also not run; static analysis predicts
a PARTIAL verdict because ~40 browser and app-preference keys have no rollback coverage.
The plan and procedures are in `docs/audit/10-test-plan.md`, Sections 2C and 3–5.
Tests 1C and 2 have the highest remaining value; 3 and 4 are lower.
→ To run: `tart clone mrk-audit-clean-prepared mrk-test-N` and follow the test plan.

**B4 — Python management strategy.** `python@3.12` and `pyenv` both remain in the
Brewfile (`Brewfile:49,51`). These represent two competing management strategies: a
pinned Homebrew-managed Python that ages in place, and a version manager. `pipx` adds
a third layer. It is not clear which Python is canonical. Documented in
`05-brewfile-and-ruby.md B4`.
→ To close: decide on one strategy. If `pyenv` is primary, remove `python@3.12` and
pin via `pyenv global` or `.python-version`. If Homebrew is primary, remove `pyenv`.
Either way, update the Brewfile.

**nvm management direction.** B3 closed by migrating `nvm` out of the Brewfile and
into `scripts/post-install` (pinned at `v0.40.4`, installed via the upstream install
script with `PROFILE=/dev/null`). The previous in-tree TODO was removed at the same
time. Whether post-install installation is the right long-term home — versus returning
to a tap, switching to `fnm` or `volta`, or going further and removing nvm in favor of
a single pinned Node — is unresolved. The current setup works; this is a direction
question, not a bug. Documented in `05-brewfile-and-ruby.md B3` (closed) and
`scripts/post-install:205–222`.
→ To close: pick a long-term Node-version-manager direction and document the rationale
in the Brewfile or in `05-brewfile-and-ruby.md`.

---

## Known limitations (documented, not blocking)

Items the audit identified that are real but classified as acceptable.

**Screensaver rollback writes 0 instead of deleting.** When `askForPassword` and
`askForPasswordDelay` are absent pre-apply, `scripts/hardening.sh` captures the `|| echo "0"`
fallback and generates `defaults write … -int 0` rollback entries. After rollback the
keys are explicitly present as `0` rather than absent. Functionally equivalent — macOS
treats absent and `0` identically for screensaver password lock — but `defaults read`
returns a value instead of an error. Documented in `11-test-results.md §5`.
→ To close: detect the fallback `0` case and emit `defaults delete` instead of
`defaults write … -int 0`, consistent with the pattern `scripts/defaults.sh` uses for
absent keys.

**~40 browser and app-preference writes have NO ROLLBACK FOUND.** Safari, Helium, Audio
Hijack, Fission, AlDente, and all six Rogue Amoeba update-suppression domains are written
by `assets/browsers/` and `assets/preferences/` scripts with no rollback entries.
The 14 plist imports (`defaults import`) and browser policy JSON files written by
`scripts/post-install` also have no rollback. Documented in `02-side-effects.md`
(macOS defaults tables) and `11-test-results.md §5`.
→ To close: extend the rollback mechanism to these paths. Significant work; lower
priority because plist imports are gated on the preferences file being absent (skip-if-
exists) and browser policies are additive, not destructive to existing user settings.

**ARGS word-split for value-bearing flags.** Make word-splits `$(ARGS)` before the
shell receives it. For single-token flags (`--dry-run`, `-c`) this is benign. For
flags with embedded spaces (`ARGS="--message hello world"`) the value is split into
three tokens. A TODO comment documents this at `Makefile:124`. No current ARGS values
trigger the problem. Documented in `04-makefile-audit.md L1`.
→ To close: quote the expansion in each recipe: `@"$(SCRIPTS)/sync" "$(ARGS)"`. For
multi-flag use, a proper argument-splitting approach or documented workaround would
also help.

**check-updates 1-second blocking timeout.** Reduced from 5 seconds to 1 second
(`scripts/check-updates:50`) in `fix/final-cleanup`. The full restructure — detached
background fetch writing a flag file, `.zshrc` checking only the flag — was deferred.
Every new interactive shell still blocks for up to 1 second on a slow network.
Documented in `03-shell-hygiene.md M3`.
→ To close: move the `git fetch` entirely to a background process that writes a flag
file (e.g., `~/.cache/mrk/update-available`); have `.zshrc` read the flag and never
wait on the network directly.

**scripts/sync python3 Brewfile write is not atomic.** The inline python3 block that
inserts new entries into the Brewfile (`scripts/sync:490`) writes directly to the
Brewfile with `open(brewfile_path, 'w')` — the same non-atomic pattern that `audit M5`
flagged in `scripts/sync-login-items`. The M5 fix (temp-and-rename) was applied only
to `sync-login-items`. Lower stakes here: the Brewfile is version-controlled, so
`git checkout Brewfile` recovers a truncated file. Documented in `03-shell-hygiene.md M5`
(by analogy) and `01-callgraph.md` sync target.
→ To close: write the output to a temp file in the same directory, then `mv` it over
the Brewfile only after a successful python3 run. Same pattern as `sync-login-items`'s
existing fix.

**snapshot-prefs has no API key scan before push.** `scripts/snapshot-prefs` exports
the full defaults domains for Raycast (`com.raycast.macos`) and MacWhisper
(`com.goodsnooze.MacWhisper`) without filtering. Both apps are known to store live API
keys in their defaults when configured for cloud services (Raycast AI Commands extension,
MacWhisper cloud transcription). A user who activates those extensions and runs
`make snapshot-prefs` will push live API keys to GitHub with no warning. No pre-push
check exists. Documented in `09-snapshot-prefs-deep-dive.md §§7d, 7e, §6`.
Verification commands: `defaults read com.raycast.macos | grep -i 'apiKey\|token\|secret\|openai'`
and `defaults read com.goodsnooze.MacWhisper | grep -i 'api\|key\|openai\|secret'`.
→ To close: add a pre-export grep for common API key patterns (sk-, ghp_, gho_, bearer,
and common key/token field names) across the to-be-exported plists; abort with a
clear warning if any match.

**M4 — hardening.sh sudo check tests PATH presence, not usability.** `command -v sudo`
confirms the binary is in `$PATH` but does not verify the current user can invoke sudo
(active credential cache, NOPASSWD, or interactive TTY available). In practice the first
actual sudo call (`sudo cp /etc/pam.d/sudo`) prompts interactively and caches the
credential; the remaining sudo calls complete within that window. Silent no-ops with
warning messages cover the failure case. Practical consequence is low on a personal
machine. Documented in `03-shell-hygiene.md M4` and `08-harden-deep-dive.md §2`.
→ To close: replace `command -v sudo` with `sudo -n true 2>/dev/null` and update the
comment. One-line change; no behavioral difference on NOPASSWD machines.

**FM5 — make harden skips stealth mode when firewall is already enabled.** When
`socketfilterfw --getglobalstate` returns `on`, the entire setglobalstate + setstealthmode
block is bypassed (`scripts/hardening.sh:86-88`). If stealth mode was off before running
`make harden`, it remains off. The script logs "Firewall already enabled" with no
indication that stealth mode was not evaluated. Documented in `08-harden-deep-dive.md §FM5`.
→ To close: split the stealth mode check out of the `if prev != "on"` branch; run it
independently of the global state check so stealth mode is always ensured when
`make harden` runs.

**make doctor --fix bare form (Make limitation).** `make doctor --fix` is interpreted
by Make as passing `--fix` as a Make option and produces `make: invalid option -- -`.
The documented canonical form is now `make doctor ARGS=--fix` (README was corrected as
part of CLAIM-06 fix; Makefile now has `$(ARGS)` passthrough). Fixing the bare form
would require MAKEFLAGS manipulation or `.RECIPEPREFIX` changes — marginal value.
Documented in `07-contract-verification.md CLAIM-06`.
→ To close: no-op unless the bare-form UX is specifically desired.

**F10 — dscl error silently discarded in mrk-status.** `exec.Command("dscl", ...)` at
`tools/mrk-status/main.go:240` discards its error return (`out, _ :=`). If `dscl`
fails (empty USER env, non-existent account, permissions), the checkShell group shows
"Login shell: (expected: /path/to/zsh)" with no diagnostic explaining what went wrong.
Documented in `06-go-audit.md F10`.
→ To close: capture the error and surface it in the warning text:
`fmt.Sprintf("dscl failed: %v", err)`. Two-line change.

**B7 — coreutils provides g-prefixed GNU tools without PATH change.** `brew "coreutils"`
is installed, but Homebrew places the GNU tools under `g`-prefixed names (`gls`, `gsed`,
`gcat`). Transparent GNU tool replacement requires prepending the `gnubin` path to
`$PATH`, which the mrk dotfiles do not do. Whether this is intentional (GNU tools
available when needed via `gls` etc.) or an oversight is unresolved.
Documented in `05-brewfile-and-ruby.md B7`.
→ To close: if transparent GNU tools are desired, add the gnubin `$PATH` prepend to
`dotfiles/.zshrc`. If `g`-prefix access is sufficient, add a comment to the Brewfile.

**fix-exec Makefile target and scripts/fix-exec binary diverge.** The `make fix-exec`
target runs `find scripts/ bin/ -maxdepth 1 | chmod +x` (covers repo files only). The
`scripts/fix-exec` binary additionally runs `chmod +x ~/bin/mrk ~/bin/mrk-*` (also
fixes the symlinks installed by `make setup`). The two silently diverged; a user who
runs `make fix-exec` after a broken install will not have `~/bin` symlinks repaired.
Documented in `03-shell-hygiene.md L5` and `04-makefile-audit.md L5`.
→ To close: either have the Makefile target call `scripts/fix-exec`, or expand the
Makefile target to also cover `~/bin/mrk*` symlinks and remove `scripts/fix-exec`.

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
