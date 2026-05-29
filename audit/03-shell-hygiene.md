# Audit 03 — Shell Hygiene
**Branch:** `audit/static-pass` | **Date:** 2026-04-24 | **Tool:** shellcheck v0.11.0

## Scope

All shell files reachable from `make` targets plus standalone scripts, excluding generated output and the `dotfiles/` subtree (covered separately). 33 files analyzed.

Active `.shellcheckrc` suppressions: SC1090 (external source), SC1091 (missing source file), SC2059 (printf format variables), SC2329 (loops). SC2086 and SC2046 (quoting) are intentionally **not** suppressed and produce zero findings — the codebase is clean on both.

---

## Summary

| Severity | Count | Files |
|----------|-------|-------|
| HIGH     | 3     | `scripts/sync`, `scripts/post-install`, ~~`scripts/syncall`~~ (removed `ba29d0c`) |
| MEDIUM   | 5     | `scripts/setup`, `scripts/defaults.sh`, `scripts/check-updates`, `scripts/hardening.sh`, `scripts/sync-login-items` |
| LOW      | 6     | `scripts/adventure-prologue` (×3), `scripts/fix-exec`, `scripts/check-updates`, `scripts/nuke-mrk` |

ShellCheck totals (all files):
- **Errors:** 1 (`scripts/sync:231` SC2168)
- **Warnings:** 6 (SC2120 ×1, SC2221 ×1, SC2222 ×1, SC2034 ×3)
- **Notes:** ~40 (SC2015 ×35 concentrated in `adventure-prologue`, SC2005 ×1, SC1037 ×2)

---

## HIGH

### H1 — `local` outside function crashes `--prune` path
**File:** `scripts/sync:231` | **ShellCheck:** SC2168

```bash
# Line 230-231 — at script (top) level, outside any function:
local_sed_args=()
local escaped_pkg       # SC2168: 'local' only valid in functions
```

`local` is not valid outside a function body. Under `set -euo pipefail` (active in this script), the `local` declaration returns exit code 1, which causes the script to abort immediately. This fires only when `--prune` is passed and the user selects entries to remove. Any `--prune` session silently exits at this point without completing the prune.

**Fix:** Replace `local escaped_pkg` with a plain `escaped_pkg=` declaration (or wrap the prune block in a function and keep `local`).

---

### H2 — DMG mount leak on SIGINT in `post-install`
**File:** `scripts/post-install` (function `install_github_app`) | **ShellCheck:** no rule covers this

```bash
install_github_app() {
  local tmp_dmg tmp_mount
  tmp_dmg=$(mktemp -t mrk)
  tmp_mount=$(mktemp -t mrk -d)
  # No trap installed

  curl -L -sf -o "$tmp_dmg" "$dmg_url" || { ...; rm -f "$tmp_dmg"; return 1; }
  hdiutil attach "$tmp_dmg" -mountpoint "$tmp_mount" -quiet -nobrowse \
    || { ...; rm -rf "$tmp_mount"; return 1; }

  # ← SIGINT here leaves tmp_mount mounted and tmp_dmg on disk

  cp -R "$found_app" /Applications/ \
    || { hdiutil detach "$tmp_mount" -quiet; rm -f "$tmp_dmg"; return 1; }
  hdiutil detach "$tmp_mount" -quiet
  rm -f "$tmp_dmg"
}
```

There is no EXIT or INT/TERM trap anywhere in `post-install`. If the user presses Ctrl-C after `hdiutil attach` completes but before `hdiutil detach`, the mountpoint stays mounted until the next reboot and the temp file leaks. The explicit error paths (`cp` failure) do clean up, but SIGINT bypasses them entirely.

There is also no script-level trap — a SIGINT at any point in `post-install` leaves partial state (partially installed apps, unmounted DMGs) with no cleanup.

**Fix:** Install a cleanup trap in `install_github_app` immediately after both temp paths are assigned:

```bash
trap 'hdiutil detach "$tmp_mount" -quiet 2>/dev/null; rm -f "$tmp_dmg"' EXIT
```

For defense-in-depth, add a script-level `trap '...' INT TERM` in `post-install` as well.

