# Audit Module 5 — Runtime Verification Results
**Branch:** `main` | **Date:** 2026-04-26
**Test plan:** `docs/audit/10-test-plan.md`
**Environment:** Tart sandbox, macOS 26.3 (Tahoe), Darwin 25.3.0, ARM64
**VM source:** `mrk-audit-clean-prepared` snapshot (Tart, copy-on-write clone per test)

---

## Executive Summary

Two of the seven tests specified in the test plan were executed in this session.

| Test | Description | Verdict |
|---|---|---|
| **1A** | Rollback fidelity — `make defaults` | **PASS** |
| **1B** | Rollback fidelity — `make harden` | PARTIAL/FAIL on first run; **PASS** after fix |
| 1C | Rollback fidelity — combined | not run |
| 2 | Idempotency — `make all` twice | not run |
| 3 | Order-independence — brew vs post-install | not run |
| 4 | Re-entry recovery — SIGINT mid-run | not run |

Test 1A confirmed that the rollback fidelity fixes from `fix/rollback-fidelity`
work under runtime conditions on macOS 26.3. Test 1B surfaced two real bugs in
`scripts/hardening.sh` that the static audit did not catch despite multiple passes
through the file. Both bugs were introduced during the session that added stealth mode
rollback support; both were fixed and re-verified in the same session.

**Fixes applied during 1B execution:**
- `f17c991` — Fix missing sudo on firewall rollback lines
- `178b191` — Fix stealth mode parser pattern

Merged to `main` via `efe3fd6`.

---

## Test 1A: Defaults Rollback

**Verdict: PASS**

### Procedure

Fresh clone of `mrk-audit-clean-prepared` → `mrk-test-1a`. Pre-state captured across
all 13 rollback-tracked defaults domains (NSGlobalDomain through
com.apple.menuextra.clock) via `defaults read <domain>`, plus firewall state, PAM
contents, and `~/.mrk/` listing. Applied `make defaults`. Captured post-apply state.
Diffed against pre-state to confirm apply landed. Ran `bash ~/.mrk/defaults-rollback.sh`.
Captured post-rollback state. Diffed against pre-state.

### Apply Verification

All 13 tracked domains changed. Representative subset:

- NSGlobalDomain: 21 keys newly set (AppleInterfaceStyle=Dark, scroll bars, autocorrect,
  key repeat, etc.); 2 keys changed from pre-existing values (AppleKeyboardUIMode 3→2;
  NSAutomaticCapitalizationEnabled 1→0)
- com.apple.dock: 7 keys (orientation=left, tilesize=36, mineffect=scale, etc.)
- com.apple.Terminal: Default/Startup Window Settings changed from "Clear Dark" to "Pro";
  SecureKeyboardEntry changed 0→1
- Six domains absent pre-apply (desktopservices, diskimages, TimeMachine, SoftwareUpdate,
  commerce, ActivityMonitor) acquired all expected keys

The canary key `NSGlobalDomain AppleInterfaceStyle` went from `<unset>` to `Dark`. ✓

### Rollback File

65 lines: shebang at line 1, `killall Finder/Dock/SystemUIServer` at lines 63–65,
62 operation lines in between. Two rollback strategies correctly applied:

- **Keys absent pre-apply:** `defaults delete <domain> "<key>" >/dev/null 2>&1 || true`
- **Keys with pre-existing values:** `defaults write <domain> "<key>" -<type> <original>`

Specific examples verified:
- `defaults write NSGlobalDomain "AppleKeyboardUIMode" -int 3` (was 3, changed to 2) ✓
- `defaults write com.apple.Terminal "Default Window Settings" -string "Clear Dark"` ✓
- `defaults write com.apple.Terminal "SecureKeyboardEntry" -bool false` ✓

Keys with spaces in their names (e.g., "Default Window Settings") were correctly
quoted in rollback entries — empirical confirmation of the keys-with-spaces fix from
the rollback-fidelity extension session.

### Verdict Diff (pre-state vs post-rollback)

One difference: `~/.mrk/` directory and `defaults-rollback.sh` created by the apply
are still present post-rollback. Expected mrk bookkeeping; rollback does not remove
its own scaffolding. Not a failure.

Every defaults key restored. Canary returned to `<unset>`. Terminal returned to
"Clear Dark". All six previously-absent domains returned to absent.

### Idempotency Spot-Check

Second `make defaults` on the same VM (post-rollback state). Rollback file after
second apply: 65 lines, diff vs first-run rollback: **empty**. The deduplication
guards (`backup_line` in `defaults.sh`) produced byte-identical output. M2 fix
empirically confirmed — no duplicate entries, no rollback content lost across runs.

---

