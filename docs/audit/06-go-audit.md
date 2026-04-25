# Audit 06 — Go Audit
**Branch:** `audit/static-pass` | **Date:** 2026-04-24

## Scope

All Go source under `tools/`: `bf/main.go` (1494 lines), `picker/main.go` (702 lines),
`mrk-status/main.go` (835 lines), `theme/theme.go` (32 lines). Plus `go.mod` and `go.sum`
for each module. Dependency source not examined.

---

## Static Analysis Results

**`go vet ./...`** run from each tool directory:

| Tool | Result |
|------|--------|
| `tools/bf` | clean — no findings |
| `tools/picker` | clean — no findings |
| `tools/mrk-status` | clean — no findings |

**`staticcheck`** and **`golangci-lint`**: not installed in this environment. Manual
review substitutes for the checks they would cover.

---

## Summary

| Severity | Count | Files |
|----------|-------|-------|
| MEDIUM   | 2     | `bf/main.go`, `mrk-status/main.go` |
| LOW      | 8     | `bf/main.go` (×3), `picker/main.go` (×2), `mrk-status/main.go` (×3) |

No HIGH findings. The code is structurally clean: no unchecked errors at system
boundaries, no bare goroutines (all async work uses `tea.Cmd`), no data races, no
string-concatenated command arguments, and all external command outputs are either
captured and surfaced or intentionally discarded with documented rationale.

---

## tools/bf/main.go

### MEDIUM

#### F01 — Non-atomic Brewfile write
**File:** `bf/main.go:165–168` | **Category:** File I/O correctness

```go
func (bf *brewfile) save() error {
    out := strings.Join(bf.lines, "\n") + "\n"
    return os.WriteFile(bf.path, []byte(out), 0644)
}
```

`os.WriteFile` opens the file with `O_TRUNC|O_WRONLY`, truncates it to zero, then
streams the content. If the process receives SIGKILL (e.g., the user force-quits the
terminal) between truncation and write completion, the Brewfile is left at zero bytes
or with partial content. Since the Brewfile is version-controlled, `git checkout
Brewfile` recovers it, but the user's unsaved in-session changes are irrecoverably lost.

**Concrete bad case:** User runs `bf`, adds ten packages, presses `w` (write), then the
machine runs out of memory and the process is killed mid-write. Brewfile is truncated.

**Fix direction:** Use temp-and-rename: write to `os.CreateTemp(filepath.Dir(bf.path),
".bf-*.tmp")`, close, then `os.Rename(tmp.Name(), bf.path)`. On the same filesystem, the
rename is atomic; on SIGKILL after the write but before the rename, the original file
is intact.

---

### LOW

#### F02 — `addEntry` does not check for duplicate names
**File:** `bf/main.go:212–249, 738–758` | **Category:** Input validation

`addEntry` inserts a new package alphabetically into a section without checking whether
a package with the same name and kind already exists anywhere in the Brewfile. The `a`
(add) flow in `handleAddSection` calls `addEntry` directly:

```go
m.bf.addEntry(m.addName, m.addKind, false, secName)
```

**Concrete bad case:** User types `a`, enters `iterm2`, selects `cask`, confirms. If
`cask "iterm2"` already exists in the Brewfile, a second identical line is inserted.
`brew bundle` is tolerant of duplicates (installs once, skips the second), but the
Brewfile now has two lines and `bf` shows the package twice in the right pane.

**Fix direction:** Before calling `addEntry`, scan `bf.sections` for an existing entry
with the same name and kind; if found, set `m.flash = "already in Brewfile"` and abort
the add flow.

---

#### F03 — `toggleGreedy` strips only two exact whitespace variants
**File:** `bf/main.go:183–192` | **Category:** Input validation

```go
if e.greedy {
    line = strings.Replace(line, `, greedy: true`, "", 1)
    line = strings.Replace(line, `, greedy:true`, "", 1)
}
```

`e.greedy` is set by `strings.Contains(m[2], "greedy")`, which matches any suffix
string containing the word "greedy". But the removal only handles `, greedy: true` (one
space) and `, greedy:true` (no space). If the Brewfile was hand-edited to use
`, greedy:  true` (two spaces), `greedy: TRUE` (wrong case), or similar, `toggleGreedy`
silently leaves the line unmodified while `e.greedy` was already `true`. The toggle
appears to succeed (no error is shown) but the line is unchanged.

