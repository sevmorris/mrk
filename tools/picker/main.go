// mrk-picker — interactive Brewfile package selector
// Two-pane Bubble Tea TUI: categories (left) | packages with descriptions (right)
// Outputs selected packages as "formula:name" or "cask:name" lines to stdout.
package main

import (
	"bufio"
	_ "embed"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"
	"unicode"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	theme "mrk-theme"
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
	// Marked for ~/.mrk/sync-ignore rather than the Brewfile. Mutually
	// exclusive with selected: "add this" and "never offer this again" are
	// opposite answers to the same question.
	ignored bool
}

type category struct {
	name string
	pkgs []*pkg
}

// ── Descriptions ──────────────────────────────────────────────────────────

// descriptions.tsv is the one description table. sync, check-picker-desc
// --fix and scripts/brew read and write it as plain lines, and Barkeep can
// too. It was a map literal here, and only a Go-aware editor could change that
// safely: scripts/lib.sh carried a Python editor and ran gofmt after it.
//
//go:embed descriptions.tsv
var descriptionsTSV string

// descriptions maps a Brewfile name to its description. descriptionsErr is set
// when the embedded table cannot be read, and main stops on it: the compiler
// refused a bad map literal, so a bad table must not reach the picker either.
var descriptions, descriptionsErr = parseDescriptions(descriptionsTSV)

// parseDescriptions reads the table: one `name<TAB>description` line for each
// name, with blank lines and lines that start with # ignored. A line with no
// tab, a second tab, a control character, an empty name or description, or a
// name given twice is an error that names the line. The order is not checked
// here: the lookup does not need it, and descriptions_test.go holds the file
// to it.
func parseDescriptions(table string) (map[string]string, error) {
	m := map[string]string{}
	for i, line := range strings.Split(table, "\n") {
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		name, desc, ok := strings.Cut(line, "\t")
		switch {
		case strings.ContainsFunc(line, func(r rune) bool { return r != '\t' && unicode.IsControl(r) }):
			// A carriage return, from an editor that writes CRLF, as
			// check-picker-desc refuses it (audit 22, Z-6).
			return nil, fmt.Errorf("descriptions.tsv line %d: a control character, such as a carriage return", i+1)
		case !ok:
			return nil, fmt.Errorf("descriptions.tsv line %d: no tab between the name and the description", i+1)
		case strings.Contains(desc, "\t"):
			return nil, fmt.Errorf("descriptions.tsv line %d: more than one tab", i+1)
		case name == "" || desc == "":
			return nil, fmt.Errorf("descriptions.tsv line %d: an empty name or description", i+1)
		}
		if _, dup := m[name]; dup {
			return nil, fmt.Errorf("descriptions.tsv line %d: %s is described twice", i+1, name)
		}
		m[name] = desc
	}
	return m, nil
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
			// Only ## lines are section headers; single-# lines are annotations.
			if !strings.HasPrefix(trimmed, "##") {
				continue
			}
			text := strings.TrimSpace(strings.TrimPrefix(trimmed, "##"))
			// Skip blank headers and the Taps header (taps aren't selectable packages)
			if text == "" || text == "Taps" {
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
	// ctrl+c only. An `i` mark is a decision the user already made, so quitting
	// with q or esc keeps those while dropping the pending additions; a hard
	// interrupt drops everything. Before this, every exit but enter discarded
	// the ignore marks, so marking packages and then quitting — the natural
	// move when you are adding nothing — silently threw the marks away and the
	// same packages came back next run.
	aborted bool
	// noIgnore hides the ignore key, for mrk brew: Phase 2 installs from the
	// Brewfile and keeps no ignore list, so a mark there had nowhere to go and
	// was dropped (audit 19, W-17). sync, which keeps ~/.mrk/sync-ignore, leaves
	// it false.
	noIgnore bool
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

func (m model) totalIgnored() int {
	n := 0
	for _, c := range m.cats {
		for _, p := range c.pkgs {
			if p.ignored {
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
		case "ctrl+c":
			m.aborted = true
			m.cancelled = true
			return m, tea.Quit
		case "q":
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
						if p.selected {
							p.ignored = false
						}
						if m.pkgIdx < len(pkgs)-1 {
							m.pkgIdx++
						}
					}
				}
			}

		case "i":
			if !m.leftFocus && !m.noIgnore {
				pkgs := m.currentPkgs()
				if m.pkgIdx < len(pkgs) {
					p := pkgs[m.pkgIdx]
					if !p.installed {
						p.ignored = !p.ignored
						if p.ignored {
							p.selected = false
						}
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
						if p.selected {
							p.ignored = false
						}
					}
				}
			}
		}
	}
	return m, nil
}

