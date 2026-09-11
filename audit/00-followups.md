# Followups

This file indexes every deferred item, known limitation, and explicitly-out-of-scope
finding from the mrk audit (modules 1–14, six fix sessions, runtime verification).
It is not a punch list of unfixed bugs — most items here were explicitly chosen to defer,
accept as a known limitation, or scope out. The value of the file is that "what's still
open?" has a single answer without grepping the whole audit directory.

For each item: what it is, where it's documented, why it was deferred, what action
would close it.

**Last re-verified:** 2026-09-09 against `605ff9f` by module 14
(`14-audit-2026-09-09.md`), which found nine items, fixed eight, and withdrew one of its own as
a false finding. It left nothing open. Its durable result is methodological: **half its
findings were only reachable by running the code.** P-5, P-6 and P-8 live in the exit
status or failure path of an operation that otherwise succeeds and says so, which is why
fourteen prior cycles of reading never found them. Module 14 added no new open items.

**Previously re-verified:** 2026-08-31 against `15c82c9`. The 2026-08-31 recursive pass
(`13-audit-2026-08-31.md`) found and fixed 14 defects, three of them HIGH, none of which
any tool reported — `ci-check`, `shellcheck`, `go vet`, `gofmt` and `bash -n` were all
green beforehand. Two sat in the key-transfer path: `restore-keys` rejected every valid
archive on a cold gpg-agent, and stranded `~/.gnupg` when the archive did not hold it.

Every item this file previously carried as open was re-checked on 2026-08-31 and all
still stand as written — one deferred decision, three known limitations and five
out-of-scope items. Module 13 added no new open items: all 14 of its findings were fixed
in the same pass, so this ledger is unchanged apart from the line reference corrected
below.

---

## Blocking

None. N-1 is fixed — see Closed below.

---

## Deferred decisions

Items that require a real choice before they can be closed in either direction.

**Tests 1C, 2, 3, and 4 — UNBLOCKED: the plan now exists; the tests have not run.**
`audit/10-test-plan.md` is written and committed. It specifies Test 1C (combined
`make defaults` + `make harden` rollback), Test 2 (idempotency), Test 3
(order-independence) and Test 4 (re-entry recovery), each with its VM setup, a shared
state-capture method derived from the module-02 write set, a procedure, an expected
result and explicit pass/fail criteria. Expectations are derived from the scripts as they
stand after the N-1/N-2/N-3 fixes.

The two broken cross-references are fixed: `11-test-results.md:3,264` pointed at
`docs/audit/10-test-plan.md` and now point at `audit/10-test-plan.md`. The
`syncall-removal.md:67-78` pointer named in the previous version of this entry was
**wrong** — that table does not reference the test plan at all; it is a record of edits to
other audit modules, whose `docs/audit/` paths were correct when written. It carries a
dated path note instead of being rewritten.

**Two corrections to the earlier prediction, both from reading the current scripts.**
First, the predicted PARTIAL verdict for 1C does not apply at that test's scope: the ~40
uncovered browser and app-preference keys are written by `assets/browsers/` and
`assets/preferences/` from `scripts/post-install`, and neither `make defaults` nor
`make harden` invokes them, so those keys are never written during 1C. The uncovered-
rollback limitation belongs to a full-install rollback test, which does not exist and
would need its own ID. Second, `make harden` is not part of `make all`, so 1C must apply
it explicitly. Documented in `12-fresh-audit-2026-08.md N-19`.
→ To close: run the four tests per the plan —
`tart clone mrk-audit-clean-prepared mrk-test-N` — and record the results in
`11-test-results.md`. Tests 3 and 4 need more than one VM.

---

## Known limitations (documented, not blocking)

Items the audit identified that are real but classified as acceptable.

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
three tokens. A TODO comment documents this at `Makefile:140-141` (was `:145-146`, and `:124` before
that). No current ARGS values trigger the problem. Documented in `04-makefile-audit.md L1`.
→ To close: quote the expansion in each recipe: `@"$(SCRIPTS)/sync" "$(ARGS)"`. For
multi-flag use, a proper argument-splitting approach or documented workaround would
also help.

**make doctor --fix bare form (Make limitation).** `make doctor --fix` is interpreted
by Make as passing `--fix` as a Make option and produces `make: invalid option -- -`.
The documented canonical form is `make doctor ARGS=--fix` (Makefile has `$(ARGS)`
passthrough at `:121`). Fixing the bare form would require MAKEFLAGS manipulation or
`.RECIPEPREFIX` changes — marginal value. Documented in
`07-contract-verification.md CLAIM-06`.
The bare form had regressed into `docs/manual.md`; Phase B corrected it in `292485f`,
and BIN-1 §2.2 now states the limitation explicitly.
→ To close: no-op unless the bare-form UX is specifically desired.

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

**adventure-prologue L1, L2 and SC2015 — CLOSED by deletion, 2026-08-31.** The three
findings were all confined to `scripts/adventure-prologue`: unbraced `$10`/`$11`
positional parameters, a pair of overlapping `case` patterns that made one path
unreachable, and 33 `A && B || C` constructions used as if-then-else. None had
production impact, all were deferred as game-only, and the script has now been
removed along with adventure mode. Documented in `03-shell-hygiene.md L1-L3`, which
still describes code that no longer exists.

---

## Closed (for reference)

Items that were on the punch list and have been closed. Pointers to commits only;
the audit artifacts have the full detail.

### Closed by module 14, the 2026-09-09 full sweep

Seven defects fixed, `P-1`, `P-3`, `P-4`, `P-5`, `P-6`, `P-7`, `P-8`. Full detail, reproductions and
the sixteen verified-clean results in `14-audit-2026-09-09.md`. As with module 13, every
tool was green beforehand.

- **P-1 — `((x++))` under `set -e` aborted the run it was counting for.** A post-increment
  on a counter still at zero returns 1, and `set -e` ends the script. `--continue-on-error`
  therefore aborted on the first phase that failed. Twelve sites matched by grep; eight were
  harmless because the enclosing function is invoked in a condition, which suppresses
  `set -e` through its whole body. All twelve converted to `X=$(( X + 1 ))`, because the
  eight are safe only by virtue of a call site in another function. The twelve were all
  in `scripts/`. 35 more, in the six `assets/` app-defaults scripts, survived until 2026-09-11 —
  written `cmd || ((failed++))`, which looks guarded and is not: under bash 5 the command after
  the last `||` still trips `set -e`. See "The preferences round trip read abandoned containers" below.
- **P-3 — a failed firewall read was recorded as "was off".** `|| true` folded a failed
  read into the same value a successful read of a disabled firewall gives, so the rollback
  would have disabled a firewall that was on. Now tracked apart with `prev_absent`, the
  pattern the screensaver keys forty lines above already used.
- **P-4 — `mrk-status` reported all 127 Brewfile packages missing when `brew list` failed.**
  The error was swallowed and the lookup map left empty. `scripts/sync:190` guards the
  identical call and says why; `sync` got the fix because there the consequence was data
  loss rather than a false alarm.
- **P-5 — an EXIT trap ending on a false test failed a successful run.** `brew --dry-run`
  printed "No changes were made" and exited 1. `sync` and `sync-login-items` already ended
  every cleanup line with `|| true`; `brew` and `snapshot-keys` did not.
- **P-6 — `mrk-push` had no argument parsing.** `msg="${1:-}"` took every argument as a
  commit message, so `mrk-push --help` committed the working tree and pushed it. It did
  exactly that during the verification pass and needed an amend and a force-push to repair.
- **P-8 — `make defaults` failed on the same key every run.** Mail is sandboxed and its
  preferences domain does not exist until Mail is configured, so the write failed and every
  run ended "1 default(s) failed to apply" — a permanent warning is one nobody reads.
- **P-9 — eight more commands had P-6's shape, and two were destructive.** Added
  2026-09-10. Of 40 commands on `PATH`, eighteen did not answer `--help`; for eight of
  those the flag was silently discarded and the command *ran*. `mrk-uninstall --help`
  unlinked `~/bin` — the `[y/N]` there guards only the rollback, so the symlinks are
  already gone by the time it is reached — and `mrk-post-install --help` installed
  applications, because its `for _arg in "$@"` loop had no `*)` arm while
  `scripts/defaults.sh`, parsing in the identical shape three files over, always did.
  Fixed with `mrk_help_guard` in `scripts/lib.sh`; refusing the *unknown argument* is the
  half that generalises, since `--help` was only the flag that happened to get typed.
  `mrk-defaults` and `doctor` followed the same day for uniformity — and `doctor` proved to
  hold a third instance of the class that is not about a flag at all: `MODE="${1:-check}"`
  reads only `$1`, so `doctor check --fix` ran the check and discarded the `--fix` in
  silence. `nuke-mrk` and `check-updates` followed too. Both had been set aside as reachable
  only through a `[y/N]`; that holds for `nuke-mrk`, but `check-updates` writes its
  rate-limit stamp and disowns a background fetch *before* the prompt, and the fingerprint
  had called it clean only because it did not cover `~/.cache`. A third round then asked
  whether it was *verified* that nothing still drops arguments — it was not, and checking
  found three more: `mrk-menu`/`mrk-status` fell through to the TUI on any argument that was
  not exactly `--help`, the three `check`/`ci` gates accepted anything, and extra positionals
  were dropped by `mrk-push` (an unquoted commit message truncated to its first word) and
  `hide_tm.sh`. All closed. Of 40 entries on `PATH`, 38 answer `--help` and 38 refuse an
  unknown argument; `decloud` forwards to git by design and `lib` is a directory. The refusal
  exit codes were then unified on 2, which BIN-1's Section 0 had already been promising while
  twelve commands exited 1. **Exit 2 now means the command line was wrong and nothing ran;
  exit 1 means it ran and failed.** Unifying them surfaced a fourth dropped argument no flag
  census could see: `restore-keys:70` assigned `ARCHIVE="$1"` inside its loop, so
  `restore-keys a.gpg b.gpg` restored b and discarded a — on the one command that exists to
  recover a Developer ID Apple cannot reissue. The check that finds this class is a grep for
  `*)` arms that *assign* rather than refuse.
- **A BIN-1 claim contradicted the code, and sevmac had it right.** Found 2026-09-10 by spot
  checking BIN-1's factual claims rather than its flag lists. `checkBackups` returns
  `ok=false` when `~/.mrk/backups` is empty, so `mrk-status` shows **eight** checks, not the
  nine BIN-1 stated, with Backups appearing fifth only when a backup exists. SMAC-1 had been
  corrected earlier in the same session and BIN-1 was never read alongside it. `CLAUDE.md`
  now says the check runs both ways.
- **mrk-status's Security Hardening fix could never have worked.** Found 2026-09-10 by
  running `scripts/status` against an empty `HOME` and reading the remediation commands it
  printed. Both status tools said `run: hardening.sh` — a name that resolves nowhere: the
  script is installed on the PATH as `harden`, and the file is in `scripts/`, not the repo
  root that `mrk-status` runs fixes from. Pressing **f** on that check failed with "command
  not found". Every other fix was already a make target. Now `make harden`, with
  `TestEveryFixCommandResolves` gating the class: it drives each check into its remediation
  branch and asserts each fix is either a real Make target or resolvable on the PATH. The
  gate is mutation-tested against both failure modes. A fix command is only a string until
  someone presses the key, which is why fourteen audits never saw it.
- **The login-shell remediation could not work on the machine it is written for.** Found
  2026-09-10 by verifying the remaining suggestions that same empty-`HOME` report printed.
  All nine resolve as commands, but `chsh -s <homebrew zsh>` fails at runtime: `man chsh`
  says "the user may not change ... to a non-standard shell. Non-standard is defined as a
  shell not found in /etc/shells", and Homebrew only prints a caveat rather than registering
  its zsh. The sequence is a fresh machine's: `make setup` runs `phase_shell` *before*
  `make brew` installs Homebrew's zsh, so it sees `/bin/zsh`, matches, and skips; `brew` then
  installs the other zsh; `status` reports the mismatch and suggests the one command that
  cannot succeed. `setup`'s own `chsh` had the same problem when re-run after `brew`, hidden
  behind a bare `warn "chsh failed"` that never said why. `setup` now registers the shell
  first via `register_shell`, and `status` checks `/etc/shells` before suggesting `chsh`.
  `register_shell` uses `grep -qxF` rather than appending blindly — the machine's own
  `/etc/shells` lists `/bin/zsh` **three times**, which is what unguarded appends look like —
  and was tested through a `SHELLS_FILE` seam: idempotent over seven calls, exact-matching, so
  `zsh-beta` is not mistaken for `zsh`. It deliberately writes no rollback entry, because
  removing a shell that is still someone's login shell is how a user loses their terminal.
- **BIN-1 documented none of `mrk-setup`'s nine options.** Found 2026-09-10 by running every
  command's own `--help` and diffing the flags against BIN-1, which `CLAUDE.md` makes the single source of truth for flags. The entry read
  `mrk-setup [options]`, the word "options" with nothing behind it: the same shape as the
  `mrk-brew [options]` gap found earlier the same day, still present in its sibling. Also
  missing: `pushall --projects` and `--no-mrk`, `mrk-brew --no-casks`, `mrk-install --help`.
  All now documented; the reconciliation reports **zero** advertised flags undocumented.
  The reverse direction was also wrong and was mine: twelve usage texts said "takes no
  options" while accepting `-h`/`--help`. They now carry an Options block and say "no options
  other than --help".
