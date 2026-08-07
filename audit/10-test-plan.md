# Audit Module 10 — Runtime Test Plan

**Branch:** `main` | **Authored:** 2026-08-07
**Companion:** `audit/11-test-results.md` (results are recorded there, not here)
**Environment:** Tart sandbox, macOS 26.3 (Tahoe), Darwin 25.3.0, ARM64
**VM source:** `mrk-audit-clean-prepared` snapshot (Tart, copy-on-write clone per test)

---

## Why this file exists

`11-test-results.md` and `00-followups.md` both referenced a test plan at
`docs/audit/10-test-plan.md`. It was never committed at any path, so Tests 1C, 2, 3 and 4
were defined nowhere and could not be run. This file is that plan, written against the
scripts as they stand **after** the N-1, N-2 and N-3 fixes, not against the state the
original plan would have described.

Expected results below are derived from reading the current scripts. Where the derivation
contradicts an earlier prediction, that is called out rather than silently reconciled.

---

## Test ID scheme

The IDs continue the scheme already used in `11-test-results.md`. The `1x` family is
rollback fidelity; the standalone numbers are the whole-system properties.

| ID | Property | Status before this plan |
|---|---|---|
| 1A | Rollback fidelity — `make defaults` | PASS, run 2026-04-26 |
| 1B | Rollback fidelity — `make harden` | PASS after fix, run 2026-04-26 |
| **1C** | **Rollback fidelity — combined** | **not run** |
| **2** | **Idempotency — `make all` twice** | **not run** |
| **3** | **Order-independence — brew vs post-install** | **not run** |
| **4** | **Re-entry recovery — interrupt and failing write** | **not run** |

---

## What the install actually does

Established by reading the scripts, and the basis for every expectation below.

`make all` = `fix-exec setup brew post-install build-tools`. **`make harden` is not part of
`make all`** — it is opt-in and separate. This matters for Test 1C's scope.

`scripts/setup` runs five phases: `xcode`, `tools`, `dotfiles`, `defaults`, `shell`.
The macOS defaults are applied inside `setup`, not by a separate top-level phase.

`scripts/defaults.sh` writes 13 domains. `write_default` reads the current value first,
appends the inverse to the rollback file **before** its idempotency check, then skips the
write when the value and type already match. So a second run performs no `defaults write`
calls but leaves the rollback file unchanged, because `backup_line` dedups with `grep -qFx`
and the pre-existing-entry guard skips the append.

The rollback file is **appended to, not truncated**, when it already exists and carries the
expected shebang (`scripts/defaults.sh:27`). Re-running preserves first-run originals.

Failure counting uses the N-1 safe form `|| failed=$(( failed + 1 ))` in both
`scripts/defaults.sh` and `scripts/post-install`. A refused write increments the counter and
the run continues to the summary.

`scripts/setup` computes `BACKUP_DIR` with a timestamp at line 103 but calls `mkdir -p` on it
only at the first actual backup (`:500`). A no-op re-run therefore creates **no** new
timestamped directory. This is the M1 fix and is a load-bearing assertion for Test 2.

`scripts/post-install` guards its expensive steps with skip-if-exists checks: browser
policies, the topgrade config link, the openjdk symlink, nvm, the pyenv runtime, the GitHub
app installs, and the plist imports.

`scripts/hardening.sh` maintains a **separate** rollback file, `~/.mrk/hardening-rollback.sh`,
with its own dedup helper. The two rollback files never write to each other.

---

## Environment and clean baseline

Every test starts from the same place. Do not reuse a VM between tests.

```bash
tart clone mrk-audit-clean-prepared mrk-test-<ID>
tart run mrk-test-<ID>
```

Inside the VM, before anything else:

```bash
git -C ~/mrk rev-parse HEAD     # record the commit under test
sw_vers                          # record the OS build
```

Record both in the results entry. A test run against an unrecorded commit is not evidence.

---

## State capture

The same capture is used by every test. Write it once in the VM as `~/capture.sh` and call it
with a label; it writes a directory of plain-text artifacts that `diff -r` can compare.

The domain list is exactly the set `scripts/defaults.sh` writes, plus the hardening domain,
plus the trackpad domains for the `--with-trackpad` path.