**Concrete bad case:** User opens a Brewfile where a cask line reads
`cask "iterm2", greedy:  true`. `bf` sees `e.greedy = true`. User presses `g` to remove
greedy. Neither replacement matches. The line is unchanged. `bf.reload()` re-parses and
still sets `e.greedy = true`. The toggle appears to silently fail.

**Fix direction:** Use a regex replace (`regexp.MustCompile(`,\s+greedy:\s+true`).
ReplaceAllString(line, "")`) rather than two fixed string replacements.

---

#### F04 — `dirty` flag cleared before commit message is confirmed
**File:** `bf/main.go:638–648` | **Category:** Error handling

```go
case "c":
    if !m.dirty {
        m.flash = "no unsaved changes to commit"
    } else {
        if err := m.bf.save(); err != nil { ... break }
        m.dirty = false          // ← cleared here
        m.inputBuf = "Brewfile: "
        m.state = stateCommit   // user types message next
    }
```

The file is saved and `m.dirty` is set to `false` before the user has typed or confirmed
the commit message. If the user presses `Esc` during the commit message prompt
(`stateCommit`), `handleInputState` returns to `stateNormal` without calling `done()`.
`m.dirty` remains `false`. A subsequent press of `c` shows "no unsaved changes to
commit" even though the changes were saved but never committed.

**Concrete bad case:** User adds a package, presses `c`, starts typing a commit message,
changes their mind and presses Esc. The file is saved. `dirty = false`. Pressing `c`
again says "no unsaved changes to commit." The only path to commit is to close and
reopen `bf` with a now-modified file.

**Fix direction:** Move `m.dirty = false` into the `done()` callback inside
`stateCommit`, after a successful `m.bf.commit(msg)` call.

---

## tools/picker/main.go

### LOW

#### F05 — Byte-length string truncation in `viewLeft` and `viewRight`
**File:** `picker/main.go:511–520, 593–605` | **Category:** Code correctness

`viewLeft` and `viewRight` truncate strings using `len()` (byte count) and byte-index
slicing:

```go
if len(name) > nameW {
    name = name[:nameW-1] + "…"
}
pad := nameW - len(name)
```

`len()` counts UTF-8 bytes, not Unicode code points or display columns. A multi-byte
character (e.g., a Japanese or Arabic package name, or a section comment with a special
character) would: (a) be counted as multiple columns by `len`, causing premature
truncation, and (b) produce an invalid UTF-8 string if sliced mid-rune (`name[:N]` where
N falls inside a multi-byte sequence).

`bf/main.go` uses `[]rune` for the same truncation, which is correct:
```go
runes := []rune(s)
if len(runes) <= n { return s }
return string(runes[:n-1]) + "…"
```

**Concrete bad case:** A Brewfile section comment of `# Repo essentials & 工具` would
have its multi-byte `工具` (3 bytes each) counted as 6 bytes by `len`, making it appear
longer than it is in columns, causing the category name to be incorrectly truncated or
padded. More concretely, `name[:nameW-1]` on a 3-byte Chinese character at the boundary
would slice mid-rune, resulting in a `strings.Builder.WriteString` call with invalid
UTF-8 and garbled output.

In practice, Brewfile section headers and package names are ASCII, so this is low risk.

**Fix direction:** Replace `len(name)` checks and `name[:N]` slices with the `[]rune`
pattern used in `bf/main.go`'s `truncate` helper.

---

#### F06 — Static descriptions map has gaps and stale entries
**File:** `picker/main.go:44–175` | **Category:** Code organization / maintenance

The `descriptions` map is 175 entries hardcoded in source. Comparing it against the
current Brewfile:

- **In Brewfile, missing from map:** `claudebar`, `softraid`, `mdrp`, `xcodegen`,
  `mac-cleanup-py` (listed as `mac-cleanup-py` in the Brewfile and map but with different
  display), `handbrake-app` (Brewfile name is `handbrake-app`, map has `handbrake`).
- **In map, not in Brewfile:** `1password`, `1password-cli`, `chatgpt`, `claude`,
  `hot`, `keybase`, `samsung-magician` and others.

When the Brewfile gains a new entry that isn't in the descriptions map, the picker shows
a blank description field for that package. This is silent — no warning, no fallback.

**Concrete bad case:** `claudebar` is in the Brewfile but not in the map. When the user
opens the picker and navigates to the claudebar entry, the description column is empty.

