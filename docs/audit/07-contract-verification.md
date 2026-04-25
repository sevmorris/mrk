# Audit 07 — Contract Verification
**Branch:** `audit/static-pass` | **Date:** 2026-04-25

## Scope

Claim-by-claim verification of the README's stated contracts against evidence found in
Modules 1–3 of this audit. Static analysis only — no execution. Each claim is given a
verdict from the set below, plus a brief rationale and the relevant evidence.

**Verdict scale:**
- `TRUE` — the claim is accurate with no meaningful qualification
- `TRUE-WITH-CAVEATS` — accurate in spirit; one or more edge cases or minor exceptions apply
- `PARTIALLY-TRUE` — the claim holds in the common case but fails in documented scenarios
- `CONTRADICTED` — audit evidence directly contradicts the claim
- `UNVERIFIABLE-STATICALLY` — would require execution or runtime state to confirm or deny

---

## Claims

### CLAIM-01
**Source:** `README.md:3`
> "Idempotent setup in three phases."

**Evidence:**
- `scripts/setup:100` — `BACKUP_DIR` assigned fresh timestamp on every run; `mkdir -p "$BACKUP_DIR"` called unconditionally in `phase_dotfiles` regardless of whether any file needs backup. Each re-run creates an empty timestamped backup directory. (`03-shell-hygiene.md M1`)
- `scripts/defaults.sh:27` — rollback file truncated (`>`) on every run. Second run generates a shebang-only rollback, destroying rollback content from the first run. (`03-shell-hygiene.md M2`)
- `scripts/post-install`: browser extension URLs are opened interactively on every run (guarded by a prompt, not a "already installed" check). Extension tabs reopen unconditionally when the user answers `y`.
- Dotfile symlinking and tool linking: genuinely idempotent (skips existing symlinks).
- Brew phase: `brew bundle` is idempotent by design.

**Verdict:** `TRUE-WITH-CAVEATS`

The three phases are broadly re-runnable. However, "idempotent" is not quite accurate: Phase 1 accumulates empty backup directories on re-runs, and Phase 1 also destroys the rollback script on re-runs (replacing it with a shebang-only stub). Phase 3 reopens browser tabs. A stricter reading of "idempotent" (identical observable state after N runs) is not satisfied.

---

### CLAIM-02
**Source:** `README.md:33`
> "Phases are independent — run any subset, in any order, as many times as you want."

**Evidence:**
- Phase 2 (`make brew`) installs Homebrew. Phase 3 (`make post-install`) calls applications installed by Phase 2 (`apply_defaults`, `import_plist`, `install_github_app`, browser policy steps) and degrades gracefully when apps are absent (`logskip` on missing apps, guarded `if [[ -d /Applications/... ]]`).
- Phase 3 runs `apply_defaults "$BROWSERS_DIR/safari-defaults.sh"` which calls `defaults write` — this does not require Phase 2. The plist imports do require Phase 2 apps to be installed but are individually skipped if not found.
- Phase 3 (`scripts/post-install:262-290`) attempts SSH key detection and auto-pull of `mrk-prefs`. On a machine where Phase 2 never ran (no `git` via Homebrew), this silently skips — but on a fresh macOS install without Xcode CLI tools (skipped Phase 1), it would also fail. The dependency is undocumented.
- Phase 2 depends on Phase 1 having set the login shell (`phase_shell`) for the correct zsh environment, but `brew install` works from any shell.
- The natural install order (1 → 2 → 3) is never stated in the README; `make all` documents no explicit ordering guarantee beyond what the table rows imply.

**Verdict:** `PARTIALLY-TRUE`

Phases are loosely independent and Phase 3 degrades gracefully when Phase 2 apps are absent. However, the claim "in any order" overstates independence: running Phase 3 before Phase 1 on a bare macOS install may fail (no git, no Homebrew toolchain). The phases are ordered for a reason, and calling them fully independent misleads users who try to cherry-pick Phase 3 on a fresh machine.

---

### CLAIM-03
**Source:** `README.md:89`
> "Re-run any phase independently without side effects."

**Evidence:**
- `scripts/defaults.sh:374-376` — `killall Finder`, `killall Dock`, `killall SystemUIServer` run unconditionally at the end of every `make defaults` invocation. These restart running apps, briefly interrupting the user's desktop session. The rollback script also includes these killalls, meaning the side effect occurs on rollback too. (`03-shell-hygiene.md M2`)
- `scripts/setup:100,451` — empty timestamped backup directory created on every re-run. (`03-shell-hygiene.md M1`)
- `scripts/defaults.sh:27` — rollback file truncated on re-run, destroying the prior run's rollback content. This is a side effect with a negative consequence: a user who runs `make defaults` twice can no longer roll back the first run's changes.
- `scripts/post-install` — browser extension URLs opened in the user's default browser on re-run (with user confirmation prompt, but still a visible side effect).

