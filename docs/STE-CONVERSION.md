# Simplified Technical English conversion

## What this is, and what it is not

The mrk documentation prose is written to align with **ASD-STE100 Simplified Technical
English**. This is a **rules-based alignment**, done by hand against the published
writing rules and the project glossary below.

**This is not certified compliance.** No licensed ASD-STE100 checker and no licensed
STE dictionary were used. The approved-word decisions here come from the published rule
set and from the project glossary, not from the controlled dictionary. Treat this
document as a record of intent and of the choices made, not as a conformance claim.

Technical accuracy outranks style. Where an STE rewrite would have made an instruction
wrong, or would have dropped a safety caveat, the meaning was kept and the deviation is
recorded in "Deviations" below.

---

## Ruleset applied

| Rule | Applied as |
|---|---|
| Sentence length | 20 words or fewer in a procedure or instruction. 25 words or fewer in a description. |
| One idea per sentence | Enforced. Compound instructions were split. |
| One instruction per sentence | Enforced in every procedure. |
| Imperative in procedures | "Run the command", not "the command should be run". |
| Voice | Active only. |
| Tense | Simple present, past or future only. No perfect tense ("has installed"). No progressive tense ("is installing"). |
| Conditionals | Kept only where the condition is real. |
| One word, one meaning, one part of speech | See the glossary below. |
| Nominalisation | Not used outside the approved verb set. |
| Articles and structure words | Kept. Words were not dropped to shorten a sentence. |
| -ing forms | Avoided where ambiguous. Gerund headings rewritten. |
| Lists | A procedure of more than two steps uses a vertical numbered list, one instruction per step. |
| Warnings and Cautions | Placed **before** the content they apply to. They open with the hazard or the command. |
| Paragraph length | 6 sentences or fewer in a description. |

---

## Project glossary

### One word, one meaning

The left column is the chosen term. The right column lists the words it replaced. Each
concept has exactly one word across all the converted files.

| Chosen term | Replaces | Notes |
|---|---|---|
| delete | remove, clear, purge, erase, take out | `--prune` and "Prune mode" survive only as flag and UI literals |
| run | execute, invoke, call, launch (a command) | |
| start | open (an app or TUI), launch (a program), initiate | |
| show | display, print, present, surface | |
| check | verify, validate, confirm (a state) | "confirm" survives only for a user answering a prompt |
| change | modify, alter, edit (a system file) | "edit" survives for a human editing a source file |
| add | append, insert, register | |
| directory | folder | |
| stop | kill, halt, terminate, block (sleep) | |
| keep | retain, preserve | |
| find | locate, detect | |
| select | choose, pick | |
| use | utilize | |
| about | approximately | |
| enough | sufficient | |
| make sure | ensure | |
| help | facilitate | |
| absent | missing, not present | "✗ absent" in status output |
| more than once | idempotent | The property is described, not named |

### Technical Names — unrestricted nouns

Homebrew · Brewfile · formula · cask · dotfile · symlink · plist · defaults domain ·
zsh · oh-my-zsh · Xcode Command Line Tools · TUI · macOS · iCloud · SSH · PATH · Dock ·
Finder · Time Machine · System Events · Automation · Launchpad · Mission Control ·
Spaces · Force Touch · Taptic Engine · Notification Centre · Quick Look · Terminal ·
GitHub · GitHub Pages · git · gum · dockutil · shellcheck · API key · token

Product and script names are also Technical Names and appear verbatim: `mrk`,
`mrk-picker`, `mrk-menu`, `mrk-status`, `bf`, `maintain`, `snapshot`, `snapshot-prefs`,
`pull-prefs`, `sync`, `sync-login-items`, `nuke-mrk`, `audio-mode`, `zoom-mode`,
`Barkeep`, `Calibre`, `Raycast`, `MacWhisper`, and the rest of the managed app list.

### Technical Verbs — the approved domain set

These verbs are allowed in their technical sense, and are used consistently:

**symlink** · **commit** · **push** · **pull** · **clone** · **fetch** · **sync** ·
**install** · **uninstall** · **export** · **import** · **restore** · **rollback** ·
**scan** · **parse** · **build** · **pause** · **resume**

`pause` and `resume` were added to the published set because they are the actual domain
operations of `audio-mode` and `zoom-mode`, and no approved general word carries the
meaning without loss.

---

## Per-file scope and degree

