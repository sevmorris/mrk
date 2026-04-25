# Audit 04 — Makefile Audit
**Branch:** `audit/static-pass` | **Date:** 2026-04-24

## Scope

`Makefile` (root, 136 lines, 29 targets) and `dotfiles/Makefile` (28 lines, 4 targets).
Static review only — no execution. Cross-references to `03-shell-hygiene.md` where findings
were already recorded there.

---

## Summary

| Severity | Count | Items |
|----------|-------|-------|
| MEDIUM   | 2     | `go-build` macro, `updates` error suppression |
| LOW      | 5     | `$(ARGS)` passthrough, `install`/`setup` duality, missing make targets, `help` sort order, `fix-exec` divergence |

No HIGH findings. The Makefile is structurally sound: `.PHONY` is complete, all targets
have `##` docstrings, `REPO_ROOT` is computed correctly, and `SHELL := /bin/bash` is
properly declared.

---

## MEDIUM

### M1 — `go-build` macro runs `go mod tidy` on every build
**Lines:** 9–17 (macro definition), 103, 108, 113 (call sites)

```makefile
define go-build
    @cd "$(REPO_ROOT)/tools/$(2)" && go mod tidy && go build -o "$(BIN_DIR)/$(1)" .
    @chmod +x "$(BIN_DIR)/$(1)"
endef
```

`go mod tidy` is not a no-op: it modifies `go.sum` (and occasionally `go.mod`) when the
module graph is out of sync. Running `make picker`, `make bf`, or `make mrk-status` in a
clean working tree may produce uncommitted changes to the `go.sum` files in `tools/picker/`,
`tools/bf/`, or `tools/mrk-status/`. Because `make build-tools` calls all three sequentially,
`make all` will always run `go mod tidy` three times.

This also means `make all` is not idempotent in a CI or scripted context — consecutive runs
can produce a dirty working tree.

**Fix:** Remove `go mod tidy` from the macro. Run it manually or in a dedicated maintenance
target. The three `go.sum` files should be committed in a known-good state and only updated
intentionally.

---

### M2 — `updates` target silently swallows all `softwareupdate` errors
**Line:** 91

```makefile
updates: ## Run macOS software updates
    @softwareupdate -ia || true
```

`|| true` causes the target to always exit 0 regardless of `softwareupdate`'s exit code.
A network failure, a permissions error, or a failed update all appear as success. This
also means `make all` (or any Makefile composition that includes `updates`) cannot detect
whether software updates actually succeeded.

`softwareupdate -ia` exits non-zero if there is nothing to install, which is a common
"success" state. That specific case justifies silence, but the current form is too broad —
it suppresses genuine errors too.

**Fix:** Distinguish the "nothing to install" case (exit 0) from real errors. One approach:

```makefile
updates:
    @softwareupdate -ia 2>&1 | grep -v "No updates are available" || exit 0
```

Or at minimum, log the exit code rather than suppressing it entirely.

---

## LOW

### L1 — Unquoted `$(ARGS)` passthrough in script-calling targets
**Lines:** 61, 67, 70, 120, 122, 131

```makefile
@"$(SCRIPTS)/setup" $(ARGS)
@"$(SCRIPTS)/brew" $(ARGS)
@"$(SCRIPTS)/post-install" $(ARGS)
@"$(SCRIPTS)/sync" $(ARGS)
@"$(SCRIPTS)/sync-login-items" $(ARGS)
@"$(SCRIPTS)/syncall" $(ARGS)
```

`$(ARGS)` is expanded and word-split by Make before the shell receives it. For the
documented ARGS values (single flags: `--dry-run`, `-c`, `-n`, `--only tools`), this is
benign. But any ARGS value with embedded spaces (e.g., `ARGS="--message hello world"`) is
passed to the script as three separate tokens, not one quoted string.

This is a known Make limitation rather than a unique bug here. It is documented because:
1. Scripts that accept `--message` or other value-bearing flags could be broken by a
   space in the value.
2. No help text or comment warns users of the limitation.

**Note:** `dotfiles/Makefile` correctly passes ARGS with shell quoting: `ARGS="$(ARGS)"`,
which propagates the value safely into the recursive `$(MAKE)` call. The root Makefile
does not extend the same treatment to the direct script invocations.

**Fix:** For script calls that may receive value-bearing flags, quote the expansion in the
recipe shell: `@"$(SCRIPTS)/sync" "$(ARGS)"`. For multi-flag use, consider a proper
argument-splitting approach or document the space limitation explicitly.

