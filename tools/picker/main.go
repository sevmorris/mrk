// mrk-picker — interactive Brewfile package selector
// Two-pane Bubble Tea TUI: categories (left) | packages with descriptions (right)
// Outputs selected packages as "formula:name" or "cask:name" lines to stdout.
package main

import (
	"bufio"
	"flag"
	"fmt"
	"os"
	"regexp"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ── Types ─────────────────────────────────────────────────────────────────

type pkgKind string

const (
	formula pkgKind = "formula"
	cask    pkgKind = "cask"
)

type pkg struct {
	name      string
	kind      pkgKind
	line      string
	desc      string
	installed bool
	selected  bool
}

type category struct {
	name string
	pkgs []*pkg
}

// ── Descriptions ──────────────────────────────────────────────────────────

var descriptions = map[string]string{
	// Formulae
	"bash":              "Modern shell (Bash 5.x) with improved features",
	"bash-completion@2": "Programmable tab completion for Bash 4.1+",
	"bat":               "cat clone with syntax highlighting and Git integration",
	"coreutils":         "GNU core utilities — enhanced versions of standard Unix tools",
	"fastfetch":         "Fast, customizable system information display",
	"gh":                "GitHub CLI — official command-line tool for GitHub",
	"git":               "Distributed version control system",
	"gnupg":             "GNU Privacy Guard — encryption and signing tool",
	"htop":              "Interactive process viewer and system monitor",
	"lsd":               "Modern ls replacement with colors and icons",
	"mac-cleanup-py":    "Clean macOS caches, logs, downloads, and trash",
	"mkdocs":            "Static site generator for project documentation",
	"moreutils":         "Useful Unix utilities: sponge, vidir, ts, and more",
	"nano":              "Simple terminal text editor",
	"nanorc":            "Syntax highlighting configurations for nano",
	"ncdu":              "Disk usage analyzer with ncurses interface",
	"nethogs":           "Monitor network bandwidth usage per process",
	"nmap":              "Network exploration and security auditing tool",
	"openssh":           "OpenSSH client and server for secure remote access",
	"pandoc":            "Universal document converter",
	"paperkey":          "Extract GnuPG secret keys for offline paper backup",
	"pinentry-mac":      "PIN/passphrase entry dialog for GnuPG on macOS",
	"pwgen":             "Secure, memorable password generator",
	"qemu":              "Generic machine emulator and virtualizer",
	"qrencode":          "Generate QR codes from text strings",
	"rclone":            "Cloud storage sync tool (S3, Dropbox, GDrive, and more)",
	"deno":              "Secure JavaScript/TypeScript runtime by the Deno team",
	"go":                "Go programming language compiler and tools",
	"gum":               "Charm TUI toolkit — used as fallback package picker",
	"ripgrep":           "Extremely fast regex search tool (rg)",
	"shellcheck":        "Static analysis and linting tool for shell scripts",
	"shfmt":             "Shell script formatter",
	"tealdeer":          "Fast tldr client — simplified, practical man pages",
	"topgrade":          "Update everything at once across all package managers",
	"trash":             "Move files to macOS Trash instead of permanently deleting",
	"tree":              "Display directory contents as a visual tree",
	"watch":             "Repeatedly run a command and display its output",
	"wget":              "Internet file retriever",
	"zsh":               "Z shell — advanced interactive shell with many features",
	"nvm":               "Node Version Manager — install and manage Node.js versions",
	"python@3.12":       "Python 3.12 programming language interpreter",
	"pipx":              "Install and run Python apps in isolated environments",
	"pyenv":             "Python version manager",
	"openjdk":           "OpenJDK — open-source Java Development Kit",
	"ffmpeg":            "Complete solution for audio/video recording and conversion",
	"chromaprint":       "Audio fingerprinting library (AcoustID core component)",
	"whisper-cpp":       "Speech-to-text engine (optimized C++ port of Whisper)",
	"yt-dlp":            "Download video and audio from YouTube and 1000+ sites",
	// Casks
	"1password":              "Password manager and secure digital wallet",
	"1password-cli":          "1Password command-line tool (op)",
	"4k-video-downloader+":   "Download videos from YouTube and other platforms",
	"a-better-finder-rename": "Powerful batch file renaming for Finder",
	"adapter":                "Convert audio, video, and image files",
	"aldente":                "Battery charge limiter to extend MacBook battery life",
	"appcleaner":             "Completely uninstall apps and all their leftover files",
	"arctic":                 "Git client for GitHub, GitLab, and Bitbucket",
	"audio-hijack":           "Record and process audio from any application",
	"auto-claude":            "Automated Claude AI workflows",
	"balenaetcher":           "Flash OS images to SD cards and USB drives",
	"bitwarden":              "Open-source password manager",
	"brave-browser":          "Privacy-focused browser based on Chromium",
	"calibre":                "E-book manager, reader, and format converter",
	"chatgpt":                "OpenAI ChatGPT desktop application",
	"claude":                 "Anthropic Claude desktop application",
	"claude-code":            "Claude Code CLI tool",
	"cryptomator":            "Client-side encryption for files stored in the cloud",
	"descript":               "AI-powered audio and video editor",
	"discord":                "Voice, video, and text chat for communities",
	"disk-drill":             "Data recovery software and disk health monitoring",
	"dropbox":                "Cloud storage and file synchronization service",
	"etrecheckpro":           "macOS system maintenance and diagnostics tool",
	"farrago":                "Robust, rapid-fire soundboard for Mac",
	"firefox":                "Free and open-source web browser by Mozilla",
	"fission":                "Fast, lossless audio editor for Mac",
	"folx":                   "Download manager with integrated torrent support",
	"github":                 "GitHub Desktop — visual Git client",
	"google-chrome":          "Google Chrome web browser",
	"google-chrome@canary":   "Chrome Canary — bleeding-edge preview builds",
	"google-drive":           "Google Drive desktop cloud storage client",
	"gpg-suite-no-mail":      "GPG tools for macOS (without the Mail plugin)",
	"handbrake-app":          "Open-source video transcoder",
	"helium-browser":         "Floating browser window that sits above other apps",
	"hot":                    "macOS menu bar CPU temperature and frequency monitor",
	"ilok-license-manager":   "iLok USB hardware license manager",
	"iterm2":                 "Feature-rich terminal emulator for macOS",
	"izotope-product-portal": "iZotope audio plugin installer and manager",
	"jordanbaird-ice":        "Menu bar item hider and manager",
	"keka":                   "File archiver and extractor for macOS",
	"keybase":                "Secure key directory, file sharing, and messaging",
	"keyboardcleantool":      "Temporarily disable keyboard and trackpad for cleaning",
	"kid3":                   "Cross-platform audio tag editor",
	"kobo":                   "Kobo e-reader desktop application",
	"loopback":               "Cable-free audio routing between apps on Mac",
	"losslesscut":            "Lossless video and audio trimmer and cutter",
	"macfuse":                "FUSE file system extensions for macOS",
	"macwhisper":             "macOS app for Whisper-powered audio transcription",
	"mdrp":                   "Mastodon and decentralized social media client",
	"mediainfo":              "Display technical information about media files",
	"minecraft":              "Minecraft game launcher",
	"musicbrainz-picard":     "Music tagger using the MusicBrainz database",
	"nordvpn":                "NordVPN client for macOS",
	"omnidisksweeper":        "Disk usage analyzer for macOS",
	"onyx":                   "System maintenance, tweaking, and cleaning for macOS",
	"openaudible":            "Audible audiobook manager and converter",
	"openmtp":                "Android file transfer client (MTP)",
	"piezo":                  "Effortless audio recording from any application",
	"pulsar":                 "Community-driven Atom editor fork",
	"raspberry-pi-imager":    "Official Raspberry Pi OS imaging tool",
	"raycast":                "Extensible macOS launcher and productivity platform",
	"samsung-magician":       "Samsung SSD firmware and management utility",
	"screenflow":             "Screen recording and video editing for Mac",
	"shutter-encoder":        "Video, audio, and image converter and encoder",
	"signal":                 "Private, end-to-end encrypted messaging",
	"slack":                  "Team messaging and collaboration platform",
	"soundsource":            "System-wide per-application audio control for Mac",
	"stats":                  "macOS system statistics in the menu bar",
	"steam":                  "Steam PC gaming platform and library",
	"subler":                 "MP4 file muxer, subtitle editor, and tag editor",
	"swift-publisher":        "Desktop publishing and brochure design for Mac",
	"the-unarchiver":         "Archive extractor supporting many formats",
	"timemachineeditor":      "Schedule and control Time Machine backup frequency",
	"typora":                 "Minimal Markdown editor with live preview",
	"utm":                    "Virtual machine host using QEMU for macOS and iOS",
	"veracrypt":              "Open-source disk encryption software",
	"vlc":                    "Free, open-source media player for any format",
	"waves-central":          "Waves audio plugin installer and license manager",
	"whatsapp":               "WhatsApp desktop messaging client",
	"zoom":                   "Video conferencing and online meetings",
}

// ── Brewfile parsing ──────────────────────────────────────────────────────

var (
	formulaRe = regexp.MustCompile(`^brew "([^"]+)"`)
	caskRe    = regexp.MustCompile(`^cask "([^"]+)"`)
)

// categoryName extracts a short, friendly name from a Brewfile comment line.
func categoryName(comment string) string {
	name := comment
	// "X - Y": use Y when ≤2 words (specific), otherwise use X (general)
	if idx := strings.LastIndex(name, " - "); idx != -1 {
		suffix := name[idx+3:]
		if len(strings.Fields(suffix)) <= 2 {
			name = suffix
		} else {
			name = name[:idx]
		}
	}
	// Strip "/ ..." or "& ..." qualifiers
	if idx := strings.Index(name, " / "); idx != -1 {
		name = name[:idx]
	}
	if idx := strings.Index(name, " & "); idx != -1 {
		name = name[:idx]
	}
	// "Casks" alone is not meaningful in context
	if strings.TrimSpace(name) == "Casks" {
		name = "Applications"
	}
	return strings.TrimSpace(name)
}

func parseBrewfile(
	path string,
	installedFormulae, installedCasks map[string]bool,
	skipFormulae, skipCasks bool,
) ([]category, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var cats []category
	var curCat *category

	push := func(p *pkg) {
		if curCat == nil {
			cats = append(cats, category{name: "General"})
			curCat = &cats[len(cats)-1]
		}
		curCat.pkgs = append(curCat.pkgs, p)
	}

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		trimmed := strings.TrimSpace(line)

		if strings.HasPrefix(trimmed, "#") {
			text := strings.TrimSpace(strings.TrimPrefix(trimmed, "#"))
			// Skip blank comments, "Taps", and commented-out mas lines
			if text == "" || text == "Taps" || strings.HasPrefix(text, "mas ") {
				continue
			}
			name := categoryName(text)
			if name == "" {
				continue
			}
			cats = append(cats, category{name: name})
			curCat = &cats[len(cats)-1]
			continue
		}

		if m := formulaRe.FindStringSubmatch(line); m != nil {
			if !skipFormulae {
				name := m[1]
				push(&pkg{
					name:      name,
					kind:      formula,
					line:      line,
					desc:      descriptions[name],
					installed: installedFormulae[name],
				})
			}
			continue
		}

		if m := caskRe.FindStringSubmatch(line); m != nil {
			if !skipCasks {
				name := m[1]
				push(&pkg{
					name:      name,
					kind:      cask,
					line:      line,
					desc:      descriptions[name],
					installed: installedCasks[name],
				})
			}
		}
	}

	// Drop empty categories
	out := cats[:0]
	for _, c := range cats {
		if len(c.pkgs) > 0 {
			out = append(out, c)
		}
	}
	return out, scanner.Err()
}

