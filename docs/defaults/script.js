// macOS defaults documentation and descriptions
const DEFAULT_DESCRIPTIONS = {
    'NSGlobalDomain.ContextMenuGesture': {
        title: 'Secondary Click Gesture',
        description: 'Sets how a secondary click is made on a trackpad. 1 is a click in the bottom-right corner.',
        category: 'Input',
        why: 'This is the global half of the setting. The two trackpad domains carry TrackpadCornerSecondaryClick, and the corner click does not work unless both are set.',
        systemDefault: '0'
    },
    'com.apple.HIToolbox.AppleFnUsageType': {
        title: 'Globe Key Action',
        description: 'Sets what the globe key does. 0 is nothing, 1 changes the input source, 2 shows the emoji picker and 3 starts dictation.',
        why: 'Dictation is off on this Mac, so the key would otherwise open a feature that is disabled.',
        category: 'Keyboard',
        systemDefault: '1 (change input source)'
    },
    'com.apple.assistant.support.Dictation Enabled': {
        title: 'Dictation',
        description: 'Turns Dictation off. macOS then does not offer to transcribe speech into a text field, and it does not download the on-device speech model.',
        category: 'Keyboard',
        why: 'The prompt that appears when you press the globe key turns Dictation on with one click, which is how it came to be enabled here. The speech model is close to a gigabyte, and nothing on this Mac had used it since 2024.',
        systemDefault: 'false'
    },
    'com.apple.assistant.support.Siri Data Sharing Opt-In Status': {
        title: 'Siri Audio Sharing',
        description: 'Records the answer to "Improve Siri & Dictation". 0 means the question was never put, 1 opts in and 2 opts out.',
        category: 'Security',
        why: 'The value is an explicit answer rather than a default, so 2 is a decision and 0 is only an unanswered prompt.',
        systemDefault: '0 (not yet asked)'
    },
    'com.apple.speech.synthesis.general.prefs.SpokenUIUseSpeakingHotKeyFlag': {
        title: 'Speak Selection',
        description: 'Lets a shortcut key speak the text you have selected.',
        category: 'System',
        systemDefault: 'false'
    },
    'com.apple.Accessibility.SpeakThisEnabled': {
        title: 'Speak Selection (Accessibility)',
        description: 'The newer mirror of the Speak Selection switch, in the Accessibility domain. Set both, or the two panes disagree.',
        category: 'System',
        systemDefault: '0'
    },
    'com.apple.commerce.AutoUpdateRestartRequired': {
        title: 'Install Updates Needing Restart',
        description: 'Installs a macOS update that needs a restart, without asking first.',
        category: 'System',
        why: 'This pairs with AutoUpdate. Set only that one and the updates that matter most still wait for a manual run.',
        systemDefault: 'false'
    },
    'com.apple.Terminal.NewTabWorkingDirectoryBehavior': {
        title: 'New Tab Directory',
        description: 'Sets the directory a new Terminal tab opens in. 1 is the default working directory rather than the directory of the current tab.',
        category: 'Terminal',
        systemDefault: '2 (same directory)'
    },
    'com.apple.mail.AddressesIncludeNameOnPasteboard': {
        title: 'Copy Bare Email Address',
        description: 'Copies only the address when you copy a name from a message header. Mail otherwise copies the display name and the address together.',
        category: 'Applications',
        why: 'Pasting a name and an address into a terminal or a web form is almost never the intent.',
        systemDefault: 'true'
    },
    'com.apple.iCal.CalDefaultCalendar': {
        title: 'Default Calendar',
        description: 'Puts a new event in the calendar you last selected. The alternative value is the identifier of one specific calendar.',
        category: 'Applications',
        why: 'A calendar identifier is different on each machine, so the sentinel is the only value that travels.',
        systemDefault: 'The first calendar in the list'
    },
    'com.apple.dt.Xcode.IDESourceControlWarnUncommittedChangesDefaultsKey': {
        title: 'Xcode Uncommitted Changes Warning',
        description: 'Stops Xcode from warning before a source-control operation that touches uncommitted work.',
        category: 'Applications',
        systemDefault: 'true'
    },
    'NSGlobalDomain.AppleActionOnDoubleClick': {
        title: 'Double-Click Title Bar Action',
        description: 'A double-click on a window title bar minimises the window. The other accepted value is "Maximize", which zooms the window instead.',
        category: 'Interface',
        why: 'Zoom is already on the green button. Minimise is the action with no other one-step control.',
        systemDefault: 'Maximize'
    },
    'NSGlobalDomain.AppleHighlightColor': {
        title: 'Selection Highlight Colour',
        description: 'Sets the tint behind selected text and selected items. The value is three space-separated floats: red, green and blue, each from 0 to 1.',
        category: 'Appearance',
        systemDefault: 'Blue (0.698039 0.843137 1.000000)'
    },
    'NSGlobalDomain.NSTableViewDefaultSizeMode': {
        title: 'Sidebar Icon Size',
        description: 'Sets the icon size in the sidebar of Finder, Mail and System Settings. 1 is small, 2 is medium, 3 is large.',
        category: 'Interface',
        systemDefault: '2 (medium)'
    },
    'NSGlobalDomain.AppleEnableSwipeNavigateWithScrolls': {
        title: 'Swipe Between Pages',
        description: 'Turns off the two-finger horizontal swipe that moves back and forward through pages.',
        category: 'Input',
        why: 'A sideways scroll inside a wide table or a code view otherwise navigates away and discards the half-completed form.',
        systemDefault: 'true'
    },
    'NSGlobalDomain.com.apple.trackpad.forceClick': {
        title: 'Force Click',
        description: 'Turns off Force Click and its haptic feedback. A firm press then does nothing extra.',
        category: 'Input',
        systemDefault: 'true'
    },
    'NSGlobalDomain.com.apple.mouse.doubleClickThreshold': {
        title: 'Double-Click Speed',
        description: 'Sets the longest gap, in seconds, that still counts as a double-click. A larger number gives you more time between the two clicks.',
        category: 'Input',
        systemDefault: '0.5'
    },
    'NSGlobalDomain.com.apple.sound.beep.sound': {
        title: 'Alert Sound',
        description: 'Sets which system sound plays for an alert. The value is a full path to an audio file in /System/Library/Sounds.',
        category: 'Audio',
        systemDefault: '/System/Library/Sounds/Funk.aiff'
    },
    'NSGlobalDomain.WebAutomaticSpellingCorrectionEnabled': {
        title: 'Autocorrect in Web Views',
        description: 'Turns off automatic spelling correction inside WebKit text fields. This covers Safari and any app that shows web content.',
        category: 'Keyboard',
        why: 'This is a separate key from NSAutomaticSpellingCorrectionEnabled. Set only that one and Safari still corrects your typing.',
        systemDefault: 'true'
    },
    'com.apple.finder.ShowPathbar': {
        title: 'Finder Path Bar',
        description: 'Shows the path bar along the bottom of a Finder window. The bar gives the folder chain, and each part of it accepts a drop.',
        category: 'Finder',
        systemDefault: 'false'
    },
    'com.apple.finder.ShowStatusBar': {
        title: 'Finder Status Bar',
        description: 'Shows the status bar along the bottom of a Finder window. It reports the item count and the free space on the disk.',
        category: 'Finder',
        systemDefault: 'false'
    },
    'com.apple.finder._FXShowPosixPathInTitle': {
        title: 'POSIX Path in Title',
        description: 'Puts the full POSIX path of the current folder in the Finder window title, instead of the folder name alone.',
        category: 'Finder',
        why: 'The title is then something you can read a path out of and paste into a terminal.',
        systemDefault: 'false'
    },
    'com.apple.finder._FXSortFoldersFirst': {
        title: 'Folders First',
        description: 'Keeps folders above files when a Finder window sorts by name.',
        category: 'File Management',
        systemDefault: 'false'
    },
    'com.apple.finder.FXPreferredViewStyle': {
        title: 'Default Finder View',
        description: 'Sets the view a new Finder window opens in. "Nlsv" is list, "icnv" is icon, "clmv" is column and "glyv" is gallery.',
        category: 'Finder',
        systemDefault: 'icnv (icon view)'
    },
    'com.apple.finder.FXDefaultSearchScope': {
        title: 'Default Search Scope',
        description: 'Sets where a Finder search starts. "SCcf" searches the current folder, "SCev" searches the whole Mac and "SCsp" searches the previous scope.',
        category: 'Finder',
        why: 'A search that starts at the whole Mac returns thousands of results when you meant the folder in front of you.',
        systemDefault: 'SCev (This Mac)'
    },
    'com.apple.finder.FXEnableExtensionChangeWarning': {
        title: 'Extension Change Warning',
        description: 'Turns off the confirmation that appears when you change a file extension.',
        category: 'File Management',
        why: 'The dialog fires on every rename that touches the extension, which teaches you to dismiss it without reading.',
        systemDefault: 'true'
    },
    'com.apple.finder.WarnOnEmptyTrash': {
        title: 'Empty Trash Warning',
        description: 'Turns off the confirmation that appears when you empty the Trash.',
        category: 'File Management',
        systemDefault: 'true'
    },
    'com.apple.finder.NewWindowTarget': {
        title: 'New Finder Window Target',
        description: 'Sets the folder a new Finder window opens. "PfDe" is the Desktop, "PfHm" is the home folder and "PfAF" is Recents.',
        category: 'Finder',
        why: 'A target other than these three also needs NewWindowTargetPath, which holds an absolute path and does not move between machines.',
        systemDefault: 'PfAF (Recents)'
    },
    'com.apple.finder.ShowHardDrivesOnDesktop': {
        title: 'Hard Disks on Desktop',
        description: 'Shows the internal hard disks on the Desktop.',
        category: 'Finder',
        systemDefault: 'false'
    },
    'com.apple.finder.ShowMountedServersOnDesktop': {
        title: 'Servers on Desktop',
        description: 'Keeps connected network servers off the Desktop.',
        category: 'Finder',
        systemDefault: 'false'
    },
    'com.apple.finder.QuitMenuItem': {
        title: 'Quit Finder',
        description: 'Adds a Quit item to the Finder menu, so Cmd-Q closes Finder. Finder restarts when you next open a window.',
        category: 'Finder',
        systemDefault: 'false'
    },
    'com.apple.finder.FinderSpawnTab': {
        title: 'Open Folders in Windows',
        description: 'Opens a folder in a new window rather than a new tab.',
        category: 'Finder',
        systemDefault: 'true'
    },
    'com.apple.screencapture.showsClicks': {
        title: 'Show Clicks in Recordings',
        description: 'Draws a circle at each mouse click in a screen recording.',
        category: 'Screenshots',
        why: 'A recording of a workflow is hard to follow when the clicks are invisible.',
        systemDefault: 'false'
    },
    'com.apple.SoftwareUpdate.ScheduleFrequency': {
        title: 'Update Check Interval',
        description: 'Sets how many days pass between automatic checks for a software update. 1 checks every day.',
        category: 'System',
        systemDefault: '7'
    },
    'com.apple.menuextra.clock.FlashDateSeparators': {
        title: 'Flashing Time Separators',
        description: 'Flashes the colon between the hours and the minutes once a second.',
        category: 'Menu Bar',
        systemDefault: 'false'
    },
    'com.apple.AdLib.allowApplePersonalizedAdvertising': {
        title: 'Personalised Ads',
        description: 'Turns off personalised advertising in the App Store, Apple News and Stocks.',
        category: 'Security',
        systemDefault: 'true'
    },
    'com.apple.AdLib.forceLimitAdTracking': {
        title: 'Limit Ad Tracking',
        description: 'Stops Apple\'s advertising platform from using the advertising identifier to target you.',
        category: 'Security',
        systemDefault: 'false'
    },
    'com.apple.CrashReporter.DialogType': {
        title: 'Crash Reporter Dialog',
        description: 'Stops the crash reporter dialog from appearing. "none" hides it, "basic" shows it and "developer" adds the full report.',
        category: 'System',
        why: 'A background process that crashes should not put a dialog in front of you for a report you do not send.',
        systemDefault: 'basic'
    },
    'com.apple.WindowManager.EnableStandardClickToShowDesktop': {
        title: 'Click Wallpaper to Show Desktop',
        description: 'Stops a click on the wallpaper from hiding every window to reveal the Desktop.',
        category: 'Interface',
        why: 'macOS Sonoma turned this on by default. A stray click near the edge of the screen then clears the screen.',
        systemDefault: 'true'
    },
    'com.apple.WindowManager.AppWindowGroupingBehavior': {
        title: 'Stage Manager Grouping',
        description: 'Sets how Stage Manager groups windows. 1 shows one window at a time, 0 groups every window of an application.',
        category: 'Interface',
        systemDefault: '0 (group by application)'
    },
    'com.apple.dt.Xcode.IDEDisableGitSupportForNewProjects': {
        title: 'Xcode Git for New Projects',
        description: 'Stops Xcode from creating a git repository when you make a new project.',
        category: 'Applications',
        why: 'The repository layout is a per-project decision, and the new-project sheet is the wrong place to make it.',
        systemDefault: 'false'
    },
    'com.apple.dt.Xcode.IDEWorkspaceSuppressCleanBuildPrompt': {
        title: 'Xcode Clean Build Prompt',
        description: 'Stops Xcode from asking for confirmation before it cleans the build folder.',
        category: 'Applications',
        systemDefault: 'false'
    },
    'com.apple.AppleMultitouchTrackpad.ActuateDetents': {
        title: 'Silent Clicking',
        description: 'Turns off the haptic detent the trackpad fires on a click. The click still registers, without the tap you feel.',
        category: 'Input',
        systemDefault: '1 (haptic feedback on)'
    },
    // General UI / UX
    'NSGlobalDomain.AppleInterfaceStyle': {
        title: 'Dark Mode',
        description: 'Turns on Dark Mode for the whole system. It changes the menu bar, the Dock, the window frames and most built-in apps. The key accepts only the string "Dark". There is no "Light" value, so you delete the key to go back to Light Mode: defaults delete NSGlobalDomain AppleInterfaceStyle.',
        category: 'Appearance',
        preference: true,
        systemDefault: 'Key absent (Light Mode)',
        background: 'macOS 10.14 Mojave introduced Dark Mode in 2018. A partial dark menu bar existed from Yosemite (10.10), but it used a different mechanism.'
    },
    'NSGlobalDomain.AppleShowScrollBars': {
        title: 'Always Show Scrollbars',
        description: 'Sets when macOS shows the scrollbars. "Always" keeps them visible. "Automatic" lets macOS decide from the input device: hidden for a trackpad, visible for a mouse. "WhenScrolling" hides them until you scroll. "Always" overrides the automatic device detection.',
        category: 'Interface',
        why: 'Overlay scrollbars appear and disappear dynamically, shifting layout and moving click targets. Always-visible scrollbars provide a consistent, predictable interface.',
        systemDefault: '"Automatic"',
        background: 'Scrollbars were always visible before OS X 10.7 Lion, which ported the iOS overlay-scrollbar paradigm to the Mac.'
    },
    'NSGlobalDomain.AppleShowAllExtensions': {
        title: 'Show All File Extensions',
        description: 'Makes Finder show the file extension for every file. This includes the types that macOS hides by default, such as .jpg, .txt and .mov. A single file can still override this with its own "Hide extension" attribute.',
        category: 'Security',
        why: 'Hidden extensions can make malicious files appear harmless — a macOS app bundle named "invoice.pdf.app" displays as "invoice.pdf" with extensions hidden.',
        background: 'This setting is also CIS Benchmark control 6.2 for macOS hardening.'
    },
    'NSGlobalDomain.NSAutomaticWindowAnimationsEnabled': {
        title: 'Disable Window Open Animations',
        description: 'Turns off the scale-up animation that plays when a window first appears, so a window opens at once. It applies only to the apps that you start after you apply it. Start a running app again for the change to reach it. The compositor handles some animations in newer macOS, and this key does not change those.',
        category: 'Performance',
        why: 'Eliminates visual delay when rapidly switching or tiling windows.',
        background: 'OS X 10.7 Lion introduced this key.'
    },
    'NSGlobalDomain.NSWindowResizeTime': {
        title: 'Sheet (Dialog) Animation Duration',
        description: 'Sets the speed of the sheet animation, not the window resize speed that the key name suggests. A sheet is a dialog that rolls down from the title bar of a window, such as Save or Print. The default is 0.2 seconds. A value of 0.001 makes a dialog appear almost at once.',
        category: 'Performance',
        why: 'The default 0.2s delay is perceptible and compounds across dozens of daily Save/Print interactions.',
        systemDefault: '0.2',
        background: 'Despite its name, this key does not affect general window resizing, and many dotfiles misidentify it as a window-resize setting. Robservatory.com measured a 47% time reduction for repeated Save dialog workflows.'
    },
    'NSGlobalDomain.NSQuitAlwaysKeepsWindows': {
        title: 'Disable Window Restoration (Resume)',
        description: 'Turns off Resume. Resume restores all the windows from your last session when you start an app again. A value of false matches "Close windows when quitting an app" in System Settings → Desktop & Dock.',
        category: 'Performance',
        why: 'Stale windows from a previous session can cause confusion after crashes or updates — apps reopen to whatever state they were in, which is rarely useful.',
        systemDefault: 'true (window restoration enabled)',
        background: 'Resume arrived in OS X 10.7 Lion and was immediately controversial; "how do I disable Resume?" was among the most-searched Lion questions in 2011. Apple finally surfaced it as a visible toggle in Ventura.'
    },
    'NSGlobalDomain.NSNavPanelExpandedStateForSaveMode': {
        title: 'Expanded Save Dialogs',
        description: 'Makes a Save dialog open in expanded mode, which shows the full directory browser. Set this key together with its "2" variant. The second key covers the other Save panel contexts that document-scoped saving added.',
        category: 'Interface',
        why: 'The collapsed panel hides the destination path. Files frequently end up saved to the wrong location because the user accepted a default they couldn\'t see.',
        background: 'Apple introduced the simplified collapsed Save dialog in OS X 10.7 Lion. Before that, Save dialogs always showed the full hierarchy.'
    },
    'NSGlobalDomain.NSNavPanelExpandedStateForSaveMode2': {
        title: 'Expanded Save Dialogs (Extended)',
        description: 'Works with NSNavPanelExpandedStateForSaveMode. It covers the other document-saving contexts, which use a separate code path. Set both keys together, so all apps behave the same way.',
        category: 'Interface'
    },
    'NSGlobalDomain.PMPrintingExpandedStateForPrint': {
        title: 'Expanded Print Dialogs',
        description: 'Makes a Print dialog open fully expanded. The expanded dialog shows the paper size, the orientation, the quality and the other options at once. Set this key together with its "2" variant.',
        category: 'Interface',
        background: 'The simplified collapsed Print dialog arrived in OS X 10.7 Lion alongside the collapsed Save dialog, and was equally unpopular.'
    },
    'NSGlobalDomain.PMPrintingExpandedStateForPrint2': {
        title: 'Expanded Print Dialogs (Extended)',
        description: 'Works with PMPrintingExpandedStateForPrint. It covers the other print dialog contexts. Set both keys together, so all apps behave the same way.',
        category: 'Interface'
    },
    'NSGlobalDomain.NSDocumentSaveNewDocumentsToCloud': {
        title: 'Default New Documents to Local Storage',
        description: 'Stops the iCloud-aware apps from using iCloud Drive as the default location for a new document. These apps include TextEdit, Pages, Preview, Numbers and Keynote. A value of false keeps local storage as the default. You can still save to iCloud by hand.',
        category: 'File Management',
        why: 'Avoids accidental sync of sensitive or work-in-progress files to iCloud without explicit intent.',
        systemDefault: 'true (saves to iCloud by default)',
        background: 'Apple introduced iCloud document storage in OS X Mountain Lion (10.8, 2012) and set it as the default save location — a decision that surprised many users who later found their documents "missing" (stored in iCloud, not locally).'
    },
    'NSGlobalDomain.QLPanelAnimationDuration': {
        title: 'Quick Look Animation Duration',
        description: 'Sets the speed of the Quick Look panel animation. A value of 0 stops the animation, but only for the close (zoom-out) step. The open (zoom-in) animation does not change.',
        category: 'Performance',
        preference: true,
        background: 'Quick Look debuted in Mac OS X 10.5 Leopard (2007). The close-only behaviour dates from El Capitan (10.11); community reports from 2016 confirmed it is intentional, not a bug.'
    },

    // Sound
    'NSGlobalDomain.com.apple.sound.beep.volume': {
        title: 'System Alert Volume',
        description: 'Sets the system alert volume. A value of 0 makes the alert silent. The key changes only the alert audio channel: the error sounds, the notification chimes and the volume-limit feedback. It does not change media playback in an app such as Spotify or Safari. Core Audio routes the alert channel separately from the main output volume.',
        category: 'Audio',
        preference: true
    },
    'NSGlobalDomain.com.apple.sound.uiaudio.enabled': {
        title: 'UI Sound Effects',
        description: 'Turns off the interface sound effects. These include the drag-to-trash swoosh, the empty-trash rumble and the other interaction sounds. A value of 0 matches "Play user interface sound effects" turned off in System Settings → Sound.',
        category: 'Audio',
        preference: true
    },

    // Keyboard & input
    'NSGlobalDomain.KeyRepeat': {
        title: 'Key Repeat Rate',
        description: 'Sets the interval between repeated characters when you hold a key. The unit is about 16.7 ms, so a value of 2 gives about 33 ms. The System Settings slider covers a limited range, and defaults write accepts a value below that minimum. A value of 1 is faster than System Settings can set. Log out and log in again for the change to take effect.',
        category: 'Keyboard',
        preference: true,
        systemDefault: '6 (~100ms)'
    },
    'NSGlobalDomain.InitialKeyRepeat': {
        title: 'Key Repeat Delay',
        description: 'Do not set a value below 10, which is about 167 ms: a delay that short repeats characters by accident. This key sets the delay before key repeat starts when you hold a key. The unit is about 16.7 ms, so a value of 15 gives about 250 ms. That is shorter than the System Settings minimum of 25, which is about 420 ms. Log out and log in again for the change to take effect.',
        category: 'Keyboard',
        preference: true,
        systemDefault: '25 (~420ms)'
    },
    'NSGlobalDomain.ApplePressAndHoldEnabled': {
        title: 'Disable Accent Picker, Restore Key Repeat',
        description: 'Turns off the accent-character picker that appears when you hold a key, and restores the traditional key repeat. macOS gives no System Settings toggle for this key. Use defaults write, or a third-party tool such as TinkerTool.',
        category: 'Keyboard',
        why: 'The accent picker interrupts keyboard-driven navigation and editing. Holding j or k in a text editor should repeat the character, not open a popup.',
        systemDefault: 'true (accent picker enabled)',
        background: 'The popup arrived in OS X 10.7 Lion as a direct port of iOS keyboard behavior, replacing decades of key-repeat defaults. It was one of the first popular Lion customization tips — osxdaily.com covered it within days of Lion\'s July 2011 release — and as of 2024 Apple still provides no System Settings toggle.'
    },
    'NSGlobalDomain.AppleKeyboardUIMode': {
        title: 'Full Keyboard Navigation',
        description: 'Turns on full keyboard navigation, so Tab moves the focus to every control. This includes the buttons, the checkboxes and the radio buttons, not only the text fields and the lists. A value of 2 turns it on, and values 2 and 3 behave the same way on current macOS. The System Settings toggle is Keyboard → "Keyboard navigation". Press Control-F7 to toggle it without a settings change.',
        category: 'Keyboard',
        why: 'Allows Tab to cycle through all controls — buttons, radio buttons, checkboxes — without reaching for the mouse.',
        systemDefault: '0 (text fields and lists only)'
    },
    'NSGlobalDomain.NSAutomaticCapitalizationEnabled': {
        title: 'Disable Auto-Capitalization',
        description: 'Turns off the automatic capitalization of the first word after a period. It matches "Capitalize words automatically" turned off in System Settings → Keyboard → Text Replacements.',
        category: 'Keyboard',
        why: 'Breaks commands, code, and domain names entered in text fields outside terminals.',
        background: 'This key belongs to the NSAutomatic* family of text-correction features, ported from iOS keyboard intelligence to macOS.'
    },
    'NSGlobalDomain.NSAutomaticDashSubstitutionEnabled': {
        title: 'Disable Smart Dashes',
        description: 'Turns off the automatic dash substitution. macOS otherwise replaces two hyphens with an en dash (–), and three hyphens with an em dash (—).',
        category: 'Keyboard',
        why: 'Silently converts "--" to an em dash, breaking markdown, CLI flags, and code pasted into apps with smart dashes enabled.'
    },
    'NSGlobalDomain.NSAutomaticPeriodSubstitutionEnabled': {
        title: 'Disable Double-Space Period',
        description: 'Turns off the double-space substitution. macOS otherwise inserts a period and a space when you type two spaces.',
        category: 'Keyboard',
        why: 'Interferes with intentional double-spacing in code, indentation, and command entry.',
        background: 'The gesture is a port of the iOS keyboard behavior.'
    },
    'NSGlobalDomain.NSAutomaticQuoteSubstitutionEnabled': {
        title: 'Disable Smart Quotes',
        description: 'Turns off the smart-quote substitution. macOS otherwise replaces the straight apostrophes and quotation marks with curly typographic ones.',
        category: 'Keyboard',
        why: 'Curly quotes break shell scripts, JSON, code snippets, and command-line arguments. The substitution is invisible until something fails.'
    },
    'NSGlobalDomain.NSAutomaticSpellingCorrectionEnabled': {
        title: 'Disable Autocorrect',
        description: 'Turns off the automatic spelling correction. It matches "Correct spelling automatically" turned off in System Settings → Keyboard → Text Replacements.',
        category: 'Keyboard',
        why: 'Mangles technical terms, hostnames, variable names, and other domain-specific vocabulary that the system dictionary doesn\'t recognize.'
    },

    // Dock
    'com.apple.dock.orientation': {
        title: 'Dock Position',
        description: 'Sets the position of the Dock on the screen. The values are "left", "bottom" and "right". Run killall Dock for the change to take effect. With more than one display, the Dock appears on the display that System Settings → Displays → Arrangement makes primary.',
        category: 'Dock',
        preference: true,
        systemDefault: '"bottom"'
    },
    'com.apple.dock.tilesize': {
        title: 'Dock Icon Size',
        description: 'Sets the size of the Dock icons in pixels. The range is about 16 to 128. The System Settings slider starts near 36 to 48, which depends on the display resolution. Run killall Dock for the change to take effect.',
        category: 'Dock',
        preference: true,
        systemDefault: '~48px (varies by display resolution)'
    },
    'com.apple.dock.mineffect': {
        title: 'Window Minimize Effect',
        description: 'Sets the window minimize animation. "genie" uses the stretchy drain-into-Dock effect. "scale" shrinks the window in place. A third value, "suck", also works, but it never appears in System Settings.',
        category: 'Dock',
        preference: true,
        systemDefault: '"genie"',
        background: 'The "suck" value is a vacuum-like animation. It has existed since macOS 10.0, reportedly even in pre-release builds, but has never appeared in System Preferences; the popular theory is that Apple kept it hidden because of the name. All three values work on macOS 15.'
    },
    'com.apple.dock.minimize-to-application': {
        title: 'Minimize Windows into App Icon',
        description: 'Makes a minimized window shrink into the Dock icon of its app. The window does not become a separate thumbnail in the minimized-windows area of the Dock.',
        category: 'Dock',
        why: 'Minimized windows otherwise accumulate as separate thumbnails in the Dock, cluttering it. This keeps the Dock layout stable regardless of how many windows are minimized.',
        systemDefault: 'false (minimized windows appear as separate thumbnails)'
    },
    'com.apple.dock.no-bouncing': {
        title: 'Disable Dock Icon Bouncing',
        description: 'Turns off both kinds of Dock icon bounce. These are the launch bounce, which plays while an app starts, and the alert bounce, which plays when an app wants your attention.',
        category: 'Dock',
        why: 'Eliminates attention-hijacking animations during focused work. If an app needs attention, the notification will still appear — it just won\'t be accompanied by a bouncing icon.',
        systemDefault: 'false (bouncing enabled)',
        background: 'In macOS 10.3 Panther these were two separate keys: launchanim controlled the launch bounce and had a UI checkbox in Dock preferences, while no-bouncing controlled the notification bounce. Both remain independently settable today.'
    },
    'com.apple.dock.show-recents': {
        title: 'Hide Recent Apps in Dock',
        description: 'Hides the "Recent Applications" section of the Dock. A divider separates this section, and it shows the apps that you used recently but did not pin.',
        category: 'Dock',
        preference: true,
        systemDefault: 'true (recent apps shown)',
        background: 'macOS 10.14 Mojave introduced this section in 2018 and turns it on by default. Power users with curated Dock layouts typically disable it.'
    },
    'com.apple.dock.autohide-delay': {
        title: 'Dock Auto-Hide Delay',
        description: 'Sets the delay before a hidden Dock appears again when the cursor reaches the screen edge. The default is about 0.5 seconds, and a value of 0 shows the Dock at once. The delay is visible only when Dock auto-hide is on. This script does not turn auto-hide on, but the value applies if you turn it on later.',
        category: 'Dock',
        preference: true,
        systemDefault: '0.5 (seconds)'
    },
    // kept for compatibility — not in defaults.sh

    // Finder
    'com.apple.finder.DisableAllAnimations': {
        title: 'Disable Finder Animations',
        description: 'Turns off the Finder animations. These include the Get Info window, the icon movement and the scroll overscroll bounce. Run killall Finder for the change to take effect. Some animations in newer macOS use compositor layers, and this key does not change those.',
        category: 'Finder',
        why: 'Makes file operations feel instant. Each animation adds visible latency per action, which compounds across a day of file management.',
        background: 'This is one of the earliest macOS performance tips, documented since about 2007.'
    },
    // kept for compatibility — not in defaults.sh

    // Screenshots
    'com.apple.screencapture.disable-shadow': {
        title: 'Disable Screenshot Window Shadow',
        description: 'Turns off the drop shadow that macOS adds to a window screenshot, which you take with Cmd+Shift+4 and then Space. A value of true gives a clean PNG file with no shadow padding. The key changes the window captures only. A region capture and a full-screen capture never have a shadow. Run killall SystemUIServer for the change to take effect.',
        category: 'Screenshots',
        why: 'Shadows add invisible padding around the image canvas and visual noise in documentation, where a clean window edge is more useful than a soft drop shadow.',
        systemDefault: 'false (shadow enabled)',
        background: 'The shadow adds transparent padding around the image, and it was a celebrated feature of Mac screenshots from the Leopard era.'
    },
    'com.apple.screencapture.show-thumbnail': {
        title: 'Disable Screenshot Thumbnail Preview',
        description: 'On macOS 15 Sequoia this preference may not persist, because it can reset itself without warning. The key hides the floating thumbnail preview that appears after you take a screenshot.',
        category: 'Screenshots',
        why: 'The thumbnail overlays the screen for several seconds after each capture and delays access to the file path — it adds friction without adding information.',
        systemDefault: 'true (thumbnail shown)',
        background: 'macOS 10.14 Mojave introduced the thumbnail. Multiple reports, including MacRumors forum threads specific to 15.3.2, confirm the setting spontaneously resets itself on Sequoia, sometimes multiple times per day.'
    },
    'com.apple.screencapture.include-date': {
        title: 'Exclude Date from Screenshot Filenames',
        description: 'Sets whether the capture date and time appear in the screenshot filename. A value of true gives a name such as "Screenshot 2025-03-20 at 13.27.20.png". A value of false gives "Screenshot.png", and adds a number to each later capture. Run killall SystemUIServer for the change to take effect.',
        category: 'Screenshots',
        why: 'Predictable, date-free filenames are easier to reference in scripts, automation, and documentation without needing to know the exact capture time.',
        systemDefault: 'true (date included)'
    },
    'com.apple.screencapture.location': {
        title: 'Screenshot Save Location',
        description: 'Sets the default save location for every screenshot. Make sure that the directory exists: if it is absent, a screenshot can fail without a message. Run killall SystemUIServer for the change to take effect.',
        category: 'Screenshots',
        preference: true,
        background: 'Before macOS 10.14 Mojave you could change this only with defaults write, because no UI option existed. Mojave added the location picker to the Shift-Cmd-5 screenshot toolbar.'
    },

    // Desktop Services
    'com.apple.desktopservices.DSDontWriteNetworkStores': {
        title: 'No .DS_Store Files on Network Volumes',
        description: 'Stops Finder from creating .DS_Store and ._ (AppleDouble) sidecar files on a network volume. This covers AFP, SMB, NFS and WebDAV. A .DS_Store file stores the view preferences of a directory, and on a network share it can also slow SMB browsing. The key does not delete the .DS_Store files that already exist.',
        category: 'File Management',
        why: '.DS_Store files expose directory metadata and appear as visible clutter to Windows and Linux users on shared volumes.',
        background: 'Apple has an official support article (HT208209) recommending this setting for enterprise SMB environments.'
    },
    'com.apple.desktopservices.DSDontWriteUSBStores': {
        title: 'No .DS_Store Files on USB Volumes',
        description: 'Stops macOS from writing .DS_Store and ._ (AppleDouble) sidecar files to a USB drive, an SD card and other removable media.',
        category: 'File Management',
        why: 'Portable drives are frequently shared across OSes. .DS_Store files are invisible on macOS but show up as junk on Windows and Linux.'
    },

    // Disk images
    'com.apple.frameworks.diskimages.skip-verify': {
        title: 'Skip DMG Checksum Verification',
        description: 'Skips the checksum check when macOS mounts a disk image (.dmg) file. This key is probably not effective on current macOS: DiskImageMounter appears to ignore it, but it writes without an error. The checksum check finds corruption and tampering, so skipping it for a downloaded image is a security trade-off.',
        category: 'Performance',
        why: 'Verification is redundant when the source is trusted and skips multi-second delays on large installers. Note: likely a no-op since El Capitan.',
        background: 'Community reports indicate DiskImageMounter has ignored these keys since OS X 10.11.3 El Capitan, although they still write without an error.'
    },
    'com.apple.frameworks.diskimages.skip-verify-locked': {
        title: 'Skip Locked DMG Verification',
        description: 'Skips the checksum check for a locked disk image. Like skip-verify, this key is probably not effective on current macOS.',
        category: 'Performance'
    },
    'com.apple.frameworks.diskimages.skip-verify-remote': {
        title: 'Skip Remote DMG Verification',
        description: 'Skips the "Verifying..." spinner for a disk image that you downloaded from the internet. Like the other two verify keys, this key is probably not effective on current macOS.',
        category: 'Performance',
        background: 'Of the three verify keys, this one was historically the most visible to the user.'
    },

    // Time Machine
    'com.apple.TimeMachine.DoNotOfferNewDisksForBackup': {
        title: 'Suppress Time Machine New Disk Prompt',
        description: 'Stops the "Do you want to use [disk] to back up with Time Machine?" dialog that appears when you connect a blank external drive. The key hides the prompt only. It does not turn Time Machine off, and it does not change an existing backup destination. Clicking "Don\'t Use" normally writes an invisible .com.apple.timemachine.donotpresent marker file to that one volume. This key instead hides the prompt for every new disk.',
        category: 'System',
        why: 'Prevents Time Machine dialogs from interrupting when external drives are connected for other purposes — archiving, file transfers, etc.'
    },

    // Software Update & App Store
    'com.apple.SoftwareUpdate.AutomaticCheckEnabled': {
        title: 'Check for Updates Automatically',
        description: 'Turns on the background check for macOS software updates. It matches "Automatically keep my Mac up to date" in System Settings → General → Software Update.',
        category: 'Security',
        why: 'Security patches are applied automatically without waiting for manual intervention. The risk of an unpatched vulnerability outweighs the risk of an automatic update.'
    },
    'com.apple.SoftwareUpdate.AutomaticDownload': {
        title: 'Download Updates Automatically',
        description: 'Turns on the background download of an available update. The download is silent. macOS does not install the update unless you also turn on an installation key, such as CriticalUpdateInstall.',
        category: 'Security'
    },
    'com.apple.SoftwareUpdate.ConfigDataInstall': {
        title: 'Install System Data Files Automatically',
        description: 'Turns on the automatic installation of the Apple security data files. These are the XProtect malware signature database, the Malware Removal Tool (MRT) and the Gatekeeper compatibility data. Apple pushes them silently. If you turn this key off, XProtect gets no new malware signatures.',
        category: 'Security',
        background: 'The CIS macOS benchmark specifically recommends leaving this enabled.'
    },
    'com.apple.SoftwareUpdate.CriticalUpdateInstall': {
        title: 'Install Critical Security Updates Automatically',
        description: 'Turns on the automatic installation of the critical security patches. These include the Apple Rapid Security Responses (RSRs).',
        category: 'Security',
        background: 'Apple introduced Rapid Security Responses in macOS Ventura. They are streamlined security-only updates that can be deployed without a full OS update, typically within hours of a critical vulnerability disclosure.'
    },
    'com.apple.commerce.AutoUpdate': {
        title: 'Auto-Update App Store Apps',
        description: 'Turns on the automatic updates for the App Store apps.',
        category: 'System',
        background: 'This key lives in com.apple.commerce, the purchase and commerce engine domain of the App Store, rather than in com.apple.SoftwareUpdate. The split reflects the historically separate lineage of the App Store and the OS-level update pipelines.'
    },

    // Activity Monitor
    'com.apple.ActivityMonitor.IconType': {
        title: 'Activity Monitor Dock Icon Display',
        description: 'Sets what the Activity Monitor Dock icon shows while the app runs. The values are 0 for the standard icon, 2 for the network usage and 3 for the disk usage. Value 5 gives the CPU meter bar, and value 6 gives the CPU history graph. This script uses 2, which shows mirrored network line graphs.',
        category: 'System Monitoring',
        why: 'Makes system activity visible at a glance in the Dock without needing to switch windows.',
        systemDefault: '0 (standard app icon)',
        background: 'Most dotfiles use 5, the CPU meter, for at-a-glance load visibility.'
    },
    'com.apple.ActivityMonitor.ShowCategory': {
        title: 'Activity Monitor Default Process Filter',
        description: 'Sets the default process filter. Value 100 shows All Processes. The other values are 101 for My Processes, 102 for System Processes and 103 for Other Processes. Value 106 shows Active Processes, and value 107 shows Windowed Processes.',
        category: 'System Monitoring',
        why: 'The default "My Processes" view hides background and system processes that may be consuming significant resources.',
        systemDefault: '101 (My Processes only)'
    },
    'com.apple.ActivityMonitor.SortColumn': {
        title: 'Activity Monitor Sort Column',
        description: 'Sets the default sort column. CPUUsage sorts by CPU consumption, which puts a runaway process at the top. The other values include CPUTime, PID, ProcessName, RealPrivateMemory and PhysicalMemory.',
        category: 'System Monitoring',
        why: 'Surfaces the highest-load process immediately on open, without manually clicking a column header each time.'
    },
    'com.apple.ActivityMonitor.SortDirection': {
        title: 'Activity Monitor Sort Direction',
        description: 'Sets the sort direction. Value 0 sorts descending, which puts the highest values first, and value 1 sorts ascending. Value 0 with CPUUsage puts the most CPU-hungry processes at the top.',
        category: 'System Monitoring'
    },
    'com.apple.ActivityMonitor.UpdatePeriod': {
        title: 'Activity Monitor Refresh Rate',
        description: 'Sets the refresh interval of Activity Monitor in seconds. Value 1 refreshes every second and is the most responsive. Value 2 refreshes every 2 seconds, and value 5 every 5 seconds. A more frequent refresh adds a small amount of CPU overhead from the monitoring process.',
        category: 'System Monitoring',
        why: 'The 5s default misses short-lived CPU spikes. A runaway process can max out a core and settle down before the display refreshes.',
        systemDefault: '5 (seconds)'
    },

    // TextEdit
    'com.apple.TextEdit.RichText': {
        title: 'Default to Plain Text',
        description: 'Makes a new TextEdit document open as plain text (.txt) instead of rich text (.rtf).',
        category: 'Applications',
        why: 'RTF creates binary files that can\'t be read by other editors, diffed in git, or inspected as plain text. TextEdit is most useful as a scratch-pad for plain text.',
        systemDefault: '1 (Rich Text / RTF)',
        background: 'The default RTF mode has confused many users who expected a plain text editor — pasting code into an RTF document silently corrupts formatting with invisible markup. This is one of the most commonly cited macOS developer setup tips, and it has existed as a preference since early Mac OS X.'
    },

    // Terminal
    'com.apple.Terminal.FocusFollowsMouse': {
        title: 'Terminal Focus Follows Mouse',
        description: 'Take care with this key: if the cursor drifts over a Terminal window while you type elsewhere, that window takes the input. The key turns on X11-style focus-follows-mouse for Terminal. A Terminal window under the cursor accepts keyboard input without a click. macOS does not raise the window, so the focus moves silently.',
        category: 'Terminal',
        why: 'Avoids needing to click to focus a terminal window when working across multiple panes, reducing hand movement.',
        systemDefault: 'false (click to focus)'
    },
    'com.apple.Terminal.SecureKeyboardEntry': {
        title: 'Secure Keyboard Entry',
        description: 'Stops other processes from reading the keystrokes that you type into Terminal. These processes include the screen readers, the accessibility tools, TextExpander and a possible keylogger. The trade-off is that TextExpander and similar keyboard-monitoring utilities stop working in a Terminal window.',
        category: 'Terminal',
        why: 'Prevents other processes from intercepting keystrokes typed into Terminal — including passwords, private keys, and API tokens.',
        systemDefault: 'false (not secure)',
        background: 'This is a Level 1 recommendation in the CIS Apple macOS benchmarks — control 6.4.1 in the Ventura benchmark, with equivalents in earlier versions.'
    },
    'com.apple.Terminal.ShowLineMarks': {
        title: 'Hide Terminal Line Marks',
        description: 'Turns off the line mark gutter. The gutter shows a small arrow in the left margin of Terminal, at the start of each shell prompt. The arrows help you move between command outputs. A value of false hides them.',
        category: 'Terminal',
        preference: true,
        systemDefault: 'true (line marks shown)'
    },

    // Menu bar clock
    'com.apple.menuextra.clock.IsAnalog': {
        title: 'Digital Clock (not Analog)',
        description: 'Run killall ControlCenter for a clock change to take effect. killall SystemUIServer does not work for the clock keys, and the wrong process leaves no visible change. This key sets the menu bar clock to digital with false, or to an analog circular face with true.',
        category: 'Menu Bar',
        preference: true,
        background: 'The clock keys moved to ControlCenter in macOS Big Sur (11.0). Before that, killall SystemUIServer applied them.'
    },
    'com.apple.menuextra.clock.ShowAMPM': {
        title: 'Show AM/PM Indicator',
        description: 'Shows the AM/PM designator in the menu bar clock for 12-hour time. Run killall ControlCenter for the change to take effect, not killall SystemUIServer.',
        category: 'Menu Bar',
        preference: true
    },
    'com.apple.menuextra.clock.ShowDayOfWeek': {
        title: 'Show Day of Week',
        description: 'Shows the abbreviated day of the week, such as "Thu", in the menu bar clock. Run killall ControlCenter for the change to take effect, not killall SystemUIServer.',
        category: 'Menu Bar',
        preference: true
    },
    'com.apple.menuextra.clock.ShowDate': {
        title: 'Show Date in Menu Bar Clock',
        description: 'Sets when the menu bar clock shows the date. Value 0 never shows it, value 1 always shows it, and value 2 shows it when space allows. Run killall ControlCenter for the change to take effect, not killall SystemUIServer.',
        category: 'Menu Bar',
        preference: true,
        background: 'macOS 12.4 Monterey introduced this key to replace the older boolean ShowDayOfMonth key, which had no "when space allows" middle option. A dotfile that still sets ShowDayOfMonth uses the deprecated predecessor.'
    },

    // kept for compatibility — not in defaults.sh

    // Terminal.app — window profile
    'com.apple.Terminal.Default Window Settings': {
        title: 'Default Terminal Profile',
        description: 'Sets the profile that Terminal uses for a new window. "Pro" is a built-in profile with a dark background and light text. This key holds the profile name as a string, so the name must match a profile that Terminal has.',
        category: 'Interface',
        preference: true,
        systemDefault: '"Basic"',
        background: 'The key name contains spaces, which is unusual for a defaults key. Quote it on the command line, or the shell splits it into three arguments.'
    },
    'com.apple.Terminal.Startup Window Settings': {
        title: 'Startup Terminal Profile',
        description: 'Sets the profile that Terminal uses for the window it opens at startup. Set this key together with "Default Window Settings". If you set only one of the two, the first window does not match the windows that you open later.',
        category: 'Interface',
        preference: true,
        systemDefault: '"Basic"'
    },

    // Trackpad (opt-in: --with-trackpad)
    'com.apple.AppleMultitouchTrackpad.Clicking': {
        title: 'Disable Tap to Click',
        description: 'Turns off tap-to-click. You must press the trackpad until it clicks. A tap alone does nothing.',
        category: 'Input',
        preference: true,
        why: 'A resting finger can register a tap and move the cursor or select text by accident.',
        systemDefault: 'false on a desktop trackpad; true on many notebooks after Setup Assistant'
    },
    'com.apple.AppleMultitouchTrackpad.ForceSuppressed': {
        title: 'Suppress Force Click',
        description: 'Turns off Force Touch. A hard press no longer triggers a force click, and it no longer gives haptic feedback for that gesture.',
        category: 'Input',
        preference: true,
        why: 'A force click fires on a firm ordinary click and opens a lookup panel that interrupts the task.',
        systemDefault: 'false (Force Touch active)',
        background: 'Apple added Force Touch to the trackpad with the Retina MacBook in 2015. The trackpad does not move; a Taptic Engine simulates the click.'
    },
    'com.apple.AppleMultitouchTrackpad.TrackpadCornerSecondaryClick': {
        title: 'Secondary Click in the Bottom-Right Corner',
        description: 'Sets the secondary click to the bottom-right corner of the trackpad. Value 2 selects the bottom-right corner. Value 1 selects the bottom-left corner. Value 0 turns the corner click off.',
        category: 'Input',
        preference: true,
        systemDefault: '0 (corner click off; two-finger click instead)'
    },
    'com.apple.AppleMultitouchTrackpad.TrackpadPinch': {
        title: 'Disable Pinch to Zoom',
        description: 'Turns off the two-finger pinch that zooms in and out.',
        category: 'Input',
        preference: true,
        why: 'The pinch fires during ordinary two-finger scrolling and changes the zoom level without intent.',
        systemDefault: 'true (pinch to zoom on)'
    },
    'com.apple.AppleMultitouchTrackpad.TrackpadRightClick': {
        title: 'Disable Two-Finger Secondary Click',
        description: 'Turns off the two-finger secondary click. Use the bottom-right corner instead. See TrackpadCornerSecondaryClick.',
        category: 'Input',
        preference: true,
        systemDefault: 'true (two-finger secondary click on)'
    },
    'com.apple.AppleMultitouchTrackpad.TrackpadRotate': {
        title: 'Disable Rotate Gesture',
        description: 'Turns off the two-finger rotate gesture.',
        category: 'Input',
        preference: true,
        why: 'The rotate gesture can turn an image or a PDF page by accident during a two-finger scroll.',
        systemDefault: 'true (rotate on)'
    },
    'com.apple.AppleMultitouchTrackpad.TrackpadThreeFingerDrag': {
        title: 'Disable Three-Finger Drag',
        description: 'Turns off three-finger drag. You cannot move a window with three fingers.',
        category: 'Input',
        preference: true,
        systemDefault: 'false (three-finger drag off)',
        background: 'macOS Sierra moved this control out of the Trackpad pane and into Accessibility → Pointer Control → Trackpad Options. The defaults key still works.'
    },
    'com.apple.AppleMultitouchTrackpad.TrackpadThreeFingerTapGesture': {
        title: 'Disable Three-Finger Tap',
        description: 'Turns off the three-finger tap that looks up a word or shows data detectors. Value 0 turns the gesture off. Value 2 turns it on.',
        category: 'Input',
        preference: true,
        systemDefault: '2 (look up on)'
    },
    'com.apple.AppleMultitouchTrackpad.TrackpadTwoFingerDoubleTapGesture': {
        title: 'Disable Smart Zoom',
        description: 'Turns off the two-finger double tap that zooms into a page or an image.',
        category: 'Input',
        preference: true,
        systemDefault: '1 (smart zoom on)'
    },
    'com.apple.AppleMultitouchTrackpad.TrackpadTwoFingerFromRightEdgeSwipeGesture': {
        title: 'Disable Notification Centre Swipe',
        description: 'Turns off the two-finger swipe from the right edge that opens Notification Centre.',
        category: 'Input',
        preference: true,
        why: 'The gesture fires when you scroll near the right edge, and the panel covers the window.',
        systemDefault: '3 (swipe on)'
    },
    'com.apple.AppleMultitouchTrackpad.TrackpadThreeFingerHorizSwipeGesture': {
        title: 'Disable Three-Finger Horizontal Swipe',
        description: 'Turns off the three-finger horizontal swipe that moves between full-screen apps and Spaces.',
        category: 'Input',
        preference: true,
        systemDefault: '2 (swipe on)'
    },
    'com.apple.AppleMultitouchTrackpad.TrackpadThreeFingerVertSwipeGesture': {
        title: 'Disable Three-Finger Vertical Swipe',
        description: 'Turns off the three-finger vertical swipe that opens Mission Control and App Expose.',
        category: 'Input',
        preference: true,
        systemDefault: '2 (swipe on)'
    },
    'com.apple.AppleMultitouchTrackpad.TrackpadFourFingerHorizSwipeGesture': {
        title: 'Disable Four-Finger Horizontal Swipe',
        description: 'Turns off the four-finger horizontal swipe that moves between full-screen apps and Spaces.',
        category: 'Input',
        preference: true,
        systemDefault: '2 (swipe on)'
    },
    'com.apple.AppleMultitouchTrackpad.TrackpadFourFingerVertSwipeGesture': {
        title: 'Disable Four-Finger Vertical Swipe',
        description: 'Turns off the four-finger vertical swipe that opens Mission Control.',
        category: 'Input',
        preference: true,
        systemDefault: '2 (swipe on)'
    },
    'com.apple.AppleMultitouchTrackpad.TrackpadFourFingerPinchGesture': {
        title: 'Disable Four-Finger Pinch',
        description: 'Turns off the four-finger pinch that opens Launchpad, and the four-finger spread that shows the desktop.',
        category: 'Input',
        preference: true,
        systemDefault: '2 (pinch on)'
    },
    'com.apple.AppleMultitouchTrackpad.TrackpadFiveFingerPinchGesture': {
        title: 'Disable Five-Finger Pinch',
        description: 'Turns off the five-finger pinch that opens Launchpad.',
        category: 'Input',
        preference: true,
        systemDefault: '2 (pinch on)'
    },
};

