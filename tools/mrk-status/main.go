// mrk-status — interactive installation health dashboard
// Two-pane Bubble Tea TUI: checks (left) | detail (right)
package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	theme "mrk-theme"
)

// ── Severity ──────────────────────────────────────────────────────────────

type severity int

const (
	sevOK   severity = iota // ✓
	sevInfo                  // ·
	sevWarn                  // ⚠
	sevErr                   // ✗
)

func (s severity) icon() string {
	switch s {
	case sevOK:
		return "✓"
	case sevWarn:
		return "⚠"
	case sevErr:
		return "✗"
	default:
		return "·"
	}
}

// ── Data ──────────────────────────────────────────────────────────────────

type statusLine struct {
	sev  severity
	text string
}

type group struct {
	name  string
	sev   severity
	lines []statusLine
	fix   string // shell command to run, or ""
}

func sl(sev severity, text string) statusLine { return statusLine{sev, text} }

func worst(lines []statusLine) severity {
	s := sevOK
	for _, l := range lines {
		if l.sev > s {
			s = l.sev
		}
	}
	return s
}

// ── Check functions ───────────────────────────────────────────────────────

func checkDotfiles(repoRoot, home string) group {
	dotDir := filepath.Join(repoRoot, "dotfiles")
	entries, err := os.ReadDir(dotDir)
	if err != nil {
		return group{"Dotfiles", sevWarn,
			[]statusLine{sl(sevWarn, "dotfiles/ not found")}, "make setup"}
	}

	var lines []statusLine
	linked, missing := 0, 0
	for _, e := range entries {
		n := e.Name()
		if strings.HasSuffix(n, ".example") || strings.HasPrefix(n, "README") || strings.HasSuffix(n, ".md") {
			continue
		}
		src := filepath.Join(dotDir, n)
		dst := filepath.Join(home, n)
		if t, err := os.Readlink(dst); err == nil && t == src {
			linked++
			lines = append(lines, sl(sevOK, n))
		} else {
			missing++
			if _, err2 := os.Lstat(dst); err2 == nil {
				lines = append(lines, sl(sevWarn, n+" (conflict — backup and re-run make setup)"))
			} else {
				lines = append(lines, sl(sevWarn, n+" (not linked — run make setup)"))
			}
		}
	}

	fix := ""
	if missing > 0 {
		fix = "make setup"
	}
	summary := fmt.Sprintf("%d linked", linked)
	if missing > 0 {
		summary += fmt.Sprintf(", %d not linked", missing)
	}
	all := append([]statusLine{sl(sevInfo, summary)}, lines...)
	sev := worst(lines)
	if len(lines) == 0 {
		sev = sevInfo
	}
	return group{"Dotfiles", sev, all, fix}
}

func checkTools(repoRoot, binDir string) group {
	entries, err := os.ReadDir(binDir)
	if err != nil {
		return group{"Tools", sevWarn,
			[]statusLine{sl(sevWarn, binDir+" not found")}, "mkdir -p ~/bin && make setup"}
	}

	var lines []statusLine
	linked, broken := 0, 0
	for _, e := range entries {
		if e.Type()&os.ModeSymlink == 0 {
			continue
		}
		full := filepath.Join(binDir, e.Name())
		target, err := os.Readlink(full)
		if err != nil || !strings.HasPrefix(target, repoRoot) {
			continue
		}
		if _, err := os.Stat(target); err == nil {
			linked++
		} else {
			broken++
			lines = append(lines, sl(sevWarn, e.Name()+" (broken → "+target+")"))
		}
	}

	fix := ""
	if broken > 0 {
		fix = "fix-exec"
	}
	summary := fmt.Sprintf("%d linked", linked)
	if broken > 0 {
		summary += fmt.Sprintf(", %d broken", broken)
	}
	all := append([]statusLine{sl(sevInfo, summary)}, lines...)
	sev := sevOK
	if broken > 0 {
		sev = sevWarn
	}
	return group{"Tools", sev, all, fix}
}

func countLines(path, pattern string) int {
	re := regexp.MustCompile(pattern)
	f, err := os.Open(path)
	if err != nil {
		return 0
	}
	defer f.Close()
	n := 0
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		if re.MatchString(sc.Text()) {
			n++
		}
	}
	return n
}