```bash
#!/usr/bin/env bash
# ~/capture.sh <label>   ->   ~/captures/<label>/
#
# Deliberately NOT `set -e`. A probe that fails or stalls must degrade to an
# empty artifact, never abort the capture: a half-written capture directory is
# worse than none, because `diff -r` cannot tell a missing file from a changed
# one and the verdict becomes unreadable. Every probe is therefore guaranteed to
# leave a file behind, and every probe runs under a timeout.
#
# A probe that times out is recorded in _incomplete.txt. If that file is
# non-empty, the capture is NOT evidence — fix the cause and re-run.
set -uo pipefail
label="${1:?usage: capture.sh <label>}"
out="$HOME/captures/$label"; mkdir -p "$out"
: > "$out/_incomplete.txt"

TMO="${CAPTURE_TIMEOUT:-20}"
probe(){
  local name="$1"; shift
  local f="$out/$name" rc=0
  : > "$f"
  timeout "$TMO" bash -c "$*" > "$f" 2>/dev/null || rc=$?
  (( rc == 124 )) && printf '%s TIMED OUT after %ss\n' "$name" "$TMO" >> "$out/_incomplete.txt"
  return 0
}

DOMAINS=(
  NSGlobalDomain com.apple.dock com.apple.finder com.apple.screencapture
  com.apple.desktopservices com.apple.frameworks.diskimages com.apple.TimeMachine
  com.apple.SoftwareUpdate com.apple.commerce com.apple.ActivityMonitor
  com.apple.TextEdit com.apple.Terminal com.apple.menuextra.clock
  com.apple.screensaver
  com.apple.AppleMultitouchTrackpad
  com.apple.driver.AppleBluetoothMultitouch.trackpad
)
for d in "${DOMAINS[@]}"; do
  probe "defaults.$d.xml" "defaults export $d - | plutil -convert xml1 -o - -"
done

# Symlinks: link -> target, sorted. basename/readlink without -exec sh -c,
# which forks a shell per entry and is the slowest part of the capture.
probe bin-symlinks.txt \
  'find "$HOME/bin" -maxdepth 1 -type l | while read -r l; do printf "%s -> %s\n" "${l##*/}" "$(readlink "$l")"; done | sort'
probe dotfile-symlinks.txt \
  'find "$HOME" -maxdepth 1 -type l | while read -r l; do printf "%s -> %s\n" "${l##*/}" "$(readlink "$l")"; done | sort'

# Login items, by name, sorted. Needs Automation access — see the VM note below.
probe login-items.txt \
  'osascript -e "tell application \"System Events\" to get the name of every login item" | tr "," "\n" | sed "s/^ *//" | sort'

# Installed package set
probe brew-leaves.txt   'brew leaves --installed-on-request | sort'
probe brew-formulae.txt 'brew list --formula | sort'
probe brew-casks.txt    'brew list --cask | sort'

# State directory: rollback files verbatim, backups by directory name only
probe defaults-rollback.sh  'cat "$HOME/.mrk/defaults-rollback.sh"'
probe hardening-rollback.sh 'cat "$HOME/.mrk/hardening-rollback.sh"'
probe backup-dirs.txt       'ls -1 "$HOME/.mrk/backups" | sort'

# Privileged / security state
probe fw-global.txt  '/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate'
probe fw-stealth.txt '/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode'
probe pam-sudo.sha   'shasum /etc/pam.d/sudo'

# Application presence (plist-import and GitHub-app targets)
probe applications.txt 'ls -1 /Applications | sort'

if [[ -s "$out/_incomplete.txt" ]]; then
  echo "CAPTURE INCOMPLETE — see $out/_incomplete.txt" >&2
  cat "$out/_incomplete.txt" >&2
fi
```

**Two VM prerequisites this harness has.** Both were found by running it, not by
reading it:

- **`timeout` must exist.** It is GNU coreutils, not stock macOS. The Brewfile installs
  coreutils and `dotfiles/.zprofile:15-24` puts `gnubin` on `PATH`, so it is present
  after `make brew` — but **not** in a capture taken before that. For a pre-`brew`
  baseline, install coreutils first or substitute `gtimeout`.
- **Automation access must be pre-granted**, or `login-items.txt` times out on the
  consent dialog and every capture is incomplete. Grant it once in the base image before
  snapshotting, the same permission `sync-login-items` needs.

**Excluded from every diff, by design.** These change on any run and are not evidence of a
write:

- `~/.mrk/install.log` — appended to by every phase.
- Timestamps and inodes — the capture records content and link targets, never `stat` output.
- `~/.mrk/preferences/` — a git clone of `mrk-prefs`; network-dependent and out of scope.
- Homebrew's own metadata under `$(brew --prefix)/var/homebrew/` — churns independently.

Compare two captures with:

```bash
diff -r ~/captures/<a> ~/captures/<b>
```

### Pre-flight: prove the harness before trusting a verdict

