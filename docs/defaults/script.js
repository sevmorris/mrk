// MRK-1, the macOS defaults reference. The keys are config/defaults.tsv,
// their descriptions docs/defaults/descriptions.tsv, and the text under each
// section heading docs/defaults/sections.tsv; the keys that make defaults
// skips are config/defaults-skip.tsv. The page reads all four when it loads,
// and check-defaults-desc keeps them in step.

class DefaultsDocGenerator {
    constructor() {
        this.sections = [];
        this.filteredSections = [];
        this.searchTerm = '';
        this.descriptions = new Map();
        this.sectionDescriptions = new Map();
        this.skips = new Set();
        this.init();
    }
    
    init() {
        this.setupEventListeners();
        this.loadTable();
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
    
    // A file of the repository on main: config/defaults.tsv, which
    // defaults.sh reads, or docs/defaults/descriptions.tsv. Served from a
    // clone on localhost (python3 -m http.server, from the top of the
    // repository), the page reads that clone's copy instead, so a change to
    // either file can be seen before it is pushed. Both files always come
    // from the same place.
    repoFileUrl(path) {
        const local = ['localhost', '127.0.0.1', '[::1]'].includes(location.hostname);
        return local ? new URL('../../' + path, location.href).href
                     : 'https://raw.githubusercontent.com/sevmorris/mrk/main/' + path;
    }

    // fetch only rejects on a network failure, so without the status check
    // an HTTP error resolved normally and response.text() handed the parser
    // the error body. Parsing "404: Not Found" yields zero sections and zero
    // entries, so the page rendered completely blank — and the catch in
    // loadTable never fired, which meant loadDemoData(), the fallback that
    // exists for exactly this, could never run. raw.githubusercontent.com
    // rate-limits unauthenticated requests, so this is reachable in ordinary
    // use, not just if the repo moves.
    async fetchText(url) {
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`HTTP ${response.status} ${response.statusText} for ${url}`);
        }
        return response.text();
    }

    async loadTable() {
        // The descriptions load beside the table. Without them every key is
        // still shown, with a generic description, under a notice that says so.
        const descriptionsUrl = this.repoFileUrl('docs/defaults/descriptions.tsv');
        const descriptions = this.fetchText(descriptionsUrl).then(
            text => { this.parseDescriptions(text); return null; },
            error => error);
        const sections = this.fetchText(this.repoFileUrl('docs/defaults/sections.tsv')).then(
            text => { this.parseSections(text); return null; },
            error => error);
        const skips = this.fetchText(this.repoFileUrl('config/defaults-skip.tsv')).then(
            text => { this.parseSkips(text); return null; },
            error => error);
        try {
            const table = await this.fetchText(this.repoFileUrl('config/defaults.tsv'));
            const descriptionsError = await descriptions;
            const sectionsError = await sections;
            const skipsError = await skips;
            this.parseTable(table);
            if (descriptionsError) {
                console.error('Failed to load the descriptions:', descriptionsError);
                this.showLoadFailure('Could not load docs/defaults/descriptions.tsv from GitHub (' +
                    this.errorText(descriptionsError) + '). Each key below has a generic description ' +
                    'in place of its own. Reload to try again, or read the file in the repository.');
            }
            if (sectionsError) {
                console.error('Failed to load the section descriptions:', sectionsError);
                this.showLoadFailure('Could not load docs/defaults/sections.tsv from GitHub (' +
                    this.errorText(sectionsError) + '). The sections below have no description. ' +
                    'Reload to try again, or read the file in the repository.');
            }
            if (skipsError) {
                console.error('Failed to load the keys to skip:', skipsError);
                this.showLoadFailure('Could not load config/defaults-skip.tsv from GitHub (' +
                    this.errorText(skipsError) + '). A key that make defaults skips is not marked below. ' +
                    'Reload to try again, or read the file in the repository.');
            }
        } catch (error) {
            console.error('Failed to load the table:', error);
            // Say so. The demo set is one section and one entry standing in for
            // the whole table; rendered silently it looks like a real reference
            // that happens to be nearly empty, which is worse than an error.
            // Order matters: loadDemoData() ends in renderSections(), which
            // assigns content.innerHTML and would wipe a notice prepended before
            // it. Render first, then put the warning above the result.
            this.loadDemoData();
            this.showLoadFailure('Could not load config/defaults.tsv from GitHub (' + this.errorText(error) +
                '). The entries below are a small demo set, not the real reference. ' +
                'Reload to try again, or read config/defaults.tsv in the repository.');
        }
    }

    errorText(error) {
        return error && error.message ? error.message : 'unknown error';
    }

    showLoadFailure(message) {
        const content = document.getElementById('content');
        if (!content) return;
        const notice = document.createElement('div');
        notice.className = 'load-failure';
        notice.setAttribute('role', 'alert');
        notice.style.cssText = 'border:2px solid #b00;padding:1rem;margin:1rem 0;' +
                               'background:#fff4f4;color:#500;font-weight:600;';
        notice.textContent = message;
        content.prepend(notice);
    }

    // docs/defaults/descriptions.tsv has one description on each line:
    // domain, key, title, category, default, preference, description, why and
    // background, separated by tabs. A line that starts with # is a comment.
    // check-defaults-desc refuses a line in any other shape, so the page
    // passes over one.
    parseDescriptions(content) {
        this.descriptions = new Map();
        for (const line of content.split('\n')) {
            if (line.startsWith('#') || !line.trim()) continue;
            const fields = line.split('\t').map(f => this.unescapeField(f));
            if (fields.length !== 9 || fields.includes(null)) continue;
            const [domain, key, title, category, systemDefault, preference, description, why, background] = fields;
            this.descriptions.set(`${domain}\t${key}`, {
                title, category, systemDefault, description, why, background,
                preference: preference === 'true'
            });
        }
    }

    // docs/defaults/sections.tsv has one section on each line: the section,
    // as config/defaults.tsv names it, and its description, separated by a
    // tab. check-defaults-desc refuses a line in any other shape, so the page
    // passes over one.
    parseSections(content) {
        this.sectionDescriptions = new Map();
        for (const line of content.split('\n')) {
            if (line.startsWith('#') || !line.trim()) continue;
            const fields = line.split('\t').map(f => this.unescapeField(f));
            if (fields.length !== 2 || fields.includes(null)) continue;
            this.sectionDescriptions.set(fields[0], fields[1]);
        }
    }

    // config/defaults-skip.tsv has one key on each line: the domain and the
    // key, separated by a tab. defaults.sh does not write these keys.
    // defaults.sh and check-defaults-desc refuse a line in any other shape, so
    // the page passes over one.
    parseSkips(content) {
        this.skips = new Set();
        for (const line of content.split('\n')) {
            if (line.startsWith('#') || !line.trim()) continue;
            const fields = line.split('\t').map(f => this.unescapeField(f));
            if (fields.length !== 2 || fields.includes(null)) continue;
            this.skips.add(`${fields[0]}\t${fields[1]}`);
        }
    }

    // A field of config/defaults.tsv or descriptions.tsv as text: \t is a
    // tab, \n a newline and \\ a backslash. null for a backslash before
    // anything else.
    unescapeField(field) {
        let bad = false;
        const text = field.replace(/\\(.?)/g, (m, c) => {
            if (c === 't') return '\t';
            if (c === 'n') return '\n';
            if (c === '\\') return '\\';
            bad = true;
            return m;
        });
        return bad ? null : text;
    }

    // config/defaults.tsv has one key on each line: domain, key, type, value,
    // when and section, separated by tabs. A line that starts with # is a
    // comment. The sections keep the order in which they first appear, and
    // the entries the order of the file. The same key, type and value in two
    // domains of one section is one setting: the entry of the first domain,
    // with the others as alsoDomains. check-defaults-desc counts it the same
    // way, and wants a description for the first domain only.
    parseTable(content) {
        const sections = new Map();

        for (const line of content.split('\n')) {
            if (line.startsWith('#') || !line.trim()) continue;
            const fields = line.split('\t').map(f => this.unescapeField(f));
            if (fields.length !== 6 || fields.includes(null)) continue;
            const [domain, key, type, tableValue, when, name] = fields;
            // A string that starts with ~/ is a path in the home directory.
            // $HOME, not ~, because the command puts the value in quotes.
            const value = type === 'string' && tableValue.startsWith('~/')
                ? '$HOME/' + tableValue.slice(2) : tableValue;

            if (!sections.has(name)) sections.set(name, { name, entries: [], when: new Set() });
            const section = sections.get(name);
            section.when.add(when);

            const first = section.entries.find(e => e.key === key && e.type === type && e.value === value);
            if (first) {
                first.alsoDomains.push(domain);
            } else {
                section.entries.push(this.makeEntry(domain, key, type, value));
            }
        }

        // A section that only --with-trackpad writes says so in its name. Its
        // description is under the name config/defaults.tsv gives it.
        this.sections = [...sections.values()].map(({ name, entries, when }) => {
            const shown = when.size === 1 && when.has('trackpad') ? `${name} (opt-in: --with-trackpad)` : name;
            return { name: shown, entries, description: this.sectionDescriptions.get(name) || null };
        });
        this.renderSections();
        this.updateNav();
    }

    // Quote a domain or key for display only when the shell would need it.
    shellQuote(s) {
        return /[^A-Za-z0-9._-]/.test(s) ? `"${s}"` : s;
    }

    makeEntry(domain, key, type, value) {
        const description = this.descriptions.get(`${domain}\t${key}`);
        const dq = this.shellQuote(domain);
        const kq = this.shellQuote(key);

        return {
            domain,
            alsoDomains: [],
            key,
            type,
            value,
            comment: description ? description.title : key,
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
                    ${section.description ? `<p class="section__description">${this.escapeHtml(section.description)}</p>` : ''}
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
    
    // A note for an entry whose key config/defaults-skip.tsv lists, in one
    // of its domains or all of them. Empty for any other entry.
    skippedNote(entry) {
        const domains = [entry.domain, ...(entry.alsoDomains || [])];
        const skipped = domains.filter(d => this.skips.has(`${d}\t${entry.key}`));
        if (!skipped.length) return '';
        const where = skipped.length === domains.length ? ''
            : ` in <code>${skipped.join('</code>, <code>')}</code>`;
        return `<div class="default-entry__skipped"><span class="skipped-label">Skipped</span>` +
            `config/defaults-skip.tsv lists this key${where}, so make defaults does not write it.</div>`;
    }

    renderEntry(entry) {
        return `
            <div class="default-entry">
                <div class="default-entry__header">
                    <h3 class="default-entry__title">
                        ${entry.comment}
                    </h3>
                    <code class="default-entry__domain-key">${entry.domain} ${entry.key}</code>
                    ${entry.alsoDomains && entry.alsoDomains.length ? `<div class="default-entry__also">mrk applies this to ${entry.alsoDomains.length + 1} domains: <code>${entry.domain}</code>, <code>${entry.alsoDomains.join('</code>, <code>')}</code></div>` : ''}
                </div>
                
                <div class="default-entry__main">
                    <p class="default-entry__description">${entry.description}</p>
                    ${entry.why ? `<div class="default-entry__why"><span class="why-label">Why this setting</span>${entry.why}</div>` : ''}
                    ${this.skippedNote(entry)}
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