func checkDefaults(stateDir string) group {
	rollback := filepath.Join(stateDir, "defaults-rollback.sh")
	if _, err := os.Stat(rollback); err != nil {
		return group{"macOS Defaults", sevInfo,
			[]statusLine{sl(sevInfo, "Not applied — run: make defaults")}, "make defaults"}
	}
	n := countLines(rollback, `defaults write|defaults delete`)
	if n == 0 {
		return group{"macOS Defaults", sevInfo,
			[]statusLine{sl(sevInfo, "Rollback script present but empty")}, ""}
	}
	return group{"macOS Defaults", sevOK, []statusLine{
		sl(sevOK, "Applied"),
		sl(sevInfo, fmt.Sprintf("%d change(s) tracked in rollback script", n)),
		sl(sevInfo, "Rollback: "+rollback),
	}, ""}
}

func checkHardening(stateDir string) group {
	rollback := filepath.Join(stateDir, "hardening-rollback.sh")
	if _, err := os.Stat(rollback); err != nil {
		return group{"Security Hardening", sevInfo,
			[]statusLine{sl(sevInfo, "Not applied — run: hardening.sh")}, "hardening.sh"}
	}
	n := countLines(rollback, `sudo|defaults write|defaults delete`)
	if n == 0 {
		return group{"Security Hardening", sevInfo,
			[]statusLine{sl(sevInfo, "Rollback script present but empty")}, ""}
	}
	return group{"Security Hardening", sevOK, []statusLine{
		sl(sevOK, "Applied"),
		sl(sevInfo, fmt.Sprintf("%d change(s) tracked in rollback script", n)),
		sl(sevInfo, "Rollback: "+rollback),
	}, ""}
}

func checkBackups(stateDir string) group {
	backupDir := filepath.Join(stateDir, "backups")
	entries, err := os.ReadDir(backupDir)
	if err != nil {
		return group{"Backups", sevInfo,
			[]statusLine{sl(sevInfo, "No backups directory")}, ""}
	}
	var dirs []string
	for _, e := range entries {
		if e.IsDir() {
			dirs = append(dirs, e.Name())
		}
	}
	if len(dirs) == 0 {
		return group{"Backups", sevInfo,
			[]statusLine{sl(sevInfo, "No backups found")}, ""}
	}
	sort.Sort(sort.Reverse(sort.StringSlice(dirs)))
	return group{"Backups", sevOK, []statusLine{
		sl(sevOK, fmt.Sprintf("%d backup(s)", len(dirs))),
		sl(sevInfo, "Latest:   "+dirs[0]),
		sl(sevInfo, "Location: "+backupDir),
	}, ""}
}

func checkShell() group {
	user := os.Getenv("USER")
	out, _ := exec.Command("dscl", ".", "-read", "/Users/"+user, "UserShell").Output()
	current := ""
	if parts := strings.Fields(strings.TrimSpace(string(out))); len(parts) >= 2 {
		current = parts[1]
	}
	zshPath, _ := exec.LookPath("zsh")
	if current != "" && current == zshPath {
		return group{"Shell", sevOK,
			[]statusLine{sl(sevOK, "Login shell: "+current)}, ""}
	}
	fix := ""
	if zshPath != "" {
		fix = "chsh -s " + zshPath
	}
	return group{"Shell", sevWarn, []statusLine{
		sl(sevWarn, fmt.Sprintf("Login shell: %s (expected: %s)", current, zshPath)),
	}, fix}
}

func checkPATH(binDir string) group {
	for _, p := range filepath.SplitList(os.Getenv("PATH")) {
		if p == binDir {
			return group{"PATH", sevOK,
				[]statusLine{sl(sevOK, binDir+" is on PATH")}, ""}
		}
	}
	return group{"PATH", sevWarn,
		[]statusLine{sl(sevWarn, binDir+" is NOT on PATH")}, "doctor --fix"}
}

func checkHomebrew() group {
	out, err := exec.Command("brew", "--version").Output()
	if err != nil {
		return group{"Homebrew", sevErr,
			[]statusLine{sl(sevErr, "Not installed — see https://brew.sh")}, ""}
	}
	ver := strings.SplitN(strings.TrimSpace(string(out)), "\n", 2)[0]
	return group{"Homebrew", sevOK,
		[]statusLine{sl(sevOK, ver)}, ""}
}