- **Method note.** Static extraction was wrong on essentially every attempt in this session —
  an awk pattern that missed `while (("$#"))`, a `sed` alternation that errored and reported
  "missing: 0" from zero references, a `<li><code>` regex that captured only the first code
  span and so lost every long flag in a short/long pair, a binary check defeated by a lossy
  decode, and a `--`-only flag regex that mis-read Go's single-dash help output. Every genuine
  finding this session came from *running* something. Prefer it.

### Probed 2026-09-10 and found clean

Recorded so a later pass does not re-derive them. Each was *run*, not read.

- **Makefile.** All 37 targets `make -n` cleanly with no missing paths. `.PHONY` is complete
  in both directions, 37/37. `make help` lists exactly the 37 defined targets, no more and
  no fewer. `install` is a pure alias for `setup`, so the two remediation strings the status
  tools print are equivalent.
- **LaunchAgents.** Both plists: label matches filename, program path exists, both loaded,
  both last exited 0. SMAC-2's Table B-1 is exactly right, including the detail that
  `clear-app-caches` carries `RunAtLoad` and `clear-derived-data` does not.
- **Dotfiles, three implementations.** `scripts/setup`, `scripts/status` and Go
  `checkDotfiles` agree on the directory glob and on the same exclusion filter
  (`*.example`, `README*`, `*.md`). Both shell copies set `shopt -s dotglob nullglob` and
  unset it on every exit path, which they must: a bare `*` does not match dotfiles, and
  without it `make setup` would link only `Makefile`.
- **References and links.** All 34 repo-relative paths in `scripts/` and `bin/` resolve; the
  two that do not are a `mktemp` template and a `cp` destination. All 14 sevmac links into
  BIN-1 resolve against its 41 anchors.
- **`~/.mrk/defaults-rollback.sh`.** 130 lines, parses under both bash 3.2 and 5, no
  duplicate lines, and the `defaults import` target plist exists. 37 of its 38 domains are
  readable. The 38th is `com.apple.mail`, the P-8 leftover — and it is harmless twice over:
  the script sets no `set -e`, and that line already ends `>/dev/null 2>&1 || true`. No
  `set -e` is the right choice for an undo script; restoring what it can beats aborting
  halfway.
- **Still not verifiable here:** `harden` has never run on this machine, so
  `hardening-rollback.sh` has never existed, and `harden` has no `--dry-run`. It stays in the
  VM bucket with `setup`, `brew` and `post-install`.

### The secret scanner, tested rather than read (2026-09-10)

Module 14 recorded V-9 — the binary-plist blind spot is covered — from reading. It is now
tested. Against synthetic, non-functional material shaped like the real thing,
`scan_for_secrets` catches **11 of 11**: AWS, GitHub classic and fine-grained, OpenAI,
Anthropic, Slack, Google, a PEM header, a generic `api_key =`, a Bearer token, and the same
GitHub token hidden inside a **binary** plist that raw grep cannot see. It flags **0 of 6**
benign shapes — a commit SHA, Keka's `ExportPassword` as `<false/>`, iTerm's integer
`AiMaxTokens`, a base64 blob, a docs URL, and a `password_field_label` string. That is the
right answer in both directions.

One caveat about the test itself: the Google case first reported a MISS, which read as a real
blind spot. The pattern is `AIza[0-9A-Za-z_-]{35}` and the *test value* was 34 characters —
the measurement was wrong, not the scanner, for the ninth time this session and the first time
where the false finding would have been a security one.

**The real find: the scanner flagged one tracked file, and had done for as long as the file
existed.** A comment in `scripts/snapshot-prefs` explaining Calibre false positives quoted an
example assignment verbatim, so the file tripped the gate on every push that staged it — the
exact failure `scan_for_secrets` guards against elsewhere, where it declines to flag Keka's
`ExportPassword` because "flagging those trains the user to dismiss the gate". Reworded to
describe the shape rather than paste the literal.

`ci-check` now runs the scan over every **tracked** file, not just staged ones, which is what
let a permanent false positive persist. The gate refuses to pass vacuously on an empty file
list, and is mutation-tested both ways: restoring the comment fails it, and a planted AWS key
in the Brewfile fails it.

### Missing-dependency degradation (2026-09-10)

Probed by hiding a tool's directory from `PATH` and running the command. Most of what the
scripts call unguarded is a macOS built-in that is always present — `dscl`, `chsh`, `plutil`,
`osascript`, `launchctl` — and `jq` and `gnupg` are both in the Brewfile, so post-install has
them by the time it runs. `gh` is handled well everywhere: `prune-deployments` and `maintain`
via `require_cmd gh || exit 1`, `mrk-push` with its own check and an install hint.

**The one gap: `ci-check` did not check for `go`.** With go hidden it died at line 91 with a
bash-level `go: command not found` and rc 127. Its sibling `bin/build-tools` has always had
`require_cmd go make || exit 1`, so this was one-of-a-pair again. It now fails with a clear
message and an install hint.

Deliberately **not** made to mirror the `shellcheck` warn-and-skip six lines above it.
shellcheck is optional because its absence removes a lint; skipping `go test` would remove the
tests while still printing "All checks passed" — the same shape that hid the picker tests for
four days on 2026-09-05. A gate that cannot run its tests must fail, not skip.

Also considered and deliberately left alone: `require_cmd` exists in `bin/lib/common.sh` and
has no equivalent in `scripts/lib.sh`. That looks like the one-of-a-pair class but is not
worth closing — exactly one script under `scripts/` does an inline tool check
(`restore-repos:59`), so a shared helper there would have a single caller.

### The rollback init guard could empty the undo button (2026-09-10)

Entry point: shared mutable state and who writes it. There is **no locking anywhere in mrk**
— the only `.lock` in the tree is a tar exclude — but that turns out not to matter much: the
install phases run in sequence, and the appends to `$ROLLBACK` are single `echo`s. The real
hazard in this area is not concurrency, it is truncation.

`~/.mrk/defaults-rollback.sh` is written by two scripts, and both decided whether to
**overwrite** it by asking whether the file contained a line matching exactly
`^#!/usr/bin/env bash$`. Lifting that guard into a harness and driving it through six file
shapes showed two silent data-loss cases: a shebang retyped as `#!/bin/bash`, and a shebang
carrying a trailing space, each truncating a file of real entries down to one line. A third
case was unsound the other way — a shebang appearing anywhere *below* line 1 was accepted,
because the check grepped the whole file.

Neither loss case is reachable through mrk's own history: `git log -p` over both writers shows
it has only ever emitted `#!/usr/bin/env bash`, across eight variants of the surrounding code.
So this was a fragility, not an active bug — but on the one artifact whose loss is not
recoverable, sitting in a directory the user is told to run scripts from.

Now one shared `init_rollback` in `lib.sh`, called by both. It tests whether **line 1** begins
with `#!`, which accepts any shebang and tolerates trailing whitespace, and a file that still
fails is **moved aside**, never overwritten. Verified across all six shapes, with the
moved-aside copy checksum-identical to the original, and end-to-end: `make defaults` leaves
the live 130-line rollback byte-for-byte unchanged.

The duplication is what let one destructive edge case exist in two places, so the copy in
`post-install` — which carried a comment explaining that it was a copy — is gone.

### The Brewfile has five parsers and no two agree (2026-09-10)

Entry point: one data format, several independent readers. The Brewfile is parsed by
`tools/picker`, `tools/mrk-status`, `scripts/brew`, `scripts/sync` and `check-picker-desc`,
each with its own expression. Run over a file of legal-but-unusual lines they returned
**three different answers**, and Homebrew — the authority, via `brew bundle list` — returned a
fourth, higher than all of them:

| line | Homebrew | mrk |
|---|---|---|
| `brew "x"` | sees | all five see it |
| `brew  "x"` (two spaces) | sees | only `mrk-status` |
| `brew<TAB>"x"` | sees | `mrk-status`, `sync` |
| ` brew "x"` (indented) | sees | **none** |
| `brew 'x'` (single quotes) | sees | **none** |

A Brewfile is Ruby, so all five are valid to `brew bundle`. The consequence is not a
miscount: a package mrk cannot see is installed by `brew bundle` and then invisible to `sync`,
`mrk-status` and the picker — and `check-picker-desc` silently *exempts* it from needing a
description, reporting OK. The gate whose job is completeness had a hole shaped exactly like
its own parser.

Reachability, checked rather than assumed: the real Brewfile is 144 lines and **100% strict**,
and `sync` emits `printf 'brew "%s"\n'`, so mrk never writes one of these. Latent, like the
rollback shebang — but the Brewfile is a file the docs tell you to hand-edit, which is where
it would come from.

Fixed by making the harmed gate **fail closed** rather than teaching five parsers Ruby:
`check-picker-desc` now refuses a Brewfile containing any line it cannot parse, and says how
to rewrite it. Mutation-tested against all four shapes; comments and blank lines are skipped,
and a well-formed new cask still falls through to the description check rather than being
swallowed by the new one.

Left alone deliberately: the five expressions still differ. With the gate guaranteeing the
input shape the difference is unreachable, and rewriting four of them to match a fifth is
churn with no behaviour change.

### "Defaults applied" is a true claim (2026-09-10)

Entry point: the ledger's recurring **overstated success** class, aimed at the biggest claim
mrk makes about the machine. `make defaults` prints "✓ Defaults applied"; nobody had ever
checked it. P-8 found one key failing *loudly* — the question was whether any fail *silently*,
where `defaults write` returns 0 and the value does not stick.

Every `write_default` call was extracted and read back with `defaults read`. Of 143 call
sites: 125 are fully literal, and **124 read back exactly what was written** — the 125th is
`com.apple.mail`, which is correctly logskipped rather than attempted since the P-8 fix. One
more uses `$HOME` (`com.apple.screencapture location`) and matches. The remaining 17 are the
opt-in trackpad block behind `if $WITH_TRACKPAD`, applied by `make trackpad`, not `make
defaults`. **126 of 126 applicable keys verified. Zero mismatches.** The claim is true.

`check-defaults-desc`'s handling of those 17 is sound too, and fail-closed: it resolves
`$domain` to the loop's first domain and the docs carry the mirror as `alsoDomains`. Verified
by extraction (it finds the real value, it is not silently using its hardcoded fallback) and
by mutation — reversing the loop order makes it report all 17 as undocumented.

**Method, and it is the point of this entry.** The measurement was wrong twice in this one
probe. First it reported **82 mismatches** — every one reading `wrote bool 'true', reads '1'`,
because the normaliser tested for `-bool` while the extracted token is `bool`. Then an awk
counter claimed 125 of 143 calls were inside the trackpad block, having matched the
`WITH_TRACKPAD` *variable declaration* and never reset. Eighty-two is a number that would have
read as a catastrophic finding. The rule that caught it is the same one every time: a
surprising result is the measurement until proven otherwise. The rewrite added a normaliser
self-check that must pass before any comparison runs.

### mrk-menu's command table (2026-09-10)

Entry point chosen for its prior: `mrk-status` was found carrying a fix command that resolved
nowhere and had never worked. `mrk-menu` is a *launcher* — every one of its 33 rows runs
something — and the same class had never been checked there.

Probed without running a single item, since one of them is `nuke-mrk`. All 33 targets resolve:
20 `cmdBin` against `~/bin`, 13 `cmdMake` against the Makefile. Every flag a row passes appears
in that command's own `--help`. Every one of the 33 labels is **literally** the command it
runs, so the menu cannot show one thing and do another. Repo-root resolution agrees across all
three tools that need it — `mrk-menu`, `mrk-status` and `update-full` all take `MRK_ROOT` and
fall back to `$HOME/mrk`. The single row carrying make arguments, `make doctor ARGS=--fix`,
still resolves to `scripts/doctor --fix` after the `$# > 1` refusal added earlier the same day,
verified in a sandbox `HOME`.

No defect. Four gates added instead, in `tools/mrk-menu/data_test.go`, each mutation-tested:
targets ship with mrk, make targets exist, **the label is the command**, and `nuke-mrk` is the
only item behind the typed confirmation — so adding a second destructive row forces a
deliberate decision rather than passing silently.

One design note worth keeping. The gates are **repo-relative, never PATH-relative**. CI runs
`scripts/ci-check` on a fresh macos-latest runner with no `make setup`, so `~/bin` holds no mrk
symlinks and an `exec.LookPath` check would fail there for entirely the wrong reason. Every
`cmdBin` target happens to be a literal filename under `bin/` or `scripts/`, which makes the
CI-safe question also the more meaningful one: does this command ship with mrk?

### The dotfiles' own content (2026-09-10)

Entry point: the most-executed code in the repo — `.aliases`, `.zshrc`, `.zprofile` and
`.zshenv` run on every interactive shell — and the ledger already records a bug of this shape,
`~/bin/adventure-prologue` outliving `scripts/adventure-prologue`.

**Found: `alias nano='nano --linenumbers'` was the one unguarded tool-dependent alias.**
`--linenumbers` is a GNU nano option. The nano macOS ships at `/usr/bin/nano` is **UW PICO
5.09**, whose own option list has no such flag — confirmed by running `nano -h` and grepping
it: zero matches. PICO does not reject the flag, it just does something else with it.

The window is the familiar one. `.aliases` is linked by `make setup` (phase 1); GNU nano
arrives with `make brew` (phase 2). Between those two phases, and on any machine where the
Brewfile has not been applied, the alias was live and could not work.

