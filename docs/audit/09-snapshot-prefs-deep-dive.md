# Audit 09 — `make snapshot-prefs` Deep Dive
**Branch:** `audit/static-pass` | **Date:** 2026-04-25

## Scope

Forensic analysis of `scripts/snapshot-prefs` (102 lines) and the `make snapshot-prefs`
Makefile target. The earlier modules established this as Hot Spot #3 in blast radius
(`02-side-effects.md`): the only target that pushes user data to a GitHub repository.
This document traces what data is exported, where it goes, who can read it, and what
happens in every failure path.

---

## 1. Summary

`make snapshot-prefs` exports current application preferences from 14 installed apps
and several app-support directories, commits them into a local git repo at
`~/.mrk/preferences/`, and pushes that repo to `git@github.com:sevmorris/mrk-prefs.git`
(or a user-specified override via the `PREFS_REPO` environment variable).

What ends up on GitHub: XML plist files for each app's preference domain (exported via
`defaults export`) plus verbatim copies of app-support files for Loopback and SoundSource
(routing configurations, device maps, presets). One commit per run, with message
`"snapshot: YYYY-MM-DD HH:MM"`.

Who can read it: anyone with read access to the remote repository. The script does not
check whether the remote is private. If the repository is public, all exported data is
publicly readable. The design assumes a private repo; no privacy gate is enforced.

---

## 2. Repository Configuration

### Remote URL

The remote is set by: `: "${PREFS_REPO:=git@github.com:sevmorris/mrk-prefs.git}"` (line 7).
This is an environment variable with a hardcoded default. To use a different remote,
the user must set `PREFS_REPO` before invoking `make snapshot-prefs`. The Makefile
target does not document this. There is no prompt, no verification, and no way to
change the remote without either the environment variable or manual `git remote set-url`.

### First-Run Behavior

Three distinct cases:

1. **`~/.mrk/preferences/.git` exists** (repo already initialized): Script skips init
   entirely. Uses the existing repo with its existing remote configuration. If the
   existing remote does not match `PREFS_REPO`, the script does not notice and does not
   update the remote — it uses whatever remote is already set. The hardcoded default
   only applies at init time.

2. **`~/.mrk/preferences` dir exists, no `.git`**: The script runs `git init` then
   `git remote add origin "$PREFS_REPO"`. This creates a new, empty-history repo with
   no connection to the remote's existing history. On `git push` (line 99), the push
   will fail with "rejected (non-fast-forward)" because the local repo has no common
   ancestor with the remote. Under `set -euo pipefail`, the script exits with an error.
   Any files exported earlier in this run remain in `~/.mrk/preferences/` as unstaged
   uncommitted changes.

3. **`~/.mrk/preferences` does not exist**: `git clone "$PREFS_REPO" ~/.mrk/preferences`
   pulls the remote's history into the local directory. Export and push then happen
   against a repo with shared history. This is the clean first-run path.

### Remote Mutability

Once the repo is initialized (case 1 or 3 above), the script never changes the remote
URL. No `git remote set-url` call exists in `snapshot-prefs`. The remote configured at
init time persists across all subsequent runs regardless of the `PREFS_REPO` env var.
Changing the push destination after init requires `git -C ~/.mrk/preferences remote set-url origin <new>` manually.

### Privacy Enforcement

None. The script does not call the GitHub API to check repository visibility before
pushing. There is no `--private` flag to `git clone`. Whether the remote repo is
public or private is entirely determined by how the user created it on GitHub; the
script cannot enforce or verify this.

---

## 3. Per-App Data Classification

Export method for all 14 apps: `defaults export <bundle_id> <output_file>`. This reads
the live defaults system (preferences daemon) and writes a clean XML plist. It captures
all keys in the app's defaults domain, including any keys the app has written but not
surfaced in its UI. It does NOT read `~/Library/Preferences/<bundle>.plist` directly;
it reads through the preferences daemon which may include in-memory (unflushed) state.

Sensitivity ratings: **PUBLIC** (UI prefs only) / **SEMI-PRIVATE** (paths, usage
patterns, installed-software topology) / **PRIVATE** (credentials, tokens, license
keys, transcripts).

---

### 3.1 BetterSnapTool — `com.hegenberg.BetterSnapTool`