// ── Model ─────────────────────────────────────────────────────────────────

type model struct {
	cats      []category
	catIdx    int  // left-pane cursor
	pkgIdx    int  // right-pane cursor
	leftFocus bool // which pane has keyboard focus
	width     int
	height    int
	confirmed bool
	cancelled bool
}

func newModel(cats []category) model {
	return model{cats: cats, leftFocus: true}
}

func (m model) Init() tea.Cmd { return nil }

func (m model) currentPkgs() []*pkg {
	if m.catIdx >= len(m.cats) {
		return nil
	}
	return m.cats[m.catIdx].pkgs
}

func (m model) totalSelected() int {
	n := 0
	for _, c := range m.cats {
		for _, p := range c.pkgs {
			if p.selected {
				n++
			}
		}
	}
	return n
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

	case tea.KeyMsg:
		switch msg.String() {
		case "q", "ctrl+c":
			m.cancelled = true
			return m, tea.Quit
		case "esc":
			if !m.leftFocus {
				m.leftFocus = true
			} else {
				m.cancelled = true
				return m, tea.Quit
			}
		case "enter":
			m.confirmed = true
			return m, tea.Quit

		case "tab", "shift+tab":
			m.leftFocus = !m.leftFocus
		case "left", "h":
			m.leftFocus = true
		case "right", "l":
			m.leftFocus = false

		case "up", "k":
			if m.leftFocus {
				if m.catIdx > 0 {
					m.catIdx--
					m.pkgIdx = 0
				}
			} else {
				if m.pkgIdx > 0 {
					m.pkgIdx--
				}
			}
		case "down", "j":
			if m.leftFocus {
				if m.catIdx < len(m.cats)-1 {
					m.catIdx++
					m.pkgIdx = 0
				}
			} else {
				pkgs := m.currentPkgs()
				if m.pkgIdx < len(pkgs)-1 {
					m.pkgIdx++
				}
			}

		case " ":
			if !m.leftFocus {
				pkgs := m.currentPkgs()
				if m.pkgIdx < len(pkgs) {
					p := pkgs[m.pkgIdx]
					if !p.installed {
						p.selected = !p.selected
						if m.pkgIdx < len(pkgs)-1 {
							m.pkgIdx++
						}
					}
				}
			}

		case "a":
			if !m.leftFocus {
				pkgs := m.currentPkgs()
				// Toggle: if all uninstalled are selected → deselect all; else select all
				allOn := true
				for _, p := range pkgs {
					if !p.installed && !p.selected {
						allOn = false
						break
					}
				}
				for _, p := range pkgs {
					if !p.installed {
						p.selected = !allOn
					}
				}
			}
		}
	}
	return m, nil
}

