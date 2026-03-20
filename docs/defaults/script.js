// macOS defaults documentation and descriptions
const DEFAULT_DESCRIPTIONS = {
    // General UI / UX
    'NSGlobalDomain.AppleInterfaceStyle': {
        title: 'Dark Mode',
        description: 'Enables system-wide Dark Mode, affecting the menu bar, Dock, window frames, and most built-in apps. Introduced in macOS 10.14 Mojave (2018). The key accepts only the string "Dark" — there is no "Light" value. To revert to Light Mode you must delete the key entirely: defaults delete NSGlobalDomain AppleInterfaceStyle. A partial dark menu bar existed since Yosemite (10.10) but used a different mechanism.',
        category: 'Appearance'
    },
    'NSGlobalDomain.AppleShowScrollBars': {
        title: 'Always Show Scrollbars',
        description: 'Controls scrollbar visibility. "Always" keeps scrollbars permanently visible; "Automatic" lets macOS decide based on input device (trackpad = hidden, mouse = visible); "WhenScrolling" hides them until you scroll. Scrollbars were always visible before OS X 10.7 Lion, which ported the iOS overlay-scrollbar paradigm to the Mac. Setting "Always" overrides the automatic device-detection logic.',
        category: 'Interface'
    },
    'NSGlobalDomain.AppleShowAllExtensions': {
        title: 'Show All File Extensions',
        description: 'Forces Finder to display file extensions for all files, including types macOS normally hides (.jpg, .txt, .mov). Improves security by preventing files from disguising themselves with misleading names. Also a CIS Benchmark recommendation for macOS hardening (control 6.2). Individual files can still override this with a per-file "Hide extension" attribute.',
        category: 'Security'
    },
    'NSGlobalDomain.NSAutomaticWindowAnimationsEnabled': {
        title: 'Disable Window Open Animations',
        description: 'Disables the scale-up animation when windows first appear, making them open instantly. Introduced in OS X 10.7 Lion. Only affects apps launched after the setting is applied; running apps must be relaunched. Some animations in newer macOS are handled by the compositor and may not be affected.',
        category: 'Performance'
    },
    'NSGlobalDomain.NSWindowResizeTime': {
        title: 'Sheet (Dialog) Animation Duration',
        description: 'Despite its name, this key controls sheet animation speed — how quickly Save and Print dialogs roll down from a window\'s title bar. It does not affect general window resizing. The default is 0.2 seconds; 0.001 makes dialogs appear near-instantly. Robservatory.com measured a 47% time reduction for repeated Save dialog workflows. Many dotfiles misidentify this as a window-resize setting.',
        category: 'Performance'
    },
    'NSGlobalDomain.NSQuitAlwaysKeepsWindows': {
        title: 'Disable Window Restoration (Resume)',
        description: 'Disables Resume — the OS X 10.7 Lion feature that restores all windows from the previous session when an app relaunches. Resume was immediately controversial on release; "how do I disable Resume?" was among the most-searched Lion questions in 2011. Setting false is equivalent to checking "Close windows when quitting an app" in System Settings → Desktop & Dock, which Apple finally surfaced as a visible toggle in Ventura.',
        category: 'Performance'
    },
    'NSGlobalDomain.NSNavPanelExpandedStateForSaveMode': {
        title: 'Expanded Save Dialogs',
        description: 'Forces Save dialogs to open in expanded mode showing the full folder browser, rather than the simplified collapsed view Apple introduced in OS X 10.7 Lion (before which Save dialogs always showed the full hierarchy). Both this key and its "2" variant are required — the second covers additional Save panel contexts added for document-scoped saving.',
        category: 'Interface'
    },
    'NSGlobalDomain.NSNavPanelExpandedStateForSaveMode2': {
        title: 'Expanded Save Dialogs (Extended)',
        description: 'Companion to NSNavPanelExpandedStateForSaveMode. Covers additional document-saving contexts that use a separate code path. Set both keys together for consistent behavior across all apps.',
        category: 'Interface'
    },
    'NSGlobalDomain.PMPrintingExpandedStateForPrint': {
        title: 'Expanded Print Dialogs',
        description: 'Forces Print dialogs to open fully expanded, showing paper size, orientation, quality, and other options immediately. The simplified collapsed Print dialog arrived in OS X 10.7 Lion alongside the collapsed Save dialog and was equally unpopular. Both this key and the "2" variant should be set together.',
        category: 'Interface'
    },
    'NSGlobalDomain.PMPrintingExpandedStateForPrint2': {
        title: 'Expanded Print Dialogs (Extended)',
        description: 'Companion to PMPrintingExpandedStateForPrint. Covers additional print dialog contexts. Set both keys together for consistent behavior across all apps.',
        category: 'Interface'
    },
    'NSGlobalDomain.NSDocumentSaveNewDocumentsToCloud': {
        title: 'Default New Documents to Local Storage',
        description: 'Prevents iCloud-aware apps (TextEdit, Pages, Preview, Numbers, Keynote) from defaulting to iCloud Drive for new document saves. Apple introduced iCloud document storage in OS X Mountain Lion (10.8, 2012) and set it as the default save location — a decision that surprised many users who later found their documents "missing" (stored in iCloud, not locally). Setting false keeps local storage as the default while still allowing manual saves to iCloud.',
        category: 'File Management'
    },
    'NSGlobalDomain.QLPanelAnimationDuration': {
        title: 'Quick Look Animation Duration',
        description: 'Controls the Quick Look preview panel animation speed. Available since Quick Look debuted in Mac OS X 10.5 Leopard (2007). Setting 0 removes the animation — but only partially: since El Capitan (10.11) this key affects only the close (zoom-out) animation. The open (zoom-in) animation is unaffected. Community reports from 2016 confirmed this is intentional, not a bug.',
        category: 'Performance'
    },

    // Sound
    'NSGlobalDomain.com.apple.sound.beep.volume': {
        title: 'System Alert Volume',
        description: 'Sets the system alert beep volume to 0 (silent). This key controls only the alert audio channel — error sounds, notification chimes, volume-limit feedback — without affecting media playback in apps like Spotify or Safari. The alert channel is routed separately from the main output volume at the Core Audio mixer layer.',
        category: 'Audio'
    },
    'NSGlobalDomain.com.apple.sound.uiaudio.enabled': {
        title: 'UI Sound Effects',
        description: 'Disables interface sound effects: the drag-to-trash swoosh, empty trash rumble, and other UI interaction sounds. Corresponds to "Play user interface sound effects" in System Settings → Sound. Setting 0 is equivalent to unchecking that option.',
        category: 'Audio'
    },

    // Keyboard & input
    'NSGlobalDomain.KeyRepeat': {
        title: 'Key Repeat Rate',
        description: 'Sets the interval between repeated characters when a key is held, in units of ~16.7 ms. Value 2 = ~33 ms (very fast). The System Settings slider exposes a limited range, but defaults write can set values below the UI minimum — value 1 (~16.7 ms) is faster than anything achievable through System Settings. Requires logout/restart to take effect.',
        category: 'Keyboard'
    },
    'NSGlobalDomain.InitialKeyRepeat': {
        title: 'Key Repeat Delay',
        description: 'Sets the delay before key repeat begins when a key is held, in units of ~16.7 ms. Value 15 = ~250 ms, which is shorter than the System Settings UI minimum of 25 (~420 ms). Caution: do not set below 10 (~167 ms) — values that low risk accidental character repetition. Requires logout/restart to take effect.',
        category: 'Keyboard'
    },
    'NSGlobalDomain.ApplePressAndHoldEnabled': {
        title: 'Disable Accent Picker, Restore Key Repeat',
        description: 'Restores traditional key-repeat behavior by disabling the iOS-style accent character picker that appears when holding a key. This popup was introduced in OS X 10.7 Lion as a direct port of iOS keyboard behavior, replacing decades of key-repeat defaults. It was one of the first popular Lion customization tips (osxdaily.com covered it within days of Lion\'s July 2011 release). As of 2024, Apple still provides no System Settings toggle — defaults write or a third-party tool like TinkerTool remain the only options.',
        category: 'Keyboard'
    },
    'NSGlobalDomain.AppleKeyboardUIMode': {
        title: 'Full Keyboard Navigation',
        description: 'Enables full keyboard navigation so Tab moves focus to all UI controls — buttons, checkboxes, radio buttons — not just text fields and lists. Value 2 enables this; values 2 and 3 appear equivalent on modern macOS. The UI toggle is System Settings → Keyboard → "Keyboard navigation." The shortcut Control-F7 toggles this live without a settings change.',
        category: 'Keyboard'
    },
    'NSGlobalDomain.NSAutomaticCapitalizationEnabled': {
        title: 'Disable Auto-Capitalization',
        description: 'Disables automatic capitalization of the first word after a sentence-ending period. Part of the NSAutomatic* family of text-correction features ported from iOS keyboard intelligence to macOS. Corresponds to "Capitalize words automatically" in System Settings → Keyboard → Text Replacements.',
        category: 'Keyboard'
    },
    'NSGlobalDomain.NSAutomaticDashSubstitutionEnabled': {
        title: 'Disable Smart Dashes',
        description: 'Disables automatic replacement of -- with an en-dash (–) and --- with an em-dash (—). Particularly disruptive when writing shell commands, markdown, code comments, or any structured text where literal hyphens are meaningful.',
        category: 'Keyboard'
    },
    'NSGlobalDomain.NSAutomaticPeriodSubstitutionEnabled': {
        title: 'Disable Double-Space Period',
        description: 'Disables the double-space to period substitution ported from iOS: typing two spaces normally inserts a period and a space. Most desktop users find this unwanted, especially when writing code or structured prose where sentence spacing is intentional.',
        category: 'Keyboard'
    },
    'NSGlobalDomain.NSAutomaticQuoteSubstitutionEnabled': {
        title: 'Disable Smart Quotes',
        description: 'Disables smart quote substitution — replacement of straight apostrophes and quotation marks with typographically correct curly variants. Critical for developers: smart quotes silently break code, JSON, YAML, shell scripts, and configuration files when pasted from an app that substituted them.',
        category: 'Keyboard'
    },
    'NSGlobalDomain.NSAutomaticSpellingCorrectionEnabled': {
        title: 'Disable Autocorrect',
        description: 'Disables automatic on-the-fly spelling correction. Corresponds to "Correct spelling automatically" in System Settings → Keyboard → Text Replacements.',
        category: 'Keyboard'
    },

    // Dock
    'com.apple.dock.orientation': {
        title: 'Dock Position',
        description: 'Sets the Dock position on screen. Valid values: "left", "bottom" (default), "right". Requires killall Dock to take effect. On multi-display setups, the Dock appears on the display designated as primary in System Settings → Displays → Arrangement.',
        category: 'Dock'
    },
    'com.apple.dock.tilesize': {
        title: 'Dock Icon Size',
        description: 'Sets Dock icon size in pixels. Valid range is approximately 16–128; the System Settings slider default is around 36–48 depending on display resolution. Requires killall Dock.',
        category: 'Dock'
    },
    'com.apple.dock.mineffect': {
        title: 'Window Minimize Effect',
        description: 'Sets the window minimize animation. "genie" (default) uses the stretchy drain-into-Dock effect; "scale" shrinks the window in place. There is also a hidden third value "suck" — a vacuum-like animation that has existed since macOS 10.0 (reportedly even in pre-release builds) but has never appeared in System Preferences. The popular theory is Apple kept it hidden because of the name. All three values work on macOS 15.',
        category: 'Dock'
    },
    'com.apple.dock.minimize-to-application': {
        title: 'Minimize Windows into App Icon',
        description: 'Minimized windows shrink into the app\'s Dock icon rather than creating a separate thumbnail in the minimized-windows area of the Dock. Keeps the Dock clean and uncluttered when many windows are minimized.',
        category: 'Dock'
    },
    'com.apple.dock.no-bouncing': {
        title: 'Disable Dock Icon Bouncing',
        description: 'Disables both types of Dock icon bouncing: the launch bounce (when clicking an icon while an app loads) and the alert bounce (when an app wants your attention). In macOS 10.3 Panther these were two separate keys — launchanim controlled launch bouncing and had a UI checkbox in Dock preferences; no-bouncing controlled notification bouncing. Both remain independently settable today.',
        category: 'Dock'
    },
    'com.apple.dock.show-recents': {
        title: 'Hide Recent Apps in Dock',
        description: 'Hides the "Recent Applications" section — the area separated by a divider showing recently used apps not permanently pinned. This section was introduced in macOS 10.14 Mojave (2018) and is enabled by default. Power users with curated Dock layouts typically disable it.',
        category: 'Dock'
    },
    'com.apple.dock.autohide-delay': {
        title: 'Dock Auto-Hide Delay',
        description: 'Sets the delay before a hidden Dock reappears when the cursor approaches the screen edge. Default is ~0.5 seconds; 0 makes it appear immediately on hover. This setting only has visible effect if Dock auto-hide is enabled — auto-hide is not enabled by this script, but the preference will apply if you enable it later.',
        category: 'Dock'
    },
    // kept for compatibility — not in defaults.sh
    'com.apple.dock.autohide': { title: 'Auto-hide Dock', description: 'Automatically hides the Dock when not in use.', category: 'Dock' },
    'com.apple.dock.autohide-time-modifier': { title: 'Auto-hide Animation Speed', description: 'Controls the speed of the Dock hide/show animation.', category: 'Dock' },
    'com.apple.dock.show-process-indicators': { title: 'Show App Running Indicators', description: 'Controls whether dots appear under running apps in the Dock.', category: 'Dock' },
    'com.apple.dock.enable-spring-load-actions-on-all-items': { title: 'Spring Loading for Dock Items', description: 'Enables spring-loading for all Dock items.', category: 'Dock' },

    // Finder
    'com.apple.finder.DisableAllAnimations': {
        title: 'Disable Finder Animations',
        description: 'Disables Finder animations including Get Info window open/close, icon movement, and scroll overscroll bounce. One of the earliest macOS performance tips, documented since ~2007. Requires killall Finder. Some animations in newer macOS use compositor layers and may not be affected.',
        category: 'Finder'
    },
    // kept for compatibility — not in defaults.sh
    'com.apple.finder.AppleShowAllFiles': { title: 'Show Hidden Files', description: 'Forces Finder to display hidden files and folders.', category: 'Finder' },
    'com.apple.finder.ShowStatusBar': { title: 'Show Finder Status Bar', description: 'Displays a status bar at the bottom of Finder windows.', category: 'Finder' },
    'com.apple.finder.ShowPathbar': { title: 'Show Finder Path Bar', description: 'Displays a path bar at the bottom of Finder windows.', category: 'Finder' },
    'com.apple.finder._FXShowPosixPathInTitle': { title: 'Show Full Path in Title', description: 'Displays the full POSIX path in the Finder title bar.', category: 'Finder' },
    'com.apple.finder.FXDefaultSearchScope': { title: 'Default Search Scope', description: 'Sets the default scope for Finder searches.', category: 'Finder' },
    'com.apple.finder.FXEnableExtensionChangeWarning': { title: 'File Extension Change Warning', description: 'Controls whether Finder warns when changing a file extension.', category: 'Finder' },
    'com.apple.finder.WarnOnEmptyTrash': { title: 'Empty Trash Warning', description: 'Controls whether Finder asks for confirmation before emptying Trash.', category: 'Finder' },
    'com.apple.finder.FXPreferredViewStyle': { title: 'Default View Style', description: 'Sets the default view mode for new Finder windows.', category: 'Finder' },
    'com.apple.finder.NewWindowTarget': { title: 'New Window Default Location', description: 'Sets where new Finder windows open by default.', category: 'Finder' },
    'com.apple.finder.ShowExternalHardDrivesOnDesktop': { title: 'Show External Drives on Desktop', description: 'Controls whether external drives appear on the Desktop.', category: 'Desktop' },
    'com.apple.finder.ShowHardDrivesOnDesktop': { title: 'Show Internal Drives on Desktop', description: 'Controls whether internal drives appear on the Desktop.', category: 'Desktop' },
    'com.apple.finder.ShowMountedServersOnDesktop': { title: 'Show Network Drives on Desktop', description: 'Controls whether mounted network shares appear on the Desktop.', category: 'Desktop' },
    'com.apple.finder.ShowRemovableMediaOnDesktop': { title: 'Show Removable Media on Desktop', description: 'Controls whether removable media appear on the Desktop.', category: 'Desktop' },

    // Screenshots
    'com.apple.screencapture.disable-shadow': {
        title: 'Disable Screenshot Window Shadow',
        description: 'Removes the drop shadow added to window screenshots (Cmd+Shift+4 then Space). The shadow adds transparent padding around the image and was a celebrated feature of Mac screenshots since the Leopard era. Setting true produces clean PNG files without shadow padding. Only affects window-mode captures; region and full-screen captures never have shadows. Requires killall SystemUIServer.',
        category: 'Screenshots'
    },
    'com.apple.screencapture.show-thumbnail': {
        title: 'Disable Screenshot Thumbnail Preview',
        description: 'Hides the floating thumbnail preview that appears after taking a screenshot, introduced in macOS 10.14 Mojave. Known bug in macOS 15 Sequoia: multiple reports (including MacRumors forum threads specific to 15.3.2) confirm this setting spontaneously resets itself, sometimes multiple times per day. The preference may not persist reliably on Sequoia.',
        category: 'Screenshots'
    },
    'com.apple.screencapture.include-date': {
        title: 'Exclude Date from Screenshot Filenames',
        description: 'Controls whether the capture date and time appear in the screenshot filename. Default (true) produces names like "Screenshot 2025-03-20 at 13.27.20.png." Setting false produces "Screenshot.png" with deduplication numbering for subsequent captures. Requires killall SystemUIServer.',
        category: 'Screenshots'
    },
    'com.apple.screencapture.location': {
        title: 'Screenshot Save Location',
        description: 'Sets the default save location for all screenshots. Before macOS 10.14 Mojave, this was only changeable via defaults write — no UI option existed. Mojave finally added the location picker to the Shift-Cmd-5 screenshot toolbar. If the specified directory does not exist, screenshots may fail silently. Requires killall SystemUIServer.',
        category: 'Screenshots'
    },
    'com.apple.screencapture.type': { title: 'Screenshot File Format', description: 'Sets the default file format for screenshots (png, jpg, pdf, tiff).', category: 'Screenshots' },

    // Desktop Services
    'com.apple.desktopservices.DSDontWriteNetworkStores': {
        title: 'No .DS_Store Files on Network Volumes',
        description: 'Prevents Finder from creating .DS_Store and ._ (AppleDouble) sidecar files on network volumes (AFP, SMB, NFS, WebDAV). .DS_Store files store folder view preferences; on network shares they appear as clutter to non-macOS users and can slow SMB browsing. Apple has an official support article (HT208209) recommending this setting for enterprise SMB environments. Does not delete existing .DS_Store files retroactively.',
        category: 'File Management'
    },
    'com.apple.desktopservices.DSDontWriteUSBStores': {
        title: 'No .DS_Store Files on USB Volumes',
        description: 'Prevents .DS_Store and ._ (AppleDouble) sidecar files from being written to USB drives, SD cards, and other removable media. Eliminates the notorious cross-platform friction where USB drives inserted into Windows PCs show up littered with invisible macOS metadata files.',
        category: 'File Management'
    },

    // Disk images
    'com.apple.frameworks.diskimages.skip-verify': {
        title: 'Skip DMG Checksum Verification',
        description: 'Skips checksum verification when mounting disk image (.dmg) files. Likely ineffective since OS X 10.11.3 El Capitan — community reports indicate DiskImageMounter ignores these keys as of that release, though they write without error. DMG verification exists to detect corruption or tampering; skipping it for downloaded images in particular is a security trade-off.',
        category: 'Performance'
    },
    'com.apple.frameworks.diskimages.skip-verify-locked': {
        title: 'Skip Locked DMG Verification',
        description: 'Skips checksum verification for locked disk images. Like skip-verify, this key is likely non-functional since OS X 10.11.3 El Capitan.',
        category: 'Performance'
    },
    'com.apple.frameworks.diskimages.skip-verify-remote': {
        title: 'Skip Remote DMG Verification',
        description: 'Skips the "Verifying..." spinner for disk images downloaded from the internet — historically the most user-visible of the three verify keys. Like the others, likely non-functional since OS X 10.11.3 El Capitan.',
        category: 'Performance'
    },

    // Time Machine
    'com.apple.TimeMachine.DoNotOfferNewDisksForBackup': {
        title: 'Suppress Time Machine New Disk Prompt',
        description: 'Suppresses the "Do you want to use [disk] to back up with Time Machine?" dialog when a blank external drive is connected. Only prevents the prompt — does not disable Time Machine or affect existing backup destinations. Normally, clicking "Don\'t Use" writes an invisible .com.apple.timemachine.donotpresent marker file to that specific volume; this preference suppresses the prompt globally for all new disks.',
        category: 'System'
    },

    // Software Update & App Store
    'com.apple.SoftwareUpdate.AutomaticCheckEnabled': {
        title: 'Check for Updates Automatically',
        description: 'Enables background checking for macOS software updates. Corresponds to "Automatically keep my Mac up to date" in System Settings → General → Software Update.',
        category: 'Security'
    },
    'com.apple.SoftwareUpdate.AutomaticDownload': {
        title: 'Download Updates Automatically',
        description: 'Enables background downloading of available updates when found. Downloads proceed silently but installation is not automatic unless other installation keys (CriticalUpdateInstall, etc.) are also enabled.',
        category: 'Security'
    },
    'com.apple.SoftwareUpdate.ConfigDataInstall': {
        title: 'Install System Data Files Automatically',
        description: 'Enables automatic installation of Apple\'s security data files: XProtect malware signature database, MRT (Malware Removal Tool), and Gatekeeper compatibility data. These are security-critical and pushed silently by Apple. The CIS macOS benchmark specifically recommends leaving this enabled — disabling it means XProtect will not receive malware signature updates.',
        category: 'Security'
    },
    'com.apple.SoftwareUpdate.CriticalUpdateInstall': {
        title: 'Install Critical Security Updates Automatically',
        description: 'Enables automatic installation of critical security patches, including Apple\'s Rapid Security Responses (RSRs) introduced in macOS Ventura — streamlined security-only updates that can be deployed without a full OS update, typically within hours of a critical vulnerability disclosure.',
        category: 'Security'
    },
    'com.apple.commerce.AutoUpdate': {
        title: 'Auto-Update App Store Apps',
        description: 'Enables automatic updates for App Store apps. This key lives in com.apple.commerce (the App Store\'s purchase/commerce engine domain) rather than com.apple.SoftwareUpdate, reflecting the historically separate lineage of App Store and OS-level update pipelines.',
        category: 'System'
    },

    // Activity Monitor
    'com.apple.ActivityMonitor.IconType': {
        title: 'Activity Monitor Dock Icon Display',
        description: 'Sets what the Activity Monitor Dock icon shows while the app is running. Value 2 = network usage (mirrored line graphs). All options: 0 = standard icon (default), 2 = network usage, 3 = disk usage, 5 = CPU meter bar, 6 = CPU history graph. Most dotfiles use 5 (CPU meter) for at-a-glance load visibility; this script uses 2 (network).',
        category: 'System Monitoring'
    },
    'com.apple.ActivityMonitor.ShowCategory': {
        title: 'Activity Monitor Default Process Filter',
        description: 'Sets the default process filter. Value 100 = All Processes. Other values: 101 = My Processes, 102 = System Processes, 103 = Other Processes, 106 = Active Processes, 107 = Windowed Processes.',
        category: 'System Monitoring'
    },
    'com.apple.ActivityMonitor.SortColumn': {
        title: 'Activity Monitor Sort Column',
        description: 'Sets the default sort column. CPUUsage sorts by CPU consumption — most useful for spotting runaway processes at the top. Other valid values include CPUTime, PID, ProcessName, RealPrivateMemory, PhysicalMemory.',
        category: 'System Monitoring'
    },
    'com.apple.ActivityMonitor.SortDirection': {
        title: 'Activity Monitor Sort Direction',
        description: 'Sets the sort direction. 0 = descending (highest values first), 1 = ascending. Descending with CPUUsage puts the most CPU-hungry processes at the top — the most useful configuration for diagnosing slowdowns.',
        category: 'System Monitoring'
    },
    'com.apple.ActivityMonitor.UpdatePeriod': {
        title: 'Activity Monitor Refresh Rate',
        description: 'Sets Activity Monitor\'s data refresh interval in seconds. Value 1 = every second (most responsive), 2 = every 2 seconds, 5 = every 5 seconds (default). More frequent updates add a small amount of CPU overhead from the monitoring process itself.',
        category: 'System Monitoring'
    },

    // TextEdit
    'com.apple.TextEdit.RichText': {
        title: 'Default to Plain Text',
        description: 'Makes new TextEdit documents open as plain text (.txt) by default instead of rich text (.rtf). TextEdit\'s default RTF mode has confused many users who expected a plain text editor — pasting code into an RTF document silently corrupts formatting with invisible markup. One of the most commonly cited macOS developer setup tips; has existed as a preference since early Mac OS X.',
        category: 'Applications'
    },

    // Terminal
    'com.apple.Terminal.FocusFollowsMouse': {
        title: 'Terminal Focus Follows Mouse',
        description: 'Enables X11/Unix-style focus-follows-mouse for Terminal windows: any Terminal window under the cursor accepts keyboard input without needing to click to bring it forward. The window is not raised — focus shifts silently. Useful for multi-terminal workflows but can cause unexpected input if the cursor drifts over a Terminal window while typing elsewhere.',
        category: 'Terminal'
    },
    'com.apple.Terminal.SecureKeyboardEntry': {
        title: 'Secure Keyboard Entry',
        description: 'Prevents other processes — screen readers, accessibility tools, TextExpander, and potential keyloggers — from intercepting keystrokes typed into Terminal. This is a Level 1 recommendation in the CIS Apple macOS benchmarks (control 6.4.1 in the Ventura benchmark and equivalents in earlier versions). Trade-off: breaks TextExpander and similar keyboard-monitoring utilities in Terminal windows.',
        category: 'Terminal'
    },
    'com.apple.Terminal.ShowLineMarks': {
        title: 'Hide Terminal Line Marks',
        description: 'Disables the line mark gutter — small arrow indicators in Terminal\'s left margin marking the start of each shell prompt, intended to help navigate between command outputs. Setting false removes them for a cleaner appearance.',
        category: 'Terminal'
    },

    // Menu bar clock
    'com.apple.menuextra.clock.IsAnalog': {
        title: 'Digital Clock (not Analog)',
        description: 'Sets the menu bar clock to digital (false) or analog circular face (true). Important: since macOS Big Sur (11.0), changes to com.apple.menuextra.clock require killall ControlCenter to take effect — killall SystemUIServer no longer works for clock settings. Using the wrong process will have no visible effect.',
        category: 'Menu Bar'
    },
    'com.apple.menuextra.clock.ShowAMPM': {
        title: 'Show AM/PM Indicator',
        description: 'Shows the AM/PM designator in the menu bar clock for 12-hour time. Requires killall ControlCenter (not SystemUIServer) on Big Sur and later to take effect.',
        category: 'Menu Bar'
    },
    'com.apple.menuextra.clock.ShowDayOfWeek': {
        title: 'Show Day of Week',
        description: 'Shows the abbreviated day of the week (e.g., "Thu") in the menu bar clock. Requires killall ControlCenter (not SystemUIServer) on Big Sur and later.',
        category: 'Menu Bar'
    },
    'com.apple.menuextra.clock.ShowDate': {
        title: 'Show Date in Menu Bar Clock',
        description: 'Controls date display in the menu bar clock. Values: 0 = never show date, 1 = always show, 2 = show when space allows. Introduced in macOS 12.4 Monterey as a replacement for the older boolean ShowDayOfMonth key, which lacked the "when space allows" middle option. Dotfiles using ShowDayOfMonth are using its deprecated predecessor.',
        category: 'Menu Bar'
    },

    // kept for compatibility — not in defaults.sh
    'NSGlobalDomain.NSDisableAutomaticTermination': { title: 'Disable Automatic App Termination', description: 'Prevents macOS from automatically terminating background apps under memory pressure.', category: 'Performance' },
    'NSGlobalDomain.com.apple.sound.beep.feedback': { title: 'Beep Feedback Volume', description: 'Controls the volume of system beep feedback sounds.', category: 'Audio' },
    'com.apple.DiskUtility.DUDebugMenuEnabled': { title: 'Disk Utility Debug Menu', description: 'Enables the debug menu in Disk Utility.', category: 'System Tools' },
    'com.apple.DiskUtility.advanced-image-options': { title: 'Advanced Disk Image Options', description: 'Enables advanced disk image creation options in Disk Utility.', category: 'System Tools' },
    'com.apple.AddressBook.ABShowDebugMenu': { title: 'Address Book Debug Menu', description: 'Enables the debug menu in the Contacts app.', category: 'Applications' },
    'com.apple.LaunchServices.LSQuarantine': { title: 'Disable Download Quarantine', description: 'Prevents macOS from quarantining downloaded files.', category: 'Security' }
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
            
            // Collect comments
            if (line.startsWith('#') && !line.match(/^#+\s*$/)) {
                const comment = line.replace(/^#\s*/, '');
                if (comment && !comment.match(/^-+$/)) {
                    pendingComment = comment;
                }
                continue;
            }
            
            // Parse write_default commands
            if (line.startsWith('write_default ')) {
                const entry = this.parseWriteDefault(line, pendingComment);
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
    
    parseWriteDefault(line, comment) {
        // Remove any shell error handling
        const cleanLine = line.split('||')[0].split('&&')[0].trim();
        const parts = cleanLine.split(/\s+/);
        
        if (parts.length < 5 || parts[0] !== 'write_default') {
            return null;
        }
        
        const domain = parts[1];
        const key = parts[2];
        const type = parts[3];
        const value = parts.slice(4).join(' ').replace(/['"]/g, '');
        
        const domainKey = `${domain}.${key}`;
        const description = DEFAULT_DESCRIPTIONS[domainKey];
        
        return {
            domain,
            key,
            type,
            value,
            comment: comment || (description ? description.title : key),
            description: description ? description.description : this.generateGenericDescription(key, value, type),
            category: description ? description.category : 'System',
            command: `defaults write ${domain} ${key} -${type} ${this.formatValueForCommand(value, type)}`
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
                </div>
                
                <div class="default-entry__main">
                    <p class="default-entry__description">${entry.description}</p>
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