**Typical plist contents:** Window snapping zones (screen edges, corners, custom
regions), keyboard shortcuts for zones, snap-on-drag sensitivity, multi-display
configurations.

**Sensitivity: PUBLIC.** Window management geometry and shortcuts reveal nothing
sensitive. License activation status may be stored as a key; if so, the license key
itself is typically a UUID-format receipt, not a reusable serial number.

**Recommendation: Keep.**

---

### 3.2 Ice — `com.jordanbaird.Ice`

**Typical plist contents:** Which menu bar items are hidden vs. always visible vs.
shown when needed. UI layout settings, trigger hotkeys.

**Sensitivity: PUBLIC.** The list of menu bar app names could reveal which apps are
installed, but this information is already implicit in the Brewfile that is public in
the mrk repo.

**Recommendation: Keep.**

---

### 3.3 iTerm2 — `com.googlecode.iterm2`

**Typical plist contents:** This is the highest-topology-revealing entry in the list.
The iTerm2 defaults domain stores the full profile configuration, which regularly
includes:
- Named profiles with custom `Initial Directory` (filesystem paths)
- Custom `Command` entries (shell invocations, `ssh user@host` commands — hostnames)
- `Tags` and triggers (regex patterns used for hostname-specific behavior)
- `Bookmarks` (the legacy internal term for profiles) — each may include a `Name`
  field set to a hostname or environment name ("prod", "staging", etc.)
- Key bindings and actions that may embed hostnames or commands
- Session restoration paths (if session restoration is enabled)

`defaults export` captures all of this as XML. The exported plist for a typical
infrastructure-using developer is a near-complete map of where they log in.

**Sensitivity: SEMI-PRIVATE** (infrastructure hostnames, server names, session
directories). Whether it reaches PRIVATE depends on whether any profile's `Command`
field embeds credentials (unusual but not impossible — some users set
`Command = "sshpass -p mypassword ssh user@host"` or similar). UNKNOWN-NEEDS-VERIFICATION
for whether this specific user's iTerm2 profiles contain embedded credentials.

**Recommendation: Keep with awareness.** If profiles contain hostnames or commands
embedding infrastructure names, treat the repo as sensitive. If any profile contains
embedded credentials, this plist should be excluded or sanitized before commit.

---

### 3.4 Raycast — `com.raycast.macos`

**Typical plist contents:** This is the highest-risk single entry. Raycast stores
configuration in its defaults domain, and depending on which extensions are configured:
- Extension settings (each extension has its own key namespace)
- **API keys for extensions**: OpenAI API key (AI Commands extension), GitHub personal
  access token (GitHub extension), Linear API key, Notion integration token, etc. These
  are commonly stored in `com.raycast.macos` defaults because Raycast uses the macOS
  defaults system as its configuration store.
- Recent files and searches (recent finder paths, recent commands)
- Clipboard history contents (if Clipboard History extension is active — history is
  typically in a separate SQLite db, not defaults, but metadata may appear)
- Custom script metadata (names, paths to local scripts)

The Raycast defaults domain has been documented publicly as containing plaintext API
keys for users who have configured the AI Commands or third-party service extensions.

**Sensitivity: PRIVATE.** UNKNOWN-NEEDS-VERIFICATION whether this specific user's
Raycast plist contains API keys. To check: `defaults read com.raycast.macos | grep -i 'key\|token\|secret\|api'` locally before the next push.

**Recommendation: VERIFY before each push.** If API keys are present, either exclude
`Raycast.plist` from the snapshot, or rotate any exposed keys immediately after
discovering they were committed. This is the single entry most likely to contain
reusable credentials.

---

### 3.5 Stats — `eu.exelban.Stats`

**Typical plist contents:** Widget type configurations (CPU, GPU, network, disk),
display positions, update intervals, which hardware interfaces are monitored.

**Sensitivity: PUBLIC.** Network interface names could reveal VPN adapter names but
this is not meaningful exposure.

**Recommendation: Keep.**

---

### 3.6 Loopback — `com.rogueamoeba.Loopback`

**Typical plist contents:** UI preferences, theme settings, window state, update
preferences. The routing configurations themselves are stored in App Support files
(see §3.14).

**Sensitivity: PUBLIC** (for the defaults export itself).