---

### H3 — `syncall` bypasses all confirmation when stdin is not a TTY
**File:** `scripts/syncall:155-185` | **ShellCheck:** no rule covers this

> **Removed** in commit `ba29d0c` (branch `audit/static-pass`). Finding retained for audit history.

```bash
if is_dirty "$r"; then
  if (( SYNCALL_DRY_RUN )); then
    log "DRY-RUN: would auto-commit $r"
  else
    if [[ -t 0 ]]; then
      # show diff, prompt user, read -r ans
      [[ ! "$ans" =~ ^[Yy]$ ]] && { warn "Skipped: $r"; continue; }
    fi
    auto_commit "$r"    # runs unconditionally when stdin is not a TTY
  fi
fi
if can_push "$r"; then
  push_repo "$r"        # push also runs unconditionally
fi
```

`auto_commit` calls `git add -A` (stages everything, including unintended files) then commits. When stdin is not a TTY — cron, CI, a shell launched by a script, or any piped invocation — the TTY gate is skipped and every dirty repo is auto-committed and pushed with no user input and no diff review.

`git add -A` is particularly risky here: it stages all untracked files including environment files, credentials, or any other sensitive content that happened to be written into a tracked repo directory.

**Fix (two-part):**
1. Replace `[[ -t 0 ]]` with an explicit `--yes` / `-y` flag. Require that flag for non-interactive operation; abort with an error if neither TTY nor `--yes` is present.
2. Replace `git add -A` in `auto_commit` with an explicit path list or at minimum `git add -u` (only tracks already-indexed files, does not stage new untracked files).

---

## MEDIUM

### M1 — Empty timestamped backup dirs accumulate on every `make setup`
**File:** `scripts/setup:100, 451` | **ShellCheck:** no rule covers this

```bash
# Line 100 — runs unconditionally at script startup:
BACKUP_DIR="$STATE_DIR/backups/$(date +%Y%m%d-%H%M%S)"

# Line 451 — inside phase_dotfiles, runs when not DRY_RUN:
if ! mkdir -p "$BACKUP_DIR"; then
```

`BACKUP_DIR` is assigned a fresh timestamp on every invocation. `mkdir -p "$BACKUP_DIR"` is called in `phase_dotfiles` regardless of whether any dotfiles actually need backing up. On re-runs where all dotfiles are already symlinked correctly, the loop skips every file but the directory has already been created. Each `make setup` invocation leaves one empty `~/.mrk/backups/YYYYMMDD-HHMMSS/` directory.

**Fix:** Move `mkdir -p "$BACKUP_DIR"` inside the per-file branch that actually copies a file to the backup location, so the directory is only created when it will be used.

---

### M2 — `defaults.sh` rollback truncated to empty after two runs
**File:** `scripts/defaults.sh:27` | **ShellCheck:** no rule covers this

```bash
# Line 27 — runs on every invocation of make defaults:
if ! printf '#!/usr/bin/env bash\n' > "$ROLLBACK"; then
```

`>` truncates and overwrites the rollback file on every invocation. The `write_default` helper is idempotent: on a second run it detects that values are already set and skips them, so it appends no rollback entries. After two runs the rollback script is a 22-byte shebang line with no actual rollback commands — it cannot undo any of the `defaults write` changes from the first run.

**Fix:** Generate the rollback to a temp file during the run and atomically replace only at the end (`mv tmp "$ROLLBACK"`). Alternatively, detect on startup whether the rollback already exists and contains content, and skip re-generation if so.

---

### M3 — `check-updates` blocks shell startup for up to 5 seconds
**File:** `scripts/check-updates:40-65` | **ShellCheck:** no rule covers this

```bash
git -C "$REPO_DIR" fetch --quiet 2>/dev/null &
fetch_pid=$!
for _ in 1 2 3 4 5; do
  kill -0 "$fetch_pid" 2>/dev/null || break
  sleep 1
done
if kill -0 "$fetch_pid" 2>/dev/null; then
  kill "$fetch_pid" 2>/dev/null
  exit 0    # silent timeout — no user feedback
fi
```