**Verdict:** `CONTRADICTED`

Every `make defaults` run kills Finder, Dock, and SystemUIServer — that is a visible, non-trivial side effect. Every `make setup` re-run creates a new empty backup directory. Every second `make defaults` run silently destroys the rollback script for the first run. The claim "without side effects" is not accurate for any of the three phases.

---

### CLAIM-04
**Source:** `README.md:91`
> "State lives in `~/.mrk`."

**Evidence (state written outside `~/.mrk`):**
- `/etc/pam.d/sudo` — modified by `scripts/hardening.sh:34-43` (Touch ID sudo). A `.backup.mrk` copy is placed at `/etc/pam.d/sudo.backup.mrk`. Rollback does move this back, so the state change is tracked — but the location is outside `~/.mrk`.
- `/Applications/` — apps installed by `install_github_app` (Barkeep). No removal mechanism provided; `make uninstall` does not remove apps from `/Applications/`.
- `~/Library/` — plist imports via `defaults import` (called by `import_plist`). These write into `~/Library/Preferences/`. Not tracked in `~/.mrk`.
- `~/bin/` — scripts and tools symlinked here by Phase 1. This is documented elsewhere but is state outside `~/.mrk`.
- `~/.config/` — some dotfiles in `dotfiles/` may expand to `~/.config/` paths depending on what is in the dotfiles subtree.
- `~/.zshrc` — the `doctor --fix` path (if invoked correctly) appends PATH configuration. The `phase_shell` function sets the login shell via `chsh`.
- Browser policy directories (`~/Library/Managed Preferences/`) — written by `install_browser_policy`.

**Verdict:** `CONTRADICTED`

State is distributed across at minimum six locations: `~/.mrk`, `/etc/pam.d/`, `/Applications/`, `~/Library/`, `~/bin/`, and browser-managed-preferences directories. The claim is not accurate. It may have been intended to mean "mrk's own bookkeeping (rollback scripts, backups, logs) lives in `~/.mrk`", which is true — but "state" without qualification covers all persistent changes the tool makes.

---

### CLAIM-05
**Source:** `README.md:91`
> "Rollback scripts are generated automatically for defaults changes."

**Evidence:**
- `scripts/defaults.sh` — `write_default()` helper appends a `defaults write` inversion command to `~/.mrk/defaults-rollback.sh` for every setting it writes. This covers the bulk of `make defaults`.
- `scripts/hardening.sh:35` — `rollback "sudo mv /etc/pam.d/sudo.backup.mrk /etc/pam.d/sudo"` appends to the same rollback file. Harden changes are included.
- **Not covered by rollback:**
  - `import_plist` in `scripts/post-install` — imports full plists with `defaults import`; no rollback entry generated.
  - `install_browser_policy` — writes JSON to `~/Library/Managed Preferences/`; no rollback entry.
  - App installations (`install_github_app`) — no rollback.
  - Browser extension URL openings — no rollback (ephemeral/manual action).
  - `phase_shell` (`chsh`) — no rollback entry for login shell change.
- `scripts/defaults.sh:27` — rollback file truncated (`>`) on every run; second run produces a shebang-only stub. (`03-shell-hygiene.md M2`) A user who runs `make defaults` twice cannot roll back the first run.

**Verdict:** `PARTIALLY-TRUE`

Rollback generation is real and works for the `write_default`-based settings and hardening changes on the first run. However: plist imports, browser policies, app installs, and login shell changes have no rollback. The truncation bug means the rollback is silently destroyed on re-runs. "Automatically" is accurate for what is covered, but the coverage is incomplete and the mechanism is fragile.

---

### CLAIM-06
**Source:** `README.md:75`
> `` `make doctor --fix` adds it to `.zshrc` ``

**Evidence:**
- `Makefile:99-100`:
  ```makefile
  doctor: ## Run diagnostics
      @"$(SCRIPTS)/doctor"
  ```
  The `doctor` target has no `$(ARGS)` passthrough. (`04-makefile-audit.md L1`)
- All other targets in `Makefile` that accept flags use `$(ARGS)`: `@"$(SCRIPTS)/setup" $(ARGS)`, `@"$(SCRIPTS)/brew" $(ARGS)`, etc. `doctor` does not follow this pattern.
- `make doctor --fix` is syntactically interpreted by Make as passing `--fix` as a Make flag, not as a shell argument to the `doctor` script. Make will exit with an error (`make: invalid option -- -`).
- The correct invocation to pass `--fix` to the doctor script is `$(SCRIPTS)/doctor --fix` directly, or via `ARGS=--fix make doctor` — neither of which is what the README documents.

**Verdict:** `CONTRADICTED`

`make doctor --fix` does not work as documented. The `doctor` Makefile target does not pass `$(ARGS)` to the underlying script, so Make intercepts `--fix` as an unrecognized flag and errors out. The correct form is not documented anywhere in the README or `make help` output.