What makes it a clean finding rather than a judgement call is that the file **already
establishes the convention**, and the template sits eleven lines above: `ls` is guarded by
`ls --version 2>/dev/null | grep -q GNU`, `cat` by `command -v bat`, `netcheck` by
`command -v networkQuality`, the brew aliases by `command -v brew`. Every tool-dependent alias
was guarded except this one. Now guarded in the file's own idiom, and mutation-tested both
ways: with only `/usr/bin` on `PATH` the alias is not defined; with GNU nano present it is.

Checked and clean in the same pass: the `dump` alias's `--file=~/Brewfile` — the tilde does
**not** survive the alias (verified in both zsh and bash, the literal string reaches the
command), but Homebrew expands it itself, so the file lands in `$HOME` as the comment says;
all seven oh-my-zsh plugins exist, five bundled and two cloned by `setup` at pinned versions;
and every other non-system command in the four files is guarded.

### MRK-1 rendered a blank page on any HTTP error (2026-09-10)

Entry point: the MRK-1 defaults page parses `scripts/defaults.sh` **at load time**, which makes
it a sixth independent parser of a mrk file — the pattern that produced the Brewfile finding.
`check-defaults-desc` compares its own shell parse against the JS `DEFAULT_DESCRIPTIONS` map;
nothing checked that the JS *parser* agreed with either.

It does. The live page renders exactly **143 `default-entry` elements**, matching the 143
`write_default` call sites and the gate's count, in 27 sections. Sixth parser, same answer.

**The defect is in how it loads.** `docs/defaults/script.js:1066` did
`fetch(url)` then `response.text()` with **no `response.ok` check**. `fetch` rejects only on a
network failure, so an HTTP error resolved normally and `parseScript` was handed the error
body. Driven through the real code path in a browser, `parseScript("404: Not Found")` yields
**0 sections and 0 entries** — a completely blank reference — and because nothing threw, the
`catch` never ran, so `loadDemoData()`, the fallback written for exactly this, could never
fire. Reachable in ordinary use: raw.githubusercontent.com rate-limits unauthenticated
requests, so this is not only a repo-moved scenario.

Fixed by throwing on `!response.ok`, and by saying so on screen. The demo set is one section
and two entries standing in for 27 and 143; rendered silently it looks like a real reference
that happens to be nearly empty, which is the overstated-success class again. Both paths now
show a red notice carrying the actual error, verified in a browser against a forced 404 and a
forced network rejection, with the normal path still rendering all 143.

**My first fix was wrong and testing caught it.** `showLoadFailure()` ran before
`loadDemoData()`, and `renderSections()` assigns `content.innerHTML`, so the notice was created
and then destroyed. The probe reported "blank page, old behaviour" — the fix looked like it had
not worked at all. Checking whether the patched code was even loaded, rather than assuming the
fix was wrong in principle, is what located it.

### sync added casks without the modifier every other cask has (2026-09-10)

Entry point: dry-run fidelity in `sync`, the daily driver that rewrites the Brewfile. That
question turned out to be untestable here — selection runs through the picker TUI, which needs
`/dev/tty`, so non-interactively nothing is ever selected and the dry run trivially matches.
The probe found something else on the way.

**`scripts/sync` composed new cask entries as a bare `cask "name"`.** 70 of the 71 casks in
this Brewfile carry `greedy: true`; the only one that does not, `gcloud-cli`, arrived in a
hand-written commit. `greedy: true` is *not* Homebrew's default — verified by running
`brew bundle dump` to a scratch file, which emitted 72 casks and **zero** greedy — so it is a
deliberate convention here, and neither of the two ways a cask can enter the Brewfile
maintained it.

It had already fired, twice. Both casks sync has ever added went in bare — `sync: add
softraid` and `sync: add nordpass` — each sitting directly between neighbours that had the
modifier, and `onyx` had to be repaired later by a bulk snapshot commit. Without `greedy: true`
`brew bundle` skips a cask when upgrading anything that sets `auto_updates` or
`version :latest`, so it quietly stops being upgraded by `make update` — the opposite of why
it was synced.

Fixed at the real write site, and the summary line above it now prints the same text it
writes. Verified by extracting sync's Python insertion block and driving it directly with a
synthetic insertions file: the entry lands as `cask "x", greedy: true`, alphabetically placed.

Two near-misses worth recording. The obvious-looking site, `sync:437`, builds the **temp
Brewfile handed to the picker**, not the real file; patching it would have changed nothing and
looked correct. And reading the history took three tries, because `git show` emits colour
escapes that defeat a `^[+-]` anchor even with `-c color.ui=false` — the same ANSI cause that
has now broken three separate measurements this session.

**`gcloud-cli` turned out to be the same oversight, and a live one.** It was left alone at
first as a possible deliberate exception. Checking rather than assuming settled it:

- It is marked `auto_updates`, which is the only condition under which `greedy: true` changes
  anything, so the omission is not inert.
- The convention is blanket, not selective: `kid3` and `mediainfo` do **not** auto-update and
  carry `greedy: true` anyway, where it is a harmless no-op. Every cask gets it.
- Homebrew's caveat for the cask is a PATH note only — nothing warns against brew-managed
  upgrades, so there is no gcloud-specific reason to exclude it.
- It arrived in a hand-written commit adding a formula and a cask together, which is exactly
  where copying `brew bundle dump`'s bare format is the natural slip.

The clinching evidence was current state: **583.0.0 installed against 584.0.0 available**,
with `brew outdated --cask` not listing it and `brew outdated --cask --greedy` listing it. The
one cask missing the modifier was a version behind and invisible to the upgrade path
`make update` uses. Now 71 of 71.

### Two TUIs rendered wider than the terminal (2026-09-10)

Entry point: the picker descriptions, checked for **accuracy** rather than the coverage
`check-picker-desc` already gates. All 127 compared against `brew desc`. Twenty-one share no
significant word with Homebrew's wording, and reading every one by hand: all accurate, several
better — `farrago` is "rapid-fire soundboard" against Homebrew's "Audio playback", `gum` adds
the mrk-specific "used as fallback package picker". No duplicates, none naming the wrong
package, no shape problems. The descriptions are clean.

The lead was the shape of that data rather than its content. `make check` prints
**`? mrk-theme [no test files]`** every run, and `theme.Truncate` is the shared helper all three
TUIs render through — **twelve call sites** — and is where F05 (byte-vs-rune truncation) lived.
Its contract turned out to be wrong at the edge: `Truncate(s, 0)` and `Truncate(s, -3)` both
returned `"…"`, one column **wider** than asked. Unreachable today because every caller clamps,
but several compute their budget by subtraction.

Driving each TUI's `View()` across a grid of terminal sizes then found two real overflows:

- **`mrk-picker`'s footer was 90 columns**, carrying the comment *"Kept under 80 columns: this
  wraps at the minimum supported width, and a wrapped footer costs a body line."* It did
  precisely what its comment said it was written to avoid — and because `lipgloss.JoinVertical`
  pads every line to the widest element, it inflated the whole frame to 90 at an 80-column
  terminal, ten trailing spaces on every row.
- **`mrk-status`'s footer was a fixed 76 columns** at every width, so any terminal under 76 got
  the same. Its header overflowed too — 42 columns at 40 — masked by the wider footer. The
  `gap < 1` clamp stops `strings.Repeat` panicking on a negative count and does nothing about
  the overflow.

`mrk-menu` was already correct: it truncates its help line to the width and prints an explicit
"Terminal too small" notice below its stated minimum. One-of-a-pair again, twice over.

Fixed by making both width-aware rather than hand-tuning strings. The picker truncates via
`theme.Truncate`, matching mrk-menu; mrk-status gained a `clampWidth` helper on lipgloss's
**ANSI-aware** `MaxWidth`, because these strings carry escape sequences and a rune-based cut
would corrupt the frame rather than shorten it. Both now render exactly to the terminal width
at 40, 60, 80 and 120 columns.

`Truncate` returns `""` for a non-positive width now, and the package has tests for the first
time: the full contract, a property sweep asserting the result never exceeds its budget across
−5..30, and a test pinning the known limitation that it counts runes rather than display
columns — fine for mrk's ASCII data, not for CJK. All three fixes are mutation-tested.

### The browser policies were never in effect (2026-09-10)

Entry point: the data files mrk ships and installs onto the system, where a malformed or
misplaced one fails silently. Everything validates — both policy JSONs parse, both LaunchAgent
plists lint, `topgrade.toml` parses, all six preference fragments pass `bash -n`. Valid is not
the same as correct.

**mrk installed Chrome and Brave managed policy as JSON under
`~/Library/Application Support/<browser>/policies/managed/`. That is the Linux mechanism.**
Chromium's own documentation is explicit: only Linux reads a `policies/managed` directory of
JSON files; macOS uses the preferences system, Windows uses the registry. Eleven policies,
several of them security-relevant — `HttpsOnlyMode: force_enabled`, `BlockThirdPartyCookies`,
`PasswordManagerEnabled: false`, `AutofillCreditCardEnabled: false` — none of them enforced.

The machine agreed before the documentation did. Chrome's `Local State` records
`enterprise_mdm_mac: 0` and a `policy` object holding nothing but `last_statistics_update`, and
none of the eleven policy names appears anywhere in Chrome's own state — only inside the JSON
files themselves. The files were installed 2026-09-02; Chrome has written its state as recently
as 2026-09-09. It has launched many times and recorded nothing.

The `_comment` inside both files asserted the opposite in detail: that Chromium reads them on
launch and that they would show a "Managed by your organization" indicator. Neither happens.

**Removed rather than reimplemented.** Making these work on macOS needs a *forced* preference,
which means an MDM configuration profile — out of scope for a personal bootstrap, and not
something a `defaults write` to the user domain can fake. Gone: both JSON files,
`install_browser_policy()` and its two call sites, and the claims in SMAC-1's phase table and
Browsers bullet.

`nuke-mrk`'s cleanup **stays**, against the first sketch of this change. Those files sit on any
machine that ran post-install before today, and removing the cleanup with the feature would
strand them there permanently. The two on this machine were deleted directly.

One loose end left deliberately: both browsers also carry a `mrk2-policy.json`, dated
2026-02-09, identical in content and left by the predecessor project the initial commit merged
from. It is equally inert. It is not mrk's file to delete unasked.

### GNU vs BSD tools, and a Brewfile section that had drifted (2026-09-10)

Entry point chosen from my own repeated failures this session: Homebrew's coreutils `gnubin`
sits early on `PATH`, so `stat`, `date`, `readlink`, `cp`, `mktemp`, `sort`, `head` and `tail`
are GNU here while `sed`, `xargs` and `awk` are BSD. **The environment is mixed**, and which
flavour a script sees depends on how it is invoked — a LaunchAgent gets no `.zprofile`, so it
gets BSD. The ledger already records this class being hit once, with `mktemp -t`.

**mrk is clean on it.** No script uses any of the flags that diverge — `stat -f`/`-c`,
`sed -i`, `date -v`/`-d`, `readlink -f`, `du -b`, `sort -V`, `grep -P`, `base64 -w`,
`find -printf`. Every `date` call is a portable format string, every `sort` is `-u` or `-r`,
and the symlink resolution loops walk `readlink` by hand rather than using `readlink -f`.
Verified by running rather than reading: all **38 commands** were driven with `gnubin` removed
from `PATH` and **none behaved differently**, and `sync --dry-run`, `prune-deployments
--dry-run` and `scripts/status` produced byte-identical output under both flavours.

**What the probe did find is in the Brewfile.** One of its five sections, "CLI Tools - General
Utilities & Power User Tools", was out of alphabetical order: `autoconf, flac, libpng,
python@3.14, unbound` sat between `cliclick` and `coreutils`. They arrived in two hand-written
commits, not from `sync`, so the insertion logic was not at fault — but it is the victim.
`sync` places a new entry before the first existing one that sorts after it, and in a
disordered run that is the wrong line: driving sync's own Python insertion block directly,
`coreutils-x` landed **between `autoconf` and `flac`**, ahead of the real `coreutils`. Disorder
makes each new insertion land wrong, and compounds.

The section is now sorted, with the `# GNU coreutils` note carried along with the `coreutils`
entry it belongs to. Verified as a pure reordering — the sorted multiset of lines is identical
before and after — with all five sections in order, counts unchanged at 56 formulae and 71
casks, and the same three insertions now landing correctly.

### sync --prune had half the guard its sibling has (2026-09-10)

Entry point: `sync-login-items`, a daily driver that reads system login items through
`osascript` and rewrites the `add_login_item` block inside `scripts/post-install`. It was the
subject of `576b22e`, "stop silent empty-list failures from corrupting diffs".

**That fix is intact, and now tested rather than assumed.** Driving it with a stub `osascript`
on `PATH`: an empty result aborts with "'You have zero login items' and 'the read failed' are
indistinguishable here", and a non-zero exit aborts surfacing the osascript stderr and pointing
at Privacy & Security → Automation. Both under `--dry-run`, which exits before any file work,
so a guard failure would have shown as a bad diff rather than a damaged repo. Also verified
that the Python block which locates `add_login_item` still finds it after today's edits to
`post-install` — 8 items, output byte-identical when nothing changes.