// ── Styles ────────────────────────────────────────────────────────────────

var (
	// Local aliases for shared theme
	stylePaneOff = theme.StylePaneOff
	stylePaneOn  = theme.StylePaneOn
	styleTitle   = theme.StyleTitle
	styleFooter  = theme.StyleFooter

	// Picker-specific styles
	styleCount     = lipgloss.NewStyle().Bold(true).Foreground(theme.ColAccent)
	styleCatActive = lipgloss.NewStyle().Bold(true).Foreground(theme.ColHighlight)
	styleCatNorm   = lipgloss.NewStyle().Foreground(theme.ColNormal)
	styleBadgeDim  = lipgloss.NewStyle().Foreground(theme.ColSubtle)
	styleInstalled = lipgloss.NewStyle().Foreground(theme.ColDim)
	stylePkgSel    = lipgloss.NewStyle().Foreground(theme.ColGreen)
	stylePkgIgn    = lipgloss.NewStyle().Foreground(theme.ColRed)
	stylePkgCurs   = lipgloss.NewStyle().Bold(true).Foreground(theme.ColHighlight)
	styleDescDim   = lipgloss.NewStyle().Foreground(theme.ColSubtle)
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
	selText := fmt.Sprintf("%d selected", m.totalSelected())
	if ign := m.totalIgnored(); ign > 0 {
		selText += fmt.Sprintf(" · %d ignored", ign)
	}
	sel := styleCount.Render(selText)
	gap := m.width - lipgloss.Width(title) - lipgloss.Width(sel)
	if gap < 1 {
		gap = 1
	}
	return title + strings.Repeat(" ", gap) + sel
}