class DefaultsDocGenerator {
    constructor() {
        this.sections = [];
        this.filteredSections = [];
        this.searchTerm = '';
        this.init();
    }
    
    init() {
        this.setupEventListeners();
        this.loadScript();
    }
    
    setupEventListeners() {
        const searchInput = document.getElementById('searchInput');
        const clearSearch = document.getElementById('clearSearch');
        const resetSearch = document.getElementById('resetSearch');
        const returnToTop = document.getElementById('returnToTop');
        
        searchInput.addEventListener('input', (e) => {
            this.handleSearch(e.target.value);
        });
        
        clearSearch.addEventListener('click', () => {
            searchInput.value = '';
            this.handleSearch('');
        });
        
        if (resetSearch) {
            resetSearch.addEventListener('click', () => {
                searchInput.value = '';
                this.handleSearch('');
            });
        }
        
        // Return to top functionality
        returnToTop.addEventListener('click', (e) => {
            e.preventDefault();
            const mainElement = document.getElementById('main');
            mainElement.scrollTo({
                top: 0,
                behavior: 'smooth'
            });
        });
        
        // Copy functionality
        document.addEventListener('click', (e) => {
            if (e.target.classList.contains('copy-button') || e.target.closest('.copy-button')) {
                this.handleCopy(e);
            }
        });
        
        // Smooth scrolling for TOC links
        document.addEventListener('click', (e) => {
            if (e.target.classList.contains('toc__link')) {
                e.preventDefault();
                const targetId = e.target.getAttribute('href').substring(1);
                const targetElement = document.getElementById(targetId);
                if (targetElement) {
                    const mainElement = document.getElementById('main');
                    const offsetTop = targetElement.offsetTop - 20; // Small offset
                    mainElement.scrollTo({
                        top: offsetTop,
                        behavior: 'smooth'
                    });
                }
            }
        });
    }
    
