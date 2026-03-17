// macOS defaults documentation and descriptions
const DEFAULT_DESCRIPTIONS = {
    // General UI/UX
    'NSGlobalDomain.AppleInterfaceStyle': {
        title: 'Dark Mode',
        description: 'Sets the system-wide appearance to Dark mode. This affects the menu bar, Dock, window frames, and most built-in apps. Dark mode reduces eye strain in low-light environments and provides a more immersive experience.',
        category: 'Appearance'
    },
    'NSGlobalDomain.AppleShowScrollBars': {
        title: 'Scrollbar Visibility',
        description: 'Controls when scrollbars are visible. "Always" shows scrollbars permanently, "WhenScrolling" shows them only during scrolling, and "Automatic" shows them only when needed. Permanent scrollbars improve accessibility and provide visual feedback about content length.',
        category: 'Interface'
    },
    'NSGlobalDomain.AppleShowAllExtensions': {
        title: 'Show All File Extensions',
        description: 'Forces Finder to display file extensions for all files, even those typically hidden (like .jpg, .txt). This improves security by making it harder for malicious files to masquerade as safe file types, and provides better file type awareness.',
        category: 'File Management'
    },
    'NSGlobalDomain.NSDocumentSaveNewDocumentsToCloud': {
        title: 'Disable iCloud Save by Default',
        description: 'Prevents apps from defaulting to iCloud when saving new documents. When disabled (false), the save dialog will default to local storage instead of iCloud Drive. Useful for maintaining local control over file storage.',
        category: 'File Management'
    },
    'NSGlobalDomain.NSNavPanelExpandedStateForSaveMode': {
        title: 'Expanded Save Panels',
        description: 'Controls whether save dialogs open in expanded view by default. When enabled, save dialogs show the full folder hierarchy and additional options immediately, rather than requiring users to click a disclosure triangle.',
        category: 'Interface'
    },
    'NSGlobalDomain.NSNavPanelExpandedStateForSaveMode2': {
        title: 'Expanded Save Panels (Extended)',
        description: 'Secondary setting for expanded save panels that ensures the expanded state is maintained across all save dialog types and applications.',
        category: 'Interface'
    },
    'NSGlobalDomain.PMPrintingExpandedStateForPrint': {
        title: 'Expanded Print Panels',
        description: 'Forces print dialogs to open in expanded view, showing all printing options immediately instead of requiring users to expand the dialog manually. Provides immediate access to paper size, orientation, quality settings, and other print options.',
        category: 'Printing'
    },
    'NSGlobalDomain.PMPrintingExpandedStateForPrint2': {
        title: 'Expanded Print Panels (Extended)',
        description: 'Secondary setting for expanded print panels that ensures the expanded state is maintained across all print dialog types and applications.',
        category: 'Printing'
    },
    'NSGlobalDomain.NSWindowResizeTime': {
        title: 'Window Resize Animation Duration',
        description: 'Sets the duration of window resize animations in seconds. A value of 0.001 makes resize animations nearly instantaneous, improving perceived system responsiveness. The default value is typically 0.2 seconds.',
        category: 'Performance'
    },
    'NSGlobalDomain.NSQuitAlwaysKeepsWindows': {
        title: 'Disable Window Restoration',
        description: 'When disabled (false), prevents apps from automatically restoring windows when relaunched. This provides a clean slate on each app launch and can improve startup performance, especially for apps with many windows.',
        category: 'Performance'
    },
    'NSGlobalDomain.NSAutomaticWindowAnimationsEnabled': {
        title: 'Window Animation',
        description: 'Controls whether windows animate when opening, closing, minimizing, and maximizing. Disabling (false) makes these operations instant, which can improve perceived performance and reduce visual distraction.',
        category: 'Performance'
    },
    'NSGlobalDomain.NSDisableAutomaticTermination': {
        title: 'Disable Automatic App Termination',
        description: 'Prevents macOS from automatically terminating apps when memory pressure is high. When enabled (true), apps will remain running even when not actively used, which can improve app launch times but may use more memory.',
        category: 'Performance'
    },
    
    // Sound
    'NSGlobalDomain.com.apple.sound.beep.feedback': {
        title: 'Beep Feedback Volume',
        description: 'Controls the volume level of system beep sounds. A value of 0 disables beep feedback entirely, while higher values increase the volume. The beep sound occurs during alerts, errors, and when reaching volume limits.',
        category: 'Audio'
    },
    'NSGlobalDomain.com.apple.sound.beep.volume': {
        title: 'System Beep Volume',
        description: 'Sets the volume level specifically for system alert beeps, separate from the main system volume. This allows fine-tuning of alert sounds without affecting media playback volume.',
        category: 'Audio'
    },
    'NSGlobalDomain.com.apple.sound.uiaudio.enabled': {
        title: 'UI Sound Effects',
        description: 'Controls whether interface sound effects are played. When disabled (false), actions like moving files to trash, connecting devices, and other UI interactions will not play sound effects.',
        category: 'Audio'
    },
    
    // Keyboard
    'NSGlobalDomain.ApplePressAndHoldEnabled': {
        title: 'Disable Press and Hold for Accents',
        description: 'When disabled (false), prevents the accent character picker from appearing when holding down keys. This allows key repeat to work normally, which is preferred by developers and power users who rely on key repeat for navigation.',
        category: 'Keyboard'
    },
    'NSGlobalDomain.KeyRepeat': {
        title: 'Key Repeat Rate',
        description: 'Sets how quickly characters repeat when a key is held down. Lower values mean faster repeat rates. A value of 1 is the fastest setting available in System Preferences, while this setting can go even lower for ultra-fast repeat.',
        category: 'Keyboard'
    },
    'NSGlobalDomain.InitialKeyRepeat': {
        title: 'Key Repeat Delay',
        description: 'Sets the delay before key repeat begins when a key is held down. Lower values mean shorter delays. A value of 10 is faster than the fastest System Preferences setting, reducing the time before repeat starts.',
        category: 'Keyboard'
    },
    'NSGlobalDomain.AppleKeyboardUIMode': {
        title: 'Full Keyboard Access',
        description: 'Enables full keyboard navigation for all controls. When set to 3, Tab and Shift-Tab can navigate to every button, checkbox, and control in dialogs and windows, not just text fields. Essential for accessibility and power user workflows.',
        category: 'Keyboard'
    },
    
    // Dock
    'com.apple.dock.tilesize': {
        title: 'Dock Icon Size',
        description: 'Sets the size of icons in the Dock in pixels. Smaller sizes (like 36 pixels) provide more space for apps while maintaining usability. The default size is typically 68 pixels.',
        category: 'Dock'
    },
    'com.apple.dock.autohide': {
        title: 'Auto-hide Dock',
        description: 'When enabled (true), the Dock automatically hides when not in use and reappears when the cursor moves to the Dock area. This maximizes available screen space, especially useful on smaller displays.',
        category: 'Dock'
    },
    'com.apple.dock.autohide-delay': {
        title: 'Auto-hide Delay',
        description: 'Sets the delay before the Dock hides when auto-hide is enabled. A value of 0 makes the Dock hide immediately when the cursor moves away, providing instant screen space reclamation.',
        category: 'Dock'
    },
    'com.apple.dock.autohide-time-modifier': {
        title: 'Auto-hide Animation Speed',
        description: 'Controls the speed of the Dock hide/show animation. A value of 0 makes the animation instant, while higher values slow down the animation. Fast animations reduce waiting time when accessing the Dock.',
        category: 'Dock'
    },
    'com.apple.dock.show-recents': {
        title: 'Show Recent Apps in Dock',
        description: 'Controls whether recently used applications appear in a separate section of the Dock. When disabled (false), only pinned applications are shown, providing a cleaner and more predictable Dock layout.',
        category: 'Dock'
    },
    'com.apple.dock.show-process-indicators': {
        title: 'Show App Running Indicators',
        description: 'Controls whether small dots appear under running applications in the Dock. When enabled (true), provides visual feedback about which apps are currently running versus just pinned to the Dock.',
        category: 'Dock'
    },
    'com.apple.dock.minimize-to-application': {
        title: 'Minimize Windows to App Icon',
        description: 'When enabled (true), minimized windows are minimized to their application icon in the Dock rather than creating separate window thumbnails. This keeps the Dock cleaner and more organized.',
        category: 'Dock'
    },
    'com.apple.dock.enable-spring-load-actions-on-all-items': {
        title: 'Spring Loading for All Dock Items',
        description: 'Enables spring-loading functionality for all items in the Dock. When dragging files, hovering over Dock items will open them or reveal their contents, making file operations more efficient.',
        category: 'Dock'
    },
    
    // Finder
    'com.apple.finder.AppleShowAllFiles': {
        title: 'Show Hidden Files',
        description: 'Forces Finder to display hidden files and folders (those beginning with a dot). This is essential for developers and system administrators who need to access configuration files, system folders, and other typically hidden items.',
        category: 'Finder'
    },
    'com.apple.finder.ShowStatusBar': {
        title: 'Show Finder Status Bar',
        description: 'Displays a status bar at the bottom of Finder windows showing information about the current folder, such as number of items, available space, and selection details. Provides useful context about folder contents.',
        category: 'Finder'
    },
    'com.apple.finder.ShowPathbar': {
        title: 'Show Finder Path Bar',
        description: 'Displays a path bar at the bottom of Finder windows showing the complete folder hierarchy from root to current location. Enables quick navigation to parent folders and provides context about current location.',
        category: 'Finder'
    },
    'com.apple.finder._FXShowPosixPathInTitle': {
        title: 'Show Full Path in Title',
        description: 'Displays the complete POSIX path (Unix-style path) in the Finder window title bar instead of just the folder name. Extremely useful for developers and users who work with deep folder hierarchies.',
        category: 'Finder'
    },
    'com.apple.finder.FXDefaultSearchScope': {
        title: 'Default Search Scope',
        description: 'Sets the default scope for Finder searches. "SCcf" restricts searches to the current folder, preventing slow system-wide searches when you only need to search within the current location.',
        category: 'Finder'
    },
    'com.apple.finder.FXEnableExtensionChangeWarning': {
        title: 'File Extension Change Warning',
        description: 'Controls whether Finder warns when changing a file extension. When disabled (false), prevents interruption when batch renaming files or changing extensions, while requiring more caution to avoid accidental changes.',
        category: 'Finder'
    },
    'com.apple.finder.WarnOnEmptyTrash': {
        title: 'Empty Trash Warning',
        description: 'Controls whether Finder displays a confirmation dialog when emptying the Trash. When disabled (false), Trash empties immediately without confirmation, speeding up the workflow but requiring more caution.',
        category: 'Finder'
    },
    'com.apple.finder.FXPreferredViewStyle': {
        title: 'Default View Style',
        description: 'Sets the default view mode for new Finder windows. "Nlsv" sets list view, which provides the most information density and is ideal for quickly scanning file details and sorting.',
        category: 'Finder'
    },
    'com.apple.finder.NewWindowTarget': {
        title: 'New Window Default Location',
        description: 'Sets where new Finder windows open by default. "PfHm" opens to the user home folder, providing immediate access to Documents, Desktop, and other personal folders.',
        category: 'Finder'
    },
    'com.apple.finder.DisableAllAnimations': {
        title: 'Disable Finder Animations',
        description: 'When enabled (true), disables various animations in Finder such as the Get Info window animation, spring-loading animations, and icon bounce effects. Improves performance and reduces visual distraction.',
        category: 'Finder'
    },
    
    // Desktop & Screen Saver
    'com.apple.finder.ShowExternalHardDrivesOnDesktop': {
        title: 'Show External Drives on Desktop',
        description: 'Controls whether external hard drives appear as icons on the Desktop when connected. When enabled (true), provides immediate visual feedback when drives are mounted and quick access for file operations.',
        category: 'Desktop'
    },
    'com.apple.finder.ShowHardDrivesOnDesktop': {
        title: 'Show Internal Drives on Desktop',
        description: 'Controls whether internal hard drives appear as icons on the Desktop. When enabled (true), provides quick access to the boot drive and any other internal storage devices.',
        category: 'Desktop'
    },
    'com.apple.finder.ShowMountedServersOnDesktop': {
        title: 'Show Network Drives on Desktop',
        description: 'Controls whether mounted network servers and shared folders appear as icons on the Desktop. When enabled (true), provides easy access to network resources and visual confirmation of network connections.',
        category: 'Desktop'
    },
    'com.apple.finder.ShowRemovableMediaOnDesktop': {
        title: 'Show Removable Media on Desktop',
        description: 'Controls whether removable media (CDs, DVDs, USB drives, SD cards) appear as icons on the Desktop when inserted. When enabled (true), provides immediate access to removable media contents.',
        category: 'Desktop'
    },
    
    // Screenshots
    'com.apple.screencapture.location': {
        title: 'Screenshot Save Location',
        description: 'Sets where screenshots are saved by default. By setting a specific folder, screenshots can be organized separately from the Desktop, reducing clutter and improving file organization.',
        category: 'Screenshots'
    },
    'com.apple.screencapture.type': {
        title: 'Screenshot File Format',
        description: 'Sets the default file format for screenshots. Options include PNG (lossless, larger files), JPG (compressed, smaller files), PDF, TIFF, or other formats. PNG is ideal for most use cases due to perfect quality and transparency support.',
        category: 'Screenshots'
    },
    'com.apple.screencapture.disable-shadow': {
        title: 'Disable Screenshot Shadows',
        description: 'When enabled (true), removes the drop shadow effect from window screenshots. This creates cleaner images for documentation and reduces file size, while maintaining the exact window content.',
        category: 'Screenshots'
    },
    
    // Activity Monitor
    'com.apple.ActivityMonitor.UpdatePeriod': {
        title: 'Activity Monitor Update Frequency',
        description: 'Sets how frequently Activity Monitor refreshes its data, in seconds. Lower values provide more real-time monitoring at the cost of slightly higher CPU usage from the monitoring itself.',
        category: 'System Monitoring'
    },
    'com.apple.ActivityMonitor.ShowCategory': {
        title: 'Activity Monitor Default View',
        description: 'Sets the default view in Activity Monitor. Different values show different process categories: All Processes, My Processes, System Processes, etc. "All Processes" provides the most comprehensive view.',
        category: 'System Monitoring'
    },
    
    // Disk Utility
    'com.apple.DiskUtility.DUDebugMenuEnabled': {
        title: 'Enable Disk Utility Debug Menu',
        description: 'Enables advanced debugging and developer options in Disk Utility. This reveals additional tools and information useful for disk diagnostics, repair operations, and low-level disk management.',
        category: 'System Tools'
    },
    'com.apple.DiskUtility.advanced-image-options': {
        title: 'Advanced Disk Image Options',
        description: 'Enables advanced options when creating disk images in Disk Utility, such as additional formats, compression levels, and encryption options not normally visible in the standard interface.',
        category: 'System Tools'
    },
    
    // Address Book
    'com.apple.AddressBook.ABShowDebugMenu': {
        title: 'Address Book Debug Menu',
        description: 'Enables a debug menu in the Contacts app (formerly Address Book) that provides access to additional diagnostic tools, import/export options, and development features.',
        category: 'Applications'
    },
    
    // Other
    'com.apple.LaunchServices.LSQuarantine': {
        title: 'Disable Quarantine for Downloaded Files',
        description: 'When disabled (false), prevents macOS from quarantining downloaded files, which eliminates the "Are you sure you want to open this file?" dialogs for downloaded applications. This improves workflow but reduces security protection.',
        category: 'Security'
    }
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
            'General UI / UX': 'Core user interface and user experience settings that affect the overall look, feel, and behavior of macOS.',
            'Sound': 'Audio feedback and sound effect settings for system events and user interface interactions.',
            'Keyboard': 'Keyboard behavior, repeat rates, and input method configurations for improved typing efficiency.',
            'Dock': 'Dock appearance, behavior, and functionality settings for application management and system navigation.',
            'Finder': 'File browser settings that control how files and folders are displayed and managed throughout the system.',
            'Desktop & Screen Saver': 'Desktop appearance and screen saver configuration options.',
            'Activity Monitor': 'System monitoring and performance tracking tool settings.',
            'Trackpad': 'Trackpad gesture and behavior settings for enhanced navigation and control.',
            'Screenshots': 'Screen capture settings including file format, location, and capture behavior.',
            'Other': 'Miscellaneous system settings and application-specific configurations.'
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
                            📋 Copy All Commands
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
                        📋 Copy
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