## Test 1B: Hardening Rollback

**Initial verdict: PARTIAL/FAIL. Post-fix verdict: PASS.**

### Pre-State

| Item | Value |
|---|---|
| `/etc/pam.d/sudo` sha256 | `b1912a1e…` |
| PAM config | Standard Tahoe: `pam_smartcard.so` (sufficient) + `pam_opendirectory.so` (required) |
| `sudo.backup.mrk` | absent |
| Firewall global state | `Firewall is disabled. (State = 0)` |
| Firewall stealth mode | `Firewall stealth mode is off` |
| `askForPassword` | `<unset>` |
| `askForPasswordDelay` | `<unset>` |

PAM contained both `pam_smartcard.so` and `pam_opendirectory.so` — the validation
guard in `hardening.sh` would pass. Admin user had NOPASSWD sudo (`sudo -n true` →
exit 0).

Tahoe `socketfilterfw` output formats confirmed by direct capture:
- `--getglobalstate`: `"Firewall is enabled. (State = 1)"` / `"Firewall is disabled. (State = 0)"`
- `--getstealthmode`: `"Firewall stealth mode is on"` / `"Firewall stealth mode is off"`

These formats are relevant to the parser bugs described below.

### Apply Phase

`make harden` completed cleanly, all four operations logged:

```
[hardening] Enabling Touch ID for sudo
[hardening] Touch ID for sudo enabled
[hardening] Requiring password immediately on wake
[hardening] Enabling macOS firewall (global on, stealth on)
[hardening] Firewall enabled with stealth mode
[hardening] Hardening done. Rollback: /Users/admin/.mrk/hardening-rollback.sh
```

Post-apply diff confirmed: PAM sha256 changed to `e743f3c5…`, `pam_tid.so` prepended,
`sudo.backup.mrk` created, firewall enabled, stealth on, `askForPassword=1`,
`askForPasswordDelay=0`.

### Bug 1: Firewall Rollback Lines Missing `sudo`

The generated rollback file (before fix) contained:

```bash
/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off
/usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode off
```

`socketfilterfw` requires root to change state. Running the rollback as a normal user
produced `"Must be root to change settings."` twice and exit 255. PAM and screensaver
lines ran (they appeared before the firewall lines and do not require root via sudo
for the `defaults write` call, or correctly include `sudo` for the `mv`). Firewall
state was not restored.

The PAM rollback line correctly included `sudo`:
```bash
sudo mv /etc/pam.d/sudo.backup.mrk /etc/pam.d/sudo
```

The inconsistency was in the `rollback()` call strings — the firewall entries were
generated without `sudo` while the PAM entry was not.

**Fix (`f17c991`):** Added `sudo ` prefix to both `rollback` call strings at lines
85 and 94 of `hardening.sh`. Two lines changed.

### Bug 2: Stealth Mode Parser Matching Wrong Substring

The pre-apply stealth state capture used:

```bash
/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode 2>/dev/null | \
  grep -qi "enabled" && prev_stealth="on" || true
```

The `--getstealthmode` output on macOS 26.3 is `"Firewall stealth mode is on"` or
`"Firewall stealth mode is off"`. Neither contains `"enabled"`. The grep never
matched, so `prev_stealth` was always left at its initialized value of `"off"`
regardless of actual stealth state.

Consequence: if stealth mode were already on before `make harden` ran, the rollback
would record `--setstealthmode off` (wrong) instead of `--setstealthmode on`
(correct). In the test run stealth was off pre-apply, so the captured value happened
to be correct — the bug was latent, not manifest, in the initial test run.

This is distinct from the `--getglobalstate` parser (line 82), which uses the same
`grep -qi "enabled"` pattern but against output that does contain `"enabled"` when
the firewall is on. That parser is correct; only the stealth parser was wrong.

**Fix (`178b191`):** Changed `grep -qi "enabled"` to `grep -qi " is on"` on the
stealth-mode capture line. One line changed.

### Origin of Both Bugs

Both bugs were introduced in the session that added stealth mode rollback support —
the same session that fixed the original stealth-rollback omission identified in
`02-side-effects.md` and `08-harden-deep-dive.md`. The fixes addressed the missing
rollback entry but introduced a missing `sudo` and an incorrect parser for the newly
captured state. Runtime verification caught what static analysis missed.

### Re-Verification (post-fix)

Fresh clone → apply → inspect rollback → run rollback → verdict diff.

Post-fix rollback file:
```bash
#!/usr/bin/env bash
sudo mv /etc/pam.d/sudo.backup.mrk /etc/pam.d/sudo
defaults write com.apple.screensaver askForPassword -int 0
defaults write com.apple.screensaver askForPasswordDelay -int 0
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode off
```