    async loadScript() {
        try {
            const response = await fetch('https://raw.githubusercontent.com/sevmorris/mrk/main/scripts/defaults.sh');
            const scriptContent = await response.text();
            this.parseScript(scriptContent);
        } catch (error) {
            console.error('Failed to load script:', error);
            // Fallback to demo data
            this.loadDemoData();
        }
    }
    
    parseScript(content) {
        const lines = content.split('\n');
        let currentSection = { name: 'General', entries: [], description: '' };
        let pendingComment = '';
        let sections = [];
        let domainLoop = null;
        
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            
            // Skip empty lines
            if (!line) continue;
            
            // Check for section banners (3-line format)
            if (this.isSectionBanner(lines, i)) {
                // Save current section if it has entries
                if (currentSection.entries.length > 0) {
                    sections.push(currentSection);
                }
                
                // Extract section name
                const sectionName = this.extractSectionName(lines, i + 1);
                currentSection = {
                    name: sectionName || 'Unnamed Section',
                    entries: [],
                    description: this.getSectionDescription(sectionName)
                };
                pendingComment = '';
                i += 2; // Skip the next 2 lines of the banner
                continue;
            }
            
            // Collect comments (skip Why: lines — those are sourced from DEFAULT_DESCRIPTIONS)
            if (line.startsWith('#') && !line.match(/^#+\s*$/)) {
                const comment = line.replace(/^#\s*/, '');
                if (comment && !comment.match(/^-+$/) && !comment.startsWith('Why:')) {
                    pendingComment = comment;
                }
                continue;
            }
            
            // Track `for domain in A B; do` so write_default "$domain" ... can be
            // resolved to a real domain instead of the literal string '$domain'.
            const loopMatch = line.match(/^for\s+domain\s+in\s+(.+?)\s*;\s*do\s*$/);
            if (loopMatch) {
                domainLoop = loopMatch[1].trim().split(/\s+/).filter(Boolean);
                continue;
            }
            if (line === 'done') {
                domainLoop = null;
                continue;
            }

            // Parse write_default commands
            if (line.startsWith('write_default ')) {
                const entry = this.parseWriteDefault(line, pendingComment, domainLoop);
                if (entry) {
                    currentSection.entries.push(entry);
                }
                pendingComment = '';
            }
        }
        
        // Add the last section
        if (currentSection.entries.length > 0) {
            sections.push(currentSection);
        }
        
        this.sections = sections;
        this.renderSections();
        this.updateNav();
    }
    
    isSectionBanner(lines, index) {
        if (index + 2 >= lines.length) return false;
        
        const line1 = lines[index].trim();
        const line2 = lines[index + 1].trim();
        const line3 = lines[index + 2].trim();
        
        return line1.match(/^#+/) && 
               line2.startsWith('#') && 
               line3.match(/^#+/);
    }
    
    extractSectionName(lines, index) {
        if (index >= lines.length) return null;
        
        const line = lines[index].trim();
        const match = line.match(/^#\s*(.+?)\s*#+?\s*$/);
        return match ? match[1].trim() : null;
    }
    
    getSectionDescription(sectionName) {
        const descriptions = {
            'General UI / UX': 'Core interface and experience settings that affect the overall look, feel, and behavior of macOS — animations, dialogs, scrollbars, text handling, and miscellaneous system-wide polish.',
            'Sound': 'Audio feedback settings for system events and UI interactions. The interface sound effects system dates to the classic Mac OS era; these defaults let you silence it globally without entering Sound preferences.',
            'Keyboard & input': 'Keyboard behavior, repeat rates, and automatic text substitution settings. macOS ships with conservative key-repeat defaults tuned for casual users — power users routinely crank InitialKeyRepeat and KeyRepeat to their minimums.',
            'Dock': 'Dock appearance, auto-hide behavior, and launch animation settings. The Dock was introduced in Mac OS X 10.0 as a replacement for the Launcher and Application Switcher; many of its animation defaults remain unchanged since 10.4 Tiger.',
            'Finder': 'Finder display and behavior settings. Finder has been the macOS file manager since System 1 (1984); the defaults domain com.apple.finder controls everything from icon sizes to whether the Quit menu item even appears.',
            'Screenshots': 'Screen capture output settings — format, save location, shadow, and thumbnail behavior. The built-in screenshot system was unified under com.apple.screencapture in macOS 10.14 Mojave when Screenshot.app replaced the older Grab utility.',
            'Desktop Services': 'Metadata file suppression settings for network shares and USB drives. .DS_Store files store Finder layout data per-folder; disabling them on external volumes prevents littering other operating systems with invisible macOS housekeeping files.',
            'Disk images': 'Disk image mount and verification settings. The skip-verify keys were added to speed up mounting of trusted disk images; note that some of these keys have had no effect since macOS 10.11.3 El Capitan due to Gatekeeper enforcement changes.',
            'Time Machine': 'Time Machine backup behavior settings. DoNotOfferNewDisksForBackup suppresses the recurring prompt to use every newly attached drive as a backup destination — useful on machines with many external drives.',
            'Software Update & App Store': 'Automatic update and app purchase settings across both the system software update mechanism and the Mac App Store. These keys control background download, auto-install, and critical update behavior independently.',
            'Activity Monitor': 'Activity Monitor display and update settings. The app is the modern successor to ProcessViewer and CPU Monitor, consolidated in OS X 10.9 Mavericks. These defaults control dock icon behavior and how frequently the display refreshes.',
            'TextEdit': 'TextEdit format and behavior settings. TextEdit has shipped with every version of Mac OS X; RichText defaults to 1 (RTF), which surprises developers who expect a plain-text editor — setting it to 0 makes TextEdit behave like a simple code-friendly notepad.',
            'Terminal.app': 'Terminal.app security and usability settings. Secure Keyboard Entry (enabled here) prevents other apps and processes from reading keystrokes while Terminal is focused — important when typing passwords in a terminal on a shared or untrusted machine.',
            'Menu bar clock': 'Menu bar clock format and display settings. The clock lives in com.apple.menuextra.clock and supports a rich custom format string. Changes require restarting ControlCenter (not the older SystemUIServer, which handled this prior to macOS 11 Big Sur).',
            'Trackpad (opt-in: --with-trackpad)': 'Trackpad gesture and sensitivity settings. This section is opt-in — it only runs when defaults.sh is invoked with the --with-trackpad flag — because trackpad preferences are highly personal and the system defaults are reasonable for most users.',
            'Finish up': 'Post-configuration cleanup — kills and restarts affected system processes so that all the changes applied above take effect immediately without requiring a logout or reboot.'
        };

        return descriptions[sectionName] || 'System configuration settings.';
    }
    
    // Split a shell argument list on whitespace, but keep a double-quoted run
    // together and drop its quotes. `write_default com.apple.Terminal
    // "Default Window Settings" string Pro` must yield 4 tokens, not 6.
    tokenizeShell(line) {
        const tokens = [];
        const re = /"([^"]*)"|(\S+)/g;
        let m;
        while ((m = re.exec(line)) !== null) {
            tokens.push(m[1] !== undefined ? m[1] : m[2]);
        }
        return tokens;
    }

    // Quote a domain or key for display only when the shell would need it.
    shellQuote(s) {
        return /[^A-Za-z0-9._-]/.test(s) ? `"${s}"` : s;
    }

    parseWriteDefault(line, comment, domainLoop) {
        // Remove any shell error handling
        const cleanLine = line.split('||')[0].split('&&')[0].trim();
        const parts = this.tokenizeShell(cleanLine);

        if (parts.length < 5 || parts[0] !== 'write_default') {
            return null;
        }

        // Inside `for domain in A B; do`, defaults.sh writes the same key to
        // every domain in the list. Use the first as canonical, and keep the
        // rest so the entry can show that the setting covers both.
        let domain = parts[1];
        let alsoDomains = [];
        if (domain === '$domain' && domainLoop && domainLoop.length) {
            domain = domainLoop[0];
            alsoDomains = domainLoop.slice(1);
        }

        const key = parts[2];
        const type = parts[3];
        const value = parts.slice(4).join(' ').replace(/['"]/g, '');

        const domainKey = `${domain}.${key}`;
        const description = DEFAULT_DESCRIPTIONS[domainKey];

        const dq = this.shellQuote(domain);
        const kq = this.shellQuote(key);

        return {
            domain,
            alsoDomains,
            key,
            type,
            value,
            comment: comment || (description ? description.title : key),
            description: description ? description.description : this.generateGenericDescription(key, value, type),
            background: description ? (description.background || null) : null,
            category: description ? description.category : 'System',
            why: description ? (description.why || null) : null,
            preference: description ? (description.preference || false) : false,
            systemDefault: description ? (description.systemDefault || null) : null,
            revertCommand: `defaults delete ${dq} ${kq}`,
            command: `defaults write ${dq} ${kq} -${type} ${this.formatValueForCommand(value, type)}`
        };
    }
    
    formatValueForCommand(value, type) {
        if (type === 'string') {
            return `"${value}"`;
        }
        return value;
    }
    
    generateGenericDescription(key, value, type) {
        return `Sets the ${key} preference to ${value}. This ${type} value controls system behavior.`;
    }
    
    loadDemoData() {
        // Demo data for testing
        this.sections = [
            {
                name: 'General UI / UX',
                description: 'Core user interface and user experience settings that affect the overall look, feel, and behavior of macOS.',
                entries: [
                    {
                        domain: 'NSGlobalDomain',
                        key: 'AppleInterfaceStyle',
                        type: 'string',
                        value: 'Dark',
                        comment: 'Dark mode',
                        description: 'Sets the system-wide appearance to Dark mode. This affects the menu bar, Dock, window frames, and most built-in apps.',
                        category: 'Appearance',
                        command: 'defaults write NSGlobalDomain AppleInterfaceStyle -string "Dark"'
                    }
                ]
            }
        ];
        this.renderSections();
        this.updateNav();
    }
    
    handleSearch(term) {
        this.searchTerm = term.toLowerCase();
        
        const searchInput = document.getElementById('searchInput');
        const clearSearch = document.getElementById('clearSearch');
        const searchStats = document.getElementById('searchStats');
        const content = document.getElementById('content');
        const noResults = document.getElementById('noResults');
        
        clearSearch.style.display = term ? 'block' : 'none';
        
        if (!term) {
            this.filteredSections = this.sections;
            this.renderSections();
            searchStats.textContent = '';
            noResults.style.display = 'none';
            return;
        }
        
        // Filter sections and entries
        this.filteredSections = this.sections.map(section => {
            const filteredEntries = section.entries.filter(entry => 
                entry.comment.toLowerCase().includes(this.searchTerm) ||
                entry.description.toLowerCase().includes(this.searchTerm) ||
                entry.key.toLowerCase().includes(this.searchTerm) ||
                entry.domain.toLowerCase().includes(this.searchTerm) ||
                entry.value.toLowerCase().includes(this.searchTerm)
            );
            
            if (filteredEntries.length > 0) {
                return { ...section, entries: filteredEntries };
            }
            return null;
        }).filter(Boolean);
        
        const totalResults = this.filteredSections.reduce((sum, section) => sum + section.entries.length, 0);
        
        if (totalResults === 0) {
            content.style.display = 'none';
            noResults.style.display = 'block';
            searchStats.textContent = 'No results found';
        } else {
            content.style.display = 'block';
            noResults.style.display = 'none';
            searchStats.textContent = `${totalResults} result${totalResults === 1 ? '' : 's'} found`;
            this.renderSections();
        }
    }
    
    renderSections() {
        const content = document.getElementById('content');
        const sectionsToRender = this.searchTerm ? this.filteredSections : this.sections;
        
        if (sectionsToRender.length === 0) {
            content.innerHTML = '<div class="loading">No sections found</div>';
            return;
        }
        
        content.innerHTML = sectionsToRender.map(section => this.renderSection(section)).join('');
    }
    
    renderSection(section) {
        const entriesHtml = section.entries.map(entry => this.renderEntry(entry)).join('');
        
        return `
            <section class="section" id="section-${this.slugify(section.name)}">
                <div class="section__header">
                    <h2 class="section__title">
                        ${section.name}
                        <span class="section__count">${section.entries.length}</span>
                    </h2>
                    ${section.description ? `<p class="section__description">${section.description}</p>` : ''}
                    <div class="section__actions">
                        <button class="button copy-section-button" data-section="${section.name}">
                            Copy All Commands
                        </button>
                    </div>
                </div>
                <div class="section__body">
                    ${entriesHtml}
                </div>
            </section>
        `;
    }
    
    renderEntry(entry) {
        const statusClass = this.getEntryStatusClass(entry);
        const statusIcon = this.getEntryStatusIcon(entry);
        
        return `
            <div class="default-entry">
                <div class="default-entry__header">
                    <h3 class="default-entry__title">
                        <div class="default-entry__status default-entry__status--${statusClass}">
                            ${statusIcon}
                        </div>
                        ${entry.comment}
                    </h3>
                    <code class="default-entry__domain-key">${entry.domain} ${entry.key}</code>
                    ${entry.alsoDomains && entry.alsoDomains.length ? `<div class="default-entry__also">mrk applies this to ${entry.alsoDomains.length + 1} domains: <code>${entry.domain}</code>, <code>${entry.alsoDomains.join('</code>, <code>')}</code></div>` : ''}
                </div>
                
                <div class="default-entry__main">
                    <p class="default-entry__description">${entry.description}</p>
                    ${entry.why ? `<div class="default-entry__why"><span class="why-label">Why this setting</span>${entry.why}</div>` : ''}
                    ${entry.preference ? `<div class="default-entry__preference"><span class="preference-label">Personal preference</span>This reflects a specific workflow and may not suit everyone. Review before applying.</div>` : ''}
                    ${entry.background ? `<div class="default-entry__background"><span class="background-label">Background — not Simplified Technical English</span>${entry.background}</div>` : ''}
                </div>
                
                <div class="default-entry__values">
                    <table class="values-table">
                        <tr>
                            <th>Property</th>
                            <th>Type</th>
                            <th>Current Value</th>
                            <th>Desired Value</th>
                        </tr>
                        <tr>
                            <td>${entry.key}</td>
                            <td>${entry.type}</td>
                            <td class="value--empty">Unknown</td>
                            <td>${entry.value}</td>
                        </tr>
                    </table>
                </div>
                
                <div class="default-entry__command">
                    <div class="command-display__label">Command</div>
                    <pre class="command-display__command">${entry.command}</pre>
                    <button class="copy-button" data-command="${this.escapeHtml(entry.command)}">
                        Copy
                    </button>
                </div>

                <div class="default-entry__revert">
                    <div class="revert-display__label">Revert to macOS default${entry.systemDefault ? ` <span class="revert-system-default">(default: ${entry.systemDefault})</span>` : ''}</div>
                    <pre class="revert-display__command">${entry.revertCommand}</pre>
                    <button class="copy-button copy-button--revert" data-command="${this.escapeHtml(entry.revertCommand)}">
                        Copy
                    </button>
                </div>
            </div>
        `;
    }
    
    getEntryStatusClass(entry) {
        // For now, return unknown since we can't read current values in a static site
        return 'unknown';
    }
    
    getEntryStatusIcon(entry) {
        return '?';
    }
    
    updateNav() {
        const nav = document.getElementById('tableOfContents');
        const sectionsToShow = this.searchTerm ? this.filteredSections : this.sections;
        
        if (sectionsToShow.length === 0) {
            nav.innerHTML = '<h2 class="toc__title">Contents</h2><div class="toc__loading">No sections available</div>';
            return;
        }
        
        const navHtml = `
            <h2 class="toc__title">Contents</h2>
            <ul class="toc__list">
                ${sectionsToShow.map((section, index) => `
                    <li class="toc__item">
                        <a href="#section-${this.slugify(section.name)}" class="toc__link">
                            ${index + 1}. ${section.name} (${section.entries.length})
                        </a>
                    </li>
                `).join('')}
            </ul>
        `;
        
        nav.innerHTML = navHtml;
    }
    
    handleCopy(event) {
        event.preventDefault();
        const button = event.target.closest('.copy-button');
        
        if (button.dataset.command) {
            // Copy individual command
            navigator.clipboard.writeText(button.dataset.command).then(() => {
                this.showCopyFeedback(button);
            });
        } else if (button.classList.contains('copy-section-button')) {
            // Copy all commands in section
            const sectionName = button.dataset.section;
            const section = this.sections.find(s => s.name === sectionName);
            if (section) {
                const commands = section.entries.map(entry => entry.command).join('\n');
                navigator.clipboard.writeText(commands).then(() => {
                    this.showCopyFeedback(button);
                });
            }
        }
    }
    
    showCopyFeedback(button) {
        const originalText = button.textContent;
        button.textContent = '✓ Copied!';
        button.classList.add('copy-button--copied');
        
        setTimeout(() => {
            button.textContent = originalText;
            button.classList.remove('copy-button--copied');
        }, 2000);
    }
    
    slugify(text) {
        return text.toLowerCase()
                  .replace(/[^a-z0-9]+/g, '-')
                  .replace(/^-|-$/g, '');
    }
    
    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML.replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    }
}

// Initialize when the page loads
document.addEventListener('DOMContentLoaded', () => {
    new DefaultsDocGenerator();
});