This script is sourced from `dotfiles/.zshrc` on every interactive shell start. On a slow or offline network, every new terminal window blocks for the full 5-second timeout with no visible feedback. The silent `exit 0` on timeout makes the hang appear to be normal startup latency.

**Fix:** Reduce the loop to 1–2 iterations (1–2 seconds) or move the fetch entirely to a background job that writes a flag file, and have the `.zshrc` hook only check the flag file (never wait on the network directly).

---

### M4 — `hardening.sh` sudo check tests PATH presence, not usability
**File:** `scripts/hardening.sh:24-30` | **ShellCheck:** no rule covers this

```bash
have_sudo=false
if command -v sudo >/dev/null 2>&1; then
  # Check if sudo is available (may require password)   ← misleading comment
  have_sudo=true
fi
```

`command -v sudo` confirms the binary is in `$PATH`. It does not check whether the current user can actually run commands with sudo (NOPASSWD configuration, active credential cache, or active session). All subsequent privileged operations are wrapped in `2>/dev/null` redirection, so failures are silently discarded. On a machine where sudo requires a password and no TTY is available, the entire hardening phase silently no-ops.

**Fix:** Replace the PATH check with a zero-cost sudo probe: `sudo -n true 2>/dev/null` returns 0 only if sudo can be used without a password prompt right now. Update the comment to reflect what the check actually tests.

---

### M5 — `sync-login-items` python3 calls are not atomic — partial-write risk
**File:** `scripts/sync-login-items:244-365` | **ShellCheck:** no rule covers this

```bash
python3 - "$POST_INSTALL" "$TEMP_ADD" "$TEMP_REMOVE" <<'PYEOF'
# ... rewrites scripts/post-install in place
PYEOF
log "post-install updated."

python3 - "$MANUAL_MD" "$items_list" <<'PYEOF'
# ... rewrites docs/manual.md
PYEOF

python3 - "$INDEX_HTML" "$items_list" <<'PYEOF'
# ... rewrites docs/index.html
PYEOF
```

With `set -euo pipefail` active, if the second `python3` call fails after the first succeeds, the script aborts immediately: `scripts/post-install` has been modified but `docs/manual.md` and `docs/index.html` have not. The three sources are now out of sync, and because `write_default`-style idempotency is not implemented here, a re-run may produce further inconsistencies depending on what caused the failure.

**Fix:** Write each output to a temp file first, then `mv` all three atomically at the end (or as close to atomically as the filesystem allows). Only update the originals after all three python3 calls succeed.

---

## LOW

### L1 — SC1037: unbraced positional parameters in `adventure-prologue`
**File:** `scripts/adventure-prologue:~1211, ~1289` | **ShellCheck:** SC1037

```bash
# Bash parses $10 as ${1}0 — the value of $1 concatenated with the literal "0"
# Correct form: ${10}
```

Two instances of positional parameters above `$9` referenced without braces inside `case` handler blocks. In bash, `$10` is `${1}` followed by the character `0`, not the tenth positional parameter. These produce wrong room-description or item-lookup values when the affected code paths are taken. No production impact (game script only), but the game logic is silently wrong on those branches.

**Fix:** Change `$10` to `${10}` and `$11` to `${11}` at both locations.

---

### L2 — SC2221/SC2222: overlapping case patterns make one game branch unreachable
**File:** `scripts/adventure-prologue:~1597, ~1602` | **ShellCheck:** SC2221/SC2222

Two `case` patterns at these lines overlap such that the first pattern always matches before the second. The second branch is dead code — one game path can never be reached regardless of user input.

**Fix:** Reorder the patterns so the more specific one appears first, or merge the two branches if they should have identical behavior.

---

### L3 — SC2015: ternary-style `&&`/`||` chains without explicit grouping
**File:** `scripts/adventure-prologue` (×33), `scripts/nuke-mrk` (×2) | **ShellCheck:** SC2015

```bash
# Pattern: cmd1 && cmd2 || cmd3
# Intent:  if cmd1 succeeds: cmd2; else: cmd3
# Actual:  if cmd1 succeeds and cmd2 fails: cmd3 also runs
```

