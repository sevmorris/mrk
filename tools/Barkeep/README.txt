IMPORTANT — Read Before First Launch
=====================================

macOS will block this app because it is not notarized with Apple.

After dragging Barkeep to Applications, open Terminal and run:

    xattr -cr /Applications/Barkeep.app

Without this step, macOS will refuse to open the app.


ABOUT
=====================================

Barkeep is a native macOS Homebrew package manager.

It reads and writes your Brewfile directly, preserving all comments,
sections, and formatting. Select a package to see its description,
version, dependencies, caveats, usage examples (via tldr), man page
excerpts, and more — all fetched on demand from Homebrew.

Packages with available updates are flagged in the list. Install,
uninstall, and upgrade directly from the app.

Barkeep is part of the mrk bootstrap system:
  https://github.com/sevmorris/mrk