var (
	reBrewPkg = regexp.MustCompile(`^brew\s+"([^"]+)"`)
	reCaskPkg = regexp.MustCompile(`^cask\s+"([^"]+)"`)
)

func checkBrewfile(repoRoot string) group {
	path := filepath.Join(repoRoot, "Brewfile")
	f, err := os.Open(path)
	if err != nil {
		return group{"Brewfile", sevWarn,
			[]statusLine{sl(sevWarn, "Brewfile not found at "+path)}, ""}
	}
	defer f.Close()

	var formulae, casks []string
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		l := strings.TrimSpace(sc.Text())
		if m := reBrewPkg.FindStringSubmatch(l); m != nil {
			formulae = append(formulae, m[1])
		} else if m := reCaskPkg.FindStringSubmatch(l); m != nil {
			casks = append(casks, m[1])
		}
	}

	if _, err := exec.LookPath("brew"); err != nil {
		return group{"Brewfile", sevInfo, []statusLine{
			sl(sevInfo, fmt.Sprintf("%d formulae, %d casks (brew unavailable — skipping checks)",
				len(formulae), len(casks))),
		}, ""}
	}

	instF, instC := map[string]bool{}, map[string]bool{}
	if out, err := exec.Command("brew", "list", "--formula").Output(); err == nil {
		for _, p := range strings.Fields(string(out)) {
			instF[p] = true
		}
	}
	if out, err := exec.Command("brew", "list", "--cask").Output(); err == nil {
		for _, p := range strings.Fields(string(out)) {
			instC[p] = true
		}
	}

	var lines []statusLine
	installed, missing := 0, 0
	for _, pkg := range formulae {
		if instF[pkg] {
			installed++
			lines = append(lines, sl(sevOK, pkg))
		} else {
			missing++
			lines = append(lines, sl(sevErr, pkg+" (missing)"))
		}
	}
	for _, pkg := range casks {
		if instC[pkg] {
			installed++
			lines = append(lines, sl(sevOK, pkg+" (cask)"))
		} else {
			missing++
			lines = append(lines, sl(sevErr, pkg+" (cask, missing)"))
		}
	}

	total := installed + missing
	summary := fmt.Sprintf("%d/%d installed", installed, total)
	if missing > 0 {
		summary += fmt.Sprintf(", %d missing", missing)
	}
	all := append([]statusLine{sl(sevInfo, summary)}, lines...)
	sev, fix := sevOK, ""
	if missing > 0 {
		sev = sevWarn
		fix = "make brew"
	}
	return group{"Brewfile", sev, all, fix}
}

// ── Messages & commands ───────────────────────────────────────────────────

type checksMsg []group
type fixDoneMsg struct{ err error }

func runChecks(repoRoot, home, binDir string) tea.Cmd {
	return func() tea.Msg {
		stateDir := filepath.Join(home, ".mrk")
		return checksMsg([]group{
			checkDotfiles(repoRoot, home),
			checkTools(repoRoot, binDir),
			checkDefaults(stateDir),
			checkHardening(stateDir),
			checkBackups(stateDir),
			checkShell(),
			checkPATH(binDir),
			checkHomebrew(),
			checkBrewfile(repoRoot),
		})
	}
}

// ── Model ─────────────────────────────────────────────────────────────────

type model struct {
	groups       []group
	groupIdx     int
	detailScroll int
	leftFocus    bool
	width        int
	height       int
	loading      bool
	flash        string
	pendingFix   bool
	repoRoot     string
	home         string
	binDir       string
}

func newModel(repoRoot, home, binDir string) model {
	return model{
		repoRoot:  repoRoot,
		home:      home,
		binDir:    binDir,
		loading:   true,
		leftFocus: true,
	}
}

func (m model) Init() tea.Cmd {
	return runChecks(m.repoRoot, m.home, m.binDir)
}