Every verdict in this plan is a `diff -r` between two captures, so the harness must be
deterministic in the VM before any test runs. Take two captures back to back, changing
nothing between them:

```bash
~/capture.sh preflight-a
~/capture.sh preflight-b
diff -r ~/captures/preflight-a ~/captures/preflight-b     # must be empty
cat ~/captures/preflight-a/_incomplete.txt                # must be empty
```

If the diff is non-empty, something in the capture set is not stable on that machine and
**no test below can be trusted** — find it and exclude it before continuing. If
`_incomplete.txt` is non-empty, a probe timed out; raise `CAPTURE_TIMEOUT` or fix the cause
(most often the Automation prompt) and re-run.

This step is not optional. It was added because the harness was observed stalling on a
different `defaults export` domain on successive runs during authoring, which would have
produced a spurious diff and a false FAIL. Confirming the harness first turns that class of
problem into a pre-flight failure rather than a wrong verdict about mrk.

---

## Test 1C — Rollback fidelity, combined

### Purpose

`make defaults` and `make harden` each maintain their own rollback file. 1A and 1B proved
each is faithful alone. 1C proves they are faithful **together**: that applying both and then
reverting both returns the machine to baseline, and that neither rollback disturbs the other's
domain.

### Scope, and a correction to the earlier prediction

`00-followups.md` predicted a PARTIAL verdict for 1C "because ~40 browser and app-preference
keys have no rollback coverage." **That prediction does not apply to this test as scoped.**
Those keys are written by `assets/browsers/` and `assets/preferences/`, which are invoked from
`scripts/post-install` (`:157,173,189,203,356,363,369,373`). Neither `make defaults` nor
`make harden` runs them, so those keys are never written during 1C and cannot fail to roll
back.

The uncovered-rollback limitation is real, but it belongs to a **full-install rollback**, which
is a different test and is not in this plan's scope. 1C is expected to PASS. If a future test
of full-install rollback is added, it should take a new ID rather than inherit 1C's.

### Setup

Fresh clone. Run `make setup` first so the tool symlinks exist, then capture.

### Capture points

`baseline` (after `make setup`, before `make defaults`), `applied` (after both applies),
`reverted` (after both rollbacks).

### Procedure

1. `~/capture.sh baseline`
2. `cd ~/mrk && make defaults`
3. `make harden`
4. `~/capture.sh applied`
5. `bash ~/.mrk/hardening-rollback.sh`
6. `bash ~/.mrk/defaults-rollback.sh`
7. `~/capture.sh reverted`
8. `diff -r ~/captures/baseline ~/captures/reverted`

Run the hardening rollback **first**. Hardening's screensaver keys sit in
`com.apple.screensaver`, which `defaults.sh` does not touch, so the order is not expected to
matter; running it first makes any coupling visible as an ordering-dependent failure rather
than masking it.

### Expected result

- Step 8 reports differences only in the two rollback-script files themselves and in
  `backup-dirs.txt` if `make setup` created a backup. The defaults domains, firewall state and
  `pam-sudo.sha` match baseline exactly.
- `fw-global.txt` and `fw-stealth.txt` return to their baseline values.
- The screensaver keys are **deleted**, not set to `0`, where they were absent at baseline —
  this is the behaviour `hardening.sh:103-115` implements.

### Pass / fail

- **PASS** — every captured artifact except the rollback scripts and `backup-dirs.txt` is
  byte-identical between `baseline` and `reverted`.
- **PARTIAL** — the defaults domains match but a privileged item (firewall, pam) does not.
- **FAIL** — any domain that `defaults.sh` or `hardening.sh` wrote differs from baseline.

---

## Test 2 — Idempotency

### Purpose

A second full install must be a no-op. This is the property that makes `make all` safe to
re-run, and it is the one users exercise most often without thinking about it.

### Setup

Fresh clone. Nothing pre-applied.

### Capture points

`run1` (after the first `make all`), `run2` (after the second).

### Procedure

1. `cd ~/mrk && make all` — let it finish.
2. `~/capture.sh run1`
3. `make all` again, capturing stdout/stderr to `~/run2.log`.
4. `~/capture.sh run2`
5. `diff -r ~/captures/run1 ~/captures/run2`

### "No changes", concretely

Against the module-02 write set, the second run must leave all of these byte-identical:

| Artifact | Why it must not change |
|---|---|
| All 13 `defaults.*.xml` domains | `write_default` skips when value and type already match |
| `defaults-rollback.sh` | `backup_line` dedups; the pre-existing-entry guard blocks re-append |
| `hardening-rollback.sh` | Absent unless `make harden` ran; `make all` does not run it |
| `bin-symlinks.txt` | `setup` skips a symlink already pointing at the right target |
| `dotfile-symlinks.txt` | Same |
| `login-items.txt` | `add_login_item` must not create a duplicate entry |
| `brew-leaves/formulae/casks.txt` | `brew bundle` installs nothing already present |
| `backup-dirs.txt` | **No new timestamped directory.** `BACKUP_DIR` is created lazily at `setup:500`, and a no-op run displaces no dotfile |
| `applications.txt` | GitHub app installs are install-only and skip when present |

### Expected result

`diff -r` reports **no differences at all**. `~/run2.log` shows skip messages
(`logskip`) for the browser policies, topgrade config, openjdk symlink, nvm, pyenv runtime and
the GitHub apps, and the defaults phase reports no failures.

### Pass / fail

- **PASS** — `diff -r` is empty.
- **PARTIAL** — differences confined to `backup-dirs.txt` **or** an additive-only change in a
  rollback file. Both indicate a real idempotency defect but a contained one; record which.
- **FAIL** — any defaults domain, symlink set, login-item list or package set differs, or a
  login item is duplicated.

---

## Test 3 — Order-independence

### Purpose

The README claims the phases may be run in any order after the initial bootstrap. This test
defines what that can legitimately mean and checks the invariant.

### What ordering can vary, and what cannot

`make setup` is **not** order-independent and is not part of this test. It links the tools that
later phases call and applies the dotfiles the shell needs; it must run first. This is the
"initial bootstrap" the README's claim excludes.

The two phases whose order can vary are `brew` (Phase 2) and `post-install` (Phase 3).

Within `post-install`, the operations are order-independent among themselves: each is guarded
by its own skip-if-exists check and none consumes another's output.

### The invariant

After `make setup`, running **both** `brew` and `post-install` must converge to the same end
state regardless of which ran first — allowing, in the `post-install`-first case, the re-run
that convergence requires.

This is deliberately two claims, because static analysis predicts they differ:

- **Claim A (single pass each):** end state after `brew; post-install` equals end state after
  `post-install; brew`. **Predicted to FAIL.** `post-install` configures apps and imports
  plists only when the app is present; run before `brew`, those steps hit their skip guards and
  never happen.
- **Claim B (converged):** end state after `brew; post-install` equals end state after
  `post-install; brew; post-install`. **Predicted to PASS**, because the second `post-install`
  finds the apps installed and performs the skipped work.

### Setup

**Two** fresh clones, `mrk-test-3a` and `mrk-test-3b`. Both run `make setup` first.

### Procedure

On `mrk-test-3a`:
1. `make setup && make brew && make post-install`
2. `~/capture.sh order-a`

On `mrk-test-3b`:
1. `make setup && make post-install && make brew`
2. `~/capture.sh order-b-singlepass`
3. `make post-install`
4. `~/capture.sh order-b-converged`

Copy the capture directories to one host and diff:

```bash
diff -r order-a order-b-singlepass    # Claim A
diff -r order-a order-b-converged     # Claim B
```

### Expected result

Claim A shows differences in `applications.txt` behaviour-dependent items and in the
app-preference domains that plist import populates — specifically the browser policy files and
the 14 `import_plist` targets at `scripts/post-install:464-477`. Claim B shows no differences.

### Pass / fail

- **PASS** — Claim B diff is empty. Claim A's differences are confined to the app-configuration
  artifacts named above and are explained by the skip guards.
- **PARTIAL** — Claim B converges except for a named artifact; record which and why.
- **FAIL** — Claim B does not converge, or Claim A differs in the base defaults domains, the
  symlink sets or the package set, none of which depend on app presence.

**Documentation consequence.** If Claim A fails as predicted, the README's "any order" claim is
too strong and should say that `post-install` must follow `brew`, or be re-run after it. Record
that as a follow-up rather than editing the README from inside the test.

---

## Test 4 — Re-entry and recovery

### Purpose

This is the test that would have caught N-1. It has two independent parts: an interruption, and
an injected failing write. Both must leave the system re-runnable and the rollback file
well-formed.

### Part 4a — interruption

**Setup.** Fresh clone, `make setup && make brew` completed.

**Procedure.**
1. `~/capture.sh pre-interrupt`
2. Start `make post-install`. Send `SIGINT` during the GitHub-app install step, which is the
   window where a DMG is mounted (`install_github_app`).
