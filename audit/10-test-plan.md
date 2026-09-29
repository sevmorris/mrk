# Audit Module 10 — Runtime Test Plan

**Branch:** `main` | **Authored:** 2026-08-07 | **Refreshed:** 2026-09-28, against `0309878`
**Companion:** `audit/11-test-results.md` (results are recorded there, not here)
**Environment:** Tart VM, macOS 26 (Tahoe), matching the host's 26.7, ARM64
**VM source:** `mrk-audit-clean-prepared`, built as described under Environment (Tart,
copy-on-write clone per test)

---

## Why this file exists

`11-test-results.md` and `00-followups.md` both referenced a test plan at
`docs/audit/10-test-plan.md`. It was never committed at any path, so Tests 1C, 2, 3 and 4
were defined nowhere and could not be run. This file is that plan. It was first written
against the scripts as they stood after the N-1, N-2 and N-3 fixes.

Expected results below are derived from reading the current scripts. Where the derivation
contradicts an earlier prediction, that is called out rather than silently reconciled.

## Refresh, 2026-09-28

Between 2026-08-07 and 2026-09-28, audits 14 to 19 changed most of what this plan describes.
The first version was also written on a Mac whose base image, `mrk-audit-clean-prepared`, did
not survive the 2026-09-15 migration: this Mac has no Tart and no `~/.tart`. Every fact and line
reference below was re-read from the scripts at `0309878`, and every expected result was
derived again. The test IDs and the verdict rules are unchanged.

Seven changes alter a test, not just a line number:

1. **Test 1C's baseline was wrong.** `setup`'s last phase runs `scripts/defaults.sh`
   (`setup:797`, `:617`). A baseline taken after `make setup` therefore already had the
   defaults applied. Reverting would have gone back past it, so 1C would have failed for a
   reason that is not a defect. The baseline is now taken after
   `make setup ARGS=--no-defaults`.
2. **Test 4a's leak check could not see a leak.** The app installer, now `scripts/install-apps`,
   attaches each DMG with `-nobrowse` at a temporary directory, `$TMPDIR/mrk.XXXXXX`, not under
   `/Volumes` (`install-apps:121`, `:139`). The check is now `hdiutil info`, and a look for
   leftover `mrk.*` temporary paths.
3. **The plist imports need `~/.mrk/preferences`.** That is a clone of the private `mrk-prefs`,
   pulled over SSH. A VM has neither, so every import would skip in every test, and Test 3's
   Claim A could not show its main expected difference. The base image is now seeded with
   fixture plists; see Environment.
4. **`make harden` changed completely.**
   - The screensaver keys are gone. The screen-lock delay is set through `sysadminctl`, which
     needs the login password, so an unattended run prints the command and changes nothing.
   - Three steps are new: LSQuarantine, Mac Analytics and Handoff.
   - Touch ID for `sudo` goes in `/etc/pam.d/sudo_local`.
5. **`defaults.sh` exits 1 when a write fails** (audit 19, W-19). Test 4b expects exit 1 where
   it expected 0.
6. **Homebrew's installer runs without a terminal.** `install.sh` switches to non-interactive
   mode when stdin is not a TTY, and then needs `sudo` without a password (`install.sh`
   `:129-146`, `:304`). The base image provides that. It needs no `NONINTERACTIVE=1`.
7. **post-install is larger.** The browser policies are gone, there are 17 plist imports, not
   14, and each import now writes a whole-domain undo line (W-13). New steps install
   LaunchAgents, Claude Code links, Node through nvm, and fonts and configs from the preferences.

The capture script changed too:
- the domain list follows `defaults.sh` and `hardening.sh`;
- an absent domain and an emptied one both read `EMPTY`, so a revert that leaves an empty
  domain does not fail on that alone;
- `timeout` falls back to `perl`, since macOS 26 has no `timeout` and coreutils is not
  installed before `make brew`;
- the new state (LaunchAgents, Node, Python, links outside `~`) is captured.

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

1A and 1B ran against a `make harden` that has since changed completely (item 4 above). 1C
covers the current one.

---

## What the install actually does

Read from the scripts at `0309878`. This is the basis for every expectation below.

**`make all`** is `fix-exec setup brew post-install build-tools` (`Makefile:65`). **`make harden`
is not part of it** (`Makefile:146`). It is opt-in and separate, which matters for Test 1C's
scope.