// ── Update ────────────────────────────────────────────────────────────────

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
	case checksMsg:
		m.groups = []group(msg)
		m.loading = false
		m.clampCursor()
	case fixDoneMsg:
		if msg.err != nil {
			m.flash = "fix failed: " + msg.err.Error()
		} else {
			m.flash = "done — refreshing…"
		}
		m.loading = true
		return m, runChecks(m.repoRoot, m.home, m.binDir)
	case tea.KeyMsg:
		return m.handleKey(msg)
	}
	return m, nil
}

func (m model) handleKey(msg tea.KeyMsg) (model, tea.Cmd) {
	key := msg.String()

	if key == "ctrl+c" {
		return m, tea.Quit
	}

	if m.pendingFix {
		switch key {
		case "enter":
			m.pendingFix = false
			m.flash = ""
			if g := m.currentGroup(); g != nil && g.fix != "" {
				shell := os.Getenv("SHELL")
				if shell == "" {
					shell = "/bin/zsh"
				}
				cmd := exec.Command(shell, "-c",
					"cd "+shellQuote(m.repoRoot)+" && "+g.fix)
				return m, tea.ExecProcess(cmd, func(err error) tea.Msg {
					return fixDoneMsg{err: err}
				})
			}
		default:
			m.pendingFix = false
			m.flash = ""
		}
		return m, nil
	}

	if key == "q" || key == "esc" {
		return m, tea.Quit
	}
	if m.loading {
		return m, nil
	}

	m.flash = ""
	switch key {
	case "tab", "shift+tab":
		m.leftFocus = !m.leftFocus
		m.detailScroll = 0
	case "left", "h":
		m.leftFocus = true
		m.detailScroll = 0
	case "right", "l":
		m.leftFocus = false

	case "up", "k":
		if m.leftFocus {
			if m.groupIdx > 0 {
				m.groupIdx--
				m.detailScroll = 0
			}
		} else {
			if m.detailScroll > 0 {
				m.detailScroll--
			}
		}
	case "down", "j":
		if m.leftFocus {
			if m.groupIdx < len(m.groups)-1 {
				m.groupIdx++
				m.detailScroll = 0
			}
		} else {
			m.scrollDown()
		}
	case "pgup":
		if !m.leftFocus {
			m.detailScroll -= m.detailViewH() / 2
			if m.detailScroll < 0 {
				m.detailScroll = 0
			}
		}
	case "pgdown":
		if !m.leftFocus {
			m.scrollDown()
			m.scrollDown()
			m.scrollDown()
			m.scrollDown()
		}

	case "r":
		m.loading = true
		return m, runChecks(m.repoRoot, m.home, m.binDir)

	case "f":
		if g := m.currentGroup(); g != nil && g.fix != "" {
			m.pendingFix = true
			m.flash = "Run \"" + g.fix + "\"? [enter] confirm  [esc] cancel"
			return m, nil
		}
		m.flash = "no fix available for this check"
	}
	return m, nil
}

func (m *model) scrollDown() {
	g := m.currentGroup()
	if g == nil {
		return
	}
	vh := m.detailViewH()
	if maxScroll := len(g.lines) - vh; maxScroll > 0 && m.detailScroll < maxScroll {
		m.detailScroll++
	}
}

// detailViewH is the number of visible detail lines in the right pane.
func (m model) detailViewH() int {
	bodyH := m.height - 2 // header + footer
	if bodyH < 6 {
		bodyH = 6
	}
	return bodyH - 2 - 1 // border(2) + group header(1)
}

func (m *model) clampCursor() {
	if m.groupIdx >= len(m.groups) {
		m.groupIdx = max(0, len(m.groups)-1)
	}
}

func (m model) currentGroup() *group {
	if m.groupIdx < len(m.groups) {
		return &m.groups[m.groupIdx]
	}
	return nil
}

// ── Styles ────────────────────────────────────────────────────────────────