// ── Styles ────────────────────────────────────────────────────────────────

var (
	colSubtle    = lipgloss.AdaptiveColor{Light: "#888888", Dark: "#555555"}
	colDim       = lipgloss.AdaptiveColor{Light: "#aaaaaa", Dark: "#444444"}
	colNormal    = lipgloss.AdaptiveColor{Light: "#222222", Dark: "#cccccc"}
	colHighlight = lipgloss.AdaptiveColor{Light: "#d7005f", Dark: "#ff87af"}
	colAccent    = lipgloss.AdaptiveColor{Light: "#005fd7", Dark: "#87d7ff"}
	colGreen     = lipgloss.AdaptiveColor{Light: "#00875f", Dark: "#5fd7a7"}

	stylePaneOff = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(colSubtle)

	stylePaneOn = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(colAccent)

	styleTitle     = lipgloss.NewStyle().Bold(true).Foreground(colNormal)
	styleCount     = lipgloss.NewStyle().Bold(true).Foreground(colAccent)
	styleFooter    = lipgloss.NewStyle().Foreground(colSubtle)
	styleCatActive = lipgloss.NewStyle().Bold(true).Foreground(colHighlight)
	styleCatNorm   = lipgloss.NewStyle().Foreground(colNormal)
	styleBadgeDim  = lipgloss.NewStyle().Foreground(colSubtle)
	styleInstalled = lipgloss.NewStyle().Foreground(colDim)
	stylePkgSel    = lipgloss.NewStyle().Foreground(colGreen)
	stylePkgCurs   = lipgloss.NewStyle().Bold(true).Foreground(colHighlight)
	styleDescDim   = lipgloss.NewStyle().Foreground(colSubtle)
)

