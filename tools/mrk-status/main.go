// mrk-status — interactive installation health dashboard
// Two-pane Bubble Tea TUI: checks (left) | detail (right)
package main

import (
	"bufio"
	"fmt"
	"io"
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

// Version and GitSHA are populated at build time via -ldflags.
var (
	Version = "dev"
	GitSHA  = "unknown"
)

// ── Severity ──────────────────────────────────────────────────────────────

type severity int

const (
	sevOK   severity = iota // ✓
	sevInfo                 // ·
	sevWarn                 // ⚠
	sevErr                  // ✗
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
		if err != nil || !strings.HasPrefix(target, repoRoot+"/") {
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
		// A broken link here points into this repo at a file that is gone — a
		// script that was deleted or renamed — so there is nothing to re-create
		// it from. setup links only what exists (and drops a renamed script's
		// old name), and until 2026-09-11 this offered "make setup", which left
		// the link broken, re-ran all of Phase 1, and offered itself again.
		// fix-exec prunes exactly these links, and scripts/status says so too.
		fix = "make fix-exec"
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
			// "make harden", not "hardening.sh". The f key runs the fix as
			// `cd <repoRoot> && <fix>`, and hardening.sh is neither on the PATH
			// (it is installed as "harden") nor in the repo root (it is in
			// scripts/), so the bare filename could never resolve. Every other
			// fix here is already a make target.
			[]statusLine{sl(sevInfo, "Not applied — run: make harden")}, "make harden"}
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

// checkBackups reports what setup displaced, not the health of anything. It
// returns false when there is nothing to report, and the caller omits the
// panel entirely: this is the only check that can neither fail nor be fixed,
// so on a clean install it would otherwise occupy a slot in a health
// dashboard to say "None" and offer no action.
// When linking a dotfile, setup MOVES a pre-existing non-symlink out of the
// way into ~/.mrk/backups/<timestamp>/ instead of deleting it. So an empty
// directory means setup never had to displace a file — the normal outcome of
// installing onto a clean home directory, not a problem.
//
// Nothing reads these back: no restore path exists in uninstall or anywhere
// else. They are an inert archive of what the machine had before mrk. Hence
// no fix on this group — there is nothing to repair.
func checkBackups(stateDir string) (group, bool) {
	backupDir := filepath.Join(stateDir, "backups")
	entries, err := os.ReadDir(backupDir)
	if err != nil {
		return group{}, false
	}
	var dirs []string
	for _, e := range entries {
		if e.IsDir() {
			dirs = append(dirs, e.Name())
		}
	}
	if len(dirs) == 0 {
		return group{}, false
	}
	sort.Sort(sort.Reverse(sort.StringSlice(dirs)))
	return group{"Backups", sevOK, []statusLine{
		sl(sevOK, fmt.Sprintf("%d backup(s)", len(dirs))),
		sl(sevInfo, "Latest:   "+dirs[0]),
		sl(sevInfo, "Location: "+backupDir),
	}, ""}, true
}

func checkShell() group {
	user := os.Getenv("USER")
	if user == "" {
		return group{"Shell", sevWarn,
			[]statusLine{sl(sevWarn, "USER environment variable is not set")}, ""}
	}
	out, err := exec.Command("dscl", ".", "-read", "/Users/"+user, "UserShell").Output()
	if err != nil {
		return group{"Shell", sevWarn,
			[]statusLine{sl(sevWarn, fmt.Sprintf("dscl failed: %v", err))}, ""}
	}
	current := ""
	if parts := strings.Fields(strings.TrimSpace(string(out))); len(parts) >= 2 {
		current = parts[1]
	}
	zshPath, _ := exec.LookPath("zsh")
	if current != "" && current == zshPath {
		return group{"Shell", sevOK,
			[]statusLine{sl(sevOK, "Login shell: "+current)}, ""}
	}
	lines := []statusLine{
		sl(sevWarn, fmt.Sprintf("Login shell: %s (expected: %s)", current, zshPath)),
	}
	fix := ""
	switch {
	case zshPath == "":
	case shellListed(zshPath):
		fix = "chsh -s " + zshPath
	default:
		// chsh refuses a shell that /etc/shells does not list — "Non-standard
		// is defined as a shell not found in /etc/shells" (man chsh) — and
		// Homebrew does not register its zsh. That is a new Mac's state after
		// make all: setup runs before brew installs the zsh it would register.
		// setup's shell phase registers it, then runs chsh. scripts/status has
		// said so since 2026-09-10; until 2026-09-11 this panel, which is what
		// `status` opens, offered the bare chsh that could only fail.
		lines = append(lines, sl(sevInfo, zshPath+" is not listed in /etc/shells, so chsh will refuse it"))
		fix = `make setup ARGS="--only shell"`
	}
	return group{"Shell", sevWarn, lines, fix}
}

// shellsFile is the list chsh checks. A variable so the tests can point it at a
// fixture, as scripts/status reads SHELLS_FILE.
var shellsFile = "/etc/shells"

// shellListed reports whether path is a whole line of shellsFile, surrounding
// whitespace aside, so zsh-beta is not taken for zsh. An unreadable file counts
// as unlisted: the fix it leads to registers the shell only if it is missing,
// so it is right either way.
func shellListed(path string) bool {
	b, err := os.ReadFile(shellsFile)
	if err != nil {
		return false
	}
	for _, l := range strings.Split(string(b), "\n") {
		if strings.TrimSpace(l) == path {
			return true
		}
	}
	return false
}

func checkPATH(binDir string) group {
	for _, p := range filepath.SplitList(os.Getenv("PATH")) {
		if p == binDir {
			return group{"PATH", sevOK,
				[]statusLine{sl(sevOK, binDir+" is on PATH")}, ""}
		}
	}
	return group{"PATH", sevWarn,
		[]statusLine{sl(sevWarn, binDir+" is NOT on PATH")}, "make doctor ARGS=--fix"}
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

	// A failed `brew list` must not be folded into the per-package results. The
	// old code swallowed the error and left the map empty, so every lookup below
	// missed and all of the Brewfile rendered as "(missing)" — a screen of
	// fabricated failures with nothing saying the check itself never ran. brew
	// being absent is already handled above via LookPath; this is brew present
	// and failing, which a broken prefix or a half-finished upgrade produces.
	//
	// scripts/sync:190 guards the identical call for the same reason, where the
	// consequence was worse: --prune would have read the empty set as "every
	// tracked entry is stale".
	instF, instC := map[string]bool{}, map[string]bool{}
	outF, errF := exec.Command("brew", "list", "--formula").Output()
	outC, errC := exec.Command("brew", "list", "--cask").Output()
	if errF != nil || errC != nil {
		which, e := "brew list --formula", errF
		if errF == nil {
			which, e = "brew list --cask", errC
		}
		return group{"Brewfile", sevWarn, []statusLine{
			sl(sevWarn, fmt.Sprintf("%d formulae, %d casks tracked", len(formulae), len(casks))),
			sl(sevWarn, fmt.Sprintf("cannot check what is installed — %s failed: %v", which, e)),
		}, "brew doctor"}
	}
	for _, p := range strings.Fields(string(outF)) {
		instF[p] = true
	}
	for _, p := range strings.Fields(string(outC)) {
		instC[p] = true
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
		groups := []group{
			checkDotfiles(repoRoot, home),
			checkTools(repoRoot, binDir),
			checkDefaults(stateDir),
			checkHardening(stateDir),
		}
		if g, ok := checkBackups(stateDir); ok {
			groups = append(groups, g)
		}
		groups = append(groups,
			checkShell(),
			checkPATH(binDir),
			checkHomebrew(),
			checkBrewfile(repoRoot),
		)
		return checksMsg(groups)
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
		// The clamp keeps strings.Repeat from panicking on a negative count, but
		// it does not stop the header running past the terminal edge — at 40
		// columns this line was 42. clampWidth finishes the job.
		gap = 1
	}
	return m.clampWidth(left + strings.Repeat(" ", gap) + right)
}

// clampWidth trims a rendered, styled line to the terminal width. lipgloss's
// MaxWidth is ANSI-aware, which a rune-based truncate is not: these strings
// carry escape sequences, and cutting one in half corrupts the rest of the
// frame rather than shortening it.
func (m model) clampWidth(s string) string {
	if m.width <= 0 {
		return s
	}
	return lipgloss.NewStyle().MaxWidth(m.width).Render(s)
}

func (m model) viewFooter() string {
	hints := styleFooter.Render("[↑↓/jk] navigate  [tab] switch pane  [f]ix  [r]efresh  [q]uit")
	version := styleFooter.Render(fmt.Sprintf("  %s (%s)", Version, GitSHA))
	if m.flash == "" {
		return m.clampWidth(hints + version)
	}
	var flashStr string
	if m.pendingFix || strings.Contains(m.flash, "fail") || strings.Contains(m.flash, "no fix") {
		flashStr = "  " + styleFlashWarn.Render(m.flash)
	} else {
		flashStr = "  " + styleFlash.Render(m.flash)
	}
	return m.clampWidth(hints + flashStr)
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

	// Scroll indicator, rendered into the header row as "start–end / total".
	if len(g.lines) > vh {
		total := len(g.lines)
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

func usage(w io.Writer) {
	fmt.Fprint(w, `mrk-status — interactive installation health dashboard

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

// parseArgs decides what to do with the command line. It returns help=true when
// usage was asked for, and bad set to the argument to refuse. Extracted from
// main so the decision is testable without os.Exit.
//
// The default arm is the point. main used to compare os.Args[1] against
// "--help" and "-h" and fall straight through on anything else, so
// `mrk-status --bogus` opened the TUI with the flag discarded — the same shape
// as the eight commands in audit/14 P-9. An extra argument was dropped too.
func parseArgs(args []string) (help bool, bad string) {
	if len(args) == 0 {
		return false, ""
	}
	if len(args) > 1 {
		return false, args[1]
	}
	switch args[0] {
	case "--help", "-h":
		return true, ""
	default:
		return false, args[0]
	}
}

func main() {
	help, bad := parseArgs(os.Args[1:])
	switch {
	case bad != "":
		usage(os.Stderr)
		fmt.Fprintf(os.Stderr, "\nunknown argument: %s\n", bad)
		os.Exit(2)
	case help:
		usage(os.Stdout)
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