**The finding is in the sibling that comment holds up as its model.** `sync-login-items` guards
*both* a failed read and an empty one. `scripts/sync` guarded only the failure: it checks the
exit status of `brew list --formula` and `--cask`, and nothing else. But staleness is computed
as "in the Brewfile, absent from the installed set" (`sync:250`), so an empty installed set
marks **every** tracked entry stale — all 127 — and `--prune` offers to delete them. `brew list`
exits 0 and prints nothing when Homebrew has nothing installed: a fresh machine after Homebrew
but before `make brew`, or a half-migrated prefix.

Guarded now, on **both** lists rather than either: a machine with casks and no formulae is
unremarkable and aborting on that would be a false alarm; both empty is not. The check is
scoped to `--prune`, the only path exposed to it — adding packages from an empty set is a
no-op, not a hazard.

Mutation-tested with a stub `brew` whose `list` succeeds and prints nothing: `--prune` aborts,
plain `--dry-run` still reports normally, and the real paths are unchanged.

### The migration checklist skipped the login items (2026-09-10)

Entry point: the checklist `CLAUDE.md` exists because of. Its stated reason is that
`snapshot-keys` landed and SMAC-1's migration checklist did not mention it for two days —
following it would have lost a Developer ID Apple cannot reissue. So: does that checklist now
cover everything a wipe would destroy?

Enumerating mrk's capture tools against the checklist's steps, **`sync-login-items` was
missing**. Login items live in the system's LaunchServices database and reach
`scripts/post-install` only when that command runs, so anything added since the last run was
on the old machine and nowhere else — and Phase 3 on the new machine would restore the stale
list. Recoverable, unlike the signing key, but only if you can remember what was there, which
is what a checklist exists to spare you. Now step 4, between the Brewfile sync and the pending
commits. Exactly the shape `CLAUDE.md` was written about, in the same checklist.

The restore half turned out to be fine and I nearly reported it as a gap. The checklist's "On
the New Machine" section says only "do the New Machine Setup procedure", and `restore-keys`
does appear — inside Step 2, "Set Up SSH", which is the right place, since restoring the
archive is how SSH starts working. I had not read far enough.

**Two more, found by comparing both sevmac tables against the repo in both directions.**
Table 2.7-1 listed `make adventure`, removed from mrk by `846f0ba`; `make adventure` now
answers "No rule to make target". Every other target the page names does exist. And
`trim-services` appeared on **neither** page, despite being both a make target and a `~/bin`
command that disables background LaunchAgents and writes a rollback — the one command in
`~/bin` covered by no row in either table. Also corrected: `make check` no longer just runs
"shellcheck, picker descriptions, go test".

**Method note.** An edit anchor failed because I read the surrounding HTML through
`sed 's/^/  /'` and used the displayed indentation — 12 spaces — when the file has 10. That is
the second time today. Reading a file through a formatting pipe and then anchoring on what
came out is a reliable way to write a patch that cannot apply; take the bytes from `cat -A`
instead.

### nuke-mrk left every login item registered (2026-09-10)

Asked directly: should `nuke-mrk` offer more than it does? Answered by diffing what mrk
*creates* against what `nuke-mrk` *removes*, rather than by opinion.

`scripts/post-install` registers **eight** login items. `nuke-mrk` contained **zero**
references to login items, while handling every other post-install artifact: the LaunchAgents,
the topgrade symlink and its backup, the openjdk symlink, Barkeep, KeyVault, the browser policy
files, and the imported plists by way of the rollback offer. One-of-a-pair, again.

It matters for precisely the job the script exists to do. Its header says "Remove all mrk
artifacts for a fresh test install" — and after a nuke all eight were still registered, so the
re-test's `add_login_item` found each one, logged "Login item exists", and skipped. **The
registration path was never exercised by the fresh install meant to prove it.**

Now an offer in the existing `[y/N]` idiom, listing the items first. Three design points, each
tested: it reads the tracked list from `scripts/post-install` rather than hardcoding it, and
reads it **before** `$MRK_DIR` is trashed — the Barkeep and KeyVault offers further down
already run after the repo is gone, which is fine for them and would not be for this; it offers
only names that appear as `add_login_item` entries, so an item added by hand is never touched;
and a failed removal warns rather than aborting the run.

Verified without running `nuke-mrk` or touching a real login item: the block was extracted and
driven with a stub `osascript` recording what it was asked to delete. Answering no records zero
deletions; answering yes deletes exactly the tracked-and-present names and never the
hand-added one; a tracked item that is not registered is not offered; nothing matching means no
prompt at all; an unreadable `post-install` skips the offer; and a failing delete warns and
continues with rc 0. The machine's own eight login items were confirmed untouched afterwards.

**Reverted the same day, and the reversal is the finding.** Seven asked the obvious question I
had not: what is gained by removing them only to re-add them? Nothing — the end state is
identical. The only benefit is that the fresh-install test exercises `add_login_item`'s
registration branch rather than its "already exists" branch, which is narrow and does not need
a nuke: remove one item by hand and re-run post-install.

And it is not free. `add_login_item` creates with **`hidden:false` hardcoded** and **`at end`**,
so a remove-then-readd resets any item set to launch hidden and rebuilds the order as
post-install's rather than the user's. All eight happen to be `hidden=false` today, which makes
it lossless on this machine at this moment and says nothing about the next one.

The category was the real error. `nuke-mrk` does not uninstall Homebrew packages, so every
application those items point at survives the run: a login item is a preference about an
application that is staying, not an mrk artifact being cleaned up. That places it with the
macOS defaults — offered as a *rollback*, defaulting to no — and not with the symlinks and
LaunchAgents it sits beside. The symmetry argument that produced the change compared it against
the wrong siblings.

The reasoning now lives as a comment in `bin/nuke-mrk` where the code was, so the next person to
notice the asymmetry finds the answer instead of re-deriving it.

**Left for a decision:** `scripts/uninstall` has the same gap — zero login-item references —
though it does remove the LaunchAgents, so it is already broader than its "does not remove user
data" header suggests. Not widened unasked, and on the reasoning above it should probably stay
that way.

### dock-setup wiped the Dock with no way back (2026-09-10)

Asked, after the login-item reversal, whether anything else is not lossless. Answered by
listing every mutating script against whether it records an undo:

| script | rollback refs | backup refs |
|---|---|---|
| `hardening.sh` | 31 | 5 |
| `defaults.sh` | 17 | 11 |
| `setup` | 12 | 16 |
| `post-install` | 12 | 15 |
| `trim-services` | 7 | 0 |
| **`dock-setup`** | **0** | **0** |

`dock-setup` runs `dockutil --remove all` and recorded nothing. The gap was sharpest inside the
rollback file itself, which already carried seven `com.apple.dock` keys — `tilesize`,
`orientation`, `mineffect`, `no-bouncing`, `show-recents` — so mrk could undo the Dock's **icon
size** but not **which icons were in it**. Thirteen apps and one folder, gone with no snapshot.

Unlike the login items this was fixed rather than removed, and the difference is the point.
Removing login items from `nuke-mrk` bought nothing, because the reinstall re-added them.
`dock-setup` has a purpose you opt into by running `make dock`; being lossy is not a reason to
delete it, it is a reason to make it record an undo like every sibling.

It now exports `com.apple.dock` to `~/.mrk/plist-backups/` and appends a `defaults import` plus
`killall Dock` to the shared rollback — the pattern `post-install` already uses for plists,
with two deliberate differences. No `defaults delete` branch, because `com.apple.dock` always
exists so "there was nothing here before" is never its right undo. And the snapshot is written
**once and never refreshed**: a second `make dock` would otherwise capture the layout it had
just applied and overwrite the original with it, which is the re-run decay recorded as M2.

**Testing found a bug in the helper, not the new code.** `init_rollback`, added earlier the
same day, fails when its directory does not exist — it writes the file with a redirect and
never created the parent. Both original callers happened to `mkdir -p` their state dir first,
so it was invisible; the new caller does not, and neither would `make dock` as the first mrk
command on a fresh machine. Fixed in `lib.sh`, where producing a usable rollback file is the
function's job.

Verified without running `dock-setup`: the block was driven in isolation against a redirected
`STATE_DIR`. First run captures 13 `persistent-apps` and 1 `persistent-others` and writes the
rollback; second and third runs skip with the snapshot byte-identical and the rollback not
growing; a failing `defaults export` warns, leaves no file and writes no rollback line. The
round trip was proved on a throwaway domain — export, import elsewhere, compare — coming back
with identical order, labels and whole dict, so the rollback restores rather than merely
describes. The live Dock stayed at 13 items throughout.