// ── View ──────────────────────────────────────────────────────────────────

func (m model) View() string {
	if m.width == 0 {
		return "Initializing…"
	}

	// Layout: left pane fixed inner width; right pane fills the rest.
	// Each rounded border adds 2 chars (1 each side).
	const leftInner = 22
	rightInner := m.width - leftInner - 4 // left border(2) + right border(2)
	if rightInner < 10 {
		rightInner = 10
	}
	// height: subtract header(1) + footer(1) + top border(1) + bottom border(1)
	paneH := m.height - 4
	if paneH < 1 {
		paneH = 1
	}

	header := m.viewHeader()
	left := m.viewLeft(leftInner, paneH)
	right := m.viewRight(rightInner, paneH)
	footer := m.viewFooter()

	panes := lipgloss.JoinHorizontal(lipgloss.Top, left, right)
	return lipgloss.JoinVertical(lipgloss.Left, header, panes, footer)
}

func (m model) viewHeader() string {
	title := styleTitle.Render("mrk brew")
	sel := styleCount.Render(fmt.Sprintf("%d selected", m.totalSelected()))
	gap := m.width - lipgloss.Width(title) - lipgloss.Width(sel)
	if gap < 1 {
		gap = 1
	}
	return title + strings.Repeat(" ", gap) + sel
}