**Recommendation: Keep.**

---

### 3.7 SoundSource — `com.rogueamoeba.soundsource`

**Typical plist contents:** Update preferences, volume levels, audio device
selections.

**Sensitivity: PUBLIC** (for the defaults export itself; routing data is in App
Support files — see §3.15).

**Recommendation: Keep.**

---

### 3.8 Audio Hijack — `com.rogueamoeba.audiohijack`

**Typical plist contents:** As documented in `01-callgraph.md` assets/preferences:
`applicationTheme`, `audioEditorBundleID` (the external editor set to iZotope RX Pro),
`bufferFrames`, `allowExternalCommands`. The full defaults domain may also include
recent session paths and recording output directories.

**Sensitivity: SEMI-PRIVATE.** The `audioEditorBundleID` reveals a specific expensive
professional audio tool is installed. Recent session paths would reveal recording
project directories and filenames. UNKNOWN-NEEDS-VERIFICATION for whether this
specific user's Audio Hijack plist includes session paths.

**Recommendation: Keep with awareness.**

---

### 3.9 Farrago — `com.rogueamoeba.farrago`

**Typical plist contents:** Theme settings, update preferences. Soundboard tile
configurations are stored in a separate App Support data file, not in the defaults
domain.

**Sensitivity: PUBLIC.**

**Recommendation: Keep.**

---

### 3.10 Piezo — `com.rogueamoeba.Piezo`

**Typical plist contents:** Update preferences, output format settings, recording
source selections. No credentials or sensitive paths expected in the defaults domain.

**Sensitivity: PUBLIC.**

**Recommendation: Keep.**

---

### 3.11 Typora — `abnerworks.Typora`

**Typical plist contents:** Editor theme, font preferences, export format settings,
recently opened file paths, last-opened directory. Typora is paid software; license
activation state may be stored in defaults (the license key itself is typically a
UUID-style receipt, not a reusable serial).

**Sensitivity: SEMI-PRIVATE.** Recent file paths reveal document names and directory
structure (`/Users/you/Documents/ClientName/project.md`). Path information can expose
client names, project names, and directory layout.

**Recommendation: Keep with awareness.** If recent-file paths are sensitive, consider
excluding this plist or clearing recents before snapshotting.

---

### 3.12 Keka — `com.aone.keka`

**Typical plist contents:** Default extraction destination, recent source/destination
paths, archive format preferences.

**Sensitivity: SEMI-PRIVATE.** Recent extraction paths could reveal directory
structure. Low practical risk.

**Recommendation: Keep.**

---

### 3.13 TimeMachineEditor — `com.tclementdev.timemachineeditor.application`

**Typical plist contents:** Backup schedule (intervals, specific times), the list of
backup volumes. May include path exclusions configured through the app.

**Sensitivity: SEMI-PRIVATE.** Backup exclusion paths reveal directory layout. Backup
volume names are low-risk. No credentials expected.

**Recommendation: Keep.**

---

### 3.14 MacWhisper — `com.goodsnooze.MacWhisper`

**Typical plist contents:** MacWhisper supports both local (Core ML) and cloud
(OpenAI Whisper API) transcription. If cloud mode is configured:
- The **OpenAI API key** for Whisper may be stored in the defaults domain.
Transcript output directory paths are stored in defaults. Recent transcription file
paths reveal document names. Some MacWhisper versions store transcription history
metadata in defaults.

**Sensitivity: PRIVATE.** UNKNOWN-NEEDS-VERIFICATION whether this specific user's
MacWhisper is configured for cloud transcription with an API key in defaults. To
check: `defaults read com.goodsnooze.MacWhisper | grep -i 'key\|api\|openai'` locally.

**Recommendation: VERIFY before each push.** If an OpenAI API key is present in
defaults, it will be exported to the snapshot and pushed to GitHub. Rotate the key if
this has already occurred.

---

### 3.15 Loopback App Support Files

**Files exported:** `Devices.plist`, `RecentApps.plist`
(from `~/Library/Application Support/Loopback/`)

`Devices.plist` contains the complete set of Loopback virtual audio device
configurations: device names, audio routing graphs, which real input sources feed each
virtual device, which apps are routed through each device, channel counts, and
processing settings.

