# Audit Module 5 — Runtime Verification Results
**Branch:** `main` | **Date:** 2026-04-26 (1A, 1B); 2026-09-28 (1C, 2, 3, 4)
**Test plan:** `audit/10-test-plan.md`
**Environment, 2026-04-26:** Tart sandbox, macOS 26.3 (Tahoe), Darwin 25.3.0, ARM64
**Environment, 2026-09-28:** Tart 2.40.0, VMs from Cirrus Labs' `macos-tahoe-vanilla:26.6.2`
(macOS 26.6.2, 25G83), commit `be0ef6a` in every VM
**VM source:** `mrk-audit-clean-prepared` snapshot (Tart, copy-on-write clone per test)

---

## Executive Summary

1A and 1B ran on 2026-04-26. 1C, 2, 3 and 4 ran on 2026-09-28, against the plan as refreshed
that day. Each verdict below is the plan's rule applied as written. Where the rule and what
happened part company, the right-hand column says how, and the section says why.

| Test | Description | Verdict | What happened |
|---|---|---|---|
| **1A** | Rollback fidelity — `make defaults` | **PASS** | |
| **1B** | Rollback fidelity — `make harden` | PARTIAL/FAIL on first run; **PASS** after fix | |
| **1C** | Rollback fidelity — combined | **FAIL** by the rule | Every key `defaults.sh` and `hardening.sh` wrote came back. The one difference is `FXDesktopVolumePositions`, which Finder writes itself |
| **2** | Idempotency — `make all` twice | **PASS** | The second run changed nothing. `make all` stopped at post-install both times (R-2), so `build-tools` was run twice on its own: also no change |
| **3** | Order-independence — brew vs post-install | Claim A differs, as predicted; Claim B **PARTIAL** by the rule | Everything mrk writes converges. Five values macOS writes for itself differ between any two VMs |
| **4** | Re-entry recovery — interrupt and failing write | 4a **PASS**; 4b passes every N-1 and W-19 check | Two 4b expectations are unmet because of the Music keys (R-1) |

Two findings came out of the run, both real on a new Mac:
- **R-1 — three Music keys can't be written.** macOS 26's System Policy denies other processes
  `user-preference-write` on `com.apple.Music`, so on a new Mac `make defaults` exits 1 every
  time.
- **R-2 — Magic Backup Machine's repository is private.** Without `gh auth`, post-install
  fails and `make all` stops before `build-tools`.

Both are under Findings from the 2026-09-28 run, below, and are open in `00-followups.md`.

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

## The 2026-09-28 run: environment

- **Host.** The owner's Mac, macOS 26.7. Tart 2.40.0 came from its GitHub release, checked
  against its published SHA-256, signed by "Developer ID Application: Cirrus Labs, Inc."
  and notarized. It is in `~/Applications/tart.app`. Homebrew could not install it: the
  `cirruslabs/cli` tap's formula pinned 2.32.1, in a form Homebrew 7.0.7 refuses.
- **Base image.** `ghcr.io/cirruslabs/macos-tahoe-vanilla:26.6.2` (digest `eeec54bf…`, 24 GB
  download), built into `mrk-audit-clean-prepared` as the plan's Environment section says:
  - the Command Line Tools 27.0, as on the host, installed by `softwareupdate -i` by label and
    nothing else;
  - passwordless `sudo`;
  - SSH by a dedicated key (`~/.tart/mrk-vm_ed25519`, valid only from 192.168.64.1);
  - Automation and Full Disk Access for `sshd-keygen-wrapper`, granted by the owner;
  - mrk at `be0ef6a`;
  - 17 fixture plists;
  - `capture.sh` from the plan, and `trim-brewfile.sh`.

  The pre-flight in the VM was clean: two captures, identical, nothing incomplete.
