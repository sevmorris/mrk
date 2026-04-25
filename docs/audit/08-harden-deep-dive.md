# Audit 08 — `make harden` Deep Dive
**Branch:** `audit/static-pass` | **Date:** 2026-04-25

## Scope

Forensic analysis of `scripts/hardening.sh` (94 lines) and the `make harden`
Makefile target. The earlier modules established this as the second-highest-blast-
radius target in the project (`02-side-effects.md` Hot Spot #2) and identified two
standing issues: a `command -v sudo` check that does not probe actual sudo usability
(`03-shell-hygiene.md M4`) and stealth-mode rollback omission (`02-side-effects.md`
security table). This document traces every code path at forensic depth.

---

## 1. What `make harden` Does

`make harden` calls `scripts/hardening.sh`, which applies three opt-in security
changes to the local machine:

1. **Touch ID for sudo** — prepends `auth sufficient pam_tid.so` to
   `/etc/pam.d/sudo`, enabling biometric authentication as an alternative to a
   password when using `sudo` in a terminal.

2. **Screensaver password lock** — sets the screensaver to require the password
   immediately on activation (no grace delay).

3. **Application Firewall** — enables the macOS application-layer firewall in
   both "global on" and "stealth mode" states; stealth mode drops rather than
   rejects unsolicited incoming packets.

After each operation the script writes a rollback entry to `~/.mrk/hardening-rollback.sh`.
Touch ID and firewall changes require `sudo`. All three operations are gated on
`have_sudo=true` (Touch ID and firewall) or run unconditionally (screensaver, which
uses `defaults write` without privilege). The script runs under `set -euo pipefail`.

---

## 2. Code Walk-Through

### Block 1 — Lines 1–18: Initialization

```bash
set -euo pipefail
ROLL_DIR="$HOME/.mrk"
ROLL="$ROLL_DIR/hardening-rollback.sh"

if ! mkdir -p "$ROLL_DIR"; then …exit 1; fi
if ! printf '#!/usr/bin/env bash\n' > "$ROLL" || ! chmod +x "$ROLL"; then …exit 1; fi
```

`set -euo pipefail` is active throughout. The rollback directory is `~/.mrk`
(created if absent). The rollback file is truncated unconditionally with `>` — every
invocation destroys the prior rollback content before writing new entries. This is the
same truncation pattern documented in `03-shell-hygiene.md M2` for `defaults.sh`. The
consequence for hardening specifically is documented in §6 (Specific Concerns).

Both `mkdir -p` and the rollback file creation are wrapped in error checks with a hard
`exit 1` — the only path in the entire script that uses `exit`. All subsequent failures
are soft (warn + continue).

---

### Block 2 — Lines 20–28: Helpers and Sudo Check

```bash
have_sudo=false
if command -v sudo >/dev/null 2>&1; then
  have_sudo=true
fi
```

`command -v sudo` confirms the `sudo` binary is in `$PATH`. It does not verify that
the current user can actually invoke sudo (active credential cache, NOPASSWD, password
required). All three subsequent privileged blocks are gated on `$have_sudo`. If sudo
requires a password and no TTY is available (piped invocation, cron), `command -v sudo`
still returns true, `have_sudo` is set, and the sudo calls in blocks 3 and 5 will
silently fail (the `2>/dev/null` on each sudo invocation suppresses error output from
the commands; the password prompt goes to `/dev/tty` and will appear or block depending
on context). This is the issue flagged in `03-shell-hygiene.md M4`. The practical
consequence is traced in §6.

---

### Block 3 — Lines 30–59: Touch ID for sudo (PAM)

```bash
if $have_sudo; then
  if ! grep -q 'pam_tid.so' /etc/pam.d/sudo 2>/dev/null; then
    if sudo cp /etc/pam.d/sudo /etc/pam.d/sudo.backup.mrk 2>/dev/null; then
      rollback "sudo mv /etc/pam.d/sudo.backup.mrk /etc/pam.d/sudo"
      tmpfile="$(mktemp -t mrk)"
      { echo 'auth       sufficient     pam_tid.so'; cat /etc/pam.d/sudo; } > "$tmpfile"
      if [[ ! -s "$tmpfile" ]] || ! grep -q 'pam_tid\.so' "$tmpfile" || \
         ! grep -qE 'pam_smartcard\.so|pam_opendirectory\.so' "$tmpfile"; then
        warn "Generated PAM config appears invalid — aborting Touch ID setup"
        rm -f "$tmpfile"
        sudo mv /etc/pam.d/sudo.backup.mrk /etc/pam.d/sudo 2>/dev/null || true
      elif sudo cp "$tmpfile" /etc/pam.d/sudo 2>/dev/null; then
        log "Touch ID for sudo enabled"
      else
        warn "Failed to write new sudo PAM config (may require password)"
        sudo mv /etc/pam.d/sudo.backup.mrk /etc/pam.d/sudo 2>/dev/null || true
      fi
      rm -f "$tmpfile"
    else
      warn "Failed to backup sudo PAM config (may require password)"
    fi
  else
    log "Touch ID for sudo already enabled"
  fi
fi
```

**Outer gate:** `if ! grep -q 'pam_tid.so' /etc/pam.d/sudo` — the entire block is
skipped if Touch ID is already enabled. This is the idempotency guard.

**Backup:** `sudo cp /etc/pam.d/sudo /etc/pam.d/sudo.backup.mrk`. If this fails
(sudo unavailable, permissions), the PAM change is abandoned entirely and only a
warning is emitted. The rollback entry is appended AFTER the successful backup — the
ordering is correct.

**Config generation:** `{ echo 'auth       sufficient     pam_tid.so'; cat /etc/pam.d/sudo; } > "$tmpfile"` —
prepends the Touch ID line to the existing PAM config by redirecting the entire
compound command output to a temp file. Because `cat /etc/pam.d/sudo` reads the
ORIGINAL file (the backup was a copy, not a move), the original is still intact at
this point. Under `set -e`, if `/etc/pam.d/sudo` is unreadable, the compound
command fails and the script exits abruptly with `$tmpfile` partially written and
the backup orphaned at `/etc/pam.d/sudo.backup.mrk`.

**Validation:** Three checks on `$tmpfile`:
1. File is non-empty (`-s`)
2. Contains `pam_tid.so`
3. Contains `pam_smartcard.so` OR `pam_opendirectory.so`

If validation fails, the backup is restored and the operation is aborted cleanly.
See §6 for the LDAP/MDM case where this matters.

**Write:** `sudo cp "$tmpfile" /etc/pam.d/sudo` — uses `cp` not `mv`, so `$tmpfile`
is preserved until the explicit `rm -f` at the end of the block. The `cp` target
(`/etc/pam.d/sudo`) is an existing system file owned by root with permissions 444 or
similar; `sudo cp` overwrites it. If this `sudo cp` fails, the backup is restored.

**PAM module ordering:** The Touch ID line is prepended: `auth sufficient pam_tid.so`
becomes the first auth module. PAM processes auth modules top-to-bottom. A `sufficient`
module, if it succeeds, causes PAM to grant auth immediately (since no prior `required`
module failed). Touch ID is therefore tried first; failure falls through to
`pam_smartcard.so` (sufficient, for Smart Card users) and then `pam_opendirectory.so`
(required — the password prompt). Prepending is the correct placement for a fast-path
biometric shortcut.

---

### Block 4 — Lines 61–68: Screensaver Password

```bash
prev1=$(defaults read com.apple.screensaver askForPassword 2>/dev/null || echo "0")
prev2=$(defaults read com.apple.screensaver askForPasswordDelay 2>/dev/null || echo "0")
rollback "defaults write com.apple.screensaver askForPassword -int ${prev1:-0}"
rollback "defaults write com.apple.screensaver askForPasswordDelay -int ${prev2:-0}"
defaults write com.apple.screensaver askForPassword -int 1
defaults write com.apple.screensaver askForPasswordDelay -int 0
```

This block reads the current screensaver values, appends rollback entries with those
values, then unconditionally writes the target values — regardless of whether the
settings are already at the target. No idempotency check. The practical consequence:
on a second run, `prev1` and `prev2` will read the already-hardened values (1 and 0),
and the rollback file will record "restore to 1" and "restore to 0" — not the original
pre-hardening values. After two runs, the rollback for screensaver settings is silently
broken (it restores to the hardened state, not the original). This is the same pattern
noted in `03-shell-hygiene.md M2`.

No sudo required; `defaults write com.apple.screensaver` is a per-user preference in
the current user's domain.

---

### Block 5 — Lines 70–91: Application Firewall

```bash
if $have_sudo; then
  prev=$(/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate 2>/dev/null \
    | awk '{print $3}' || echo "off")
  : "${prev:=off}"
  rollback "/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate $prev"
  if [[ "$prev" == "on" ]]; then
    log "Firewall already enabled"
  else
    log "Enabling macOS firewall (global on, stealth on)"
    if sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on 2>/dev/null; then
      if sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on 2>/dev/null; then
        log "Firewall enabled with stealth mode"
      else
        warn "Failed to enable firewall stealth mode"
      fi
    else
      warn "Failed to enable firewall (may require password)"
    fi
  fi
fi
```

**State capture:** `awk '{print $3}'` on the socketfilterfw output. On macOS Sonoma/Ventura,
`--getglobalstate` outputs `"Firewall is on (State = 1)"` or `"Firewall is off (State = 0)"`,
making `$3` either `"on"` or `"off"`. This has been stable across recent macOS versions, but
it is an implicit format dependency. If Apple changes the output string, `$prev` could contain
a garbage value; the `if [[ "$prev" == "on" ]]` test would be false, and the rollback entry
would record the garbage value (which `setglobalstate` would likely reject or ignore).

**Rollback gap:** The rollback records the previous `--setglobalstate` value only. The
`--setstealthmode on` at line 80 has no corresponding rollback entry. This is the gap
documented in `02-side-effects.md` security table. After rollback, the firewall returns
to its prior global state but stealth mode remains on permanently (it persists across
global state changes). The user has no automated path to restore stealth mode to its
pre-hardening setting.

**Stealth mode is only attempted when firewall was off:** The outer `if [[ "$prev" == "on" ]]`
check skips the entire setglobalstate + setstealthmode block when the firewall is already on.
If the user's firewall was on before running `make harden`, stealth mode is silently not
enabled. The user may believe `make harden` ensures stealth mode regardless of prior state;
it does not.

**Sudo credential:** See §6 for full trace of credential lifecycle.

---

### Block 6 — Line 93: Completion Log

```bash
log "Hardening done. Rollback: $ROLL"
```

Prints the rollback path to stdout. This is only reached if no `exit 1` or `set -e`
abort fired. A successful final log does not imply all three operations succeeded —
the PAM and firewall operations are guarded with `warn` + continue, so this line
prints even if both privileged operations were silently skipped.

---

## 3. State-Transition Analysis

### 3a — `/etc/pam.d/sudo`

| Dimension | Detail |
|---|---|
| **Pre-state assumed** | File exists, readable as root, contains `pam_opendirectory.so` or `pam_smartcard.so` |
| **Mutation performed** | Backup to `/etc/pam.d/sudo.backup.mrk`; new file written with `pam_tid.so` prepended |
| **Post-state (success)** | `/etc/pam.d/sudo` has Touch ID line first; backup remains at `.backup.mrk`; rollback script has restore command |
| **Post-state (partial fail: backup ok, write fails)** | Original restored from backup; `/etc/pam.d/sudo.backup.mrk` deleted (via rollback or script cleanup); no Touch ID |
| **Post-state (partial fail: backup fails)** | Original untouched; operation skipped with warning; no rollback entry written |
| **Post-state on SIGINT (after backup, before write)** | Original intact; `.backup.mrk` orphaned; rollback entry written; running rollback moves backup back over original (both are identical — safe but redundant) |
| **Post-state on SIGINT (after write)** | Touch ID enabled; `.backup.mrk` exists; rollback valid; screensaver/firewall not yet changed |
| **Post-state on re-run** | `grep -q 'pam_tid.so'` fires; entire block skipped; rollback entry NOT re-written (because block is skipped) |
| **Rollback** | `sudo mv /etc/pam.d/sudo.backup.mrk /etc/pam.d/sudo` — restores original PAM config |

**Note on backup orphaning:** On re-runs after a successful first run, the backup
`/etc/pam.d/sudo.backup.mrk` still exists from the first run. The script never cleans
it up on subsequent runs (because the idempotency check fires). The backup accumulates
indefinitely until the rollback script is run.

---

### 3b — `/etc/pam.d/sudo.backup.mrk`

| Dimension | Detail |
|---|---|
| **Pre-state assumed** | Does not exist |
| **Mutation performed** | `sudo cp /etc/pam.d/sudo /etc/pam.d/sudo.backup.mrk` |
| **Post-state (success)** | File exists, identical to original `/etc/pam.d/sudo` at time of backup |
| **Post-state (partial fail: write fails)** | Backup moved back to `/etc/pam.d/sudo` (or never written on backup failure) |
| **Post-state on SIGINT** | File exists; script exited before cleanup; orphaned until rollback or manual removal |
| **Post-state on re-run** | Idempotency check fires; this file is never touched again by the script |
| **Rollback** | Consumed by `sudo mv .backup.mrk /etc/pam.d/sudo` |

---

### 3c — Application Firewall Global State

| Dimension | Detail |
|---|---|
| **Pre-state assumed** | Either "on" or "off" (script reads current state) |
| **Mutation performed** | `sudo socketfilterfw --setglobalstate on` (only if was "off") |
| **Post-state (success)** | Firewall globally enabled |
| **Post-state (partial fail)** | Remains "off"; warning printed; rollback entry already written (would try to restore to "off" — correct no-op) |
| **Post-state on SIGINT (after global on, before stealth)** | Firewall on; stealth off; rollback entry written to restore to previous state |
| **Post-state on re-run (firewall was on)** | Idempotency check fires (prev == "on"); skipped entirely — stealth mode NOT evaluated |
| **Rollback** | `socketfilterfw --setglobalstate $prev` — restores prior global state |

---

### 3d — Application Firewall Stealth Mode

| Dimension | Detail |
|---|---|
| **Pre-state assumed** | Not checked; assumed off |
| **Mutation performed** | `sudo socketfilterfw --setstealthmode on` (only if global was off before this run) |
| **Post-state (success)** | Stealth mode on |
| **Post-state (partial fail: setglobalstate failed)** | Never attempted; stealth remains at prior value |
| **Post-state on SIGINT between setglobalstate and setstealthmode** | Firewall globally on; stealth off; no rollback for stealth |
| **Post-state on re-run (firewall already on)** | stealth mode block entirely skipped |
| **Rollback** | **NO ROLLBACK.** Stealth mode persists even after global firewall rollback. |

---

### 3e — `com.apple.screensaver askForPassword` and `askForPasswordDelay`

| Dimension | Detail |
|---|---|
| **Pre-state assumed** | Any value; script reads it |
| **Mutation performed** | `defaults write com.apple.screensaver askForPassword -int 1` + `…Delay -int 0` |
| **Post-state (success)** | Password required immediately on lock; rollback holds prior values |
| **Post-state on partial fail** | `defaults write` failures under `set -e` abort the script; rarely fails for user-domain prefs |
| **Post-state on SIGINT (before line 67-68)** | Values not changed; rollback not written for screensaver (written after PAM block) — no rollback needed, no mutation occurred |
| **Post-state on SIGINT (mid-block)** | One of two values might be written without the other; screensaver requires password but delay might be stale |
| **Post-state on re-run** | Values already at target; prev1=1, prev2=0 read; rollback records "restore to 1/0" — prior original values permanently lost from rollback |
| **Rollback** | `defaults write com.apple.screensaver askForPassword -int $prev1` — after re-run, restores to already-hardened state, not original |

---

### 3f — `~/.mrk/hardening-rollback.sh`

| Dimension | Detail |
|---|---|
| **Pre-state assumed** | May or may not exist |
| **Mutation performed** | Truncated with `>` and rebuilt on every invocation |
| **Post-state (success, first run)** | Contains shebang + PAM restore entry + screensaver restore (with original values) + firewall global restore |
| **Post-state (success, re-run)** | Contains shebang + PAM entry (skipped — block not entered, so NO PAM entry) + screensaver restore (with already-hardened values, not originals) + firewall entry (possibly with "on" as prev) |
| **Post-state on SIGINT (after PAM, before screensaver)** | Contains only the PAM rollback entry; screensaver and firewall entries not yet written |
| **Post-state on re-run after rollback was used** | Previous rollback file has been partially consumed (the PAM entry ran `sudo mv`); new run rewrites with current readings |
| **Rollback** | The rollback file itself has no rollback — if it is corrupted or deleted, all rollback capability is lost |

---

## 4. Failure-Mode Enumeration

### FM1 — Sudo timeout mid-script (user steps away)

Default sudo timeout is 5 minutes. The script's privileged operations span lines 34,
43, 79, and 80. In normal execution all four complete within 2–5 seconds: an expired
credential between them is implausible. If it did expire (e.g., the system was
extremely slow, or sudo was built with 0-second timeout), the subsequent `sudo` calls
would issue a new password prompt to `/dev/tty`. With `2>/dev/null` on each call, any
error output is silenced, but the prompt itself is visible. If the user provides the
password, the call succeeds and execution continues normally. If they time out the new
prompt or if `/dev/tty` is unavailable, the sudo fails, the `if` condition is false,
and the operation is skipped with a warning. The script continues and completes with a
`"Hardening done"` message even though some operations were skipped — the final log
message is not an accurate success indicator.

### FM2 — User answers `n` to a confirmation

There is no confirmation prompt in `scripts/hardening.sh`. `make harden` runs
immediately with no "are you sure?" gate. The README does not warn about this. A user
who expects an interactive confirmation before PAM modification gets none.

### FM3 — PAM file already customized by another tool (ESET, 1Password, MDM)

Corporate MDM, ESET Endpoint Security, and 1Password CLI each modify `/etc/pam.d/sudo`
in their own ways — inserting their own auth module or replacing `pam_opendirectory.so`
with `pam_ldap.so`, `pam_krb5.so`, or a proprietary module. The validation check at
lines 38–39 requires `pam_smartcard.so` OR `pam_opendirectory.so` to be present. If
neither is present (LDAP-only or corporate PAM stack), validation fails, the backup is
restored, and the script emits `"Generated PAM config appears invalid"` with no
explanation. This is the CORRECT outcome — the script correctly refuses to write an
incompatible PAM config. However, the user receives an opaque warning rather than a
diagnostic explaining which auth module is missing and what would need to change to
proceed safely.

If the corporate config uses `pam_opendirectory.so` as a secondary module, validation
passes, the Touch ID line is prepended, and the config is written. This could conflict
with the MDM's intended auth flow if the MDM module is order-sensitive.

### FM4 — PAM validation passes but sudo later fails (silent PAM bug)

The validation only checks for string presence (`grep -q`). A formatting error in the
pam_tid.so line — wrong spacing, wrong module name variant (e.g., `pam_tid` vs.
`pam_tid.so`) — would pass the grep but be silently rejected by PAM at runtime. In
that scenario: `make harden` reports success, but `sudo` ignores the malformed line
and falls through to password auth. Touch ID for sudo silently does not work. This is
not a security regression (password fallback still works), but the user believes Touch
ID is enabled when it is not.

The script uses the exact string `'auth       sufficient     pam_tid.so'` (with
multiple spaces). PAM is generally whitespace-insensitive on most macOS versions for
module config files, so this specific format is not the risk. The risk is a future
macOS update that renames or relocates `pam_tid.so`.

### FM5 — Firewall global state already on; stealth mode was off

When `--getglobalstate` returns "on", the script logs `"Firewall already enabled"` and
skips the entire setglobalstate + setstealthmode block. If stealth mode was off before
running `make harden`, it remains off. No rollback entry is written for this case
(because neither setglobalstate nor setstealthmode was modified). The user who expects
`make harden` to guarantee stealth mode regardless of prior state is not served. This
is a silent gap, not a failure per se, but it makes the target's behavior
non-idempotent with respect to stealth mode.

### FM6 — Stealth mode rollback missing

Confirmed at `02-side-effects.md` security table and traced above (§3d). The rollback
script contains an entry to restore firewall global state but no entry for stealth mode.
After `make harden` followed by `make uninstall` → `yes` to rollback: the firewall
returns to its previous global state (off or on), but stealth mode remains on. The user
is left with stealth mode permanently enabled with no automated path to disable it. To
disable stealth mode manually: `sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode off`.

### FM7 — SIGINT between Touch ID write and validation

Extremely narrow window (~millisecond). If it fires: tmpfile exists (partially or fully
written), backup exists, `/etc/pam.d/sudo` is the ORIGINAL (the validation condition
fires before `sudo cp "$tmpfile" /etc/pam.d/sudo`). State is clean. No PAM change was
made. Rollback entry was written (at line 35 after the successful backup). Running
rollback: moves backup over original (no-op net effect, both are identical). Clean.

### FM8 — SIGINT between validation pass and final PAM write

Another narrow window. After validation passes but before `sudo cp "$tmpfile" /etc/pam.d/sudo`:
state is identical to FM7 (original still in place). Same clean outcome.

### FM9 — Script run twice in succession (re-run)

First run:
- PAM: modified (pam_tid.so prepended); backup at `.backup.mrk`; rollback has PAM entry.
- Screensaver: set to 1/0; rollback has original values.
- Firewall: enabled + stealth; rollback has prior global state.

Second run:
- PAM block: skipped (idempotency check fires, `pam_tid.so` already present). No PAM
  rollback entry written this time.
- Screensaver: prev1 reads 1, prev2 reads 0; rollback records "restore to 1/0" — original
  values LOST.
- Firewall block: prev reads "on"; skips. No stealth mode evaluation.

Result: rollback after second run does NOT undo the screensaver hardening from the
first run, and does not undo Touch ID (the PAM rollback entry was not written on the
second run). The rollback file after the second run is effectively useless for undoing
the original hardening.

### FM10 — Script run after the rollback was already used

After rollback: PAM restored (pam_tid.so removed), screensaver restored to original
values, firewall restored to prior global state (stealth mode remains on). Running
`make harden` again starts fresh: Touch ID check fires (pam_tid.so absent → enables
again), screensaver block captures the restored values as "prev" and sets rollback
correctly for those, firewall reads current state. This is a clean re-hardening with
a fresh rollback.

### FM11 — macOS PAM config with non-standard comment header

On some machines or after certain macOS upgrades, `/etc/pam.d/sudo` may begin with a
`# sudo: ...` comment line. Prepending `auth sufficient pam_tid.so` BEFORE this comment
is fine — PAM ignores comment lines in module entries. The comment ends up on line 2
and the Touch ID line is line 1. PAM processes only non-comment lines; line ordering
of comments has no effect on auth behavior.

---

## 5. Recoverability Matrix

| Mutation | Rollback Method | Rating |
|---|---|---|
| `/etc/pam.d/sudo` modified (pam_tid.so added) | `~/.mrk/hardening-rollback.sh` → `sudo mv .backup.mrk /etc/pam.d/sudo` | **Self-recoverable** (first run only) |
| `/etc/pam.d/sudo.backup.mrk` orphaned after SIGINT | Manual: `sudo rm /etc/pam.d/sudo.backup.mrk` | **User-recoverable** |
| Firewall global state enabled | `~/.mrk/hardening-rollback.sh` → `socketfilterfw --setglobalstate $prev` | **Self-recoverable** (first run only) |
| Firewall stealth mode enabled | Manual: `sudo socketfilterfw --setstealthmode off` | **User-recoverable** |
| Screensaver `askForPassword=1` | `~/.mrk/hardening-rollback.sh` → `defaults write … askForPassword -int $prev1` | **Self-recoverable** (first run only; broken on re-run) |
| Screensaver `askForPasswordDelay=0` | Same rollback file | **Self-recoverable** (first run only; broken on re-run) |
| Rollback script truncated on re-run (prior rollback data lost) | Manual: re-derive previous values and write them by hand | **User-recoverable** (requires knowing prior values) |
| PAM corruption (backup lost, harden failed mid-write) | Boot to Recovery; Terminal; restore from Time Machine or `sudo` single-user | **Hard-recoverable** |
| PAM corruption (no backup, no rollback, no recovery media) | Reinstall macOS or boot via Target Disk Mode | **Hard-recoverable** |

No mutation in the normal success path is unrecoverable. The PAM file is the only one
that could reach "hard-recoverable" state (requires recovery media), and this requires
multiple simultaneous failures: backup fails to write AND the existing file is corrupted
AND the rollback script is absent.

---

## 6. Specific Concerns

### 6a — Sudo credential lifecycle

`command -v sudo` (`03-shell-hygiene.md M4`) tells you the binary exists, not that the
user has an active credential or can use sudo at all. When the script runs, the first
actual sudo call is at line 34: `sudo cp /etc/pam.d/sudo /etc/pam.d/sudo.backup.mrk`.
This call is interactive — it will prompt for a password on `/dev/tty` if needed. Once
the user enters their password, the credential is cached for the system's sudo timeout
(default 5 minutes per session, per tty).

All subsequent sudo calls (lines 43, 79, 80) run within the same process, sequentially,
and almost certainly within a few seconds of each other. The credential will be valid
for all of them. There is no documented scenario in which the sudo credential expires
mid-script under normal conditions.

If sudo is configured with `timestamp_timeout=0` (immediate expiry — unusual but
possible under corporate policy), each `sudo` invocation would require a new password
entry. The `if sudo ... 2>/dev/null` pattern handles this gracefully: if the sudo call
fails (no password entered, non-TTY), the conditional is false and the operation is
skipped with a warning. The script does not silently skip and report success — it emits
a warning. However, `log "Hardening done. Rollback: $ROLL"` is still printed at the
end regardless of how many operations were actually skipped.

**Does the script ever lose its credential and report success incorrectly?** No, but
it does report "Hardening done" unconditionally. The completion message is not a
success indicator for all three operations; it means only that the script ran to
completion without an unhandled `set -e` abort. A user who walks away after starting
`make harden` and sees "Hardening done" on return cannot tell from the output alone
whether all three operations succeeded.

### 6b — Stealth mode rollback gap

Confirmed with code citation (line 80 vs. rollback entries at lines 35, 65, 66, 74):

```
Line 74: rollback "/usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate $prev"
Line 80: sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on
```

No `rollback "…setstealthmode…"` call exists anywhere in the script.

**User-facing consequence:** A user who runs `make harden`, later runs `make uninstall`
and chooses to roll back hardening, will have their firewall global state restored
(likely to "off") but stealth mode will remain on. On a machine where the firewall is
turned off, stealth mode being on has no practical effect (stealth mode is a property
of the firewall's behavior; when the firewall is off, all traffic is passed regardless
of stealth setting). However, if the user later turns the firewall back on manually,
they will find stealth mode already on — a setting they did not intentionally set.

### 6c — LDAP / non-standard PAM validation

The validation at lines 38–39 requires the generated PAM config to contain either
`pam_smartcard.so` or `pam_opendirectory.so`. On a standard macOS install, both are
present in the default `/etc/pam.d/sudo`. On an LDAP-bound machine, `pam_opendirectory.so`
may be replaced with `pam_ldap.so` or `pam_krb5.so`. In that case:

- Validation fails (`grep -qE 'pam_smartcard\.so|pam_opendirectory\.so'` returns false).
- The script emits `"Generated PAM config appears invalid — aborting Touch ID setup"`.
- The backup is restored.
- Touch ID is not enabled.

This is the **correct behavior** — it refuses to modify a PAM config it cannot
validate. The weakness is the diagnostic quality: the user receives no information
about which expected module is missing or how to proceed. The check should be expanded
to log which patterns were looked for and what the actual config contains.

One additional edge case: if an MDM pushes a `/etc/pam.d/sudo` that includes
`pam_opendirectory.so` (for fallback) alongside a proprietary MDM module, validation
passes and Touch ID is prepended. If the proprietary MDM module is order-sensitive
and relies on being first, prepending Touch ID before it could break the MDM's auth
flow. The validation logic cannot detect this scenario.

### 6d — PAM module ordering

Apple's PAM auth stack for sudo, when unmodified, on macOS Ventura/Sonoma:

```
auth       sufficient     pam_smartcard.so
auth       required       pam_opendirectory.so
account    required       pam_permit.so
password   required       pam_deny.so
session    required       pam_permit.so
```

After hardening:

```
auth       sufficient     pam_tid.so
auth       sufficient     pam_smartcard.so
auth       required       pam_opendirectory.so
...
```

PAM processes `auth` modules in order. `sufficient` means: if this module succeeds, do
not process further auth modules (provided no earlier `required` module failed). Touch
ID (`pam_tid.so`) at position 1 is tried first. Success → sudo granted immediately.
Touch ID failure (finger not recognized, sensor unavailable) → falls through to
`pam_smartcard.so` (sufficient). Smart Card not present → falls through to
`pam_opendirectory.so` (required — the password prompt). The auth chain degrades
gracefully. Prepending is the correct placement for an "prefer fast-path, fallback to
password" design. It does not break sudo on machines without Touch ID hardware or when
the sensor fails.

---

## 7. Verdict

On a well-configured standard macOS machine with default PAM configuration, `make harden`
is safe to run once. The PAM validation guard is meaningful and correctly rejects
incompatible configs before writing anything. The sudo backup-and-restore pattern is
sound. Failure paths in the Touch ID block restore the original PAM file before exiting.

Repeated runs are problematic in one specific way: the rollback for screensaver settings
is silently destroyed on the second run. After two runs, `~/.mrk/hardening-rollback.sh`
cannot restore the original screensaver state. This is an inherited defect from the
rollback-truncation pattern in `03-shell-hygiene.md M2`, and is the most actionable
issue in this script.

The stealth mode rollback gap is a real but mild bug: the consequence is that stealth
mode persists after rollback, which is low-severity since stealth mode is harmless when
the firewall is off (the rollback-restored state).

On a machine with non-default PAM configuration (LDAP, corporate MDM), the script
correctly refuses to modify the PAM file but gives a poor diagnostic. It is safe but
not fully usable without manual intervention.

The rollback is trustworthy for PAM changes on the first run. It is not trustworthy for
screensaver changes after re-runs, and it is not trustworthy for stealth mode under any
conditions. The target is safe for a standard single-machine personal setup where it is
run once and rolled back if needed, but is not reliable as a day-to-day idempotent
operation.