**Fix direction:** Either (a) move descriptions to a sidecar file (e.g., `descriptions.yml`)
so they can be maintained without recompiling, or (b) add a `// missing:` comment block
listing Brewfile entries with no description, to make gaps visible at review time.

---

## tools/mrk-status/main.go

### MEDIUM

#### F07 — Fix commands execute immediately with no confirmation prompt
**File:** `mrk-status/main.go:497–511` | **Category:** Error handling / UX

```go
case "f":
    if g := m.currentGroup(); g != nil && g.fix != "" {
        shell := os.Getenv("SHELL")
        if shell == "" { shell = "/bin/zsh" }
        cmd := exec.Command(shell, "-c",
            "cd "+shellQuote(m.repoRoot)+" && "+g.fix)
        return m, tea.ExecProcess(cmd, func(err error) tea.Msg {
            return fixDoneMsg{err: err}
        })
    }
```

Pressing `f` immediately invokes the fix command for the selected check group without
any confirmation. Fix commands include `make setup` (runs Phase 1 in full), `make brew`
(installs all Homebrew packages), and `make defaults` (applies 60+ `defaults write`
calls, kills Finder/Dock/SystemUIServer). These are non-trivial operations with side
effects documented in `02-side-effects.md`.

**Concrete bad case:** User opens mrk-status to inspect the Homebrew check. They press
`f` intending to scroll down (misremembering the keybinding) and immediately trigger
`make brew`, which begins an interactive package installation session inside the TUI.

**Fix direction:** Add a single-line confirmation step before executing: set a
`pendingFix bool` in the model and display a `[f]ix: run "<cmd>"? [enter] confirm [esc]
cancel` prompt. Execute only on the second keypress.

---

### LOW

#### F08 — Dead `indicator` variable computation
**File:** `mrk-status/main.go:730–733` | **Category:** Code organization

```go
indicator := styleDim.Render(fmt.Sprintf(" %d/%d", shown, total))
// replace last char of header row with indicator — simpler: append as last line
_ = indicator // we'll embed it in the header instead
```

`indicator` is computed (formatting a string, calling `styleDim.Render`), then
immediately discarded with `_ = indicator`. The comment shows this was in-progress code
cleanup. The dead computation runs on every render frame when the detail pane is
scrollable, which is every frame during scroll. Minor CPU waste; more importantly, the
comment leaves the reader uncertain whether this is an incomplete feature or deliberate.

**Fix direction:** Delete lines 730–733 entirely. The scroll info is already rendered
correctly in `sb2`/`header` below via `scrollInfo`.

---

#### F09 — `repoRoot` hardcoded to `~/mrk`
**File:** `mrk-status/main.go:814` | **Category:** Code organization

```go
repoRoot := filepath.Join(home, "mrk")
```

This hardcodes the assumption that mrk lives at `~/mrk`. If the user cloned mrk to a
different path (e.g., `~/projects/mrk`), all check functions (`checkDotfiles`,
`checkTools`, `checkBrewfile`) would silently look in the wrong directory. The
`checkDotfiles` would report all dotfiles as missing; `checkBrewfile` would report
Brewfile not found.

`bf/main.go` uses `defaultBrewfilePath()` which also hardcodes `~/mrk/Brewfile` but
accepts a command-line argument override. `mrk-status` has no such override.

**Concrete bad case:** User who kept their mrk clone at `~/projects/mrk` runs
mrk-status. Every check group shows warnings or errors even though the install is
correct.

**Fix direction:** Resolve the actual repo root by walking up from `os.Executable()`
or by accepting `--repo` / `MRK_ROOT` env var as an override. The current path is
acceptable for the documented use case (mrk at `~/mrk`) but should at minimum check
that the directory exists and warn if not.

---

#### F10 — `dscl` error silently discarded in `checkShell`
**File:** `mrk-status/main.go:240` | **Category:** Error handling

```go
out, _ := exec.Command("dscl", ".", "-read", "/Users/"+user, "UserShell").Output()
```

The error from `dscl` is discarded. If `dscl` fails (USER env var empty, non-existent
account, unexpected `dscl` output format, permission denied on a managed Mac), `out` is
nil/empty, `current` is "", and the function returns a `sevWarn` group saying "Login
shell: (expected: /path/to/zsh)". The actual failure reason is invisible.