- **A trimmed Brewfile.** The image's disk is 50 GB, with 17 GB free. `tart set --disk-size
  120` grew the disk, but the 5.4 GB recovery partition sits between the main container and
  the new space. SIP forbids removing it (`This operation is not allowed because the given
  disk is an APFS Recovery Physical Store`). Removing it anyway would have left SIP off for
  good. The whole Brewfile needs 25–30 GB, measured on the host: 5.7 GB of `/opt/homebrew`,
  15.6 GB of cask apps and a 9.6 GB download cache. So every test VM that installs packages
  ran `trim-brewfile.sh` first. It cuts the Brewfile to the 25 entries post-install and
  `make all` depend on:
  - **Formulae:** `coreutils`, `gnupg`, `pinentry-mac`, `topgrade`, `go`, `openjdk` and
    `pyenv`, with 48 dependencies (1.0 GB).
  - **Casks (2.7 GB):** the 18 apps behind post-install's login items, app-defaults scripts
    and plist imports:
    - `audio-hijack`, `farrago`, `fission`, `loopback`, `piezo`, `soundsource`;
    - `macwhisper`, `waves-central`, `iterm2`, `dropbox`, `helium-browser`, `raycast`;
    - `typora`, `aldente`, `keka`, `stats`, `thaw`, `timemachineeditor`.

  The tests check mrk's logic, not the number of packages. The owner chose this over a fresh
  VM from an IPSW, or SIP off.
- **Each test** ran in its own clone of the base, deleted once the captures were copied out.
  Every VM reported `be0ef6a` and macOS 26.6.2 (25G83). The evidence is quoted below exactly
  as captured.

---

## Test 1C: Combined Rollback

### Procedure

As the plan specifies:
1. `make setup ARGS=--no-defaults`, then the `baseline` capture;
2. `make defaults`, then `make harden`, then the `applied` capture;
3. `hardening-rollback.sh`, then `defaults-rollback.sh`, then the `reverted` capture.

### Evidence

```
== make setup ARGS=--no-defaults: exit 0
== make defaults: exit 2  (⚠ 3 default(s) failed to apply; the rest are applied. …)
== make harden: exit 0
== hardening-rollback.sh: exit 0
== defaults-rollback.sh: exit 0
```

`make defaults` exits 2 because of R-1's three Music keys. `make harden` ran with no terminal,
so its screen-lock step printed `sysadminctl -screenLock immediate -password -` and changed
nothing, as the plan expects.

**The applies ran.** `applied` differs from `baseline` in 31 of the domains `defaults.sh` writes, both undo
files, and all six hardening items:

```
fw-global.txt                                                  changed
fw-stealth.txt                                                 changed
pam-sudo-local.txt                                             changed
defaults.com.apple.LaunchServices.xml                          changed
defaults.currentHost.com.apple.coreservices.useractivityd.xml  changed
diagnostics.xml                                                changed
screen-lock.txt                                                UNCHANGED
```

**`diff -r baseline reverted`** lists three files: the two undo files, which are expected, and
one domain:

```
diff -r captures/baseline/defaults.com.apple.finder.xml captures/reverted/defaults.com.apple.finder.xml
333a334,347
> 	<key>FXDesktopVolumePositions</key>
> 	<dict>
> 		<key>Macintosh HD_0x1.816b4658p+29</key>
…
```

### Verdict

**FAIL, by the rule** — "any domain that `defaults.sh` or `hardening.sh` wrote differs from
baseline".

In substance, every key the two scripts wrote is back:
- **defaults.sh:** the 31 domains it changed, including every key of Finder's it wrote.
- **hardening.sh:** firewall, stealth mode, `sudo_local`, LSQuarantine, Handoff and Mac
  Analytics.

The one difference is a key Finder writes itself. `defaults.sh:335` sets
`ShowHardDrivesOnDesktop true` where the image had `false`, and `killall Finder` restarts
Finder. Finder then draws the disk on the desktop and records where it put it. The undo puts
`ShowHardDrivesOnDesktop` back to `false`, and Finder's note of the icon's position stays. It is
harmless, and it is outside what mrk writes or records.

The plan's rule does not tell a script's key from an app's reaction to it. The correction is
in `10-test-plan.md`.

---

## Test 2: Idempotency

### Procedure

On a fresh clone: `trim-brewfile.sh`, `make all`, the `run1` capture, `make all` again, and
the `run2` capture. It ran detached in the VM.

### Evidence

```
== run 1: make all exit 2  at 04:21:09
== run 2: make all exit 2  at 04:21:18
== package counts in run1: formulae 55, casks 18
== 5. diff -r run1 run2 (expected: empty)
   EMPTY — no differences