35 instances of `A && B || C` used as if-then-else. This is a known bash footgun: if `B` fails, `C` runs as a fallback even though the intent was "run C only when A fails." In `adventure-prologue` these are all in game-logic contexts (low production risk). In `nuke-mrk` the same pattern appears in cleanup sequences where silent double-execution could be more consequential.

**Fix (nuke-mrk):** Convert to explicit `if/then/else` blocks. For `adventure-prologue`, fix or accept as game-only risk.

---

### L4 — SC2005: redundant `echo $(...)` in `check-updates`
**File:** `scripts/check-updates` | **ShellCheck:** SC2005

```bash
echo $(git -C "$REPO_DIR" log ...)
# Should be:
git -C "$REPO_DIR" log ...
# or at minimum:
echo "$(git -C "$REPO_DIR" log ...)"
```

`echo $(...)` is redundant (the subshell output is just echoed as-is) and also strips the quoting protection, causing word-splitting on multi-word output. Style issue only in this context since the git log output is being displayed to the user, not processed further.

**Fix:** Remove the `echo $()` wrapper and call `git log` directly, or quote: `echo "$(git ...)"`.

---

### L5 — `fix-exec` Makefile target and `scripts/fix-exec` binary are not equivalent
**File:** `Makefile` target `fix-exec`, `scripts/fix-exec` | **ShellCheck:** n/a

```makefile
# Makefile target:
fix-exec:
    find scripts/ bin/ -maxdepth 1 -type f | xargs chmod +x
```

```bash
# scripts/fix-exec additionally:
chmod +x ~/bin/mrk ~/bin/mrk-*   # also fixes mrk symlinks in ~/bin
```

The Makefile target covers `scripts/` and `bin/` only. The standalone binary also fixes the mrk symlinks installed into `~/bin`. A user running `make fix-exec` expecting full repair of a broken install will not have their `~/bin` symlinks fixed.

`scripts/fix-exec` is also listed as a dead-code candidate in `01-callgraph.md` (no make target calls it). The two implementations should be reconciled: either have the Makefile target call `scripts/fix-exec`, or remove `scripts/fix-exec` and expand the Makefile target to cover `~/bin`.

---

### L6 — SC2034: false-positive unused-variable warnings on `NONINTERACTIVE`
**File:** `scripts/setup`, `scripts/brew`, `scripts/post-install` | **ShellCheck:** SC2034

```
scripts/setup: line 35: warning: NONINTERACTIVE appears unused. [SC2034]
scripts/brew:  line 12: warning: NONINTERACTIVE appears unused. [SC2034]
```

`NONINTERACTIVE` is exported by `lib/env.sh` and consumed by downstream scripts. Because `.shellcheckrc` suppresses SC1091 (missing source), ShellCheck cannot follow the `source lib/env.sh` chain and flags the variable as unused. These are false positives with no correctness impact. They could be silenced per-line with `# shellcheck disable=SC2034` if desired, but suppressing SC1091 is the right tradeoff here (the alternative would be a flood of source-not-found errors).

**No fix required.** Document as expected behavior of the SC1091 suppression.

---

## Files with zero findings

The following files were analyzed and are clean:

`lib/colors.sh`, `lib/env.sh`, `lib/log.sh`, `lib/prompt.sh`, `lib/state.sh`,
`scripts/audit`, `scripts/defaults.sh` (logic issues only — no ShellCheck findings),
`scripts/hardening.sh` (logic issues only), `scripts/init`, `scripts/nuke-mrk` (SC2015 noted above),
`scripts/picker`, `scripts/post-install` (trap gap noted above — no ShellCheck finding),
`scripts/pull-prefs`, `scripts/snapshot`, `scripts/snapshot-prefs`, `scripts/sync-login-items`
(logic issue noted above — no ShellCheck finding), `scripts/update`, `bin/mrk`, `bin/mrk-push`,
`bin/mrk-status`, `tools/bf/main.go` (not shell), `tools/mrk-status/main.go` (not shell),
`tools/picker/main.go` (not shell)

> Go tools are outside ShellCheck scope and were not analyzed for shell hygiene. They are listed here for completeness.