func (m model) viewFooter() string {
	// Truncated to the terminal width, the way mrk-menu's help line already is.
	//
	// This used to be a bare string carrying the comment "Kept under 80
	// columns: this wraps at the minimum supported width, and a wrapped footer
	// costs a body line." It was 90 columns. So at the 80-column minimum it did
	// wrap, costing exactly the body line the comment was written to protect —
	// and because lipgloss.JoinVertical pads every line to the widest element,
	// the footer also inflated the whole frame to 90, putting ten trailing
	// spaces on every row of an 80-column terminal.
	//
	// Truncating rather than shortening the text keeps the full hint on a wide
	// terminal and stops the width being something a future edit can quietly
	// break again.
	help := "↑↓/jk move · tab/hl pane · space add · i ignore · a all · enter ok · q quit (ignores kept)"
	if m.noIgnore {
		help = "↑↓/jk move · tab/hl pane · space add · a all · enter ok · q quit"
	}
	if m.width > 0 {
		help = theme.Truncate(help, m.width)
	}
	return styleFooter.Render(help)
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
		name := theme.Truncate(cat.name, nameW)
		pad := nameW - len([]rune(name))
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
		} else if p.ignored {
			indicator = stylePkgIgn.Render("✗ ")
		}

		isCursor := i == m.pkgIdx && !m.leftFocus

		name := theme.Truncate(p.name, nameW)
		pad := nameW - len([]rune(name))
		if pad < 0 {
			pad = 0
		}

		desc := p.desc
		if descW > 0 {
			desc = theme.Truncate(desc, descW)
		}

		var line string
		switch {
		case p.installed:
			line = indicator +
				styleInstalled.Render(name) + strings.Repeat(" ", pad+2) +
				styleInstalled.Render(desc)
		case isCursor && p.ignored:
			line = stylePkgCurs.Render("▸ ") +
				stylePkgCurs.Render(name) + strings.Repeat(" ", pad+2) +
				stylePkgIgn.Render(desc)
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
		case p.ignored:
			line = indicator +
				stylePkgIgn.Render(name) + strings.Repeat(" ", pad+2) +
				stylePkgIgn.Render(desc)
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

// emitLines renders the picker's decisions as "type:name" lines. Ignored
// packages take an "ignore-" prefixed type rather than a third field, so the
// caller's `IFS=: read -r a b` split keeps working unchanged.
//
// cancelled means the user left with q or esc. That abandons the pending
// additions but keeps the ignore marks: "never offer this again" is a decision
// already made, and discarding it was why ignoring a package did not stick —
// quitting is the natural move when you are adding nothing, and it used to
// throw every mark away. A ctrl+c abort exits before reaching here.
func emitLines(cats []category, cancelled bool) []string {
	var out []string
	for _, cat := range cats {
		for _, p := range cat.pkgs {
			switch {
			case p.selected && !cancelled:
				out = append(out, fmt.Sprintf("%s:%s", p.kind, p.name))
			case p.ignored:
				out = append(out, fmt.Sprintf("ignore-%s:%s", p.kind, p.name))
			}
		}
	}
	return out
}

type options struct {
	brewfile, installedFormulae, installedCasks string
	skipFormulae, skipCasks, noIgnore           bool
}

// parseFlags reads mrk-picker's command line. flag.ErrHelp means -h was given
// and the flags have been printed; any other error, a wrong command line. A
// stray argument is one: until 2026-09-28 it was never checked, so
// `mrk-picker --brewfile Brewfile bogus` opened the picker as though nothing
// were wrong, where mrk-status and mrk-menu refuse it (audit 19, W-24).
func parseFlags(args []string, errOut io.Writer) (options, error) {
	fs := flag.NewFlagSet("mrk-picker", flag.ContinueOnError)
	fs.SetOutput(errOut)
	var o options
	fs.StringVar(&o.brewfile, "brewfile", "Brewfile", "Path to Brewfile")
	fs.StringVar(&o.installedFormulae, "installed-formulae", "", "Comma-separated installed formulae")
	fs.StringVar(&o.installedCasks, "installed-casks", "", "Comma-separated installed casks")
	fs.BoolVar(&o.skipFormulae, "skip-formulae", false, "Exclude formulae from picker")
	fs.BoolVar(&o.skipCasks, "skip-casks", false, "Exclude casks from picker")
	fs.BoolVar(&o.noIgnore, "no-ignore", false, "Hide the ignore key (mrk brew, which keeps no ignore list)")
	if err := fs.Parse(args); err != nil {
		return o, err
	}
	if fs.NArg() > 0 {
		fs.Usage()
		return o, fmt.Errorf("unexpected argument: %s", fs.Arg(0))
	}
	return o, nil
}

func main() {
	if descriptionsErr != nil {
		fmt.Fprintf(os.Stderr, "mrk-picker: %v\n", descriptionsErr)
		os.Exit(1)
	}

	o, err := parseFlags(os.Args[1:], os.Stderr)
	if errors.Is(err, flag.ErrHelp) {
		os.Exit(0)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "mrk-picker: %v\n", err)
		os.Exit(2)
	}

	installedFormulae := map[string]bool{}
	installedCasks := map[string]bool{}
	for _, s := range strings.Split(o.installedFormulae, ",") {
		if s = strings.TrimSpace(s); s != "" {
			installedFormulae[s] = true
		}
	}
	for _, s := range strings.Split(o.installedCasks, ",") {
		if s = strings.TrimSpace(s); s != "" {
			installedCasks[s] = true
		}
	}

	cats, err := parseBrewfile(o.brewfile, installedFormulae, installedCasks, o.skipFormulae, o.skipCasks)
	if err != nil {
		fmt.Fprintf(os.Stderr, "mrk-picker: %v\n", err)
		os.Exit(1)
	}
	if len(cats) == 0 {
		fmt.Fprintln(os.Stderr, "mrk-picker: no packages found in Brewfile")
		os.Exit(1)
	}

	// Open /dev/tty explicitly so the TUI renders correctly even when
	// stdout is captured by a shell subshell ($(...)).
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		fmt.Fprintf(os.Stderr, "mrk-picker: cannot open terminal: %v\n", err)
		os.Exit(1)
	}
	defer tty.Close()

	m := newModel(cats)
	m.noIgnore = o.noIgnore
	p := tea.NewProgram(m, tea.WithAltScreen(), tea.WithInput(tty), tea.WithOutput(tty))
	final, err := p.Run()
	if err != nil {
		fmt.Fprintf(os.Stderr, "mrk-picker: %v\n", err)
		os.Exit(1)
	}

	result := final.(model)
	if result.aborted {
		os.Exit(1)
	}

	for _, line := range emitLines(result.cats, result.cancelled) {
		fmt.Println(line)
	}
}