This is acceptable for a status dashboard (showing a warning is correct behavior when
dscl can't be queried), but the diagnostic value is lower than it could be.

**Fix direction:** Capture the error and include it in the warning text:
`sl(sevWarn, fmt.Sprintf("dscl failed: %v", err))`.

---

## Cross-cutting observations

**No bare goroutines:** All three tools perform async work exclusively via `tea.Cmd`
(returning `tea.Msg`). The Bubble Tea runtime manages goroutine lifecycle. No goroutines
outlive the program.

**No data races:** Bubble Tea models are value types passed by copy through `Update`.
No shared mutable state between the model and any `tea.Cmd` closure.

**External command arguments:** All `exec.Command` calls pass arguments as a slice, not
as a string-concatenated shell command. The single exception is `mrk-status`'s `f`-key
handler, which builds `"cd "+shellQuote(m.repoRoot)+" && "+g.fix` as a shell string
— but `g.fix` is a hardcoded constant string (e.g., `"make setup"`), not user input,
so there is no injection risk.

**`brew` path resolution:** `exec.Command("brew", ...)` in `bf`'s `fetchSectionDescs`
and `fetchPruneList` invokes `brew` by name, relying on PATH. If `brew` is not on PATH
in the environment where `bf` runs (e.g., launched from a shell without Homebrew's
`shellenv`), descriptions and the prune list silently fail to populate. This is handled
gracefully (the TUI shows no descriptions, prune shows "checking…" forever). In
`mrk-status`, `exec.LookPath("brew")` is used as a guard in `checkBrewfile` but
`exec.Command("brew", "--version")` in `checkHomebrew` does not call LookPath first —
minor inconsistency.

**Duplicate `truncate` / `max` helpers:** Both `bf/main.go` and `mrk-status/main.go`
define identical `truncate(s string, n int) string` functions. `bf` also defines
`min`/`max` which shadow the Go 1.21+ builtins. The `theme` package is the natural home
for shared utilities; moving `truncate` there would eliminate the duplication.

**`tea.Quit` on `q`/`esc`/`ctrl+c`:** All three tools handle these consistently — clean.

**`WindowSizeMsg` handling:** All three check `m.width == 0` before rendering and return
a "Loading…" placeholder. Layout calculations include minimum size guards (e.g., `if
bodyH < 4 { bodyH = 4 }`). Very narrow terminals (width < ~30) produce visually broken
but non-crashing output.

**No help key (`?`):** None of the three tools implement an in-TUI help overlay. Help
text is available only via `--help` at the command line. Consistent across all three,
so not an inconsistency, but notable gap for discoverability.

---

## Dependency Hygiene

All three modules declare `go 1.22`. Direct dependencies:

| Dependency | Version | Status |
|---|---|---|
| `github.com/charmbracelet/bubbletea` | `v1.1.0` | Current stable; no known CVEs |
| `github.com/charmbracelet/lipgloss` | `v1.0.0` | Current stable v1; no known CVEs |
| `mrk-theme` (local) | `v0.0.0` + `replace` | Local package; standard pattern |

Indirect dependencies include `golang.org/x/text v0.3.8` (pulled transitively through
bubbletea). The current release of `x/text` is `v0.22.0`. CVE-2021-38561 (panic via
`language.ParseAcceptLanguage`) affected versions before `v0.3.7`; `v0.3.8` is patched.
No known CVEs apply to `v0.3.8` for the specific APIs used here (string rendering via
bubbletea's internal chain). The version mismatch is notable but not a current security
concern.

No pre-1.0 direct dependencies. No `replace` directives pointing to external forks.
`go.sum` files are present and consistent with the module graph. The `go mod tidy`
invocation in the `go-build` Makefile macro (flagged in `04-makefile-audit.md` M1) is
the only mechanism that would modify these files at build time.

---

## Top Findings

| # | Severity | File:line | Finding |
|---|----------|-----------|---------|
| 1 | MEDIUM | `bf:165` | Non-atomic Brewfile write — kill mid-write truncates file |
| 2 | MEDIUM | `mrk-status:500` | Fix commands run with no confirmation (`make setup`, `make brew`, etc.) |
| 3 | LOW | `bf:638` | `dirty` flag cleared before commit message confirmed — TUI gets stuck |
| 4 | LOW | `bf:212` | `addEntry` creates duplicate Brewfile lines with no warning |
| 5 | LOW | `picker:511` | Byte-length truncation; `bf` uses correct rune-length pattern |