`RecentApps.plist` lists recently used applications in Loopback by bundle identifier
and display name.

**Sensitivity: SEMI-PRIVATE.** The routing graphs in `Devices.plist` reveal:
- All audio software installed (DAW names, plugin hosts, virtual instruments, recording
  software — named by their bundle ID or display name as audio sources)
- The user's audio workflow topology (what records from what, what monitors what)

For an audio professional, this is a detailed picture of their toolset and session
routing strategy. It does not contain credentials, but it reveals software inventory
that the user may consider confidential (unreleased DAW projects, specific plugin suites).

Export method: `cp` (verbatim copy), not `defaults export`. Binary plist keys are
preserved if present.

**Recommendation: Keep with awareness.** If DAW/plugin software confidentiality is
a concern, exclude these files.

---

### 3.16 SoundSource App Support Files

**Files exported:** `Presets.plist`, `CustomPresets.plist`, `Sources.plist`, `Models.plist`
(from `~/Library/Application Support/SoundSource/`)

`Presets.plist` and `CustomPresets.plist` contain named audio routing presets —
arrangements of which apps route through which audio outputs, with volume levels.

`Sources.plist` stores audio source configurations by name and identifier.

`Models.plist` contains hardware device model data for known audio interfaces.

**Sensitivity: SEMI-PRIVATE.** Preset names and source configurations can reveal app
names in the audio routing chain (same considerations as Loopback). `Models.plist` is
essentially a hardware inventory; low sensitivity.

Export method: `cp` (verbatim copy).

**Recommendation: Keep with awareness.**

---

### 3.17 Confirmed Exclusions

| App | Explicitly excluded | Reason notable |
|---|---|---|
| Bitwarden | Yes — not in script | Password manager; correct exclusion |
| NordPass | Yes — not in script | Password manager; correct exclusion |
| 1Password | Yes — not in script | Password manager; correct exclusion |
| Barkeep | Yes — not in script | mrk companion app; no sensitive data |

No password manager is in scope. The `com.hegenberg.BetterSnapTool` bundle is
BetterSnapTool, not Bitwarden — they have no relationship.

---

### Summary Table

| App | Export Method | Sensitivity | Action |
|---|---|---|---|
| BetterSnapTool | defaults export | PUBLIC | Keep |
| Ice | defaults export | PUBLIC | Keep |
| iTerm2 | defaults export | SEMI-PRIVATE | Keep; verify no embedded credentials |
| Raycast | defaults export | **PRIVATE** | Verify API keys before each push |
| Stats | defaults export | PUBLIC | Keep |
| Loopback | defaults export | PUBLIC | Keep |
| SoundSource | defaults export | PUBLIC | Keep |
| Audio Hijack | defaults export | SEMI-PRIVATE | Keep with awareness |
| Farrago | defaults export | PUBLIC | Keep |
| Piezo | defaults export | PUBLIC | Keep |
| Typora | defaults export | SEMI-PRIVATE | Keep; recent paths may be sensitive |
| Keka | defaults export | SEMI-PRIVATE | Keep |
| TimeMachineEditor | defaults export | SEMI-PRIVATE | Keep |
| MacWhisper | defaults export | **PRIVATE** | Verify API keys before each push |
| Loopback App Support | cp (verbatim) | SEMI-PRIVATE | Keep with awareness |
| SoundSource App Support | cp (verbatim) | SEMI-PRIVATE | Keep with awareness |

Sensitivity distribution: PUBLIC × 7, SEMI-PRIVATE × 7, PRIVATE × 2 (Raycast, MacWhisper).

---

## 4. Push Semantics

### Force-push or fast-forward?

`git push` at line 99 with no `--force` flag. This is a normal fast-forward-only push.
The remote will reject the push if the remote has commits the local doesn't.

### Remote diverged (snapshot from another machine)

If the same user runs `make snapshot-prefs` on Machine A and then Machine B without
first pulling on Machine B: Machine B's local repo is behind the remote (Machine A's
push advanced it). `git push` fails with "rejected (non-fast-forward)". Under
`set -euo pipefail`, the script exits with the push error. The local exports on Machine B
are complete (all plists written to `~/.mrk/preferences/` and staged via `git add .`)
but not committed or pushed. The user must manually run `git -C ~/.mrk/preferences pull`
(or `pull --rebase`) to advance the local branch, then re-run. The plist files in the
working tree are already at the Machine B state; after pull, `git add .` on the next
run will stage Machine B's new changes on top of Machine A's history.

