# Audit 05 — Brewfile and Ruby Review
**Branch:** `audit/static-pass` | **Date:** 2026-04-24

## Scope

`Brewfile` (138 lines): taps, formulae, and casks. Static review — no `brew bundle check`
execution. Cross-referenced against `scripts/post-install` and `scripts/snapshot-prefs`
to identify coverage gaps (apps configured but not installed).

Ruby: no `Gemfile`, no `.rb` files, and no `ruby` formula are present in the repository.
There is no Ruby content to review. The Ruby section below reflects this finding.

---

## Brewfile

### Structure and Stats

| Category | Count |
|----------|-------|
| Formulae | 38 |
| Casks    | 63 |
| Taps     | 0 (empty section header) |
| `mas` entries | 0 |

---

### Findings

#### B1 — Empty `# Taps` section header
**Line:** 1

```
# Taps

# CLI Tools - General...
```

The `# Taps` comment appears at the top of the file but has no `tap` declarations beneath it.
If no custom taps are needed (all formulae and casks are available from the default
`homebrew/core` and `homebrew/cask` taps), the section should be removed. Its presence
implies taps exist when they don't, and any future tap additions should be placed here rather
than discovered later.

**Fix:** Remove the empty section header, or add tap declarations if any formulae or casks
require them (e.g., if a third-party cask ever moves to a custom tap).

---

#### B2 — `greedy: true` inconsistently applied to casks
**Lines:** 38, 122

```
cask "claudebar"          # ← no greedy: true
...
cask "softraid"           # ← no greedy: true
...
cask "iterm2", greedy: true  # representative of all other casks
```

All 63 casks have `greedy: true` except `claudebar` and `softraid`. The `greedy: true`
option causes `brew bundle` to upgrade a cask even if the app reports itself as up-to-date
(bypassing the app's own auto-update check). Its absence on these two means they will be
skipped by `brew bundle` once installed unless Homebrew's version metadata changes.

This is likely an oversight rather than a deliberate exception. `softraid` in particular
is a paid system extension where being on the latest version for compatibility matters.

**Fix:** Add `greedy: true` to both lines, or — if the omission is intentional for
`claudebar` or `softraid` — add a comment explaining why.

---

#### B3 — `nvm` installed via Homebrew; official docs recommend against this
**Line:** 49 (`brew "nvm"`)

The nvm README explicitly states: _"Homebrew installation is not supported."_ The Homebrew
formula for `nvm` requires additional manual shell configuration that the standard install
script handles automatically. It does not set up the required `.zshrc` sourcing:

```bash
export NVM_DIR="$HOME/.nvm"
[ -s "$HOMEBREW_PREFIX/opt/nvm/nvm.sh" ] && source "$HOMEBREW_PREFIX/opt/nvm/nvm.sh"
```

Without this, `nvm` is installed but non-functional after a fresh bootstrap. The mrk
dotfiles (`dotfiles/.zshrc`) would need to include the above lines for Homebrew-nvm to
work. If they don't, every user who installs via `make all` has a broken `nvm` with no
error message.

**Fix:** Either add the nvm initialization lines to `dotfiles/.zshrc` (with a comment
explaining they target the Homebrew install path), or replace `brew "nvm"` with the
official install-script method (added to `scripts/post-install` or `scripts/brew`).

---

#### B4 — `python@3.12` hardcoded version alongside `pyenv`
**Lines:** 51 (`brew "python@3.12"`), 53 (`brew "pyenv"`)

Both a pinned Python version (`python@3.12`) and a Python version manager (`pyenv`) are
present. These represent two competing management strategies:

- `python@3.12` provides a fixed, Homebrew-managed Python that ages in place. When
  `python@3.13` becomes the Homebrew default, `python@3.12` becomes a legacy tap.
- `pyenv` lets the user switch Python versions on demand via `.python-version` files.
  When `pyenv` is the active manager, the Homebrew `python@3.12` may not even be on
  `$PATH` depending on shell configuration.

`pipx` (line 52) adds a third layer — it installs Python applications in isolated
environments using whatever Python it finds first.

The result is ambiguous: it is not clear which Python is canonical for this system or
which tools use which interpreter. If `pyenv` is the intended manager, `python@3.12`
should be removed from the Brewfile and its version pinned via `pyenv` instead.

**Fix:** Decide on one Python management strategy. If `pyenv` is primary, remove
`python@3.12` from the Brewfile and manage the version via a `.python-version` file or
`pyenv global`. If Homebrew-managed Python is primary, remove or comment out `pyenv`.

---

#### B5 — `openjdk` requires a post-install `sudo ln` step that is not automated
**Line:** 54 (`brew "openjdk"`)

Homebrew's `openjdk` formula caveats require a manual step after install for the JDK to
be visible to system Java finders:

```
sudo ln -sfn /opt/homebrew/opt/openjdk/libexec/openjdk.jdk \
  /Library/Java/JavaVirtualMachines/openjdk.jdk
```

Without this, `java` is present at the Homebrew prefix but not on the system JVM path that
tools like Maven, Gradle, and `java_home` use. This step is not performed by any mrk script.
A fresh bootstrap with `make all` installs `openjdk` but leaves the system Java path empty.

**Fix:** Add the `sudo ln -sfn` command to `scripts/post-install` (after the brew phase
completes), guarded by a check for whether the link already exists:

```bash
if [[ ! -e "/Library/Java/JavaVirtualMachines/openjdk.jdk" ]]; then
  sudo ln -sfn /opt/homebrew/opt/openjdk/libexec/openjdk.jdk \
    /Library/Java/JavaVirtualMachines/openjdk.jdk
fi
```

---

#### B6 — `bash-completion@2` is vestigial: primary shell is zsh
**Line:** 5 (`brew "bash-completion@2"`)

`bash-completion@2` provides tab-completion for bash. The mrk bootstrap changes the login
shell to zsh (`make setup` → `phase_shell`), and the dotfiles configure zsh. The
`bash-completion@2` formula requires sourcing a script from `~/.bash_profile` or
`~/.bashrc` to activate, which mrk does not do.

The formula installs silently, does nothing for zsh users, and adds ~15 MB for no benefit
on a fresh bootstrap.

**Fix:** Remove `brew "bash-completion@2"` unless there is a specific use case (e.g.,
scripts that invoke bash explicitly and need completions). If kept, document why in a
comment.

---

#### B7 — `coreutils` provides GNU tools under `g`-prefixes only, without PATH change
**Line:** 6 (`brew "coreutils"`)

Homebrew's `coreutils` installs GNU versions of standard POSIX tools (`ls`, `cat`, `sed`,
etc.) under `g`-prefixed names (`gls`, `gcat`, `gsed`). To replace the macOS system tools
with GNU equivalents requires explicitly prepending the gnubin path:

```bash
export PATH="$(brew --prefix coreutils)/libexec/gnubin:$PATH"
```

The mrk dotfiles do not include this PATH modification (not visible in the call graph or
shell audit). As a result, `coreutils` installs `g`-prefixed aliases but does not change
the behavior of `ls`, `cat`, etc. — the macOS BSD tools remain active.

This may be intentional (GNU tools available when needed via `gls`, `gsed`, etc.) or an
oversight (expecting GNU tool behavior transparently). If the intent is transparent GNU
replacement, the PATH change needs to be added to `dotfiles/.zshrc`.

---

#### B8 — Apps configured by `post-install` are missing from the Brewfile
**Source:** `scripts/post-install:395-404`, `scripts/post-install:318`

`scripts/post-install` configures login items and imports preferences for apps that are not
present in the Brewfile. `post-install` gracefully skips apps that are not installed
(the `add_login_item` function checks for the `.app` bundle before registering), so this
does not cause a hard failure. However, it means a fresh `make all` leaves these apps
unconfigured until the user installs them manually and re-runs `make post-install`.

| App | Configured in `post-install` | In Brewfile | Available via |
|-----|------------------------------|-------------|---------------|
| BetterSnapTool | Login item + prefs import | ✗ | Mac App Store |
| Bitwarden | Login item | ✗ | `cask "bitwarden"` available |
| Hammerspoon | Login item | ✗ | `cask "hammerspoon"` available |
| Chrono Plus | Login item | ✗ | Mac App Store (unclear) |

**BetterSnapTool** is Mac App Store only (no Homebrew cask), so it cannot be added to the
Brewfile. Its absence is expected if the user installs it from MAS separately.

**Bitwarden** and **Hammerspoon** have Homebrew casks. Their absence from the Brewfile
means they must be manually installed before `make post-install` can configure them.

**Fix:** Add `cask "bitwarden"` and `cask "hammerspoon"` to the Brewfile. Add a `# Mac
App Store` section comment and note BetterSnapTool and Chrono Plus as requiring manual
installation (or add `mas` entries if App Store IDs are known).

---

### Observations (no action required)

- **`greedy: true` on all auto-updating apps**: Applying `greedy: true` universally causes
  `brew bundle` to upgrade casks even when the app's own auto-updater has already done so.
  This results in double-updates for apps like Chrome, Dropbox, and Slack on routine `brew
  bundle` runs. This is a deliberate policy tradeoff (guarantees Homebrew version metadata
  stays current) rather than a bug.

- **`qemu` and `utm` together**: UTM is a GUI wrapper around QEMU. Having both is
  intentional — `qemu` provides CLI access and UTM provides the GUI.

- **`whisper-cpp` and `macwhisper`**: The CLI (`whisper-cpp`) and the GUI (`macwhisper`)
  serve different workflows. Not a redundancy.

- **`mkdocs`**: Used for `sevmorris.github.io/mrk` site generation. Reasonable to include
  as a dev dependency.

- **`xcodegen` in "Repo essentials"**: An Xcode project generator is not a bootstrap
  essential in the narrow sense, but the section appears to be "tools needed to work in
  this repo" rather than "tools needed to run mrk." The placement is clear enough.

- **`chromaprint` inline comment** (line 60): Only formula with an inline comment.
  Consistent style is preferable but this is minor.

- **Trailing empty line** (line 138): `brew bundle` ignores it. No action needed.

---

## Ruby

No Ruby content was found:

- No `Gemfile` or `Gemfile.lock`
- No `.ruby-version` or `.tool-versions` file
- No `*.rb` source files
- No `ruby` formula in the Brewfile
- No `gem install` calls in any script

Nothing to review.