Checked and genuinely lossless: plist imports (`backup_plist` before every `defaults import`,
with the matching rollback line), the app-support restore (skips existing outright — "won't
overwrite"), the dotfiles (replaced files copied to `~/.mrk/backups/`), and the login window
message. Two deliberate no-undo cases stand: the login items above, and the login shell, where
reverting `chsh` could strand the user in a shell they did not choose.

### App Store apps: the ecosystem already covered a gap mrk declared manual (2026-09-10)

Asked whether any existing project covers mrk's gaps. Its own migration checklist names four
things it does not capture: App Store applications, software licences, VPN/certificate/system
settings, and notarytool credentials. Three have no general answer — licences vary by vendor,
VPN and TCC need an MDM configuration profile, and a notarytool keychain profile genuinely has
no export. **The first one did.**

`brew bundle` supports `--mas` natively; App Store apps are a first-class Brewfile entry. mrk
already runs `brew bundle` and had **22 App Store applications installed** — Final Cut Pro,
Logic Pro, Xcode, Compressor, Pixelmator Pro among them — while the checklist said "you must
manually install these again from your Purchases". Two of the 22, BetterSnapTool and Chrono
Plus, are in the eight login items post-install registers: mrk registered login items for
applications it could not install.

Now tracked, all 22, plus `brew "mas"` itself. Three things had to be worked out by testing
rather than reading, and each would have produced a wrong result:

- **`mas list` returns nothing here.** mas 7 reads the App Store id from Spotlight's
  `kMDItemAppStoreAdamID`, and `mdutil -s /` reports indexing disabled on this machine — not
  mrk's doing, it never touches Spotlight. So `brew bundle dump --mas` produces an empty file
  and the obvious way to build the list does not work. `mas search`, `mas info` and
  `mas install` query the App Store API instead, so the entries still install; only
  regenerating them is blocked.
- **Name matching is not enough.** App Store display names carry marketing suffixes the bundle
  names do not — "Keynote" is listed as "Keynote: Design Presentations", "Speedtest" as
  "Speedtest by Ookla" — so exact-name matching resolved only 12 of 22.
- **Version matching caught a genuinely wrong id.** Comparing each installed
  `CFBundleShortVersionString` against `mas info` matched 18 of 22 outright, and of the four
  that did not, three were merely outdated installs. The fourth was real: the installed Hush is
  1.2.1 and "Hush Nag Blocker" is 1.0.19. The bundle id `ca.iansampson.Hush` settled it —
  "Hush | AI for Spoken Audio" by Ian Sampson, id 1664181766. Name matching alone would have
  written a free content blocker's id for an $89.99 audio tool.

One manual step remains and cannot be removed: `mas` has had no `signin` since macOS 12, so
App Store.app must be signed into by hand once before the first `make brew`. That trades 22
manual reinstalls for one sign-in. `mas` also requests sudo on macOS 13+, since Apple made
`installd` root-only.

Verified: `brew bundle list --mas --file=Brewfile` returns all 22, `check-picker-desc` passes
at 128 packages — the `mas` entries correctly need no picker description, since it parses only
`brew` and `cask` — and the strict-form gate added earlier today already accepted `mas` lines.
`sync` does not see them either, so they are maintained by hand or by `dump`, not by the picker.

### A third manual, ungoverned (2026-09-10)

Entry point: mrk's own published documentation. `docs/index.html` is a 21-line redirect, and
`docs/manual.md` behind it is a 796-line manual nobody had looked at all day. It carried three
claims this day's work had falsified — Phase 3 "applies the Chrome and Brave managed policies",
"The App Store apps. Install them again from Purchases", and dock-setup "does not save your
current layout". **Two of those three sentences had been corrected in BIN-1 or SMAC-1 the same
afternoon and left standing here.**

The cause is governance, not the file. `CLAUDE.md` exists solely to stop documentation
drifting, opens with "sevmorris/sevmac documents this repository", and **never mentioned
`docs/manual.md`** — which duplicates SMAC-1 by section name: Overview, Command Reference,
Troubleshooting, "How to set up a new machine", "How to prepare for a new machine".

**Deleting it was the first instinct and was wrong.** Checking what depends on it changed the
answer: it is the README's first link, the Pages site redirects to it, and
`scripts/sync-login-items` **writes** to it, exiting 1 if it cannot find the sentence it
templates. Deleting it would have broken a daily-driver command. On that evidence manual.md is
the primary mrk manual and SMAC-1 the wider personal-systems guide that also covers mrk, so
deleting it would have discarded the primary for the secondary.

`CLAUDE.md` now opens with "three documents describe this repository, and none of them update
themselves", and carries a second table for manual.md alongside the sevmac one. The dependency
list is written into that section as well, so the next person to notice the duplication finds
out why deleting it is not the fix.

### update-full would have quit the session running it (2026-09-10)

Entry point: `bin/update-full`, the most destructive daily driver — it quits every running
application and can reboot. Its header promises it keeps "the terminal you are running in".

It identified that terminal from `TERM_PROGRAM`, mapping four values and falling through to an
empty string for everything else. An empty `CURRENT_TERM` adds nothing to `KEEP`, and the quit
loop's only other filter is whether a matching `.app` exists in `/Applications`,
`/System/Applications` or `~/Applications`.

**From a Claude Code session `TERM_PROGRAM` is unset.** Process `Claude`,
`/Applications/Claude.app` present, nothing in `KEEP` — so update-full would have quit the
session running it, at step 2 of 8, having already quit every other application and before any
update ran. Not hypothetical: that is the shell this repository's maintenance has been run from
all day. The same hole is open for WezTerm, kitty and Alacritty, none of which `TERM_PROGRAM`
covers.

Fixed by walking the process tree instead of consulting an environment variable the host may
never set. Two rounds, both caught by testing rather than reading:

- The first version returned the **first** bundle in the ancestry and stopped. From this
  session that is `claude-code/…/claude.app`, whose basename is `claude` — while the process
  at risk is `Claude`, and `KEEP` is case-sensitive. It would have changed nothing.
- The real ancestry is three deep: the nested helper, then
  `/Applications/Claude.app/Contents/Helpers/…`, then
  `/Applications/Claude.app/Contents/MacOS/Claude`. The one that matters is **last**. It now
  collects every bundle in the chain, so both `claude` and `Claude` are kept.

Verified: detection returns both names, `KEEP` protects both, an ordinary application (`Safari`)
is still correctly quit, `--help` exits 0, `--bogus` exits 2, and running it with no TTY and no
`--yes` still refuses. 81 processes still running afterwards; nothing was quit during the
probe.

### snapshot-keys / restore-keys: clean (2026-09-10)

Entry point: the path with no second chance, deferred all day because it is the one where a
mistake is unrecoverable. Nothing found. Recorded because "we checked and it is correct" is
worth more here than anywhere else in the repo.

**What snapshot-keys bundles was compared against the filesystem, not read.** `--dry-run`
builds the tar and lists it without writing, so the manifest could be diffed against
`find ~/.ssh ~/.gnupg`. 36 entries bundled, 42 present, and the six absent are exactly right:
two `S.gpg-agent.*` sockets and four stale `.#lk*` lock files. Everything gpg actually needs is
in: `private-keys-v1.d`, `trustdb.gpg`, `pubring.kbx`, `gpg-agent.conf`, `openpgp-revocs.d`,
and on the ssh side eight `id_*` entries, `known_hosts`, `config` and `authorized_keys`.

**restore-keys' permission correction was driven from a hostile starting state** — every
directory 777, private keys 666, in a sandbox `HOME`. All eight cases come out right, including
the one that is easy to get backwards: `id_ed25519.pub` started at 600 and was correctly
*widened* to 644, not narrowed. It also kills `gpg-agent` afterwards, so imported secret keys
are visible without a logout — a subtlety that would otherwise present as "the restore did not
work".

Still untestable, as recorded before: the `.p12` signing-identity round trip needs GUI keychain
prompts, and a VM does not help because it has no Developer ID to export.

Two observations rather than defects. `~/.gnupg` carries six stale `.#lk*` lock files naming
**three previous machines** — inert, correctly excluded from the bundle, and not deleted here
because that directory is not mine to tidy. And `stat -f` was hit for the **third** time today,
in a session where the trap is written into this very file; the fix each time is `ls -l`.

**P-2 was withdrawn as a false finding** and deliberately kept in the module rather than
deleted: it records that `clear-app-caches`, `clear-derived-data`, `clean-ds` and `decloud`
were examined and are correct, which a deleted entry would not say. It was re-flagging
module 13's P-10, missed because detection used `head -5` and the `set -` lines sit at 7,
8, 15 and 25.

### The commit gates, driven rather than read (2026-09-10)

Entry point: `bin/pushall`, which commits and pushes every repository in `~/Projects`, so a
defect in it multiplies across all fifteen of them and mrk. Probed in a sandbox of repositories with local bare remotes;
the real `~/Projects` was only ever given `--dry-run`. What pushall got wrong, mrk-push and
snapshot-prefs got wrong too, because all three built their scan list the same way.

**1. The scan list let three kinds of file through unread.** All three gates listed files with
`git diff --cached --name-only --diff-filter=AM`, and `scan_for_secrets` skipped any path that
was not a regular file (`[[ -f "$file" ]] || continue`). A name git C-quotes
(`"caf\303\251.txt"`) is not a path, so it was skipped as clean; a staged rename is R and a
symlink replaced by a file is T, so neither was listed. Planted in the sandbox, all three secrets
reached their remotes through pushall, which reported "committed 0 file(s)" for two of them.
pushall's dry run *did* flag the renamed file — its dry run read unstaged changes, where the edit
shows as M — so a clean dry run was not a promise about the real run. snapshot-prefs is the
likeliest trigger: `git add -A` stages a plist whose name changed as R069, and the old list for
that case was empty, which skipped the gate entirely.

**2. mrk-push scanned nothing when run from a subdirectory.** `--name-only` answers relative to
the top level; mrk-push has no `cd`; the scanner resolved each path from the current directory.
In a clone of mrk with a planted secret in `docs/manual.md`, `mrk-push --dry-run` from the root
caught it and exited 1; from `docs/` it printed "Would commit 2 file(s) … Would push to origin."
and exited 0. This one needs nothing unusual — only a shell that is not at the repo root.

**3. mrk-push dropped commits that only delete or rename.** It decided "is there anything to
commit" from the scan list, which holds no deleted file. In a clone pushing to a local bare:
`rm docs/STE-CONVERSION.md; mrk-push "test: delete only"` printed "Nothing to commit.", pushed,
exited 0, and left `D  docs/STE-CONVERSION.md` staged with the message discarded.

**4. An unfinished merge was concluded with its conflict markers and pushed.** `git add -u` marks
every conflicted file resolved, markers and all, and `git commit` then concludes the merge. In
the sandbox pushall did this to a mid-merge and a mid-cherry-pick repository and pushed
`<<<<<<< HEAD` to both remotes. mrk-push (`add -u`) and snapshot-prefs (`add -A`) have the same
shape. A conflicted `git stash pop` leaves unmerged files and no `*_HEAD`, so the guard also
tests the index.

**Live versus latent on this machine.** Zero C-quoted tracked paths in all fifteen repositories,
in mrk, and in `~/.mrk/preferences` (131 files); mrk's two historical rename commits are pure
R100, whose content was scanned under the old name; no repository is mid-operation. So nothing
has escaped through 1 or 4. Findings 2 and 3 need nothing unusual.

**Fixed** in `scripts/lib.sh`: `commit_paths` (:349) lists with `-z` and `--diff-filter=d` and
makes every path absolute; `git_in_progress` (:376) names a merge, rebase, cherry-pick, revert,
`git am`, bisect or unmerged index; `scan_for_secrets` now skips symlinks and directories (:239),
which commit no content, and **fails closed** on any other path it cannot read (:247), so the
next listing bug is loud. Callers: `bin/pushall:103,121-128`, `bin/mrk-push:136,168-191` (the
commit decision is now `git diff --cached --quiet`), `scripts/snapshot-prefs:96` (before any app
is quit) and `:471`. `scripts/ci-check:59` lists tracked files with `-z` as well.

**New gate: `scripts/check-commit-gates`**, run by ci-check and so by CI. It plants all of the
above in throwaway repositories — 32 assertions, about five seconds — and pairs every "was
refused" with a control that must be pushed, because a harness in which nothing is ever pushed
passes every refusal test. It also fails if pushall's dry run and real run disagree about what
they refuse. It is hermetic three ways: its own git configuration, `HOME` and working directory,
and pushall always gets both `--projects` and `--no-mrk`, so a regression in either flag cannot
reach `~/Projects` or mrk.

**Mutation-tested: 11 mutations, 10 caught, and the survivor was right to survive.** Dropping
`--no-renames` changed nothing, because `=d` already lists a rename by its new name; the flag was
removed rather than kept under a comment claiming it mattered. The relative-path mutation made
the point of finding 2 by accident: run from a directory that happened to hold a clean `a.txt`
and `b.txt`, the scanner read *those*, and two planted secrets were pushed. The check now `cd`s
into its temporary directory. Its first run also failed on a fixture trap — macOS's temporary
directory is `/var`, git reports `/private/var` — fixed by building the expectation from git's
own answer.

**5. Five options exited 1 on a missing value.** `${2:?…}` in `pushall --projects` and
`prune-deployments --repo/--keep/--environment` exits 1 with bash's own
`line 71: 2: --keep needs a number` and no usage — the exit-2 sweep this morning covered unknown
flags and missed this form. `snapshot-keys -o` exited 1 too, and `-o ""` fell through to the
Desktop default. prune-deployments also exited 1 for a `--keep` or `--repo` it could not use,
where `bin/maintain` already exits 2 for the identical `--keep` message. All now exit 2
(`bin/pushall:80`, `bin/prune-deployments:71,92,96`, `scripts/snapshot-keys:86`).

Smaller, fixed in passing: pushall's usage omitted `--no-mrk` and prune-deployments' omitted
`--environment`; snapshot-keys printed its usage to stdout on an error; BIN-1's Table 3.1-1 had
no row for `mrk_help_guard` or `init_rollback`, both added to lib.sh this morning — drift of my
own; BIN-1 numbering skipped 2.24 since `846f0ba` removed `adventure-prologue` on 2026-09-02, and
check-commit-gates now fills it; BIN-1 said only snapshot-prefs and mrk-push scan for secrets.

Verified on the real machine afterwards: `pushall --dry-run` over `~/Projects` reports fifteen
repositories up to date and mrk "would commit 7 file(s)", scan clean, exit 0; `make check` green.

Not acted on: ci-check's shellcheck step still lists scripts without `-z` — a lint, not a gate,
over names that are typed at a prompt. pushall's mrk pull discards git's error text, so a
divergent pull reports only "pull failed"; with `pull.rebase` and `pull.ff` unset, git 2.55
refuses before merging, so it fails safe. And mrk-status's Tools panel counts broken `~/bin`
links but not missing ones, so check-commit-gates has no link until the next `make setup` and
nothing says so.

### CI was red for nineteen pushes, and a gate written today was the cause (2026-09-10)

Found only because the commit-gate work above was the first change today whose CI run was
checked after the push. **Every CI run from `c924fdd` (17:26) to `6213a03` failed**, nineteen
in a row, on `TestEveryCmdBinTargetShipsWithMrk` in `tools/mrk-menu/data_test.go` — a test
added in `c924fdd` itself, whose own comment argued it was CI-safe: *"Every cmdBin target is a
literal filename under bin/ or scripts/."* mrk-status is not. It is a Go binary that
`make build-tools` writes into `bin/`, `.gitignore:61` keeps out of git, and the workflow builds
only after `ci-check`. On this machine the file exists, and `go test` answered "(cached)" on every
local `make check` since, so local was green all afternoon while every push was red.

Fixed by checking a built target against the Makefile rule that builds it — the
`$(call go-build,NAME,DIR)` line and `tools/DIR/main.go` — never against the file, so the answer
is the same on every checkout. Verified the only way that counts here: a fresh `git clone`
reproduced CI's exact failure at HEAD, passed with the fix, and failed again under two mutations
(the target renamed, and the Makefile rule pointed at a missing directory). The complete
`ci-check` then passed in that clone.

The CI run for the commit-gate work failed earlier still, at a second environment gap: the
`macos-latest` runner has only `/bin/bash` 3.2, and check-commit-gates — like pushall and
mrk-push, which it runs — needs bash 4 and found no Homebrew bash to re-exec into. The workflow
now installs `bash` beside `shellcheck`. Skipping the gate when bash is old was not an option:
that is the warn-and-skip shape rejected for `go` this morning, which hid the picker tests for
four days.

**Method, recorded so it is not relearned.** A gate that reads the working tree must be proven
in a fresh clone, where no build output or gitignored file can answer for it; and a push is not
finished until its CI run is. Both were skipped nineteen times today.

One more of the same kind, caught before it shipped anywhere that could run it: `commit_paths`
was first written with `declare -n`, a bash-4.3 nameref, in the library whose `confirm` comment
records that fourteen of its callers carry no bash-4 guard. Nothing on bash 3.2 calls it today,
so no test failed. It now fills the caller's array through `eval` on a validated name, with the
paths expanded as variables and never as code. Under `/bin/bash` 3.2 it lists ten hostile names
— `$(touch PWNED1)`, a backtick form, `semi;touch PWNED3`, quotes, a glob — and executes none.

### The repository manifest's round trip, and the checklist around it (2026-09-10)

Entry point: `snapshot_repos` in snapshot-prefs → `~/.mrk/preferences/repos.tsv` →
`restore-repos`. Module 14 confirmed the manifest *has* a replay path, and ran `restore-repos
--dry-run` inside a fingerprint; nobody had compared the manifest's contents with `~/Projects`,
driven a real restore, or asked what the round trip cannot carry.

**The manifest itself is right.** Regenerated read-only and diffed against the committed copy
(last written 2026-08-29): identical — fifteen work repositories and the DoublEnder overlay, names
with spaces included. `~/Projects` holds fifteen repositories, not the sixteen stated in the
entries above this morning; those counts are corrected in place.

**`restore-repos`, driven in a sandbox `HOME`** with a manifest built to hurt: a name with
spaces, a bad remote, a folder in the way, an already-cloned repo, a bare overlay, a line short
of its fields. It clones and skips correctly and leaves the colliding folder's contents alone.
Two defects: **it exited 0 after failing** — an unconditional `exit 0` after printing
"2 repo(s) had problems" — and **a malformed line vanished**, named nowhere in either run.
Now exit 1 (`scripts/restore-repos` end) and a warning with the line number.

**What the round trip cannot carry, measured on this machine.** Magic Backup Machine has 17
sources and none covers `~/Projects`, so the new machine gets `~/Projects` back from GitHub and
from nothing else — and the migration checklist had no step that pushes `~/Projects` at all
(step 5 pushed only mrk). Today that would lose:
- **Two commits that exist on no remote**, verified against `ls-remote` so the local view is
  current: sevmac `audit/sevmac` (`3c88fe1`, 2026-04-25, 670 lines of audit documents) and
  ClipHack `claude/trusting-borg-522b76` (`798519d`, a three-line `.gitignore` change in a Claude
  worktree). pushall would not have saved them either: it pushes only the current branch.
  Neither is mine to push or delete; both are reported to Seven.
- **Four folders that are not repositories**: FloppyLetters, Graphics assets, hacks-checklist,
  JustIn. Neither the manifest nor Magic Backup Machine carries them.
- **DoublEnder's two overlay secrets**, `DoublEnderCloud/doublender-10af32ff2d11.json` (the GCS
  service-account key) and `ingest.env`, refused by the overlay's pre-commit hook by design.
  DoublEnder's own setup doc says "restore from secure backup" without naming one. Whether
  KeyVault holds them is Seven's to check; the checklist now says to copy ignored credential files.