There is no automatic rebase or merge in the script. Multi-machine workflows require
manual intervention when the remote diverges.

### Local uncommitted changes from prior failed run

`git add .` at line 94 stages ALL changes in the working tree, including any leftovers
from a prior partial export. If a previous run exported some plists but failed before
committing (e.g., a `defaults export` failure aborted the script), those plists remain
in `~/.mrk/preferences/`. On the next successful run, `git add .` stages both the
new exports and the prior-run leftovers, and all are committed together. This is
correct behavior — the next commit catches up with everything.

### Commit message and granularity

One commit per script invocation. Commit message: `"snapshot: YYYY-MM-DD HH:MM"`.
The message does not identify which apps changed, only the timestamp. Browsing the
commit history reveals when snapshots were taken but not what changed. `git diff` or
`git show` is required to see per-app changes. This is a usability limitation, not a
correctness issue.

The `git diff --cached --quiet` check at line 95 correctly skips commit and push if
there are no staged changes (i.e., all exported plists are byte-for-byte identical to
the last committed versions). This prevents empty commits.

---

## 5. Failure Modes

### FM1 — Network failure mid-export

Export phase (lines 41–89) does not use the network. Network is only required for the
initial `git clone` (if `~/.mrk/preferences` doesn't exist) and for `git push`. If
the network fails during `git push`, the script exits with the push error under
`set -e`. All exports were completed and committed before the push; the local commit
exists at `HEAD`. Re-running after the network recovers will find no staged changes
(all already committed) and no diff to commit. The push will succeed on the next run.
Net result: the export is committed locally but not yet visible on GitHub until the
next run in a connected state.

### FM2 — Network failure mid-push

A push that starts but fails mid-transfer leaves the remote in an undefined partial
state. Git pushes are atomic at the remote protocol level (the remote writes the pack
file and updates the ref atomically only on success). A network interruption means the
remote ref was either updated or not — there is no partial-ref update. Practically:
the remote is in its previous state (push failed). Local state has the commit. Next
push attempt on reconnect will succeed via fast-forward.

### FM3 — SSH key not present or wrong key for the remote

The remote URL `git@github.com:sevmorris/mrk-prefs.git` requires SSH auth. If no SSH
key is configured for `github.com`, `git push` fails with
`Permission denied (publickey)`. Under `set -e`, the script exits. This failure occurs
at the very end of the script, after all exports and the local commit. The plist files
are exported and locally committed; the push simply failed. User must configure SSH
credentials and re-run (the next run will find no new staged changes and the push will
succeed for the already-committed snapshot).

`git clone` at line 21 (first-run case) will also fail with the same SSH error,
aborting before any exports occur.

### FM4 — Disk full during plist export

`defaults export` writes an XML file to `~/.mrk/preferences/`. If the disk is full,
the export fails. The `|| { log "Warning: failed to export $name"; return 1; }` handler
in `snapshot_plist` returns 1 from the function. Since `snapshot_plist` is called at
the top level without a conditional or `||`, under `set -e` the script exits at the
first failed export. Subsequent apps are not exported. The already-exported plists
remain in `~/.mrk/preferences/` in a partially-updated state. No commit or push occurs.
On re-run after freeing disk space, the already-exported plists from the failed run
remain; `defaults export` overwrites them with current values. Eventually a clean run
commits everything.

### FM5 — One app's plist export fails, others succeed

Same abort behavior as FM4 — `set -e` causes the script to exit at the first failure.
Apps listed BEFORE the failing app in the script have their plists exported and
written; apps listed AFTER have not. This creates a partially-updated `~/.mrk/preferences/`
that is never committed until a full clean run succeeds.

The app order in the script is: BetterSnapTool → Ice → iTerm2 → Raycast → Stats →
Loopback → SoundSource → Audio Hijack → Farrago → Piezo → Typora → Keka →
TimeMachineEditor → MacWhisper. A failure at BetterSnapTool aborts before any others
are exported. A failure at MacWhisper (last) means all others are complete and the only
missed plist is MacWhisper. The commit never happens in either case, so the partially-
updated state is always local.

### FM6 — mrk-prefs repo deleted, renamed, or visibility changed on GitHub

`git push` fails with a "repository not found" or "repository was archived" error.
Under `set -e`, the script exits. Local state is unaffected. If the repo was made
public: any data previously pushed to GitHub is now publicly readable. There is no
automated alert for this scenario.

### FM7 — Git remote rejects the push (branch protection, force-push protection)

If `mrk-prefs` has branch protection rules on its default branch (e.g., required
status checks, admin enforcement), the push will be rejected. Script exits at push with
an error. Local commit exists. User must resolve the branch protection rule manually.

### FM8 — Simultaneous snapshots from two machines

Machine A and Machine B both complete their export and local commit. Machine A pushes
first. Machine B's subsequent push fails (non-fast-forward, as in §4). Machine B's
snapshot is committed locally but not pushed. Machine B user must pull, resolve any
automatic merge (if plist content differs), and push. There is no lock mechanism; this
is standard multi-machine git behavior with no snapshot-specific protection.

---

## 6. Privacy Verdict

### Assuming mrk-prefs is private

The current default behavior is **reasonably safe** for a typical user who maintains
the repository as private and has not configured Raycast with third-party service
extensions or MacWhisper for cloud transcription. The public-only entries (Stats,
BetterSnapTool, Ice, Farrago, Piezo, Loopback defaults, SoundSource defaults) pose
negligible risk. The semi-private entries (iTerm2, Typora, Keka, Audio Hijack,
TimeMachineEditor, Loopback App Support, SoundSource App Support) reveal infrastructure
topology and file system layout — meaningful if the user treats those as confidential,
but not catastrophic.

The highest-risk entries (Raycast, MacWhisper) are a conditional risk: they only
become PRIVATE if those specific apps are configured with API keys stored in defaults.
A user who uses Raycast with the AI Commands extension or MacWhisper in cloud mode is
pushing live API keys to GitHub on every snapshot run without any notification.

### If the repo is public

If `mrk-prefs` is public or becomes public through any means (accidental creation as
public, API, GitHub settings change, fork visibility), all previously pushed snapshots
are immediately readable by anyone. Raycast API keys, MacWhisper API keys, iTerm2
infrastructure hostnames, and all file system paths are exposed at the commit level —
including historical commits that cannot be purged without a force-push history rewrite.
The "rotate your key" response applies to any API key found in the history.

The script has no safeguard against this. There is no pre-push check that reads the
remote's visibility setting via the GitHub API.

### Worst-case exposure if the remote is compromised

Remote compromise (GitHub account access, leaked deploy key, or accidental public
visibility) exposes: active OpenAI API keys (Raycast AI Commands + MacWhisper cloud),
GitHub personal access token (if Raycast GitHub extension is configured), any other
service-specific tokens stored in Raycast extension settings, iTerm2 server hostnames
and session commands, Typora recent file paths (document names, client names),
Loopback/SoundSource audio routing graphs (installed software inventory), and all
other accumulated snapshot history going back to the first push.

The most immediately actionable consequence is the API key exposure: any key committed
to the repo should be treated as compromised and rotated immediately.

---

## 7. Specific Concerns

### 7a — Export method: `defaults export` vs. raw plist copy

The 14 apps in the main export list use `defaults export "$bundle_id" "$output_file"`.
This reads from the macOS preferences daemon via the `defaults` command, not from
`~/Library/Preferences/<bundle>.plist` directly. The result is a clean UTF-8 XML
plist file. The export includes all keys the app has written to its defaults domain
(in-memory or on-disk). Binary-only keys are converted to XML representation where
possible; keys that cannot be represented in XML plist format may be omitted by the
`defaults` tool.

The practical implication: `defaults export` can produce a cleaner file than a raw
binary plist copy, but it captures the full defaults domain including keys the user
never directly set — internal app state, telemetry IDs, session state, and any
credentials the app stored via the macOS defaults system. There is no filtering.

### 7b — App-support files: verbatim copy, no filtering

The Loopback and SoundSource App Support files are copied with `cp` (lines 76-78).
These are verbatim copies of whatever files exist in `~/Library/Application Support/`.
Binary plist format is preserved. The files are NOT run through `defaults export` or
`plutil -convert xml1`. Any binary blobs, large data structures, or encoded content
within these plists is included as-is.

A Loopback `Devices.plist` for a professional audio setup can be large (10–100KB+)
and contains the full routing graph. Audio-routing names that embed DAW or plugin
vendor names are explicitly present in the file as human-readable strings.

### 7c — iTerm2 profile data

iTerm2 stores all profile data in its defaults domain. Each "profile" (called a
"Bookmark" internally) is a nested dictionary within the plist. A profile may contain:
- `Initial Text` (a command that runs on session start, e.g., `ssh user@hostname`)
- `Command` (custom shell command, possibly with hostnames or arguments)
- `Working Directory` (a filesystem path)
- `Triggers` (regex patterns and associated actions, often host-specific)
- `SSH Config` (if iTerm2's SSH integration is used — includes hostnames and config)

`defaults export com.googlecode.iterm2` captures all of this. For a user with multiple
server profiles, the exported plist is a nearly complete inventory of infrastructure
access points. Whether embedded credentials are present depends on how the user
configured iTerm2.

UNKNOWN-NEEDS-VERIFICATION: whether any profile contains a `Command` or `Initial Text`
that embeds a password, API key, or other reusable credential. Inspect locally with:
`defaults export com.googlecode.iterm2 /dev/stdout | grep -A2 -i 'Command\|Initial Text'`

### 7d — MacWhisper API key verification

MacWhisper stores its OpenAI API key (when cloud transcription is configured) in the
`com.goodsnooze.MacWhisper` defaults domain. The key may be under a key named
`openAIAPIKey`, `apiKey`, or similar — the exact key name varies across MacWhisper
versions. To verify locally before the next snapshot:

```bash
defaults read com.goodsnooze.MacWhisper 2>/dev/null | grep -i 'api\|key\|openai\|secret'
```

If any output appears containing a token-format string (sk-..., or a UUID-format key),
the next `make snapshot-prefs` will push it to GitHub.

### 7e — Raycast API key verification

Raycast stores extension configuration in its defaults domain. Extensions that connect
to external services (OpenAI, GitHub, Linear, Notion, Slack, etc.) store their
credentials under keys namespaced by extension ID. To verify locally:

```bash
defaults read com.raycast.macos 2>/dev/null \
  | grep -i 'apiKey\|api_key\|token\|secret\|password\|openai'
```

Any output containing a bearer token, `sk-` prefix string, or `ghp_` / `gho_` format
string is a live credential that will be exported. If Raycast is configured with AI
Commands or any third-party extension requiring credentials, this check MUST be run
before each snapshot push on a machine where those extensions are active.

### 7f — Password manager exclusion confirmed

Verified by reading `scripts/snapshot-prefs` top to bottom: no call to `defaults export`
or `snapshot_plist` with bundle IDs for Bitwarden (`com.bitwarden.desktop`), NordPass
(`com.nordvpn.NordPass`), or 1Password (`com.1password.1password`, `com.agilebits.onepassword7`).
These are correctly excluded. Their exported plists would contain vault encryption keys
or authentication tokens.

---

## 8. Verdict

The snapshot-prefs design is **conditionally safe** for a private repository and a user
who does not configure Raycast or MacWhisper with cloud service API keys. For that
specific user profile, the exported data is primarily UI preferences and semi-private
topology information with no reusable credentials. The git workflow (no force-push,
skip on no-change, SSH-only remote) is sound.

The design is **unsafe by default** in two respects. First, it performs no pre-push
privacy check — if the remote is public or becomes public, all historical snapshot data
is immediately exposed with no warning. Second, it exports the full defaults domain for
Raycast and MacWhisper without any key filtering, and these apps are known to store
live API keys in their defaults domains when configured for cloud services. A user who
adds Raycast's AI Commands extension and then runs `make snapshot-prefs` has pushed
their OpenAI API key to GitHub without any notification.

The highest-value near-term change would be a pre-push hook or a pre-export scan that
greps for common API key patterns in the to-be-exported plists and aborts with a
warning if any are found. Short of that, the user must manually verify Raycast and
MacWhisper defaults before each snapshot run — which is not documented anywhere in
the README or in the script itself.