3. Immediately check for a leaked mount: `mount | grep -i '/Volumes/'` and `ls /Volumes`.
4. `~/capture.sh interrupted`
5. `make post-install` again, to completion.
6. `~/capture.sh recovered`
7. Compare `recovered` against a clean `brew; post-install` capture from Test 3's `order-a`.

**Expected result.** No DMG remains mounted after the interrupt. Two traps cooperate here and
both must fire: the script-level `INT`/`TERM` trap at `scripts/post-install:61` prints
`interrupted — exiting` and exits 1, which then triggers the `_cleanup_github_app` `EXIT` trap
installed at `:323`, whose `hdiutil detach` at `:319` releases the mount. The re-run completes
and reports no failures. `recovered` matches `order-a`.

### Part 4b — injected failing write (the N-1 trigger)

**Setup.** Fresh clone. Shadow the real `defaults` binary with a stub that refuses exactly one
key and passes everything else through, so the failure is guaranteed and isolated:

```bash
mkdir -p ~/stub && cat > ~/stub/defaults <<'EOF'
#!/usr/bin/env bash
# Refuse one specific write; delegate everything else.
if [[ "$1" == "write" && "$3" == "AppleKeyboardUIMode" ]]; then
  echo "stub: refusing write to $2 $3" >&2
  exit 1
fi
exec /usr/bin/defaults "$@"
EOF
chmod +x ~/stub/defaults
export PATH="$HOME/stub:$PATH"
```

**Procedure.**
1. `~/capture.sh pre-inject`
2. `bash scripts/defaults.sh` with the stub on `PATH`, capturing output to `~/inject.log`
3. Record the exit code.
4. `~/capture.sh injected`
5. Inspect `~/.mrk/defaults-rollback.sh`: line count, shebang present, executable bit,
   and that it parses — `bash -n ~/.mrk/defaults-rollback.sh`
6. Remove the stub from `PATH` and re-run `bash scripts/defaults.sh` to completion.
7. `~/capture.sh recovered-inject`

**Expected result.** This is the precise N-1 assertion:

- The run **does not abort** at the refused write. It continues through every remaining write.
- `~/inject.log` ends with the summary line `1 default(s) failed to apply` from
  `scripts/defaults.sh:387-389`.
- Every other domain in `injected` is fully applied — the failure is isolated to
  `AppleKeyboardUIMode`.
- The rollback file is **well-formed**: starts with `#!/usr/bin/env bash`, is executable,
  passes `bash -n`, and contains an entry for each domain+key touched before *and after* the
  refused write. A file that stops at the refusal is the N-1 regression.
- The step-6 re-run applies the previously refused key and reports zero failures.

### Pass / fail

- **PASS** — 4a and 4b both meet every expectation above.
- **PARTIAL** — 4a passes and 4b's run continues and counts the failure, but the rollback file
  has a cosmetic defect (for example a missing trailing `killall` line).
- **FAIL** — the run aborts at the refused write, the rollback file is truncated at the point of
  failure, the summary is absent, or a DMG remains mounted after the interrupt. Any of these is
  an N-1 regression and stops the session.

---

## Recording results

Extend `audit/11-test-results.md` in its existing format: update the Executive Summary table
verdicts, add a `## Test <ID>` section per test with Procedure / Evidence / Verdict, and replace
the "Tests Deferred" section with the outcomes. Keep the evidence verbatim — captured diffs and
log excerpts, not paraphrase.

State explicitly whether the N-1, N-2 and N-3 fixes hold, since these tests are the runtime
confirmation those static fixes never had:

- **N-1** — Test 4b. The run continues past a refused write and the rollback file stays
  well-formed.
- **N-3** — Tests 1C and 2 both call `sync-login-items` indirectly through no path, so N-3 is
  **not** covered here; it was reproduced with a stubbed `osascript` in the fix session and that
  remains its evidence. Do not claim runtime coverage this plan does not provide.
- **N-2** — the secret-scanner fixes are exercised by `snapshot-prefs` and `mrk-push`, neither of
  which any test above runs. Same caveat: not covered here.

---

## Known limitations that will shape verdicts

These are expected and must not be recorded as test failures.

- **~40 browser and app-preference writes have no rollback.** Out of scope for 1C as scoped
  above; would matter to a full-install rollback test, which does not exist.
- **Plist imports are skip-if-exists.** A domain already populated is left alone, which is what
  makes Test 3's Claim A fail in a predictable, documented way.
- **Network dependence.** `brew`, the GitHub app installs and `pull-prefs` all need the network.
  A network failure is an inconclusive run, not a FAIL — re-run it.