func (m model) viewFooter() string {
	return styleFooter.Render("↑↓/jk move · tab/hl switch pane · space toggle · a all · enter confirm · q quit")
}

func (m model) viewLeft(inner, height int) string {
	var sb strings.Builder
	lines := 0

	start := 0
	if m.catIdx >= height {
		start = m.catIdx - height + 1
	}

	for i, cat := range m.cats {
		if i < start {
			continue
		}
		if lines >= height {
			break
		}

		selN := 0
		for _, p := range cat.pkgs {
			if p.selected {
				selN++
			}
		}
		total := len(cat.pkgs)

		badge := fmt.Sprintf("(%d)", total)
		if selN > 0 {
			badge = fmt.Sprintf("(%d/%d)", selN, total)
		}

		// Name: truncate to fit, leaving room for badge + cursor + space
		nameW := inner - len(badge) - 3
		if nameW < 1 {
			nameW = 1
		}
		name := cat.name
		if len(name) > nameW {
			name = name[:nameW-1] + "…"
		}
		pad := nameW - len(name)
		if pad < 0 {
			pad = 0
		}

		var line string
		isActive := i == m.catIdx
		if isActive {
			if m.leftFocus {
				line = styleCatActive.Render("▸ "+name) + strings.Repeat(" ", pad+1) + styleCount.Render(badge)
			} else {
				line = styleCatNorm.Render("▸ "+name) + strings.Repeat(" ", pad+1) + styleCatNorm.Render(badge)
			}
		} else {
			line = styleCatNorm.Render("  "+name) + strings.Repeat(" ", pad+1) + styleBadgeDim.Render(badge)
		}

		sb.WriteString(line + "\n")
		lines++
	}

	content := strings.TrimRight(sb.String(), "\n")
	pane := stylePaneOff
	if m.leftFocus {
		pane = stylePaneOn
	}
	return pane.Width(inner).Height(height).Render(content)
}