**Repair:** Add `$(ARGS)` passthrough to the `doctor` target:
```makefile
doctor: ## Run diagnostics
    @"$(SCRIPTS)/doctor" $(ARGS)
```
Or update the README to document the correct invocation.

---

### CLAIM-07
**Source:** `README.md:95`
> "Barkeep … is installed automatically by `make post-install`."

**Evidence:**
- `scripts/post-install:225`:
  ```bash
  install_github_app "/Applications/Barkeep.app" "sevmorris/Barkeep" "Barkeep" || ((failed++))
  ```
- `install_github_app` fetches the latest release DMG from GitHub using the GitHub API (`api.github.com/repos/<owner>/<repo>/releases/latest`), mounts it, copies the `.app` bundle to `/Applications/`, and detaches.
- The `claudebar` cask in the Brewfile (`brew/Brewfile`) also references a Barkeep-related package (`claudebar`). However, `install_github_app` for Barkeep is called directly in `post-install`, not via Homebrew.
- `scripts/post-install:188`: "To update Barkeep, use Barkeep itself or re-run after removing the app." — confirms re-install is the update path and that it is managed via `post-install`, not Homebrew.
- The install depends on network access to the GitHub API and release assets. The `install_github_app` function handles a failed download gracefully (`|| ((failed++))`) but the failure only produces a warning, not an error exit.

**Verdict:** `TRUE-WITH-CAVEATS`

Barkeep is installed by `make post-install` via `install_github_app` — the claim is accurate. Caveat: the install requires network access and the GitHub Releases API. The `install_github_app` function has a DMG mount leak on SIGINT (`06-go-audit.md` — actually `03-shell-hygiene.md H2`), so a Ctrl-C mid-install can leave a mounted DMG until reboot. Additionally, the Brewfile contains a separate `claudebar` cask — it is unclear whether `claudebar` and `Barkeep.app` are the same or different packages, creating a potential double-install ambiguity.

---

## Summary

| Claim | Location | Verdict |
|-------|----------|---------|
| CLAIM-01: "Idempotent setup in three phases" | `README:3` | TRUE-WITH-CAVEATS |
| CLAIM-02: "Phases are independent — run any subset, in any order" | `README:33` | PARTIALLY-TRUE |
| CLAIM-03: "Re-run any phase independently without side effects" | `README:89` | CONTRADICTED |
| CLAIM-04: "State lives in `~/.mrk`" | `README:91` | CONTRADICTED |
| CLAIM-05: "Rollback scripts generated automatically for defaults changes" | `README:91` | PARTIALLY-TRUE |
| CLAIM-06: `` `make doctor --fix` adds it to `.zshrc` `` | `README:75` | CONTRADICTED |
| CLAIM-07: "Barkeep installed automatically by `make post-install`" | `README:95` | TRUE-WITH-CAVEATS |

---

## Top README Repair Items

Ordered by impact (correctness before clarity):

1. **Fix `make doctor --fix` syntax** (`04-makefile-audit.md L1`): Add `$(ARGS)` passthrough to the `doctor` Makefile target, or rewrite the README example. This is the only claim that produces a hard error at the command line as documented.

2. **Fix defaults rollback truncation** (`03-shell-hygiene.md M2`): `scripts/defaults.sh:27` truncates the rollback file on every run. Without this fix, "rollback scripts are generated automatically" is only reliable on the first run.

3. **Qualify "without side effects"** (`README:89`): `killall Finder/Dock/SystemUIServer` are visible side effects on every `make defaults` re-run. The claim should be qualified or the kills should be skipped when values are already set.

4. **Qualify "state lives in `~/.mrk`"** (`README:91`): Scope the claim to mrk's own bookkeeping, or enumerate the actual state locations (`/etc/pam.d/`, `~/Library/`, `/Applications/`, `~/bin/`).

5. **Qualify phase independence** (`README:33`): The phases have a soft dependency order: Phase 3 works best after Phase 2, and Phase 2 works best after Phase 1 installs Xcode CLI tools. Replace "independent" with "loosely ordered" or "independently re-runnable after initial setup."

---

## Cross-References

| Claim | Related Audit Finding |
|-------|-----------------------|
| CLAIM-01 (backup dirs) | `03-shell-hygiene.md M1` |
| CLAIM-01, CLAIM-05 (rollback truncation) | `03-shell-hygiene.md M2` |
| CLAIM-03 (killall side effects) | `03-shell-hygiene.md M2` |
| CLAIM-06 (`make doctor --fix`) | `04-makefile-audit.md L1` |
| CLAIM-07 (DMG mount leak) | `03-shell-hygiene.md H2` |
| CLAIM-07 (claudebar/Barkeep overlap) | `05-brewfile-and-ruby.md B8` |