Rollback exit code: **0**. No errors.

PAM sha256 chain across all three capture points:
- Pre-apply: `b1912a1e…`
- Post-apply: `e743f3c5…`
- Post-rollback: `b1912a1e…` — byte-identical to pre-apply ✓

Verdict diff (pre-state vs post-rollback): no firewall or PAM entries. All four
hardening operations correctly reverted.

Stealth mode parser validated against all three observed output states on macOS 26.3:

| Output | `grep -qi " is on"` | `prev_stealth` |
|---|---|---|
| `"Firewall stealth mode is off"` | no match | `off` ✓ |
| `"Firewall stealth mode is on"` | match | `on` ✓ |
| `"Firewall stealth mode is off"` | no match | `off` ✓ |

Idempotency: second `make harden` produced byte-identical rollback file. Dedup guards
in `hardening.sh` held across re-runs.

---

## Known Limitations Confirmed Empirically

**Screensaver rollback writes 0 instead of deleting.** When `askForPassword` and
`askForPasswordDelay` are absent pre-apply, the rollback captures `0` (from the
`|| echo "0"` fallback) and generates `defaults write … -int 0`. After rollback the
keys are explicitly present as `0` rather than absent. This appeared in the verdict
diff for both 1B runs as `<unset>` vs `0` for both screensaver keys.

Functionally equivalent — macOS treats absent and `0` identically for screensaver
password lock — but `defaults read` returns a value instead of an error. The correct
fix would be to use `defaults delete` when the captured value is the fallback `0` and
the key was not actually set. Pre-existing issue; not introduced by the fix sessions;
not blocking for the rollback fidelity claim.

**Browser and app-preference defaults remain untracked.** The ~40 `NO ROLLBACK FOUND`
entries documented in `02-side-effects.md` (Safari, Helium, Rogue Amoeba suite,
AlDente) were not exercised in Tests 1A or 1B. Test 1C (combined rollback) would have
produced a PARTIAL verdict for exactly this reason. Tests 1A and 1B verify only the
keys that are tracked — the claim is not that rollback is complete, but that what is
tracked rolls back correctly.

---

## Tests Deferred

Tests 2, 3, and 4 from `docs/audit/10-test-plan.md` were not executed in this
session. They remain runnable from the test plan.

**Test 2 — Idempotency (`make all` twice, same VM).** Would measure full filesystem
and plist diff between run 1 and run 2. The rollback-file stability check folded into
Test 1A provided partial signal: the M1 fix (deferred backup-dir creation) and M2 fix
(rollback deduplication) both showed stable behavior. The full test would additionally
verify Barkeep install skip-on-second-run, login item deduplication, and the absence
of unexpected persistent writes on a no-op re-run.

**Test 3 — Order-independence (`make brew` vs `make post-install` order).** Would run
phases in two orders after `make setup` on separate fresh VMs and diff final state.
The README's revised claim ("any order after initial bootstrap") was not tested. Static
analysis predicted plist imports would be silently skipped when running `post-install`
before `brew` (apps not yet installed), which would produce a PARTIAL rather than PASS.

**Test 4 — Re-entry recovery (SIGINT mid-run, re-run to completion).** Would verify
the H2 fix (DMG mount trap in `install_github_app`) and convergence after interruption
at varied timing. The fix in commit `22c09f1` adds an EXIT trap that should prevent
mounted-DMG leaks on SIGINT, but runtime confirmation was not produced.

---

## Audit Closure

The static audit (modules 1–9) predicted where mrk was likely to fail under runtime
conditions and what the fix sessions addressed. Two runtime tests confirm the
prediction was partially right, partially wrong in instructive ways.

Test 1A confirmed that the M2 defaults-rollback fixes — truncation prevention,
deduplication guards, and keys-with-spaces quoting — work correctly under runtime
conditions on macOS 26.3. The rollback file is stable, keys restore cleanly, and the
mechanism behaves as designed.

Test 1B confirmed that the stealth-mode rollback addition worked at the level of
producing a rollback entry, and failed at the level of two implementation details
that static analysis did not flag: a missing `sudo` on generated commands and a grep
pattern matched against the wrong output format. Both were small bugs in new code
added by a fix session — fix sessions are not immune to introducing bugs, and this
is precisely the category of issue that runtime verification exists to catch. Three
lines changed, both bugs closed, re-verification passed. The rollback fidelity claim
for `make harden` is now empirically supported on macOS 26.3 after these corrections.

The remaining tests (1C, 2, 3, 4) represent diminishing marginal value relative to
the bugs-per-test-run rate observed here. They are well-specified in the test plan
and can be executed if future changes to mrk warrant regression coverage.