---

### L2 — `install` and `setup` both appear in `help` output with different descriptions
**Lines:** 59–61

```makefile
install: setup ## Run Phase 1 setup
setup: ## Phase 1: shell, dotfiles, macOS defaults
```

Both `install` and `setup` are in `.PHONY` and both have `##` docstrings. Because `help`
sorts its output, they appear adjacent in the list with subtly different descriptions. A
user reading the help output may believe they are distinct operations.

`install` is a pure alias — it has no recipe of its own and only adds `setup` as a
dependency. The `## Run Phase 1 setup` description does not make this clear.

**Fix:** Either remove `install` from the `##` docstring pattern (so it doesn't appear in
`help` output) by changing its marker to a single `#`, or change its description to
explicitly say `(alias for setup)`.

---

### L3 — No make targets for `bin/nuke-mrk` or `bin/snapshot`
**Cross-ref:** `01-callgraph.md` dead code candidates

`bin/nuke-mrk` is a complete teardown tool. `bin/snapshot` exports preferences from
running apps into `assets/preferences/` (distinct from `make snapshot-prefs`, which
exports to `~/.mrk/preferences/`). Both are linked into `~/bin` by `make setup` but
have no corresponding make targets.

The missing `make nuke` target means users must know to run `nuke-mrk` directly. The
naming collision between `make snapshot-prefs` (the prefs-repo tool) and `bin/snapshot`
(the assets-export tool) is particularly confusing — a `make snapshot` target would
clarify the distinction.

**Fix:** Add `make nuke` → `bin/nuke-mrk` and `make snapshot` → `bin/snapshot` targets.
Update `.PHONY` and `##` docstrings accordingly.

---

### L4 — `help` output is sorted alphabetically, obscuring install phase order
**Lines:** 19–22

```makefile
help:
    @grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
        | awk '...' \
        | sort
```

The `| sort` at the end of the pipeline renders targets in alphabetical order. The mrk
install flow has a natural sequence (setup → brew → post-install → harden) that the
sorted output does not convey. A new user reading `make help` sees `all`, `adventure`,
`bf`, `brew`, `build-tools`, `defaults` … without a clear sense of which targets are
phases and which are utilities.

**Fix:** Remove `| sort` and either order targets in the Makefile by natural usage sequence,
or add a grouping comment (e.g., `## ── Install phases ──`) that `awk` can render as a
visual separator.

---

### L5 — `fix-exec` Makefile target vs `scripts/fix-exec` binary divergence
**Cross-ref:** `03-shell-hygiene.md § L5`

The Makefile `fix-exec` target uses inline `find | chmod` and covers `scripts/` and `bin/`
only. `scripts/fix-exec` additionally fixes mrk symlinks in `~/bin` but is never called by
any make target. The two diverged silently and are now semantically different. See
`03-shell-hygiene.md § L5` for the full analysis and fix recommendation.

---

## Clean / no findings

- **`.PHONY` declaration**: Complete. All 29 targets are declared. No target will be
  mistakenly skipped due to a same-named file.
- **`SHELL := /bin/bash`**: Correctly declared. The `all` recipe uses bash-specific syntax
  (`[[ ]]`); without this override, Make would invoke `/bin/sh` and the recipe would
  silently misbehave on macOS.
- **`REPO_ROOT` computation**: `$(abspath $(dir $(lastword $(MAKEFILE_LIST))))` is the
  correct idiomatic pattern for determining the Makefile's own directory regardless of
  where `make` is invoked from. It also correctly resolves when the Makefile is included
  by `dotfiles/Makefile`.
- **All targets have `##` docstrings**: The `grep -E` pattern in `help` will find every
  target. No target is undocumented.
- **`go-build` Go presence check**: The macro correctly tests for `go` in PATH before
  building and emits a human-readable error with the install command. It does not silently
  fail.
- **`adventure` chaining**: `@"$(SCRIPTS)/adventure-prologue" && $(MAKE) all` correctly
  gates the full install on the user completing (not quitting) the adventure. The `&&`
  is intentional and correct.
- **`dotfiles/Makefile` shim**: Correctly delegates to `~/mrk/Makefile` via
  `$(MAKE) -C $(MRK)`. Exposes only the subset of targets appropriate for `$HOME`-level
  invocation (sync, snapshot-prefs, pull-prefs, picker). Passes `ARGS` with shell quoting
  (`ARGS="$(ARGS)"`) in the one target that uses it.