The overlay itself is fully pushed (`main` = `origin/main`) and tracks the other 38 files.

**Fixed**: pushall now names all of it — commits on other branches on no remote, stashes, and
non-repository folders — and says so again in its summary, without changing its exit status
(`bin/pushall` `report_local_only`). snapshot-prefs names the folders the manifest cannot record.
check-commit-gates covers the report in both modes (six assertions, 38 in all). Mutation-tested:
14 of 14 caught, after one real survivor — dropping `HEAD` from `--not --remotes HEAD` changed
nothing because no sandbox repo had an unpushed commit on its current branch, which is exactly
the case the exclusion exists for (without it, pushall calls its own next push "work it will not
push"). A fixture for it was added; the mutation is now caught.

**The two checklists had drifted in both directions**, the thing CLAUDE.md's "the check runs both
ways" exists to catch. SMAC-1 never mentioned KeyVault — manual.md has had "Export the KeyVault
vault" since `1fa38e8` on 2026-08-29, and the 2026-08-31 audit added snapshot-keys to SMAC-1 but
not this — so the published checklist would have lost the API keys and notes KeyVault holds,
and its new-machine walkthrough never imported them. manual.md lacked "Capture the login items",
which I added to SMAC-1 at 12:13 today and did not copy, and the Magic Backup Machine step. Both
are now the same ten steps in the same order, with step 7 "Push the project repositories".

**Stale since 2026-09-02** (`4429ebc`, when snapshot-prefs took over Helium, Descript, Waves
Central and MusicBrainz Picard from Magic Backup Machine): manual.md, SMAC-1 and the README said
14 plist apps where there are 18, and BIN-1 said 18 while listing 14 names. The README also said
`defaults.sh` holds "~77 keys"; it holds 143.

**Help went to stderr in five commands** — harden, restore-keys, restore-repos, snapshot-keys,
trim-services — so `restore-repos --help | less` showed nothing; this morning's `--help` sweep
checked exit codes, not streams. Now stdout, and a sweep of all 39 commands finds only
`mrk-picker` on stderr, which is right: its stdout is the selection `mrk-brew` captures with
`$(…)`. restore-keys with no archive exited 1 after checking for gpg; now 2, first.

**Two measurement errors, both caught before they became claims.** The "nothing changed" check
after that sweep used `find -newermt '-10 minutes'`; in this shell `find` is `bfs`, which rejects
that format, and `2>/dev/null` hid the error — an empty result that proved nothing. Redone with
an ISO timestamp and a control file that must appear: nothing changed. And a "core.bare and
core.worktree do not make sense" warning looked like a decloud defect; it came from my own
`--git-dir` calls without `--work-tree`, and `decloud status` is clean.

### Two repositories one folder down, and a claim Time Machine falsified (2026-09-10)

Follow-up to the entry above, from looking inside the four "non-repository" folders before
recommending a home for each. **Two of them are wrappers around repositories**:
`FloppyLetters/FloppyLetter2601` (origin `sevmorris/wp-sim-93`, 145 commits) and `JustIn/JustIn`
(origin `sevmorris/JustIn`, 18 commits). Both were fully pushed, but pushall and the manifest look
only at `~/Projects/*/`, so neither had ever been pushed by pushall or recorded for
`restore-repos` — a new machine would not have cloned them — and pushall's new report, shipped an
hour earlier, called both folders "not git repositories". (`FL2601`, Cypher's GitHub name, is a
coincidence: the two repos share no commit.)

**Fixed with one walk for both commands**: `project_repos` in `scripts/lib.sh` lists every repo
directly in `~/Projects` and every repo one level down in a folder that is not one, and names
what holds no repo. pushall sweeps that list and snapshot-prefs records the same list, so the two
cannot drift apart — two copies of the walk is the one-of-a-pair shape this repo keeps
producing. Never deeper, never inside a repository, and a linked worktree is skipped. Verified:
unit-tested under `/bin/bash` 3.2 against seven shapes and an empty and a missing root; pushall's
real dry run now sweeps both nested repos and names only Graphics assets and hacks-checklist;
the manifest snapshot-prefs would write differs from the committed one by exactly the two new
lines; `restore-repos` clones a nested path into a fresh and into an existing wrapper folder, and
skips both on a second run. check-commit-gates gains the cases (44 assertions); three mutations
of the walk are all caught. The committed manifest gains the two lines at the next
`snapshot-prefs` run; it was not run here, because it quits applications.

**Correction to the entry above.** It said a migration "would lose" what is not on GitHub, and
SMAC-1 and manual.md said such work "is gone". Time Machine is configured — a network
destination on the Raspberry Pi, `~/Projects` included, macOS's own schedule off
(`AutoBackup = 0`) and TimeMachineEditor's scheduler daemon installed in its place — so the
accurate claim is narrower: nothing in mrk restores from Time Machine, so such work comes back
only by hand, and only as of the last backup, whose date needs Full Disk Access to read. Both
checklists, SMAC-2, BIN-1 and the pushall comment now say that.

**Decisions taken by Seven the same evening**: the ClipHack worktree branch, whose change had
reached main as `6a15c71`, was deleted with its worktree; `audit/sevmac` was exported to a zip
(verified intact: three documents, 24,776 bytes) and then deleted rather than pushed, since
sevmac is public; KeyVault holds DoublEnder's two overlay secrets.

### The App Store entries never reached brew bundle (2026-09-10)

Entry point: the 22 `mas` entries added at 19:49 (`c56e4c2`), and the claim written into
manual.md, SMAC-1 and BIN-1 the same hour that "`make brew` reinstalls them" — traced through
every reader of the Brewfile rather than through `brew bundle` alone.

**`make brew` never installed one.** `scripts/brew` has two paths. The interactive one — every
`make brew` from a terminal — skipped every `mas` line, under a comment from the first commit
(`10e5f86`) reading "Mac App Store support removed due to reliability issues"; it did nothing
until this afternoon gave it 22 lines to skip. The `--yes`/no-terminal path passed the Brewfile
through whole, and that fails differently: Homebrew's bundle installs a `mas` entry by running
`mas install <id>` (`bundle/extensions/mac_app_store.rb`, the install and `mas get` fallback)
as the user, and `mas help install` in mas 7.0.0 says "Requires root privileges to install
apps". brew never runs as root.

**brew bundle cannot see them on this Mac either.** It decides what is installed from
`mas list` alone, and `mas list` reads Spotlight, which is off here: `brew bundle check`
reported **all 22 installed App Store apps missing** (32 unsatisfied in all; the other 10 were
cask and formula updates). `brew bundle dump` writes **0 of the 22** `mas` lines, so
`snapshot --brewfile`, which overwrites the Brewfile with a dump, would have dropped the whole
section — its warning named the comments and the `greedy` annotations, not this.

**Unaffected, and checked rather than assumed**: `sync` (its add path preserves lines it does
not parse; its prune path matches only `brew`/`cask`), `status` and mrk-status (only
`brew`/`cask` regexes), the picker (the same), and topgrade, whose config in
`assets/topgrade.toml` already disables its `mas` step.

**Fixed**: both bundle paths now leave the `mas` entries out, and every run — the dry run too —
ends by naming how many there are and the one command that installs them after an App Store
sign-in, `grep '^mas ' Brewfile | sed 's/.*id: //' | xargs sudo mas install`. The `--yes` path no
longer fails on them. `snapshot --brewfile` puts the section back from `Brewfile.bak` when a dump
holds no App Store entries but the Brewfile did. Corrected: the picker's description of `mas`,
BIN-1's mrk-brew entry (whose two `mas` notes had also been nested inside its options list),
BIN-1's snapshot entry, manual.md and SMAC-1.

Verified: the command's pipeline yields exactly the 22 ids, all numeric; the filtered Brewfile
keeps all 129 formula, cask and tap entries and `brew bundle list` parses it with no `mas`; the
dry run prints the note; the snapshot block, extracted and run against a real mas-less dump,
restores all 22 lines byte-identical, and leaves a Brewfile that has them unchanged. **Not
verified, and why**: a real `brew bundle` run, because it installs, and `resolve_homebrew`
hardcodes `/opt/homebrew/bin/brew`, so no stub on the PATH can intercept one; and
`sudo mas install` itself, which needs a sign-in, root and a download.

**Correction to "App Store apps: the ecosystem already covered a gap" above.** "mrk already
runs `brew bundle`" and "the entries still install" were never true of `make brew`, and its
"Verified" meant only that `brew bundle` could parse the entries. The gap it closed was the
*record* of which apps to reinstall; the reinstall is one manual command, not zero.

**A near-miss of my own.** To see mas's root error I ran `mas install 1`, an id that cannot
exist. Before failing, mas 7 found an App Store app missing from Spotlight and printed
"Indexing now". Indexing stayed disabled on both volumes and the app's
`kMDItemAppStoreAdamID` stayed null, so nothing changed; but an install command is not a probe,
and `mas help install` had already answered the question. Also hit again: GNU `stat -f`, for the
fourth time today, and zsh expanding a `======` divider as `=command`.

### The one installer that fetches code checked nothing (2026-09-10)

Entry point: `install_github_app` in `scripts/post-install`, the only place mrk downloads
executable code and puts it in `/Applications` — Barkeep and KeyVault, from their latest GitHub
releases, in Phase 3 of every new machine. Driven by a harness that loads the real function and
stubs `curl`, `hdiutil` and `cp`, so nothing was downloaded or mounted and `/Applications` was
never written, under `/bin/bash` 3.2 with `set -euo pipefail` as post-install runs.

- **No signature was ever checked.** It copied whatever the DMG held, then ran `xattr -cr` on
  it; `curl` sets no quarantine, so Gatekeeper never assessed it either. An unsigned app
  installed with a ✓. The real apps are Developer ID, team `T9RLNAXPWU`, pass
  `codesign --verify --deep --strict` and are accepted as notarized, so a check costs a
  legitimate release nothing.
- **The failure paths left their EXIT trap set**, so it fired again when post-install ended,
  with the function's locals gone: `tmp_mount: unbound variable`. A temp directory leaked too.
- **A DMG whose app is named differently** printed ✓ for a path that did not exist and was
  downloaded again on every run. Latent: both release scripts name the bundles correctly.
- **A copy that failed part-way was left in place**, and every later run skipped it as
  installed.
- **post-install exited 0 whatever had failed** — it ended on an `echo` — so `make all` printed
  "mrk installed successfully" after it, although mrk-setup and mrk-brew both exit 1.
- Stale beside it: post-install's `--help` still said it installs the managed browser policy
  files, removed at 18:54 today; a leftover comment line from the same removal; manual.md's
  fork list said `defaults.sh` writes 77 keys, not 143; SMAC-1's Phase 3 list named Barkeep and
  not KeyVault.

**Fixed**: `github_app_trusted` requires a full strict verify, the team in
`GITHUB_APP_TEAM_ID`, and a Gatekeeper accept, in the DMG and again after the copy. The app must
carry the name the skip test checks; `ditto` copies it to that exact path (on this Mac `cp` is
GNU coreutils); a partial copy is removed; every exit runs `_github_app_done`, which also clears
the trap; an API failure is no longer reported as "no DMG in the release". post-install exits 1
when any step failed. The fork instructions now mention `GITHUB_APP_TEAM_ID`, since it refuses
anyone else's apps.

Verified: the six harness cases (a genuine notarized app, a failed download, a misnamed app, a
failed copy, an unsigned app, and an app signed by another team — Stats, `RP2S87B72W`) against
the old code and the new; an interrupt mid-download under both, which cleans up either way, so
the mount-leak fix (H2) is intact; a GNU `cp -R` copy of KeyVault still verifies, so that risk
was latent; post-install uses no bash-4 syntax, so running under 3.2 on a new Mac is fine.
**Not verified**: a real download and install, which writes `/Applications`. The harness is
not in CI, because it borrows KeyVault.app and Stats.app from this Mac.

One measurement error: the first interrupt test sent SIGINT to a background job, which a
non-interactive shell starts with SIGINT ignored, and bash cannot trap a signal that was
ignored at startup. The run finished its install and "passed". Redone with TERM, which the same
trap covers.

### clear-app-caches cleared the wrong Chrome profile (2026-09-10)

Entry point: `bin/clear-app-caches`, the one destructive job that runs unattended — daily at
03:00 and at every load of its LaunchAgent. Module 14 examined only its shell options.
Measured against this Mac rather than read:

- **Chrome: only `Default` was cleared, and on this Mac it was empty.** Profiles 1, 4 and 10
  held **2.3 GB** of cache (Profile 10 alone 1.3 GB) that the job had never touched.
- **Helium: seven of its eight paths named folders Helium does not create.** Chromium keeps
  each profile's HTTP and code cache under `~/Library/Caches` and its GPU caches inside the
  profile folder; the script named Application Support paths and browser-level shader caches.
  Only its `~/Library/Caches` line had ever removed anything, and the per-profile
  `GPUCache`, `DawnGraphiteCache` and `DawnWebGPUCache` were never cleared.
- **Spotify (latent — not installed here): `PersistentCache` is not a cache.** It is
  Spotify's default offline-storage location, so the job would have deleted every downloaded
  playlist daily, against its own promise that "the caches rebuild on next launch".
- Chrome's "Media Cache" is a folder Chromium no longer creates.

**Fixed**: every Chrome profile's `Cache` and `Code Cache`; Helium's `~/Library/Caches` folder
plus each profile's GPU caches; Spotify's `~/Library/Caches` folder only. Verified in a
sandbox `HOME` built from the measured layout, including profile data, Slack's Local Storage
and a stand-in offline track that must survive: the old script fails 10 of 21 checks — the
per-profile GPU caches and three profiles' caches survive, and the offline track is deleted —
and the new one passes all 21. A `HOME` with none of the apps runs cleanly.

**Considered and left**: it does not wait for an application to quit, and a calendar job that
misses 03:00 during sleep runs at the next wake, when browsers are open. This Mac supplied the
evidence that this is tolerated: the agents were reloaded at 18:37, the job ran at load, and
Helium, running since 06:36, rebuilt its cache folder from that minute — created 18:37, all
5,845 files since, 464 MB by 22:05. The `runs = 1` in `launchctl print` looked at first like a
schedule that never fired; it is that reload resetting the counter.

### maintain and the TUI binaries: essentially clean (2026-09-10)

Entry point: whether today's Go fixes — mrk-status's fix command, the menus' argument
handling, the width clamps — reached the binaries actually run, and whether `maintain`'s
freshness step would say if they had not.

**They are deployed.** The reflog shows `~/mrk` freshly cloned at 18:37:05 today, and in the
same minute all 41 `~/bin` links, the three binaries and both LaunchAgent plists were rewritten
and the origin was switched back to SSH — a full reinstall, run outside this session, while
everything was already pushed. All three binaries postdate every source file. (The same
reinstall is what reset `clear_app_caches` to `runs = 1`, in the entry above.)

**The freshness check is sound.** It passes `~/bin/<name>`, a symlink, as the `-newer`
reference; macOS's `/usr/bin/find` follows it to the binary (tested: binary 10:00, source
11:00, link 12:00 — flagged as stale), and `make build-tools` recreates the link on every build
anyway. It also already compares the shared `tools/theme`, which all three import.