var (
	// Local aliases for shared theme
	stylePaneOff = theme.StylePaneOff
	stylePaneOn  = theme.StylePaneOn
	styleTitle   = theme.StyleTitle
	styleFooter  = theme.StyleFooter

	// mrk-status-specific styles
	styleFlash     = lipgloss.NewStyle().Foreground(theme.ColGreen)
	styleFlashWarn = lipgloss.NewStyle().Foreground(theme.ColAmber)
	styleDim       = lipgloss.NewStyle().Foreground(theme.ColDim)
	styleCursor    = lipgloss.NewStyle().Bold(true).Foreground(theme.ColHighlight)
	styleNorm      = lipgloss.NewStyle().Foreground(theme.ColNormal)
	styleLoading   = lipgloss.NewStyle().Foreground(theme.ColSubtle)

	styleOK   = lipgloss.NewStyle().Foreground(theme.ColGreen)
	styleWarn = lipgloss.NewStyle().Foreground(theme.ColAmber)
	styleErr  = lipgloss.NewStyle().Foreground(theme.ColRed)
	styleInfo = lipgloss.NewStyle().Foreground(theme.ColDim)
)

func sevStyle(s severity) lipgloss.Style {
	switch s {
	case sevOK:
		return styleOK
	case sevWarn:
		return styleWarn
	case sevErr:
		return styleErr
	default:
		return styleInfo
	}
}

// ── View ──────────────────────────────────────────────────────────────────

func (m model) View() string {
	if m.width == 0 {
		return "Loading…"
	}
	return lipgloss.JoinVertical(lipgloss.Left,
		m.viewHeader(),
		m.viewBody(),
		m.viewFooter(),
	)
}

func (m model) viewHeader() string {
	left := styleTitle.Render("mrk-status") + styleFooter.Render("  Installation Health")
	var right string
	if m.loading {
		right = styleLoading.Render("checking…")
	} else {
		warns, errs := 0, 0
		for _, g := range m.groups {
			switch g.sev {
			case sevWarn:
				warns++
			case sevErr:
				errs++
			}
		}
		if errs > 0 {
			right = styleErr.Render(fmt.Sprintf("%d error(s)", errs))
		} else if warns > 0 {
			right = styleWarn.Render(fmt.Sprintf("%d warning(s)", warns))
		} else {
			right = styleOK.Render("all clear")
		}
	}
	gap := m.width - lipgloss.Width(left) - lipgloss.Width(right)
	if gap < 1 {
		gap = 1
	}
	return left + strings.Repeat(" ", gap) + right
}

func (m model) viewFooter() string {
	hints := styleFooter.Render("[↑↓/jk] navigate  [tab] switch pane  [f]ix  [r]efresh  [q]uit")
	if m.flash == "" {
		return hints
	}
	var flashStr string
	if m.pendingFix || strings.Contains(m.flash, "fail") || strings.Contains(m.flash, "no fix") {
		flashStr = "  " + styleFlashWarn.Render(m.flash)
	} else {
		flashStr = "  " + styleFlash.Render(m.flash)
	}
	return hints + flashStr
}

func (m model) viewBody() string {
	bodyH := m.height - 2
	if bodyH < 4 {
		bodyH = 4
	}
	paneH := bodyH - 2 // subtract border top+bottom

	if m.loading && len(m.groups) == 0 {
		inner := m.width - 4
		return stylePaneOn.Width(inner).Height(paneH).
			Render(styleLoading.Render("Checking installation…"))
	}

	const leftInner = 26
	rightInner := m.width - leftInner - 4
	if rightInner < 10 {
		rightInner = 10
	}

	return lipgloss.JoinHorizontal(lipgloss.Top,
		m.viewLeft(leftInner, paneH),
		m.viewRight(rightInner, paneH),
	)
}

func (m model) viewLeft(inner, height int) string {
	var sb strings.Builder
	for i, g := range m.groups {
		icon := sevStyle(g.sev).Render(g.sev.icon())
		nameW := inner - 5 // "▸ " or "  " (2) + icon(1) + " " (1) + padding(1)
		name := theme.Truncate(g.name, nameW)
		pad := strings.Repeat(" ", max(0, nameW-lipgloss.Width(name)))

		var line string
		if i == m.groupIdx {
			if m.leftFocus {
				line = styleCursor.Render("▸ ") + icon + " " + styleCursor.Render(name) + pad
			} else {
				line = styleNorm.Render("▸ ") + icon + " " + styleNorm.Render(name) + pad
			}
		} else {
			line = "  " + icon + " " + styleNorm.Render(name) + pad
		}
		sb.WriteString(line + "\n")
	}

	content := strings.TrimRight(sb.String(), "\n")
	pane := stylePaneOff
	if m.leftFocus {
		pane = stylePaneOn
	}
	return pane.Width(inner).Height(height).Render(content)
}