```

Run 1 took seven minutes; run 2 took nine seconds. Run 2's log skips every install, link,
import, login item and LaunchAgent. For example:

```
     · 37 tool(s) (already linked)
     · 8 dotfile(s) (already linked)
   Skipping install of pyenv formula. It is already installed.
     · Thaw plist (exists — skipping import (won't overwrite))
     · dependency-updates session hook (installed)
```

**`make all` stopped at post-install in both runs:**

```
  ▸ Warning: could not read the latest MagicBackupMachine release from GitHub — not installed (a private repo needs an authenticated gh)
  ▸ Warning: 1 post-install step(s) failed
make: *** [post-install] Error 1
```

That is R-2. `build-tools`, the last target, never ran, so it was run twice in the same VM
with a capture after each:

```
== build-tools run 1: exit 0
== build-tools run 2: exit 0
== diff bt1 bt2 (expected: empty)
   EMPTY — no differences
```

The first run added `mrk-menu`, `mrk-picker`, `mrk-status` and `status` to `~/bin`.

### Verdict

**PASS.** A second `make all` changes nothing: `diff -r` is empty over every artifact the
plan names. `build-tools` is idempotent too. Two expectations are unmet, and neither is an
idempotency defect:
- setup's defaults phase reports R-1's three Music failures in both runs;
- `make all` does not complete, because of R-2.

**A harness defect this test found.** A later capture in the same VM sorted `applications.txt`
differently: `iTerm.app` moved. `capture.sh` sorts by the locale, and the later SSH session
carried `LC_ALL=en_US.UTF-8`. Test 2's two captures came from one session, so its empty diff
stands. Tests 3 and 4a set `LC_ALL=C` in the capture script. The plan's copy now does too.

---

## Test 3: Order-Independence

### Procedure

Two fresh clones, run at the same time.
- **3a:** `make setup`, then `make brew`, then `make post-install`, then the `order-a`
  capture.
- **3b:** `make setup`, then `make post-install`, then `make brew`, then the
  `order-b-singlepass` capture; then `make post-install` again, then the `order-b-converged`
  capture.

The plan chains the phases with `&&`. post-install exits 1 here (R-2), so each phase ran
regardless of the last, and its exit code was kept. Both VMs' captures sorted with `LC_ALL=C`.

### Evidence

```
3a: setup exit 0 · brew exit 0 · post-install exit 2
3b: setup exit 0 · post-install exit 2 · brew exit 0 · post-install exit 2
```

**Claim A, `order-a` vs `order-b-singlepass`:**

```
=== login-items.txt  (< order-a  > single pass)
< AlDente
< Dropbox
< Raycast
< Thaw
=== other-links.txt
< .config/topgrade.toml -> /Users/admin/mrk/assets/topgrade.toml
< openjdk.jdk -> /opt/homebrew/opt/openjdk/libexec/openjdk.jdk
=== runtimes.txt
< 3.12.14
< pinentry-program /opt/homebrew/bin/pinentry-mac
=== defaults-rollback.sh — 15 whole-domain lines only in order-a, one per imported cask app
< defaults delete com.stonerl.Thaw …   (and 14 more)
```

3b's first post-install logged `Skipping login item (not installed): AlDente` and the other
five login items.

**Claim B, `order-a` vs `order-b-converged`:** five domains differ. None of the differing
values is one mrk writes:

| Domain | Difference |
|---|---|
| `com.apple.chronod` | a UUID and a timestamp |
| `com.apple.sharingd` | two dates, one second apart |
| `com.apple.dock` | `last-analytics-stamp` |
| `com.apple.TelephonyUtilities` | a base64 JSON blob of zero counters, serialized in another key order |
| `com.apple.amp.mediasharingd` | the same Music sharing playlists, in another array order |

### Verdict

- **Claim A differs, as the README says.** "Phase 3 configures only what Phase 2 has
  installed." The differences are the ones the skip guards explain, plus the topgrade link.
  The plan had predicted the topgrade link in both orders, and that was wrong: post-install
  links the config only when `command -v topgrade` succeeds (`post-install:181`). That is a
  correction to the plan, not a defect in mrk.
- **Claim B is PARTIAL, by the rule** — "converges except for a named artifact". The named
  artifacts are those five domains, and the reason is that they hold values macOS writes for
  itself. Every key, link, login item, runtime, package and undo line mrk writes is identical.
- **Not observed:** the app-defaults keys the plan also predicted for Claim A. The capture does
  not record the apps' own domains. The plan now lists that as a gap in the capture.

---

## Test 4: Re-entry and Recovery

### Part 4a — interruption

**Procedure.** On a fresh clone: `trim-brewfile.sh`, `make setup`, `make brew`, then the
`pre-interrupt` capture. Next, `make post-install`, interrupted while `ditto` copied a GitHub
app out of its mounted DMG. Then the leak checks, the `interrupted` capture, `make
post-install` to the end, and the `recovered` capture.

**The first attempt tested nothing,** and is kept as `4a-attempt1` in the evidence:
- its watcher's time limit ran out during pyenv's Python build, which comes before the apps;
- its `kill -INT -- -<pgid>` reached no process, because with no terminal `set -m` had not
  made a process group.

post-install ran to its end, uninterrupted. The second attempt waited for the first app's
`Downloading` line, caught `ditto` at once, and signalled `ditto`, the post-install script
and `make` by process ID, the processes Ctrl-C would reach.

**Evidence.**

```
== copy in progress when interrupted: ditto /var/folders/p7/…/T//mrk.vX2LsI/ClipHack.app /Applications/ClipHack.app
   images from mrk temp paths attached just after the signal: 1
== interrupted post-install: exit 2
   [post-install] interrupted — exiting
== after the interrupt: images from mrk temp paths still attached: 0
   mrk.* left in /var/folders/p7/…/T: 0
   /Applications/ClipHack.app: present
     codesign exit: 0
== post-install again: exit 2
     · ClipHack (installed — skipping)
   /Applications/ClipHack.app after the re-run: signature valid
```

`recovered` against Test 3's `order-a` differs only in the five macOS-written values of
Claim B, and in one date in `com.apple.Terminal` that Terminal writes for itself.

**Verdict: PASS.**
- **Both traps fired.** post-install's `INT` trap exited, and `_github_app_done` detached the
  image and removed both temporary paths.
- **The re-run recovered.** Its one failure is R-2.
- **The state matches `order-a`** in everything mrk writes.

**Not shown: a copy cut short.** ClipHack's copy had finished when the signal took effect: its
signature verified straight after. So a half-copied app was not produced. By reading the code
(`install-apps:166-167`), one would survive: the signal traps detach and delete the temporary
paths, but only a failed `ditto` removes the partial app. The re-run's skip test would then
treat it as installed. This is open in `00-followups.md`.

### Part 4b — injected failing write

**Procedure.** As the plan specifies, with its stub refusing `AppleKeyboardUIMode`.

**Evidence.**

```
== injected run: exit 1
== undo file: 121 lines, line 1 '#!/usr/bin/env bash', mode -rwxr-xr-x
   bash -n: parses
   AppleKeyboardUIMode lines:
     26:defaults write NSGlobalDomain AppleKeyboardUIMode -int 3
   last 4 lines: … killall Finder … killall Dock … killall SystemUIServer …
== recovery run: exit 1
== summaries
     ⚠ 4 default(s) failed to apply; the rest are applied. …
     ⚠ 3 default(s) failed to apply; the rest are applied. …
== stub refusals in the injected run: 1
== diff injected vs recovered-inject (expected: AppleKeyboardUIMode only)
< 	<integer>3</integer>
---
> 	<integer>2</integer>
```

The injected run changed the same 31 domains a clean run does. The three failures besides the stub's are R-1's,
found by a pass-through stub that logs failed writes:

```
rc=1  defaults write com.apple.Music showAppleMusic -bool false
   -> … Could not write domain com.apple.Music; exiting
rc=1  defaults write com.apple.Music userWantsPlaybackNotifications -bool false
rc=1  defaults write com.apple.Music useErrorCorrection -bool true
```

**Verdict.** Every N-1 and W-19 assertion holds:
- **the run did not abort** at the refused write;
- **it counted the failure and exited 1**;
- **the failure is isolated** to `AppleKeyboardUIMode`, which is the only difference from the
  recovered run;
- **the undo file is well-formed,** records the refused key's prior value `3` before the write,
  and ends with its `killall` lines.

Two expectations are unmet, both because of R-1:
- the summary reads `4 default(s)`, not `1`;
- the stub-free re-run exits 1 with `3 default(s)`, not 0 with `Defaults applied`.

### Test 4 verdict

Under the plan's rule, 4a passes. 4b meets every expectation except the two R-1 accounts for,
and the rule has no category for that. On a Mac where the Music keys can be written, both parts
would pass. **N-1 holds at runtime:** a refused write does not stop the run or truncate the undo
file.

---

## Findings from the 2026-09-28 run

**R-1 — three Music keys can't be written on macOS 26.** `defaults.sh:628-632` writes
`showAppleMusic`, `userWantsPlaybackNotifications` and `useErrorCorrection` to
`com.apple.Music`. On macOS 26.6.2 every such write fails. The VM's log gave the reason:

```
cfprefsd … rejecting write of key(s) <private> in { com.apple.Music, admin, kCFPreferencesAnyHost, /Users/admin/Library/Preferences/com.apple.Music.plist, …
kernel … System Policy: defaults(6627) deny(1) user-preference-write com.apple.music
```

- **Neither grant lifts it.** The SSH session had Full Disk Access. Opening Music once, which
  created its preferences file, did not help either.
- **On a new Mac:** `make defaults` reports three failures and exits 1 every time, and setup
  warns `defaults.sh returned non-zero` in every `make all`.
- **On the owner's Mac:** the three keys came over in the migration already at mrk's values, so
  `write_default` skips them and never tries a write. Whether 26.7 also denies them was not
  checked, because it would mean writing to the owner's real Music settings.

**R-2 — Magic Backup Machine's repository is private.** `sevmorris/magic-backup-machine` has
visibility `PRIVATE`. Without an authenticated `gh`, `install-apps` cannot read its release, and
post-install counts a failed step and exits 1. `make` then stops, so `make all` never reaches
`build-tools`: `mrk-status`, `mrk-menu` and `mrk-picker` are not built. The manual's new-machine
walkthrough never mentions `gh auth login`. The other six apps installed in every run.

**Both fixed on 2026-09-28,** in branch `claude/r1-r2-fixes`:
- **R-1:** the three Music keys are gone from `defaults.sh` and MRK-1, leaving 133 keys.
- **R-2:** the walkthrough has `gh auth login`, and a private repo gh cannot reach is a skip
  that names `make apps`, not a failure.

A re-run of 4b and 2 would show both at runtime.

**Corrections to the plan,** made in `10-test-plan.md` alongside these results:
- `capture.sh` sets `LC_ALL=C`;
- comparisons across VMs, and 1C's revert, treat keys macOS or an app writes for itself as named
  exceptions;
- Test 3's procedure no longer chains the phases with `&&`, and topgrade joins Claim A's list;
- 4a uses the watcher that worked;
- the capture's missing app domains are recorded as a gap;
- the trimmed Brewfile is recorded.

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

**The 2026-09-28 run** executed them. What the scripts do held:
- rollback restores what it wrote;
- a second install changes nothing;
- running the phases out of order converges once Phase 3 runs again;
- an interrupt leaves nothing mounted;
- a refused write neither stops the run nor truncates its undo file.

What the run found lay outside the scripts' logic:
- **R-1:** macOS 26 refuses three of `defaults.sh`'s writes.
- **R-2:** one app's repository is private, and without a GitHub login that stops `make all`
  short.
- **The plan's own rules:** in two places they could not tell mrk's keys from ones macOS and
  Finder write for themselves.

None of these would have shown on the owner's migrated Mac, where the settings and the logins
were already in place. The same pattern held in April: runtime testing finds what reading
misses.