Fixed: it compared `.go` files only, so a dependency bump that changed just `go.mod`/`go.sum`
read as up to date — latent, since no commit has ever done that, and shown in a scratch clone
where the old step passed a bumped `go.mod` and the new one flags that tool alone. BIN-1
contradicted itself: its build-tools entry said "nothing warns you that one is older than its
source" while its maintain entry documents the step that does; SMAC-2 said the same. Both now
say nothing warns you *on its own*, and point at `make maintain`. The code comment said "all
four TUIs"; there are three, and `tools/theme` is a library.

### The preferences round trip read abandoned containers (2026-09-11)

Entry point: `pull-prefs`, which no probe had covered — and behind it the restore it feeds,
`post-install`'s imports, checked against where each app on this Mac actually keeps its
settings rather than against the code on either side. The two lists agree exactly (18 apps,
same ids, files and paths). What they disagree with is macOS.

**The measured rule.** Given a bare bundle id, `defaults` reads and writes the copy inside the
app's sandbox container whenever the container holds one, and `~/Library/Preferences` otherwise.
A sandboxed app's first launch *moves* `~/Library/Preferences/ID.plist` into its container.
Both were measured with an ad-hoc-signed sandboxed test app (`local.mrkprobe.sbx`), since doing
it to a real app would have overwritten its settings: imported before first launch, the value
reached the app through that move; imported after, it went into the container; a container that
existed but held no copy sent the import to `~/Library/Preferences`, where the app never saw it.
The path form (`defaults export ~/Library/Preferences/ID`) always reads that exact file.

- **snapshot-prefs saved stale copies of five of my own apps.** DoubleEnder, FilmStrip, JustIn,
  JustLoop and WaxOn each kept a container from an earlier sandboxed build; the installed builds
  are not sandboxed and write `~/Library/Preferences`, whose copies are the newer in every case.
  By id, `defaults export` read the containers. The repository held all five container copies:
  JustIn's one key (a window frame) where the live file has five, missing `justInDiag_*` and
  `justInWaveformPanelHeight`; WaxOn's one key, missing `WaxOnSettings`; FilmStrip's five `fs_*`
  keys from a build that no longer uses them. A new machine would have restored those.
- **post-install's "won't overwrite" check was blind to sandboxed apps.** It tested for
  `~/Library/Preferences/ID.plist`. Keka is sandboxed, so after its first launch that file does
  not exist: on this Mac, with Keka set up, the check found nothing, and a second run of
  `post-install` would have imported the snapshot over Keka's live settings — shown end to end on
  the test app, where the old `import_plist` printed "Imported" and replaced the live value and
  the new one skips. BIN-1's mrk-post-install entry promised it "never overwrites a live
  configuration".
- **An app with no domain was exported as an empty dict and pushed.** `defaults export` exits 0
  on an absent domain and writes `<dict/>` (`backup_plist` already knew). Installed-but-unset-up
  is BetterSnapTool's state on a new Mac: it comes from the App Store, installed by hand after
  `make all` has run `post-install`.
- **Nothing restored BetterSnapTool at all, or registered two login items.** `post-install`
  imports and registers only apps that are installed, and on SMAC-1's path (`make -C ~/mrk all`)
  it runs before the App Store command can be. BetterSnapTool's preferences and the BetterSnapTool
  and Chrono Plus login items were skipped and nothing said to run it again. README said that
  after Phase 1 "Phases 2 and 3 can run in either order" — written 2026-04-25 from module 7's
  finding that Phase 3 *degrades gracefully* without Phase 2, which is not the same thing: a Phase
  3 run first skips every preference, login item and app-settings script, and a later Phase 2
  never returns for them. README's Phase 3 row still listed "browser policies", removed 2026-09-10.
- **The help text, BIN-1, the manual and SMAC-1 said snapshot-prefs quits each app** "so the app
  flushes its preferences first". It never had: no version contains any quitting code. The
  sentence entered its usage text on 2026-09-10, and I repeated it in three documents and a code
  comment the same day. It also shaped behaviour: that session declined to run snapshot-prefs
  because "it quits apps". Quitting is not needed — a running test process's unsynchronised
  write was visible to `defaults export` within 1.5 s.
- **Ten empty ClipHack test domains had been saved.** `ScratchDefaults` names a suite per test
  process and accepts the leftovers by design; each is a 42-byte empty dict.
- **Latent, not live:** FL2601 is sandboxed, so its domain exists only in its container and the
  `~/Library/Preferences` glob never listed it — it holds only a window frame. `bin/snapshot`
  computed the right file (outside the container first) and then exported by id regardless; none
  of its ten apps has a stale container, so nothing it wrote was wrong.

**Fixed.** `prefs_source` in `lib.sh` (bash-3.2-clean) exports by path when the file outside the
container exists, and by id otherwise; `snapshot_plist` and `snapshot_own_apps` use it, skip a
domain `defaults read` cannot read (absent or empty), and the own-app group is listed with
`defaults domains`, which includes container-only domains without the script reading another
app's container itself. `post-install` asks `defaults read ID` whether the domain holds
anything. `bin/snapshot` exports the file it chose. `make brew`'s hint and `make all`'s summary
say to run `post-install` again after the App Store command. Verified: patched copies of the old
and new snapshot-prefs run against this Mac's real domains into scratch repositories — the five
now match the live files, FL2601 and SevmoPodcastLeveler are captured, the ten empties are not,
all 17 third-party plists and the app-support, config, fonts and manifest output are
byte-identical, and a saved copy survives an absent domain where the old run emptied it. The new
gate still imports on a fresh domain, with the `defaults delete` rollback line.

**The P-1 class survived in `assets/`: 35 sites.** Module 14's sweep converted twelve
`((x++))` sites, all in `scripts/`; the six app-defaults scripts in `assets/` each count with
`|| ((failed++))` under `set -euo pipefail` — a form that looks guarded and is not, because under
bash 5 the command after the last `||` still trips `set -e`. Under Homebrew's bash, which `apply_defaults` runs,
the first failed write returned 1 from zero and ended the script — measured against a failing
`defaults` stub: one write tried of 12, no summary. Under `/bin/bash` 3.2 the same line does not
exit. Safari is the realistic trigger: a terminal without Full Disk Access cannot write its
domain. Converted to `failed=$(( failed + 1 ))`, and each script now exits 1 after trying every
write if any failed, so the exit status `apply_defaults` branches on is unchanged in both the
failing and the clean case — only the abort is gone.

**Left for you:** the ten `io.github.sevmorris.ClipHack.tests.*.plist` files are still in
mrk-prefs' `sevmorris-apps/`; snapshot-prefs no longer adds them but does not delete what is
there. The test app left `~/Library/Containers/local.mrkprobe.sbx` holding only macOS's own
metadata file, which the system will not let a shell remove.

**Method.** Three measurements were wrong before they were right, each in a way that would have
produced a finding: a `plutil -extract` keypath split `com.apple.security.app-sandbox` on its
dots and called every app unsandboxed; zsh's unquoted `$ids` did not word-split and ran one
iteration; and a variable named `path` — which zsh ties to `PATH` — emptied the search path and
made every script "fail" with zero writes.

### Two status programs, each missing the other's fix (2026-09-11)

Entry point: `check-updates`, the one mrk script that runs — and can prompt — in every
interactive shell (`dotfiles/.zshrc:48`), and from there the health report it sits beside.

**check-updates: clean but for one latent line.** Driven in a real pty against sandbox repos
(`REPO_DIR` and `HOME` pointed at a scratch remote and clone) through nine cases — up to date,
behind with each answer, behind but not yet fetched, ahead, diverged, a second run in the same
week, no terminal — eight behave exactly as documented, including the designed one-week lag.
The ninth: with no `origin/HEAD`, `rev-parse --abbrev-ref origin/HEAD | cut` failed under
`pipefail`, `set -e` ended the script with 128, and the `${default_branch:-main}` fallback
on the next line was unreachable. It had written the week's timestamp first and dies before any
fetch that could restore the ref, so it would do this every week. A clone always has
`origin/HEAD` and git 2.55 recreates it on any fetch, so this Mac was never affected. Fixed
with `symbolic-ref --quiet … || true`. `rev-parse` itself could not be rescued with `|| true`:
it prints `origin/HEAD` to stdout even when it fails. Its background fetch cannot prompt on the
terminal here — the GitHub key authenticates under `BatchMode` — nor on a new Mac, where the
remote stays HTTPS until post-install has authenticated.

**The two status programs.** `status` in `~/bin` is the Go dashboard; `make status` runs
`scripts/status`, which setup deliberately links nowhere. On this healthy Mac they agree on all
eight checks. In the failure branches — the only place a fix matters — they did not:

- **The dashboard's Shell fix was a `chsh` that cannot work.** The 2026-09-10 fix that stopped
  suggesting `chsh -s <zsh>` for a zsh missing from `/etc/shells` (commit `001ab72`) changed
  `scripts/setup` and `scripts/status` only; the ledger said "`status` checks `/etc/shells`",
  and the `status` on the PATH is the one that did not. With an unlisted zsh first on PATH the
  dashboard's fix was `chsh -s <that zsh>` while `make status` said chsh would refuse it. Now
  both offer `make setup ARGS="--only shell"` — narrower than the `make setup` the shell twin
  had suggested, which re-applies every default.
- **`make status` still had P-4.** With `brew list` failing, it reported "0/128 installed, 128
  missing"; the dashboard, fixed 2026-09-09, said it could not check. Guarded the same way.
- **The dashboard's Tools fix could not fix anything.** For a broken `~/bin` link it offered
  `make setup`, on the stale reasoning that "fix-exec only chmods existing files; broken links
  need re-creation". A broken link points at a script that is gone, so nothing can re-create it;
  setup links only what exists. Run in a sandbox `HOME`: after setup's linking phase the
  dashboard still reported "1 broken" and offered the same fix again, having re-run all of
  Phase 1 in the process; `fix-exec` pruned the link in one run. Now `make fix-exec`, and the
  shell twin drops its "or make install". fix-exec's own help text and BIN-1 never said it
  deletes those links; both do now.