func (m model) viewRight(inner, height int) string {
	pane := stylePaneOff
	if !m.leftFocus {
		pane = stylePaneOn
	}

	g := m.currentGroup()
	if g == nil {
		return pane.Width(inner).Height(height).Render(styleDim.Render("no data"))
	}

	// Header: group name + fix hint
	header := styleTitle.Render(g.name)
	if g.fix != "" {
		header += styleDim.Render("  [f] " + g.fix)
	}

	// Detail lines viewport
	vh := height - 1 // lines available below header
	start := m.detailScroll
	end := start + vh
	if end > len(g.lines) {
		end = len(g.lines)
	}

	var sb strings.Builder
	sb.WriteString(header + "\n")
	for _, l := range g.lines[start:end] {
		icon := sevStyle(l.sev).Render(l.sev.icon())
		text := theme.Truncate(l.text, inner-3)
		sb.WriteString(icon + " " + styleNorm.Render(text) + "\n")
	}

	// Scroll indicator
	if len(g.lines) > vh {
		shown := end
		total := len(g.lines)
		indicator := styleDim.Render(fmt.Sprintf(" %d/%d", shown, total))
		// replace last char of header row with indicator — simpler: append as last line
		_ = indicator // we'll embed it in the header instead
		header = styleTitle.Render(g.name)
		if g.fix != "" {
			header += styleDim.Render("  [f] " + g.fix)
		}
		scrollInfo := styleDim.Render(fmt.Sprintf("  %d–%d / %d", start+1, end, total))
		gap := inner - lipgloss.Width(header) - lipgloss.Width(scrollInfo)
		if gap < 0 {
			gap = 0
		}
		var sb2 strings.Builder
		sb2.WriteString(header + strings.Repeat(" ", gap) + scrollInfo + "\n")
		for _, l := range g.lines[start:end] {
			icon := sevStyle(l.sev).Render(l.sev.icon())
			text := theme.Truncate(l.text, inner-3)
			sb2.WriteString(icon + " " + styleNorm.Render(text) + "\n")
		}
		content := strings.TrimRight(sb2.String(), "\n")
		return pane.Width(inner).Height(height).Render(content)
	}

	content := strings.TrimRight(sb.String(), "\n")
	return pane.Width(inner).Height(height).Render(content)
}

// ── Helpers ───────────────────────────────────────────────────────────────

func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", "'\\''") + "'"
}

// ── Main ──────────────────────────────────────────────────────────────────

func usage() {
	fmt.Print(`mrk-status — interactive installation health dashboard

Usage:
  mrk-status          Open the TUI dashboard
  mrk-status --help   Show this help

TUI keys:
  ↑/↓  k/j           Navigate checks (left) or scroll detail (right)
  ←/→  h/l           Switch panes
  tab / shift+tab     Switch panes
  pgup / pgdown       Scroll detail pane faster
  f                   Run fix command for selected check
  r                   Refresh all checks
  q / esc             Quit
`)
}

func main() {
	if len(os.Args) > 1 && (os.Args[1] == "--help" || os.Args[1] == "-h") {
		usage()
		os.Exit(0)
	}

	home, err := os.UserHomeDir()
	if err != nil {
		fmt.Fprintf(os.Stderr, "mrk-status: cannot determine home directory: %v\n", err)
		os.Exit(1)
	}

	repoRoot := filepath.Join(home, "mrk")
	if r := os.Getenv("MRK_ROOT"); r != "" {
		repoRoot = r
	}
	binDir := filepath.Join(home, "bin")

	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		fmt.Fprintf(os.Stderr, "mrk-status: cannot open terminal: %v\n", err)
		os.Exit(1)
	}
	defer tty.Close()

	p := tea.NewProgram(
		newModel(repoRoot, home, binDir),
		tea.WithAltScreen(),
		tea.WithInput(tty),
		tea.WithOutput(tty),
	)
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "mrk-status: %v\n", err)
		os.Exit(1)
	}
}