func (m model) viewRight(inner, height int) string {
	pkgs := m.currentPkgs()
	pane := stylePaneOff
	if !m.leftFocus {
		pane = stylePaneOn
	}

	if len(pkgs) == 0 {
		return pane.Width(inner).Height(height).Render(
			styleDescDim.Render("No packages"),
		)
	}

	start := 0
	if m.pkgIdx >= height {
		start = m.pkgIdx - height + 1
	}

	// Columns: indicator(2) + name(nameW) + gap(2) + description(rest)
	const nameW = 24
	descW := inner - nameW - 4
	if descW < 0 {
		descW = 0
	}

	var sb strings.Builder
	written := 0

	for i, p := range pkgs {
		if i < start {
			continue
		}
		if written >= height {
			break
		}

		indicator := "  "
		if p.installed {
			indicator = styleInstalled.Render("● ")
		} else if p.selected {
			indicator = stylePkgSel.Render("✓ ")
		}

		isCursor := i == m.pkgIdx && !m.leftFocus

		name := p.name
		if len(name) > nameW {
			name = name[:nameW-1] + "…"
		}
		pad := nameW - len(name)
		if pad < 0 {
			pad = 0
		}

		desc := p.desc
		if descW > 0 && len(desc) > descW {
			desc = desc[:descW-1] + "…"
		}

		var line string
		switch {
		case p.installed:
			line = indicator +
				styleInstalled.Render(name) + strings.Repeat(" ", pad+2) +
				styleInstalled.Render(desc)
		case isCursor && p.selected:
			line = stylePkgCurs.Render("▸ ") +
				stylePkgCurs.Render(name) + strings.Repeat(" ", pad+2) +
				stylePkgSel.Render(desc)
		case isCursor:
			line = stylePkgCurs.Render("▸ ") +
				stylePkgCurs.Render(name) + strings.Repeat(" ", pad+2) +
				styleDescDim.Render(desc)
		case p.selected:
			line = indicator +
				stylePkgSel.Render(name) + strings.Repeat(" ", pad+2) +
				stylePkgSel.Render(desc)
		default:
			line = indicator +
				styleCatNorm.Render(name) + strings.Repeat(" ", pad+2) +
				styleDescDim.Render(desc)
		}

		sb.WriteString(line + "\n")
		written++
	}

	content := strings.TrimRight(sb.String(), "\n")
	return pane.Width(inner).Height(height).Render(content)
}

// ── Main ──────────────────────────────────────────────────────────────────

func main() {
	brewfilePath := flag.String("brewfile", "Brewfile", "Path to Brewfile")
	installedFormulaeStr := flag.String("installed-formulae", "", "Comma-separated installed formulae")
	installedCasksStr := flag.String("installed-casks", "", "Comma-separated installed casks")
	skipFormulae := flag.Bool("skip-formulae", false, "Exclude formulae from picker")
	skipCasks := flag.Bool("skip-casks", false, "Exclude casks from picker")
	flag.Parse()

	installedFormulae := map[string]bool{}
	installedCasks := map[string]bool{}
	for _, s := range strings.Split(*installedFormulaeStr, ",") {
		if s = strings.TrimSpace(s); s != "" {
			installedFormulae[s] = true
		}
	}
	for _, s := range strings.Split(*installedCasksStr, ",") {
		if s = strings.TrimSpace(s); s != "" {
			installedCasks[s] = true
		}
	}

	cats, err := parseBrewfile(*brewfilePath, installedFormulae, installedCasks, *skipFormulae, *skipCasks)
	if err != nil {
		fmt.Fprintf(os.Stderr, "mrk-picker: %v\n", err)
		os.Exit(1)
	}
	if len(cats) == 0 {
		fmt.Fprintln(os.Stderr, "mrk-picker: no packages found in Brewfile")
		os.Exit(1)
	}

	p := tea.NewProgram(newModel(cats), tea.WithAltScreen())
	final, err := p.Run()
	if err != nil {
		fmt.Fprintf(os.Stderr, "mrk-picker: %v\n", err)
		os.Exit(1)
	}

	result := final.(model)
	if result.cancelled {
		os.Exit(1)
	}

	// Output selected packages as "type:name" lines
	for _, cat := range result.cats {
		for _, p := range cat.pkgs {
			if p.selected {
				fmt.Printf("%s:%s\n", p.kind, p.name)
			}
		}
	}
}