| File | Degree | State |
|---|---|---|
| `docs/bin/mrk-usage.html` | Full STE on all prose. HTML structure and callout classes kept. | Done — commit `89fd1af` |
| `docs/manual.md` | Full STE. Procedures strict; descriptions STE-descriptive. | Done — commit `292485f` |
| `scripts/sync-login-items` | The doc-emitting template only. | Done — commit `292485f` |
| `docs/defaults/script.js` | Data reconcile + STE on the 18 newly authored entries. | Partial — commit `7f3d8de` |
| `README.md`, `docs/index.html` | Optional, low priority. | Not started |

### `docs/bin/mrk-usage.html`

All prose inside the existing HTML. Command syntax, flags, paths and key bindings are
unchanged — verified by diffing every `<pre><code>` block against the previous revision.
The only code-block changes are two corrected usage lines (`bf`, `mrk-picker`, both of
which had been inaccurate) and five new blocks for the five newly documented commands.

### `docs/manual.md`

Full conversion. Gerund headings became "How to ..." forms. Multi-instruction
troubleshooting cells became numbered steps.

### `scripts/sync-login-items` — generator

This script templates one line of `docs/manual.md`. Its `re.subn` pattern anchored on
the old wording, so an STE rewrite of that sentence alone would have made the next run
fail its drift guard and exit 1. The sentence, the template and the regex were changed
together, and the round trip was verified by driving the real script through a pty.

### `docs/defaults/script.js` — reconcile done, prose split outstanding

The reconcile is complete: 77 parsed keys, 77 descriptions, 0 keys without a
description, 0 orphans, and no command containing an unexpanded variable.

The 18 entries authored during the reconcile (2 Terminal keys, 16 trackpad keys) are
written in STE, with Background notes where there was historical material to keep. They
are the worked example of the intended split.

**The 59 pre-existing descriptions have not been converted.** Each one mixes functional
text with historical and editorial material in a single paragraph, so the split is a
per-entry authoring task rather than a mechanical pass. The rendering support for it is
already in place: an entry may carry a `background` field, which renders in a block
labelled "Background — not Simplified Technical English".

---

## Deviations

Every deliberate departure from the ruleset.

1. **Background notes are not STE, by design.** The historical, editorial and
   measurement material in `DEFAULT_DESCRIPTIONS` is kept verbatim in a `background`
   field and rendered in a visually distinct block with an explicit label. Converting it
   would destroy the voice that makes the reference worth reading.

2. **"Troubleshooting" is kept as a heading.** It is an -ing form, but it is an
   established section noun rather than a gerund phrase describing an action.

3. **Over-length sentences kept for accuracy.** A small number of cautions exceed 20
   words because splitting them would separate a hazard from its condition. Examples:
   the `sync-login-items` empty-read caution, which must state the failure, the reason
   and the fix together; and the secret-scan cautions in BIN-1 §2.7 and §2.20, which
   must state both non-interactive abort conditions.

4. **Key-binding and flag tables keep sentence fragments.** A table cell such as
   "Move up and down" has no subject. Adding one would make the tables unreadable
   without improving clarity.

5. **A prose comment inside one code block was reworded.** In BIN-1 §2.20 the comment
   `# prompts for message` became `# mrk-push asks for the message`. It is prose, not
   command syntax, and no command changed.

6. **`prune` survives as a literal.** The flags `--prune` / `-p`, the `bf` "Prune mode"
   label, and the git command `git fetch --prune` keep the word. The chosen verb for
   the act itself is "delete" everywhere in prose.

7. **`snapshot` is both a Technical Name and an action in one place.** The command is
   named `snapshot`. Where the act is described, the prose says "exports".

8. **British spelling "Centre" in one new entry.** `Notification Centre` follows the
   surrounding entries' existing style. The rest of the documentation uses US spelling.

---

## How to check this work

There is no licensed checker. These greps catch the mechanical rules across the
converted files:

```bash
grep -rniE '\b(utilize|approximately|initiate|sufficient|ensure|facilitate|execute|invoke)\b' docs/manual.md docs/bin/mrk-usage.html
grep -rniE '\b(has been|have been|had been|is being|are being)\b' docs/manual.md docs/bin/mrk-usage.html
grep -rnE '^#{1,3} .*\b[A-Za-z]+ing\b' docs/manual.md
```

All three are clean, except the "Troubleshooting" heading recorded as deviation 2.

Widening the first grep to all of `docs/` still reports hits. They come from the 59
unconverted descriptions in `docs/defaults/script.js` — for example "approximately
16–128" in the Dock icon-size entry. That is expected until the defaults-page prose
split is done, and it is a useful marker of what remains.

Sentence length, one-idea-per-sentence and voice need a human read.
