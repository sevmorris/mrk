# App Store Apps

These applications come from the Mac App Store. **mrk does not install them.** On a new
machine, sign in to App Store.app and install them by hand — the list below is the record of
which ones belong on this Mac, because the App Store's own Purchased list also holds
everything ever bought, installed or not.

Each name links to its App Store page.

| App | Notes |
|---|---|
| [Amphetamine](https://apps.apple.com/app/id937984704) | |
| [BetterSnapTool](https://apps.apple.com/app/id417375580) | `post-install` restores its preferences and registers its login item — run `make post-install` again after installing it |
| [Chrono Plus - Time Tracker](https://apps.apple.com/app/id946047238) | `post-install` registers its login item — same re-run applies |
| [Final Cut Pro](https://apps.apple.com/app/id424389933) | Large download |
| [Hush \| AI for Spoken Audio](https://apps.apple.com/app/id1664181766) | |
| [Keynote](https://apps.apple.com/app/id361285480) | Installed as `Keynote Creator Studio.app` |
| [Logic Pro](https://apps.apple.com/app/id634148309) | Large download; its sound library downloads separately, inside the app |
| [Numbers](https://apps.apple.com/app/id361304891) | Installed as `Numbers Creator Studio.app` |
| [Pages](https://apps.apple.com/app/id361309726) | Installed as `Pages Creator Studio.app` |
| [Parcel Classic](https://apps.apple.com/app/id639968404) | |
| [Pixelmator Pro](https://apps.apple.com/app/id1289583905) | |
| [Pure Paste](https://apps.apple.com/app/id1611378436) | |
| [Xcode](https://apps.apple.com/app/id497799835) | Large download; needed to build the app repositories in `~/Projects` |

## Why they are not in the Brewfile

They were listed as `mas` entries until 2026-09-11, and `mas` was removed because nothing in
mrk could use those entries:

- `brew bundle` installs a `mas` entry by running `mas install <id>`, and mas 7 requires root
  to install an app. `brew bundle` never runs as root, so every entry failed.
- `mas list`, which `brew bundle` reads to decide what is already installed, gets its answers
  from Spotlight. Spotlight indexing was off on the Mac this was written on, so `brew bundle
  check` reported all 22 as missing and a run would have downloaded every one again. (It is
  on here: the setting is not one mrk carries, and it did not survive the 2026-09-15
  migration.)
- `mrk-brew` therefore filtered the entries out of every run and printed a `sudo mas install`
  command instead. That command is what you would type anyway, which left mas as an
  installed formula, three pieces of special-case code, and no work it could do.

`ci-check` refuses a Brewfile that has a `mas` line, so a `brew bundle dump` cannot put them
back silently.

## Keeping this list current

Nothing checks it. When you install or stop using an App Store app, edit this file.

`post-install` restores preferences and login items only for applications that are installed
when it runs, so on a new machine install these first, then run `make post-install` again.

Until 2026-09-28 it also listed Blackmagic Disk Speed Test, Code of War Mobile Shooter,
Compressor, DM1 - The Drum Machine, Encrypto, Mactracker and Speedtest by Ookla. None of them
was installed after the 2026-09-15 migration, so they were taken off the list (audit 15, T-15).
They are still in the App Store's Purchased list if you want one back.

GarageBand and iMovie were removed from this Mac on 2026-10-01, and taken off the list the
same day. GarageBand's sounds were left in `/Library/Application Support/GarageBand` and
`/Library/Audio/Apple Loops`: Logic Pro reads the loops and the instrument library.