**`scripts/setup`** runs under the `/bin/bash` 3.2 that macOS supplies (audit 19, W-1). Its
phases run in this order: `xcode`, `tools`, `dotfiles`, `shell`, `defaults` (`setup:793-797`).
- **The `defaults` phase runs `scripts/defaults.sh`** (`setup:617`), so every `make setup`
  applies the macOS defaults. `--no-defaults` skips that phase.
- **Backups.** `setup` computes `BACKUP_DIR` with a timestamp at `setup:126`, but creates it only
  at the first backup (`setup:566`). A no-op re-run therefore creates **no** new timestamped
  directory, and Test 2 depends on that. Since 2026-09-28 anything in a dotfile's place is backed
  up, except a link that already reaches the same file.

**`scripts/defaults.sh`** writes 136 keys across 36 domains. The trackpad keys go into two more
domains, and only with `--with-trackpad` (`defaults.sh:464`), which `make trackpad` passes and
`make all` does not.
- **Each write.** `write_default` (`defaults.sh:93`) reads the current value, and records the
  inverse in the undo file **before** its already-set check. It skips the write when the value
  and type already match. `backup_line` (`:59`) dedups with `grep -qFx`. So a second run makes no
  `defaults write` call, and leaves the undo file unchanged.
- **The undo file.** `init_rollback` (`lib.sh:112`) keeps an existing file whose first line is
  any shebang. Until 2026-09-27 it emptied one whose shebang was not exactly
  `#!/usr/bin/env bash` (W-3).
- **Failures.** A refused write counts `|| failed=$(( failed + 1 ))`, and the run goes on. At the
  end the script writes the `killall` lines and restarts Finder, the Dock and SystemUIServer.
  When any write failed, it prints `N default(s) failed to apply; the rest are applied. Revert
  with: …` and **exits 1** (`defaults.sh:668-671`).

**`scripts/post-install`** continues whether or not Homebrew is on the PATH
(`homebrew_on_path || true`, `:71`), and traps `INT` and `TERM` (`:100`). Each step guards
itself:

| Step | Where | Skips or does nothing when |
|---|---|---|
| topgrade config link | `:179-196` | already linked |
| `~/Projects` CLAUDE.md and skills links | `:200-260` | already linked, or no `~/Projects` |
| dependency-updates skill and SessionStart hook | `:262-306` | already linked, hook already present |
| plist imports, 17 (`import_plist`) | `:414`, calls `:465-493` | app absent, plist absent from `~/.mrk/preferences`, or domain not empty |
| app-defaults scripts | Safari `:504`, Helium `:544`, Audio Hijack `:737`, Fission `:744`, Rogue Amoeba `:751`, AlDente `:755` | app absent; Safari also without Full Disk Access |
| openjdk link | `:556` | link present, or no Homebrew openjdk |
| nvm, pinned, then the Node LTS | `:592-638` | nvm present; a default Node already set |
| pyenv Python from `.python-version` | `:659-712` | already installed; **silently** when pyenv is absent |
| GitHub apps, 7 (`install_companion_apps`) | `:722`, `install-apps:58-66` | app present (install-only) |
| pinentry-mac line in `gpg-agent.conf` | `:836-` | already set, or no pinentry-mac |
| login items (AlDente, BetterSnapTool, Chrono Plus, Dropbox, Raycast, Thaw) | `:962-967` | app absent, or item already present |
| LaunchAgents `com.user.clear_app_caches`, `com.user.clear_derived_data` | `:1005-1006` | already installed |

- **The import order.** The imports run **before** the app-defaults scripts, so mrk's keys land
  on top of the restored preferences (W-2).
- **The import undo.** Each import appends a whole-domain undo line to
  `~/.mrk/defaults-rollback.sh`. `make uninstall` and `nuke-mrk` offer those lines separately
  (W-13).

**`scripts/hardening.sh`** keeps its own undo file, `~/.mrk/hardening-rollback.sh`
(`init_rollback`, `:49`). The two undo files never write to each other, and no domain is written
by both scripts. It has six steps:

| Step | Where | What it changes | Undo |
|---|---|---|---|
| 1 Touch ID for `sudo` | `:65` | a `pam_tid` line in `/etc/pam.d/sudo_local`, which `/etc/pam.d/sudo` includes | put the old file back, or remove it |
| 2 screen-lock delay | `:148` | `sysadminctl -screenLock immediate`, which needs the login password: **only at a terminal**. Unattended, it prints the command and changes nothing | the previous delay |
| 3 firewall | `:197` | global state and stealth mode on | the previous states |
| 4 quarantine prompt | `:273` | `com.apple.LaunchServices LSQuarantine false` (lowers the security floor, deliberately) | restore or delete the key |
| 5 Mac Analytics | `:310` | `AutoSubmit`, `ThirdPartyDataSubmit` false in `/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist`, with `sudo` | restore or delete each |
| 6 Handoff | `:353` | `-currentHost com.apple.coreservices.useractivityd` keys false | restore or delete each |

`confirm` (`lib.sh:48`) passes without a TTY, and so does `--yes`, so `make harden` runs
unattended apart from step 2.

---

## Environment and clean baseline

Every test starts from the same place. Do not reuse a VM between tests.

### Building the base image, once

Items marked **owner** need the owner. The rest can be driven from the host.

1. **Tart on the host (owner's approval).** `brew install cirruslabs/cli/tart`. It is not in the
   Brewfile, so `sync` offers it afterwards. Remove it when the tests are recorded, or add it.
2. **A macOS 26 image (owner's approval).** It comes from Cirrus Labs' registry,
   `ghcr.io/cirruslabs`, and is tens of gigabytes. Confirm the current Tahoe image's name and size
   before pulling. `tart clone <image> mrk-base`.
3. **In the VM:**
   - **Command Line Tools.** Installed, or installed now: `xcode-select --install` opens a
     dialog.
   - **Passwordless `sudo`** for the test user, proved with `sudo -n true`. Cirrus images ship
     it. The Homebrew installer, `setup`'s `chsh` and `make harden` rely on it.
   - **Access without a typed password.** `tart exec` where the image's guest agent supports it,
     or else SSH with a key in `~/.ssh/authorized_keys`.
4. **Grants, once, in the VM's window (owner).** The runner is the process the commands run
   under: the guest agent, or the SSH session.
   - **Automation.** The runner must be allowed to control System Events, for the login-items
     capture and `add_login_item`. Without it, `login-items.txt` times out on the consent dialog.
   - **Full Disk Access** for the runner, for the Safari defaults and the Mac Analytics plist.
     Without it both are skipped, consistently, in every run. That is not a failure, but it
     leaves them unexercised.
5. **mrk.** `git clone https://github.com/sevmorris/mrk ~/mrk`. Each test checks out the commit
   under test.
6. **Fixture preferences.** Seed `~/.mrk/preferences/` with one plist per `import_plist` target,
   under the file name post-install expects (`post-install:465-493`). Each is a small dictionary
   with one harmless key, **made in the VM, not copied from `mrk-prefs`**, so no personal
   setting enters the image.
   - Because `~/.mrk/preferences` exists, post-install does not try to pull `mrk-prefs`
     (`post-install:404`), which in any case needs an SSH key the VM does not have.
   - Without the fixtures every import skips in every test, and Test 3's Claim A has nothing to
     show.
7. **`~/capture.sh`,** from the next section.
8. **Shut down.** Rename the image `mrk-audit-clean-prepared`. It is never run directly again.

### Each test

```bash
tart clone mrk-audit-clean-prepared mrk-test-<ID>
tart run --no-graphics mrk-test-<ID> &
```

Inside the VM, before anything else:

```bash
git -C ~/mrk checkout <commit under test>
git -C ~/mrk rev-parse HEAD     # record the commit under test
sw_vers                          # record the OS build
```

Record both in the results entry. A test run against an unrecorded commit is not evidence.
When the captures are copied to the host, `tart delete mrk-test-<ID>`.

- **Two VMs at most.** macOS runs at most two macOS guests at once. Test 3 needs exactly two.
- **Disk.** A clone is copy-on-write, but a full Homebrew install adds tens of gigabytes to it.
  Keep one test VM at a time, except for Test 3.

---

## State capture

The same capture is used by every test. It lives in the base image as `~/capture.sh`, and is
called with a label. It writes a directory of plain-text artifacts that `diff -r` can compare.

The domain list is exactly the set `scripts/defaults.sh` writes (36 domains), plus the two
trackpad domains, plus `hardening.sh`'s LaunchServices domain. Handoff's ByHost domain and the
Mac Analytics plist are captured separately, because neither is an ordinary user domain.

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
# macOS 26 has no timeout(1), and coreutils arrives only with `make brew`. perl's
# alarm does the same job: the child is killed by SIGALRM, exit 142.
run_timed(){
  if command -v timeout >/dev/null 2>&1; then timeout "$TMO" "$@"
  else perl -e 'alarm shift; exec @ARGV' "$TMO" "$@"; fi
}
probe(){
  local name="$1"; shift
  local f="$out/$name" rc=0
  : > "$f"
  run_timed bash -c "$*" > "$f" 2>/dev/null || rc=$?
  (( rc == 124 || rc == 142 )) && printf '%s TIMED OUT after %ss\n' "$name" "$TMO" >> "$out/_incomplete.txt"
  return 0
}
# domain_xml [-currentHost] export DOMAIN — the domain as XML. An absent domain
# and an emptied one both read EMPTY: a revert that deletes every key it added
# can leave an empty plist behind, and that is not a difference.
domain_xml(){
  local x
  x=$(defaults "$@" - 2>/dev/null | plutil -convert xml1 -o - - 2>/dev/null)
  if [[ -z "$x" ]] || ! grep -q "<key>" <<<"$x"; then echo EMPTY; else printf '%s\n' "$x"; fi
}

DOMAINS=(
  NSGlobalDomain com.apple.Accessibility com.apple.ActivityMonitor com.apple.AdLib
  com.apple.airplay com.apple.amp.mediasharingd com.apple.assistant.support com.apple.chronod
  com.apple.CrashReporter com.apple.desktopservices com.apple.dock com.apple.dt.Xcode
  com.apple.finder com.apple.FolderActionsDispatcher com.apple.frameworks.diskimages
  com.apple.HIToolbox com.apple.iCal com.apple.mail com.apple.menuextra.clock
  com.apple.messages.nicknames com.apple.Music com.apple.Passwords
  com.apple.Safari.SandboxBroker com.apple.screencapture com.apple.Sharing com.apple.sharingd
  com.apple.Siri com.apple.speech.synthesis.general.prefs com.apple.SpeechRecognitionCore
  com.apple.TelephonyUtilities com.apple.Terminal com.apple.TextEdit com.apple.TextInputMenu
  com.apple.TimeMachine com.apple.voicetrigger com.apple.WindowManager
  com.apple.AppleMultitouchTrackpad com.apple.driver.AppleBluetoothMultitouch.trackpad
  com.apple.LaunchServices
)
for d in "${DOMAINS[@]}"; do
  probe "defaults.$d.xml" "$(declare -f domain_xml); domain_xml export $d"
done
probe defaults.currentHost.com.apple.coreservices.useractivityd.xml \
  "$(declare -f domain_xml); domain_xml -currentHost export com.apple.coreservices.useractivityd"
probe diagnostics.xml \
  'sudo -n plutil -convert xml1 -o - "/Library/Application Support/CrashReporter/DiagnosticMessagesHistory.plist"'

# Symlinks: link -> target, sorted.
links(){ find "$1" -maxdepth "${2:-1}" -type l 2>/dev/null | while read -r l; do printf "%s -> %s\n" "${l#"$HOME"/}" "$(readlink "$l")"; done | sort; }
probe bin-symlinks.txt     "$(declare -f links); links \"\$HOME/bin\""
probe dotfile-symlinks.txt "$(declare -f links); links \"\$HOME\""
probe other-links.txt      "$(declare -f links); { links \"\$HOME/.config\"; links \"\$HOME/.claude\" 2; links \"\$HOME/Projects\" 2; ls -l /Library/Java/JavaVirtualMachines | awk 'NR > 1 {print \$9, \$10, \$11}'; } | sort"

# Login items, by name, sorted. Needs Automation access — see Environment.
probe login-items.txt \
  'osascript -e "tell application \"System Events\" to get the name of every login item" | tr "," "\n" | sed "s/^ *//" | sort'
probe launchagents.txt 'ls -1 "$HOME/Library/LaunchAgents" | sort'
probe claude-hook.txt  '/usr/bin/jq -c "[.hooks.SessionStart[]?.hooks[]?.command]" "$HOME/.claude/settings.json"'

# Installed package set, and the runtimes post-install adds
probe brew-leaves.txt   'brew leaves --installed-on-request | sort'
probe brew-formulae.txt 'brew list --formula | sort'
probe brew-casks.txt    'brew list --cask | sort'
probe runtimes.txt      'cat "$HOME/.nvm/alias/default"; ls -1 "$HOME/.nvm/versions/node"; ls -1 "$HOME/.pyenv/versions"; grep -h pinentry "$HOME/.gnupg/gpg-agent.conf"'

# State directory: undo files verbatim, backups by directory name only
probe defaults-rollback.sh  'cat "$HOME/.mrk/defaults-rollback.sh"'
probe hardening-rollback.sh 'cat "$HOME/.mrk/hardening-rollback.sh"'
probe backup-dirs.txt       'ls -1 "$HOME/.mrk/backups" | sort'

# Privileged / security state
probe fw-global.txt       '/usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate'
probe fw-stealth.txt      '/usr/libexec/ApplicationFirewall/socketfilterfw --getstealthmode'
probe pam-sudo.sha        'shasum /etc/pam.d/sudo'
probe pam-sudo-local.txt  'cat /etc/pam.d/sudo_local'
probe screen-lock.txt     'sysadminctl -screenLock status 2>&1 | sed "s/^.*\] //"'

# Application presence (plist-import, login-item and GitHub-app targets)
probe applications.txt 'ls -1 /Applications | sort'

if [[ -s "$out/_incomplete.txt" ]]; then
  echo "CAPTURE INCOMPLETE — see $out/_incomplete.txt" >&2
  cat "$out/_incomplete.txt" >&2
fi
```

The script is the plan's text. The first test session proves it (next section) before any
verdict is taken from it. A probe that captures the wrong thing is fixed there, in this file,
before the tests run.

**Two VM prerequisites the harness has.** Both are provided by the base image:
- **Automation access** for the login-items probe. Without it the probe times out on the
  consent dialog, and every capture is incomplete.
- **Passwordless `sudo`** for the Mac Analytics probe.

`timeout` is no longer a prerequisite: the script falls back to `perl`.

**Excluded from every diff, by design.** These change on any run and are not evidence of a
write:

- `~/.mrk/install.log` — appended to by every phase.
- Timestamps and inodes — the capture records content and link targets, never `stat` output.
- `~/.mrk/preferences/` — the fixture set, which no test writes.
- `~/.mrk/plist-backups/` — pre-import snapshots, whose content the undo lines already name.
- Homebrew's own metadata under `$(brew --prefix)/var/homebrew/` — churns independently.
- The Go binaries `make build-tools` rebuilds in `~/mrk/bin`. Their links are captured, and the
  links do not change.

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

**A domain that reads `EMPTY` in every capture is not being observed.** An `applied` capture
shows whether a domain the scripts write is visible to the probe at all. A domain that stays
`EMPTY` even there can match in any diff, and proves nothing. Name it in the results, rather
than counting it towards a PASS.

**Proved on the host, 2026-09-28.** The script above ran twice on the owner's Mac, read-only.
Each capture took under two seconds. The two captures were identical, and `_incomplete.txt`
was empty. Two artifacts were empty for reasons the VM does not share: `diagnostics.xml`,
because the host's `sudo` asks for a password, and `backup-dirs.txt`. `com.apple.mail` read
`EMPTY` with the defaults applied. Mail keeps that key where the probe does not look, so that
domain is the first case of the rule above.

---

## Test 1C — Rollback fidelity, combined

### Purpose

`make defaults` and `make harden` each maintain their own rollback file. 1A and 1B proved
each was faithful alone, against the `make harden` of April. 1C proves the current pair is
faithful **together**: that applying both and then reverting both returns the machine to
baseline, and that neither rollback disturbs the other's state.

### Scope

The ~40 app-preference writes with no undo are written by `assets/browsers/` and
`assets/preferences/`, from `scripts/post-install`. Neither `make defaults` nor `make harden`
runs them, so they are never written during 1C and cannot fail to roll back. The same holds for
the plist imports, whose whole-domain undo lines post-install writes. A full-install rollback
is a different test, not in this plan. If one is added, it takes a new ID rather than 1C's.

The screen-lock step is outside 1C unattended, since it needs the login password. The run
records no undo line for it and changes nothing. `screen-lock.txt` must still match.

### Setup

Fresh clone. **Run `make setup ARGS=--no-defaults`,** so the tools, dotfiles and shell are in
place and the defaults are not. Then capture. (Until 2026-09-28 this read "`make setup` first",
which applies the defaults; see the refresh note.)

### Capture points

`baseline` (after `make setup ARGS=--no-defaults`), `applied` (after both applies),
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

Run the hardening rollback **first**. The two scripts write no domain in common, so the order is
not expected to matter. Running it first makes any coupling visible as an ordering-dependent
failure, rather than masking it.

Step 4 must differ from baseline in every item both scripts change:
- the defaults domains;
- `fw-global.txt` and `fw-stealth.txt`;
- `pam-sudo-local.txt`;
- LSQuarantine;
- Handoff's ByHost domain;
- `diagnostics.xml`, where the two keys were not already false.

If `applied` equals `baseline`, the applies did not run, and the test says nothing.

### Expected result

- **The diff.** Step 8 reports differences only in the two rollback-script files themselves,
  and in `backup-dirs.txt` if `make setup` created a backup. Everything else matches baseline
  exactly: every defaults domain, the ByHost domain, `diagnostics.xml`, both firewall files,
  both PAM artifacts and `screen-lock.txt`.
- **Emptied domains.** A domain absent at baseline and emptied by the revert reads `EMPTY` in
  both captures.
- **Deleted, not zeroed.** Keys absent at baseline are **deleted**, not set to `0` or `false`.
  This holds for LSQuarantine, the Handoff keys and the Mac Analytics keys.
- **`sudo_local`** is removed again if it was absent at baseline, or put back as it was.

### Pass / fail

- **PASS** — every captured artifact except the rollback scripts and `backup-dirs.txt` is
  byte-identical between `baseline` and `reverted`.
- **PARTIAL** — the defaults domains match but a privileged item (firewall, PAM, Mac
  Analytics) does not.
- **FAIL** — any domain that `defaults.sh` or `hardening.sh` wrote differs from baseline.

---

## Test 2 — Idempotency

### Purpose

A second full install must be a no-op. This is the property that makes `make all` safe to
re-run, and it is the one users exercise most often without thinking about it. The README
promises it: "On an already-configured machine all phases can be re-run freely in any order."

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

The second run must leave all of these byte-identical:

| Artifact | Why it must not change |
|---|---|
| All `defaults.*.xml` domains | `write_default` skips when value and type already match |
| `defaults-rollback.sh` | `backup_line` dedups; the recorded-key guard blocks re-append; the imports skip, so they add no whole-domain line |
| `hardening-rollback.sh` | Absent unless `make harden` ran; `make all` does not run it |
| `bin-symlinks.txt`, `dotfile-symlinks.txt` | `setup` skips a link already pointing at its target |
| `other-links.txt` | topgrade, the Claude Code links and openjdk each skip when already linked |
| `claude-hook.txt` | the SessionStart hook is added once |
| `login-items.txt` | `add_login_item` must not create a duplicate entry |
| `launchagents.txt` | `install_launch_agent` skips an installed agent |
| `runtimes.txt` | nvm, the Node default, the pyenv Python and pinentry each skip when present |
| `brew-leaves/formulae/casks.txt` | `brew bundle` installs nothing already present |
| `backup-dirs.txt` | **No new timestamped directory.** `BACKUP_DIR` is created lazily at `setup:566`, and a no-op run displaces nothing |
| `applications.txt` | GitHub app installs are install-only and skip when present |

### Expected result

`diff -r` reports **no differences at all**. `~/run2.log` shows skip messages for:
- the topgrade config ("linked"), the Claude Code links, Node ("nvm default is …") and the pyenv
  Python ("already installed");
- the seven GitHub apps ("installed — skipping");
- every present login item ("exists: …") and both LaunchAgents ("already installed");
- the imports ("exists — skipping import").

setup's defaults phase reports no failures.

### Pass / fail

- **PASS** — `diff -r` is empty.
- **PARTIAL** — differences confined to `backup-dirs.txt` **or** an additive-only change in a
  rollback file. Both indicate a real idempotency defect but a contained one; record which.
- **FAIL** — any defaults domain, symlink set, login-item list, LaunchAgent list, runtime or
  package set differs, or a login item is duplicated.

---

## Test 3 — Order-independence

### Purpose

The README says: "On a fresh machine, run them in order. … Phase 3 configures only what Phase
2 has installed: it skips the preferences, login items and settings of any app that is not
there yet, and a later Phase 2 does not go back for them." This test checks both halves of
that: what goes missing when the order is wrong, and that re-running Phase 3 recovers it. (The
first version of this plan tested an older "any order" claim, which the README has since
dropped.)

### What ordering can vary, and what cannot

`make setup` is **not** order-independent and is not part of this test. It links the tools that
later phases call and applies the dotfiles the shell needs; it must run first.

The two phases whose order can vary are `brew` (Phase 2) and `post-install` (Phase 3).

### The invariant

After `make setup`, running **both** `brew` and `post-install` must converge to the same end
state regardless of which ran first — allowing, in the `post-install`-first case, the re-run
that convergence requires.

This is deliberately two claims, because the scripts predict they differ:

- **Claim A (single pass each):** end state after `brew; post-install` equals end state after
  `post-install; brew`. **Predicted to FAIL,** as the README says. post-install run before
  `brew` finds the casks and Homebrew's tools absent, and its guards skip everything that needs
  them.
- **Claim B (converged):** end state after `brew; post-install` equals end state after
  `post-install; brew; post-install`. **Predicted to PASS**, because the second
  `post-install` finds the apps and tools installed and does the skipped work.

### Setup

**Two** fresh clones, `mrk-test-3a` and `mrk-test-3b`, both with the fixture preferences. Both
run `make setup` first.

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

**Claim A differs** in what post-install skips when Homebrew has not run yet:
- **Login items** for the four cask apps: AlDente, Dropbox, Raycast and Thaw. BetterSnapTool and
  Chrono Plus come from the App Store and are absent in both orders.
- **The imported domains** of the cask apps among the 17 targets, and the matching whole-domain
  lines in `defaults-rollback.sh`.
- **The app-defaults keys** for the installed casks: Helium, Audio Hijack, Fission, AlDente and
  the Rogue Amoeba apps.
- **In `other-links.txt`,** the openjdk link.
- **In `runtimes.txt`,** the pyenv Python and the pinentry-mac line.

It does **not** differ in:
- the defaults domains, which `setup` wrote;
- the dotfile and tool links;
- the topgrade and Claude Code links;
- nvm and the Node default, the GitHub apps and the LaunchAgents;
- the package set: `brew` ran in both orders.

**Claim B shows no differences.**

### Pass / fail

- **PASS** — Claim B diff is empty. Claim A's differences are confined to the artifacts named
  above and are explained by the skip guards.
- **PARTIAL** — Claim B converges except for a named artifact; record which and why.
- **FAIL** — Claim B does not converge, or Claim A differs in the defaults domains, the
  symlink sets, nvm, the GitHub apps or the package set, none of which depend on Homebrew's
  apps.

**Documentation consequence.** If Claim A fails as predicted, the README already says so. If it
fails *differently*, the README's list of what Phase 3 skips is wrong. Record that as a
follow-up, rather than editing the README from inside the test.

---

## Test 4 — Re-entry and recovery

### Purpose

This is the test that would have caught N-1. It has two independent parts: an interruption, and
an injected failing write. Both must leave the system re-runnable and the rollback file
well-formed.

### Part 4a — interruption

**Setup.** Fresh clone, with the fixture preferences. `make setup && make brew` completed.

**Procedure.**
1. `~/capture.sh pre-interrupt`
2. Start `make post-install` in its own process group, and interrupt it while a GitHub app's DMG
   is attached. That is the window between `hdiutil attach` (`install-apps:139`) and the
   detach. A watcher makes the timing repeatable, rather than a hand on Ctrl-C:
   ```bash
   set -m; make -C ~/mrk post-install > ~/4a.log 2>&1 & pg=$!
   until hdiutil info | grep -q "image-path.*/mrk\."; do sleep 0.1; done
   kill -INT -- -"$pg"          # the whole group, as Ctrl-C would
   wait "$pg"; echo "exit $?"
   ```
3. Immediately check for leaks. `hdiutil info` must list no image under `$TMPDIR/mrk.*`, and
   `ls -d "${TMPDIR:-/tmp}"/mrk.*` must show no DMG or mount point from the install. The mount
   is at a temporary path, not under `/Volumes`, so `ls /Volumes` cannot show it; the first
   version of this plan looked there.
4. `~/capture.sh interrupted`
5. `make post-install` again, to completion.
6. `~/capture.sh recovered`
7. Compare `recovered` against Test 3's `order-a`, at the same commit with the same fixtures.

**Expected result.**
- **No DMG stays attached after the interrupt.** Two traps cooperate here, and both must fire:
  - post-install's `INT`/`TERM` trap (`post-install:100`) prints
    `[post-install] interrupted — exiting` and exits 1;
  - that exit fires `install_github_app`'s `EXIT` trap, `_github_app_done` (`install-apps:128-134`),
    whose `hdiutil detach` releases the mount and which deletes both temporary paths.
- **The re-run completes** and reports no failures. It installs the app that was interrupted.
- **`recovered` matches `order-a`.**

If the watcher misses the window, because the copy out of the image was too quick, the run is
**inconclusive**, not a pass. Repeat it.

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

`AppleKeyboardUIMode` is still written, at `defaults.sh:262`
(`write_default NSGlobalDomain AppleKeyboardUIMode int 2`).

**Procedure.**
1. `~/capture.sh pre-inject`
2. `cd ~/mrk && bash scripts/defaults.sh` with the stub on `PATH`, capturing output to
   `~/inject.log`
3. Record the exit code.
4. `~/capture.sh injected`
5. Inspect `~/.mrk/defaults-rollback.sh`: line count, a shebang on line 1, the executable bit,
   and that it parses — `bash -n ~/.mrk/defaults-rollback.sh`
6. Remove the stub from `PATH` and re-run `bash scripts/defaults.sh` to completion.
7. `~/capture.sh recovered-inject`

**Expected result.** This is the precise N-1 assertion, with W-19's exit status:

- **The run does not abort** at the refused write. It continues through every remaining write.
- **The summary.** `~/inject.log` shows `1 default(s) failed to apply; the rest are applied.
  Revert with: …` (`defaults.sh:668-671`).
- **The exit code is 1.** Until W-19 it was 0, which hid the failure from `setup` and
  `make defaults`.
- **The failure is isolated.** Every other domain in `injected` is fully applied, and only
  `AppleKeyboardUIMode` is not.
- **The rollback file is well-formed.** It has a shebang on line 1, is executable and passes
  `bash -n`. It holds an entry for each domain and key touched before *and after* the refused
  write, and for the refused key itself, since `write_default` records before it writes. A file
  that stops at the refusal is the N-1 regression.
- **The step-6 re-run** applies the refused key, exits 0 and prints "Defaults applied".

### Pass / fail

- **PASS** — 4a and 4b both meet every expectation above.
- **PARTIAL** — 4a passes and 4b's run continues and counts the failure, but the rollback file
  has a cosmetic defect (for example a missing trailing `killall` line).
- **FAIL** — any of these is an N-1 or W-19 regression, and stops the session:
  - the run aborts at the refused write;
  - the rollback file is truncated at the point of failure;
  - the summary is absent;
  - 4b exits 0;
  - a DMG stays attached after the interrupt.

---

## Recording results

Extend `audit/11-test-results.md` in its existing format:
- update the Executive Summary table's verdicts;
- add a `## Test <ID>` section per test, with Procedure, Evidence and Verdict;
- replace the "Tests Deferred" section with the outcomes;
- close the VM-tests item in `00-followups.md`.

Keep the evidence verbatim — captured diffs and log excerpts, not paraphrase. Record the commit
and the OS build of each run.

State explicitly whether the N-1, N-2 and N-3 fixes hold, since these tests are the runtime
confirmation those static fixes never had:

- **N-1** — Test 4b. The run continues past a refused write and the rollback file stays
  well-formed.
- **N-3** — no test here runs `sync-login-items`. N-3 was reproduced with a stubbed `osascript`
  in the fix session, and that remains its evidence. Do not claim runtime coverage this plan
  does not provide.
- **N-2** — the secret-scanner fixes are exercised by `snapshot-prefs` and `mrk-push`, neither of
  which any test above runs. Same caveat: not covered here.

---

## Known limitations that will shape verdicts

These are expected and must not be recorded as test failures.

- **About 40 app-defaults writes have no undo.** Safari, AlDente and Fission have none at all.
  Helium, Audio Hijack and the Rogue Amoeba apps are covered only where post-install also
  imported the domain. Out of scope for 1C as scoped above; it would matter to a full-install
  rollback test, which does not exist.
- **Plist imports are skip-if-not-empty.** A domain already populated is left alone. That is
  what makes Test 3's Claim A fail in a predictable, documented way.
- **The imports use fixtures.** The VM has no access to `mrk-prefs`. The fixture plists exercise
  the import path, not the owner's real preferences.
- **The screen-lock step needs the login password.** No test here sets it. Unattended runs
  record and change nothing for it.
- **Safari needs Full Disk Access** for the runner. Without the grant, its defaults are skipped
  in every run, consistently.
- **Network dependence.** `brew`, the GitHub app installs and nvm's Node all need the network.
  A network failure is an inconclusive run, not a FAIL — re-run it.