- **README and the manual said `make status` opens the dashboard.** It has run `scripts/status`
  since the first commit; the two rows were wrong from the day they were written (2026-03-10).
  SMAC-1 had it right, with a caution that the two are different programs.

Tests: `TestCheckShellOffersChshOnlyForAListedShell` drives the real check with a fake zsh first
on PATH and a fixture `/etc/shells` (a listed `-beta` sibling must not count), and
`TestToolsFixRepairsADeadLink` runs the Tools fix the way the **f** key does and requires the
check to pass afterwards — the existing gate only proved that a fix command *resolves*, which
`make setup` always did. Mutation-tested: restoring `make setup`, a bare `chsh`, a prefix
match and an untrimmed match each fail a test.

**Method.** Three more broken measurements, all caught before they were reported: `go test`
suppresses a passing test's output without `-v`, so the first Go probe printed nothing; a
`^  [A-Z]` filter silently dropped "macOS Defaults"; and the old `scripts/status`, run from the
scratchpad, resolved `REPO_ROOT` there and "differed" on every section.

### nuke-mrk trashed unpushed work, its own sync commit included (2026-09-11)

Entry point: `bin/nuke-mrk`, the most destructive command in the repo. The 2026-09-10 probe
looked only at the login items it leaves. Run end to end in a sandbox `HOME` — a fake GitHub
remote, `~/mrk` cloned from it, and the `/Applications` and `/Library` paths in a copy of the
script rewritten into the sandbox so no real app or system link was reachable — driven through
a pty.

- **An unpushed commit and an uncommitted edit went into the Trash with "✔ Nuked."** Nothing
  looked. The fresh clone the script prints as the next step (`git clone … ~/mrk`) had neither;
  both existed only in `~/.Trash/mrk`, which macOS can empty on its own after 30 days.
- **The pre-nuke snapshot's Brewfile half never reached GitHub.** It runs `make sync ARGS=-c`,
  and `sync -c` commits and does not push (`scripts/sync:888-889`); the commit then went to the
  Trash with the repository. `snapshot-prefs`, the other half, pushes.
- **`~/Projects/CLAUDE.md` survived, dangling.** post-install links it into `assets/`; the nuke
  removed only `~/bin` and top-of-`$HOME` links.
- **`snapshot-keys` and the manual said `make uninstall` deletes `~/mrk` and `~/.mrk`.** It
  never has: all seven versions of `scripts/uninstall` in the history leave both, and its own
  help says it removes "no user data … and not the repository itself". The manual contradicted
  itself (line 379 had it right). The refusal it justified is correct — nuke-mrk does trash both —
  only the reason overreached.

**Fixed.** A guard before the first deletion lists, per repository (`~/mrk` and
`~/.mrk/preferences`), uncommitted changes, commits on no remote with their subjects, and
stashes, and stops — exit 1, "nothing has been deleted" — unless answered `y`. The snapshot now
pushes the sync commit when it is the one commit waiting and touches only the Brewfile, so it
can never publish other work; anything else falls to the guard. The CLAUDE.md link and legacy
`~/.local/bin` links are removed. Six sandbox scenarios on the fixed script: decline stops with
everything intact; accept proceeds and removes the new links; a clean repo sees no extra prompt;
a lone sync commit is pushed; a sync commit on top of earlier local work is not, and the guard
names both; an uncommitted change in the prefs repo is caught — that one under `/bin/bash` 3.2.
With the "only commit waiting" condition mutated away, the fifth scenario publishes the
earlier work — so that condition is tested, not assumed.

**Checked and clean.** Moving into `~/.Trash` works without Full Disk Access — only *listing*
it is refused, and `[[ -e ]]` inside it still answers, so `trash_item`'s collision check holds
(tested with an empty probe file, removed afterwards). SMAC-1's "each has a preview or dry-run
mode" holds for all three commands it names: nuke-mrk lists what it will remove and update-full
summarises its steps before asking; prune-deployments has `--dry-run`.

**Portability, found while fixing.** The guard names each repository with `~`. bash 3.2 and 5.3
disagree about a literal tilde in a `${var/#pattern/~}` replacement — 3.2 needs `~`, 5.3
expands it back to the full path unless escaped, and escaping breaks 3.2 — so the replacement
comes from a variable, which neither expands. nuke-mrk runs under whichever bash `env` finds.

**Method.** One more zsh trap: `"$c:scripts/uninstall"` is zsh's `:s` substitution modifier on
`$c`, so a history loop printed "bad substitution" seven times and then its "(none listed =
never)" summary — a conclusion drawn from zero iterations. Re-run in bash.

### Closed by module 13, the 2026-08-31 recursive audit

Fourteen defects, `P-1`…`P-14`, found and fixed in one pass. Full detail, including the
reproductions, in `13-audit-2026-08-31.md`. None were reported by any tool: `ci-check`,
`shellcheck -x`, `go vet -all`, `gofmt -l` and `bash -n` were all green beforehand.

- **P-1 / P-4 — the gpg archive check was coupled to gpg's exit status.**
  `gpg --list-packets` prints the packet listing and then tries the session key anyway,
  exiting 2 when it cannot get the passphrase; under `set -o pipefail` that status won
  over a successful `grep`. `restore-keys` therefore rejected every valid archive on a
  cold gpg-agent — on a new machine, the only place it runs — and `snapshot-keys` passed
  only because the agent still cached the passphrase from the encryption seconds before.
  Both now capture the output before matching, and pass `--pinentry-mode error` so the
  check raises no dialog, which is what its comment had always claimed.
- **P-2 — `restore-keys` stranded `~/.gnupg`.** Both directories were moved aside, so an
  archive holding only `.ssh` left the machine with no live `~/.gnupg`. Anything the
  extract does not recreate is now put back.
- **P-3 / P-5 — deployment pruning deleted the live page.** `mrk-push` kept only the
  newest deployment, which right after a push is the pending one, so it deleted the
  successful deployment still serving the site — the same failure N-16 recorded for
  `--keep=0`. `bin/prune-deployments` already had the fix and it had never been
  back-ported. `mrk-push` now delegates to it; `maintain` got the protection inline to
  keep its confirmation step.
- **P-6 / P-7 — LaunchAgents.** `launchctl load` on an already-loaded label fails, so an
  edited plist silently kept the old definition until the next logout; the install now
  unloads first. Neither `nuke-mrk` nor `uninstall` removed the agents, leaving jobs
  firing against deleted symlinks; both now unload and delete them.
- **P-8 — bash-4 syntax without the re-exec guard** in `mrk-push`, `snapshot-prefs` and
  `lib.sh`. These fail at runtime, not parse time, which is why `bash -n` and shellcheck
  both passed. The two scripts gained the standard guard; `lib.sh` instead dropped to
  `tr`, because a shared library should not impose a bash version on its nine callers.
- **P-9 to P-14 — smaller items.** `maintain` checked for the removed `bf` binary; the
  two cache scripts ran unattended with no `set -u` or `HOME` guard; `README.md`
  documented `make bf`, which errors; BIN-1 was missing ten commands (a recurrence of
  N-7); `mrk-menu` offered `restore-keys`, which cannot take an argument from a menu;
  and `scripts/lib.sh` was executable despite documenting itself as sourced.

### Closed by the follow-up batch, branch `fix/audit-followups-batch`, 2026-08-14

Six ledger items, each with an adversarial reproduction run against the pre-fix
code for contrast.

- **N-9 — unpinned oh-my-zsh and zsh plugin clones** — `0593bb2`. Checking upstream
  split the item in two, with opposite answers. The two zsh-users plugins tag releases
  and `omz update` does not touch custom plugins, so an unpinned clone was
  nondeterministic on install day and then frozen forever — this machine had plugin code
  from 2023-09 and 2024-01 against an oh-my-zsh from 2025-11. They are now pinned to
  v0.7.1 and 0.8.0. oh-my-zsh is deliberately left unpinned and the reason is recorded
  at the clone: it publishes no tags, and `.zshrc` sets `zstyle ':omz:update' mode auto`,
  so it would leave any pin within days. Verified in a sandboxed HOME: correct tags, a
  re-run skips, a bad tag warns and continues, and the git detached-HEAD advice is
  suppressed. `docs/manual.md` records how to bump a plugin.

- **N-13 / N-14 — sync write-path hardening** — `f5d9e1f`. Both replace sites now go
  through `replace_brewfile()`, which refuses a zero-byte temp and chmods 644 before the
  swap. The python3 block also writes the source through unchanged when the insertions
  payload is empty, instead of exiting without producing `out_path`. Verified: empty
  payload writes 3694 bytes through; an empty temp is refused with the target unchanged;
  a 0600 temp lands as 0644 (a plain `mv` left 0600).
- **N-10 — maintain build-freshness ignored tools/theme** — `f0b55c3`. All four TUIs
  carry `replace mrk-theme => ../theme`, so a theme edit staled every binary while Step 4
  reported them current. The find now spans the tool's sources and `tools/theme`.
  Verified by touching `tools/theme/theme.go`: pre-fix all four said "up to date",
  post-fix all four said "source newer than binary".
- **N-15 / N-16 — deployment-pruning edges** — `9bc2416`. `bin/mrk-push` now scopes its
  deployment query to `?environment=github-pages`, matching `bin/maintain`; unscoped it
  would delete deployments in environments it does not own. `--keep` now requires at
  least 1, because 0 selected the live deployment and took the published page offline.
  Verified: `--keep=0`, `-1` and `abc` all rejected with exit 2; `1` and `10` accepted;
  scoped and unscoped queries return the same 10 deployments on this repo today.
- **N-5 — deleted config files persisted in mrk-prefs** — `087c5a2`. Staging listed
  files found on disk, and a list of existing files cannot express a deletion, so a
  dropped file stayed in HEAD and kept being pushed. Now uses pathspecs with
  `git add -A`, still never `git add .`; `:(glob)` keeps the plist pattern top-level as
  the old shell glob did. Verified on a git fixture simulating an uninstalled Calibre
  plugin: old logic staged nothing and the file stayed in HEAD; new logic staged
  `D config/calibre/plugins/dedrm.json` and the unrelated top-level plist stayed tracked.
- **N-11 — Calibre restore sentinel was a single file** — `e32629d`. `cp -R` overwrote
  every matching file when the sentinel was absent but the directory held others.
  Restore now requires an absent or empty directory. Verified across four states;
  in the part-initialised case the pre-fix version overwrote the live file with the
  backup copy and the fixed version preserves it. `docs/manual.md:240` described the old
  guard and was corrected in the same commit.

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

### Defaults-page prose split closed, branch `docs/ste-defaults-split`, 2026-08-07

- **Defaults-page prose split** — `8aec5fc`, `5084d9a`, `b76d741`, `b6e1daa`, `6a0e9cf`.
  This was the last item carried from the Phase B STE conversion, and the largest
  documentation item on the board. The 59 legacy `DEFAULT_DESCRIPTIONS` entries each mixed
  functional text with historical and editorial material in one paragraph; all 59 are now
  split, in five commits by subject area. Functional text stays in `description`, in STE;
  the historical aside moves to `background`, which renders in a block labelled as not-STE.
  `background` fields stand at 34 of 77 entries — the 3 original worked examples plus 31
  added here. An entry with no historical material did not get one.
  Verified across all 77 entries rather than per batch: `node --check` passes, the parser
  finds 77 entries, every entry has a description, no description contains a historical
  marker, no sentence exceeds 25 words, and no description uses a perfect, progressive or
  passive construction. `scripts/defaults.sh` was not touched, so the page still resolves
  77/77 keys with 0 orphans against the copy on `main` — no URL repoint was needed.
  This also closes the last "approximately" in the repository, which
  `docs/STE-CONVERSION.md` had named as the marker of what remained.
  Three judgement calls are recorded as deviations 9 to 11 in `docs/STE-CONVERSION.md`:
  a live caveat stays in `description` even when it names a macOS version; an editorial
  aside that restated the entry's own `why` was deleted rather than moved; and a citation
  shared by several entries is written once.
  With this closed, `docs/defaults/script.js` moves to Done in the per-file scope table,
  and the only STE work left is the optional, low-priority `README.md` and
  `docs/index.html`.

### N-17 closed in full, 2026-08-06

- **N-17 — `bash-completion@2` in the Brewfile (reopened B6)** — `5d9db62`. B6 removed it
  in `3fe44dd`; `43c4d55` reintroduced it. It is now removed again, and this time the
  removal holds.
  **N-17 named one entry but described a class:** a deliberate untrack can be silently
  re-added by a later sync, because "installed but not tracked" and "never tracked" are
  indistinguishable to the diff. The class had two halves and both closed first — see the
  two sections below — after which only the decision remained. Both ignore files now exist
  on this machine and are in use, which had never been true before: `~/.mrk/sync-ignore`
  holds `bash-completion@2` and `~/.mrk/login-items-ignore` holds `NordPass`.
  **What keeps the package out is the ignore entry, not transitivity.** The commit that
  removed it first said "transitive dep"; that was wrong and the message was corrected
  before it was pushed. `brew leaves --installed-on-request` lists `bash-completion@2`, and
  `brew uses --installed bash-completion@2` reports nothing, so Homebrew has it as an
  explicitly requested top-level formula that nothing pulls in. The package stays
  installed. Delete the `~/.mrk/sync-ignore` line and the next `make sync` re-offers it.
  That line is load-bearing, and this is the round-trip N-17 asked to have documented.

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
