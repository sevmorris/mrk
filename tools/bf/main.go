// bf — interactive Brewfile manager
// Two-pane Bubble Tea TUI: sections (left) | packages (right)
// Directly reads and writes the mrk Brewfile.
package main

import (
	"bufio"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"unicode/utf8"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// ── Types ─────────────────────────────────────────────────────────────────

type pkgKind int

const (
	kindBrew pkgKind = iota
	kindCask
)

func (k pkgKind) String() string {
	if k == kindCask {
		return "cask"
	}
	return "brew"
}

type entry struct {
	lineIdx int
	name    string
	kind    pkgKind
	greedy  bool
}

type section struct {
	name          string
	fullName      string // original comment text
	headerLineIdx int    // -1 if implicit
	entries       []*entry
}

// ── Brewfile ──────────────────────────────────────────────────────────────

var (
	reFormula = regexp.MustCompile(`^brew\s+"([^"]+)"(.*)$`)
	reCask    = regexp.MustCompile(`^cask\s+"([^"]+)"(.*)$`)
	reHeader  = regexp.MustCompile(`^#\s+([A-Z].+)$`)
)

type brewfile struct {
	path     string
	repoRoot string
	lines    []string
	sections []*section
}

func loadBrewfile(path string) (*brewfile, error) {
	f, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer f.Close()

	var lines []string
	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
	}
	if err := scanner.Err(); err != nil {
		return nil, err
	}

	bf := &brewfile{
		path:     path,
		repoRoot: filepath.Dir(path),
		lines:    lines,
	}
	bf.sections = parseLines(lines)
	return bf, nil
}

func sectionFriendlyName(s string) string {
	// "CLI Tools - General Utilities & Power User Tools" → "CLI Tools"
	if idx := strings.Index(s, " - "); idx != -1 {
		s = s[:idx]
	}
	if idx := strings.Index(s, " — "); idx != -1 {
		s = s[:idx]
	}
	return strings.TrimSpace(s)
}

func parseLines(lines []string) []*section {
	var sections []*section
	var cur *section

	push := func(e *entry) {
		if cur == nil {
			cur = &section{name: "General", fullName: "General", headerLineIdx: -1}
			sections = append(sections, cur)
		}
		cur.entries = append(cur.entries, e)
	}

	for i, line := range lines {
		trimmed := strings.TrimSpace(line)

		if m := reHeader.FindStringSubmatch(trimmed); m != nil {
			fullName := strings.TrimSpace(m[1])
			cur = &section{
				name:          sectionFriendlyName(fullName),
				fullName:      fullName,
				headerLineIdx: i,
			}
			sections = append(sections, cur)
			continue
		}

		if strings.HasPrefix(trimmed, "#") {
			continue
		}

		if m := reFormula.FindStringSubmatch(trimmed); m != nil {
			push(&entry{
				lineIdx: i,
				name:    m[1],
				kind:    kindBrew,
				greedy:  strings.Contains(m[2], "greedy"),
			})
			continue
		}

		if m := reCask.FindStringSubmatch(trimmed); m != nil {
			push(&entry{
				lineIdx: i,
				name:    m[1],
				kind:    kindCask,
				greedy:  strings.Contains(m[2], "greedy"),
			})
		}
	}

	// Drop empty sections
	out := sections[:0]
	for _, s := range sections {
		if len(s.entries) > 0 {
			out = append(out, s)
		}
	}
	return out
}

func (bf *brewfile) reload() {
	bf.sections = parseLines(bf.lines)
}

func (bf *brewfile) save() error {
	out := strings.Join(bf.lines, "\n") + "\n"
	return os.WriteFile(bf.path, []byte(out), 0644)
}

func (bf *brewfile) deleteEntry(e *entry) {
	idx := e.lineIdx
	if idx < 0 || idx >= len(bf.lines) {
		return
	}
	bf.lines = append(bf.lines[:idx], bf.lines[idx+1:]...)
	bf.reload()
}

func (bf *brewfile) toggleGreedy(e *entry) {
	if e.kind != kindCask || e.lineIdx < 0 || e.lineIdx >= len(bf.lines) {
		return
	}
	line := bf.lines[e.lineIdx]
	if e.greedy {
		line = strings.Replace(line, `, greedy: true`, "", 1)
		line = strings.Replace(line, `, greedy:true`, "", 1)
	} else {
		line = strings.TrimRight(line, " \t") + ", greedy: true"
	}
	bf.lines[e.lineIdx] = line
	bf.reload()
}

func formatLine(name string, kind pkgKind, greedy bool) string {
	suffix := ""
	if greedy && kind == kindCask {
		suffix = ", greedy: true"
	}
	return fmt.Sprintf(`%s "%s"%s`, kind, name, suffix)
}

// sectionNames returns the full names of all sections (for pickers).
func (bf *brewfile) sectionNames() []string {
	var names []string
	for _, s := range bf.sections {
		names = append(names, s.name)
	}
	return names
}

// addEntry inserts a new package alphabetically within the named section.
func (bf *brewfile) addEntry(name string, kind pkgKind, greedy bool, secName string) {
	newLine := formatLine(name, kind, greedy)

	var target *section
	for _, s := range bf.sections {
		if s.name == secName {
			target = s
			break
		}
	}

	if target == nil || len(target.entries) == 0 {
		bf.lines = append(bf.lines, newLine)
		bf.reload()
		return
	}

	// Find alphabetical insertion point (within same kind where possible)
	insertAt := -1
	for _, e := range target.entries {
		if e.kind == kind && e.name > name {
			insertAt = e.lineIdx
			break
		}
	}
	if insertAt == -1 {
		// After last entry in section
		last := target.entries[len(target.entries)-1]
		insertAt = last.lineIdx + 1
	}

	newLines := make([]string, 0, len(bf.lines)+1)
	newLines = append(newLines, bf.lines[:insertAt]...)
	newLines = append(newLines, newLine)
	newLines = append(newLines, bf.lines[insertAt:]...)
	bf.lines = newLines
	bf.reload()
}

func (bf *brewfile) moveEntry(e *entry, targetSec string) {
	name := e.name
	kind := e.kind
	greedy := e.greedy
	bf.deleteEntry(e)
	bf.addEntry(name, kind, greedy, targetSec)
}

func (bf *brewfile) commit(msg string) error {
	cmd := exec.Command("git", "-C", bf.repoRoot, "add", "Brewfile")
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("git add: %w\n%s", err, out)
	}
	cmd = exec.Command("git", "-C", bf.repoRoot, "commit", "-m", msg)
	if out, err := cmd.CombinedOutput(); err != nil {
		return fmt.Errorf("git commit: %w\n%s", err, out)
	}
	return nil
}

// ── Search ────────────────────────────────────────────────────────────────

type searchResult struct {
	secIdx int
	entIdx int
	name   string
	sec    string
	kind   pkgKind
	greedy bool
}

func (bf *brewfile) search(query string) []searchResult {
	if query == "" {
		return nil
	}
	q := strings.ToLower(query)
	var results []searchResult
	for si, s := range bf.sections {
		for ei, e := range s.entries {
			if strings.Contains(strings.ToLower(e.name), q) {
				results = append(results, searchResult{
					secIdx: si,
					entIdx: ei,
					name:   e.name,
					sec:    s.name,
					kind:   e.kind,
					greedy: e.greedy,
				})
			}
		}
	}
	return results
}

// ── Descriptions ──────────────────────────────────────────────────────────

type descMsg map[string]string

func fetchSectionDescs(entries []*entry) tea.Cmd {
	return func() tea.Msg {
		result := make(map[string]string)

		var formulas, casks []string
		for _, e := range entries {
			if e.kind == kindBrew {
				formulas = append(formulas, e.name)
			} else {
				casks = append(casks, e.name)
			}
		}

		fetch := func(kind string, names []string) {
			if len(names) == 0 {
				return
			}
			args := append([]string{"desc", "--" + kind}, names...)
			out, err := exec.Command("brew", args...).Output()
			if err != nil {
				return
			}
			for _, line := range strings.Split(string(out), "\n") {
				if idx := strings.Index(line, ": "); idx != -1 {
					name := strings.TrimSpace(line[:idx])
					desc := strings.TrimSpace(line[idx+2:])
					result[name] = desc
				}
			}
		}

		fetch("formula", formulas)
		fetch("cask", casks)
		return descMsg(result)
	}
}

func (m model) missingDescs(entries []*entry) []*entry {
	var missing []*entry
	for _, e := range entries {
		if _, ok := m.descCache[e.name]; !ok {
			missing = append(missing, e)
		}
	}
	return missing
}

// ── TUI State ─────────────────────────────────────────────────────────────

type viewState int

const (
	stateNormal viewState = iota
	stateSearch
	stateAddName
	stateAddKind
	stateAddSection
	stateMove
	stateDeleteConfirm
	stateCommit
)

type model struct {
	bf *brewfile

	// Normal navigation
	secIdx    int
	entIdx    int
	leftFocus bool

	// Description cache (keyed by package name)
	descCache map[string]string

	// Search
	searchQuery   string
	searchResults []searchResult
	searchIdx     int

	// Add flow
	addName    string
	addKind    pkgKind
	addKindIdx int
	addSecIdx  int

	// Move
	moveSecIdx int

	// Text input
	inputBuf string

	// UI
	width  int
	height int
	state  viewState
	dirty  bool
	flash  string
}

func newModel(bf *brewfile) model {
	return model{bf: bf, leftFocus: true}
}

func (m model) Init() tea.Cmd {
	sec := m.currentSection()
	if sec == nil {
		return nil
	}
	return fetchSectionDescs(sec.entries)
}

// ── Update ────────────────────────────────────────────────────────────────

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height
	case tea.KeyMsg:
		return m.handleKey(msg)
	case descMsg:
		if m.descCache == nil {
			m.descCache = make(map[string]string)
		}
		for k, v := range msg {
			m.descCache[k] = v
		}
	}
	return m, nil
}

func (m model) handleKey(msg tea.KeyMsg) (model, tea.Cmd) {
	key := msg.String()

	// Global
	if key == "ctrl+c" {
		return m, tea.Quit
	}

	switch m.state {
	case stateNormal:
		return m.handleNormal(key)
	case stateSearch:
		return m.handleSearch(key, msg)
	case stateAddName:
		return m.handleInputState(key, msg, func(m model) model {
			m.addName = strings.TrimSpace(m.inputBuf)
			m.inputBuf = ""
			m.state = stateAddKind
			m.addKindIdx = 0
			return m
		})
	case stateAddKind:
		return m.handleAddKind(key)
	case stateAddSection:
		return m.handleAddSection(key)
	case stateMove:
		return m.handleMove(key)
	case stateDeleteConfirm:
		return m.handleDeleteConfirm(key)
	case stateCommit:
		return m.handleInputState(key, msg, func(m model) model {
			msg := strings.TrimSpace(m.inputBuf)
			if msg == "" {
				m.state = stateNormal
				return m
			}
			if err := m.bf.commit(msg); err != nil {
				m.flash = "commit failed: " + err.Error()
			} else {
				m.flash = "committed: " + msg
				m.dirty = false
			}
			m.inputBuf = ""
			m.state = stateNormal
			return m
		})
	}
	return m, nil
}

func (m model) handleNormal(key string) (model, tea.Cmd) {
	m.flash = ""
	prevSec := m.secIdx
	switch key {
	case "q", "esc":
		return m, tea.Quit

	// Pane navigation
	case "tab", "shift+tab":
		m.leftFocus = !m.leftFocus
	case "left", "h":
		m.leftFocus = true
	case "right", "l":
		if m.currentSection() != nil {
			m.leftFocus = false
		}

	// Section navigation (left pane)
	case "up", "k":
		if m.leftFocus {
			if m.secIdx > 0 {
				m.secIdx--
				m.entIdx = 0
			}
		} else {
			if m.entIdx > 0 {
				m.entIdx--
			}
		}
	case "down", "j":
		if m.leftFocus {
			if m.secIdx < len(m.bf.sections)-1 {
				m.secIdx++
				m.entIdx = 0
			}
		} else {
			sec := m.currentSection()
			if sec != nil && m.entIdx < len(sec.entries)-1 {
				m.entIdx++
			}
		}

	// Actions
	case "a":
		m.inputBuf = ""
		m.state = stateAddName
	case "d":
		if m.currentEntry() != nil {
			m.state = stateDeleteConfirm
		}
	case "m":
		if m.currentEntry() != nil {
			m.moveSecIdx = m.secIdx
			m.state = stateMove
		}
	case "g":
		if e := m.currentEntry(); e != nil {
			if e.kind != kindCask {
				m.flash = "greedy only applies to casks"
			} else {
				m.bf.toggleGreedy(e)
				m.bf.reload()
				m.dirty = true
				m.flash = "toggled greedy"
				m.clampCursor()
			}
		}
	case "/":
		m.searchQuery = ""
		m.inputBuf = ""
		m.searchResults = nil
		m.searchIdx = 0
		m.state = stateSearch
	case "w":
		if err := m.bf.save(); err != nil {
			m.flash = "save failed: " + err.Error()
		} else {
			m.flash = "saved"
			m.dirty = false
		}
	case "c":
		if !m.dirty {
			m.flash = "no unsaved changes to commit"
		} else {
			if err := m.bf.save(); err != nil {
				m.flash = "save failed: " + err.Error()
				break
			}
			m.dirty = false
			m.inputBuf = "Brewfile: "
			m.state = stateCommit
		}
	}

	var cmd tea.Cmd
	if m.secIdx != prevSec {
		if sec := m.currentSection(); sec != nil {
			if missing := m.missingDescs(sec.entries); len(missing) > 0 {
				cmd = fetchSectionDescs(missing)
			}
		}
	}
	return m, cmd
}

func (m model) handleSearch(key string, msg tea.KeyMsg) (model, tea.Cmd) {
	switch key {
	case "esc":
		m.state = stateNormal
		m.searchQuery = ""
		m.searchResults = nil
	case "enter":
		if len(m.searchResults) > 0 && m.searchIdx < len(m.searchResults) {
			r := m.searchResults[m.searchIdx]
			m.secIdx = r.secIdx
			m.entIdx = r.entIdx
			m.leftFocus = false
		}
		m.state = stateNormal
		m.searchQuery = ""
		m.searchResults = nil
	case "up", "k":
		if m.searchIdx > 0 {
			m.searchIdx--
		}
	case "down", "j":
		if m.searchIdx < len(m.searchResults)-1 {
			m.searchIdx++
		}
	case "backspace", "ctrl+h":
		if len(m.inputBuf) > 0 {
			_, size := utf8.DecodeLastRuneInString(m.inputBuf)
			m.inputBuf = m.inputBuf[:len(m.inputBuf)-size]
			m.searchQuery = m.inputBuf
			m.searchResults = m.bf.search(m.searchQuery)
			m.searchIdx = 0
		}
	default:
		if len(msg.Runes) > 0 {
			m.inputBuf += string(msg.Runes)
			m.searchQuery = m.inputBuf
			m.searchResults = m.bf.search(m.searchQuery)
			m.searchIdx = 0
		}
	}
	return m, nil
}

func (m model) handleAddKind(key string) (model, tea.Cmd) {
	switch key {
	case "esc":
		m.state = stateNormal
	case "up", "k", "left", "h":
		m.addKindIdx = 0
	case "down", "j", "right", "l":
		m.addKindIdx = 1
	case "enter", " ":
		if m.addKindIdx == 0 {
			m.addKind = kindBrew
		} else {
			m.addKind = kindCask
		}
		m.addSecIdx = m.secIdx
		m.state = stateAddSection
	}
	return m, nil
}

func (m model) handleAddSection(key string) (model, tea.Cmd) {
	secs := m.bf.sections
	switch key {
	case "esc":
		m.state = stateNormal
	case "up", "k":
		if m.addSecIdx > 0 {
			m.addSecIdx--
		}
	case "down", "j":
		if m.addSecIdx < len(secs)-1 {
			m.addSecIdx++
		}
	case "enter":
		if m.addSecIdx < len(secs) {
			secName := secs[m.addSecIdx].name
			m.bf.addEntry(m.addName, m.addKind, false, secName)
			m.dirty = true
			m.flash = fmt.Sprintf("added %s \"%s\"", m.addKind, m.addName)
			// Navigate to new entry
			m.secIdx = m.addSecIdx
			m.leftFocus = false
			m.clampCursor()
			// Find the new entry
			if sec := m.currentSection(); sec != nil {
				for i, e := range sec.entries {
					if e.name == m.addName {
						m.entIdx = i
						break
					}
				}
			}
		}
		m.state = stateNormal
	}
	return m, nil
}

func (m model) handleMove(key string) (model, tea.Cmd) {
	secs := m.bf.sections
	switch key {
	case "esc":
		m.state = stateNormal
	case "up", "k":
		if m.moveSecIdx > 0 {
			m.moveSecIdx--
		}
	case "down", "j":
		if m.moveSecIdx < len(secs)-1 {
			m.moveSecIdx++
		}
	case "enter":
		e := m.currentEntry()
		if e != nil && m.moveSecIdx < len(secs) {
			targetName := secs[m.moveSecIdx].name
			if targetName == m.currentSection().name {
				m.flash = "already in that section"
				m.state = stateNormal
				break
			}
			entName := e.name
			m.bf.moveEntry(e, targetName)
			m.dirty = true
			m.flash = fmt.Sprintf("moved \"%s\" → %s", entName, targetName)
			// Navigate to moved entry
			for si, s := range m.bf.sections {
				if s.name == targetName {
					m.secIdx = si
					m.entIdx = 0
					for ei, en := range s.entries {
						if en.name == entName {
							m.entIdx = ei
							break
						}
					}
					break
				}
			}
			m.leftFocus = false
		}
		m.state = stateNormal
	}
	return m, nil
}

func (m model) handleDeleteConfirm(key string) (model, tea.Cmd) {
	switch key {
	case "y", "d", "enter":
		if e := m.currentEntry(); e != nil {
			name := e.name
			m.bf.deleteEntry(e)
			m.dirty = true
			m.flash = fmt.Sprintf("removed \"%s\"", name)
			m.clampCursor()
		}
		m.state = stateNormal
	default:
		m.state = stateNormal
		m.flash = "cancelled"
	}
	return m, nil
}

// handleInputState processes a text input field and calls done when Enter is pressed.
func (m model) handleInputState(key string, msg tea.KeyMsg, done func(model) model) (model, tea.Cmd) {
	switch key {
	case "esc":
		m.inputBuf = ""
		m.state = stateNormal
	case "enter":
		if strings.TrimSpace(m.inputBuf) != "" {
			m = done(m)
		}
	case "backspace", "ctrl+h":
		if len(m.inputBuf) > 0 {
			_, size := utf8.DecodeLastRuneInString(m.inputBuf)
			m.inputBuf = m.inputBuf[:len(m.inputBuf)-size]
		}
	default:
		if len(msg.Runes) > 0 {
			m.inputBuf += string(msg.Runes)
		}
	}
	return m, nil
}

// ── Helpers ───────────────────────────────────────────────────────────────

func (m model) currentSection() *section {
	if m.secIdx < len(m.bf.sections) {
		return m.bf.sections[m.secIdx]
	}
	return nil
}

func (m model) currentEntry() *entry {
	sec := m.currentSection()
	if sec == nil {
		return nil
	}
	if m.entIdx < len(sec.entries) {
		return sec.entries[m.entIdx]
	}
	return nil
}

func (m *model) clampCursor() {
	if m.secIdx >= len(m.bf.sections) {
		m.secIdx = max(0, len(m.bf.sections)-1)
	}
	sec := m.currentSection()
	if sec != nil && m.entIdx >= len(sec.entries) {
		m.entIdx = max(0, len(sec.entries)-1)
	}
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func min(a, b int) int {
	if a < b {
		return a
	}
	return b
}

func truncate(s string, n int) string {
	runes := []rune(s)
	if len(runes) <= n {
		return s
	}
	if n <= 1 {
		return "…"
	}
	return string(runes[:n-1]) + "…"
}

func padRight(s string, n int) string {
	w := lipgloss.Width(s)
	if w >= n {
		return s
	}
	return s + strings.Repeat(" ", n-w)
}

// ── Styles ────────────────────────────────────────────────────────────────

var (
	colSubtle    = lipgloss.AdaptiveColor{Light: "#888888", Dark: "#555555"}
	colDim       = lipgloss.AdaptiveColor{Light: "#aaaaaa", Dark: "#444444"}
	colNormal    = lipgloss.AdaptiveColor{Light: "#222222", Dark: "#cccccc"}
	colHighlight = lipgloss.AdaptiveColor{Light: "#d7005f", Dark: "#ff87af"}
	colAccent    = lipgloss.AdaptiveColor{Light: "#005fd7", Dark: "#87d7ff"}
	colGreen     = lipgloss.AdaptiveColor{Light: "#00875f", Dark: "#5fd7a7"}
	colAmber     = lipgloss.AdaptiveColor{Light: "#875f00", Dark: "#ffd787"}
	colRed       = lipgloss.AdaptiveColor{Light: "#af0000", Dark: "#ff8787"}

	stylePaneOff = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(colSubtle)

	stylePaneOn = lipgloss.NewStyle().
			Border(lipgloss.RoundedBorder()).
			BorderForeground(colAccent)

	styleTitle     = lipgloss.NewStyle().Bold(true).Foreground(colNormal)
	styleCount     = lipgloss.NewStyle().Foreground(colAccent)
	styleFooter    = lipgloss.NewStyle().Foreground(colSubtle)
	styleFlash     = lipgloss.NewStyle().Foreground(colGreen)
	styleFlashWarn = lipgloss.NewStyle().Foreground(colAmber)
	styleDirty     = lipgloss.NewStyle().Foreground(colAmber)
	styleCatActive = lipgloss.NewStyle().Bold(true).Foreground(colHighlight)
	styleCatNorm   = lipgloss.NewStyle().Foreground(colNormal)
	styleBadge     = lipgloss.NewStyle().Foreground(colSubtle)
	styleEntCursor = lipgloss.NewStyle().Bold(true).Foreground(colHighlight)
	styleEntNorm   = lipgloss.NewStyle().Foreground(colNormal)
	styleGreedy    = lipgloss.NewStyle().Foreground(colAccent)
	styleDim       = lipgloss.NewStyle().Foreground(colDim)
	styleInput     = lipgloss.NewStyle().Foreground(colNormal)
	styleInputPfx  = lipgloss.NewStyle().Foreground(colAccent).Bold(true)
	stylePrompt    = lipgloss.NewStyle().Foreground(colAmber).Bold(true)
	styleSearchHit = lipgloss.NewStyle().Foreground(colHighlight).Bold(true)
	styleSearchSec = lipgloss.NewStyle().Foreground(colSubtle)
	styleKindSel   = lipgloss.NewStyle().Bold(true).Foreground(colHighlight)
	styleKindNorm  = lipgloss.NewStyle().Foreground(colNormal)
	styleDelete    = lipgloss.NewStyle().Foreground(colRed).Bold(true)
)

// ── View ──────────────────────────────────────────────────────────────────

func (m model) View() string {
	if m.width == 0 {
		return "Loading…"
	}

	header := m.viewHeader()
	footer := m.viewFooter()
	body := m.viewBody()

	return lipgloss.JoinVertical(lipgloss.Left, header, body, footer)
}

func (m model) viewHeader() string {
	left := styleTitle.Render("bf") + styleFooter.Render("  Brewfile Manager")
	dirtyMark := ""
	if m.dirty {
		dirtyMark = styleDirty.Render(" ●")
	}
	path := styleFooter.Render(m.bf.path) + dirtyMark
	gap := m.width - lipgloss.Width(left) - lipgloss.Width(path)
	if gap < 1 {
		gap = 1
	}
	return left + strings.Repeat(" ", gap) + path
}

func (m model) viewFooter() string {
	switch m.state {
	case stateAddName:
		return styleInputPfx.Render(" add › name: ") + styleInput.Render(m.inputBuf+"█")
	case stateAddKind:
		brew := styleKindNorm.Render("  brew  ")
		cask := styleKindNorm.Render("  cask  ")
		if m.addKindIdx == 0 {
			brew = styleKindSel.Render("▸ brew  ")
		} else {
			cask = styleKindSel.Render("▸ cask  ")
		}
		return styleInputPfx.Render(" add › type: ") + brew + cask + styleFooter.Render("  ↑↓ choose · enter confirm · esc cancel")
	case stateDeleteConfirm:
		e := m.currentEntry()
		if e == nil {
			return ""
		}
		return styleDelete.Render(fmt.Sprintf(" delete \"%s\"? ", e.name)) +
			stylePrompt.Render("[y]") + styleFooter.Render("es  ") +
			stylePrompt.Render("[n]") + styleFooter.Render("o")
	case stateCommit:
		return styleInputPfx.Render(" commit: ") + styleInput.Render(m.inputBuf+"█")
	case stateSearch:
		indicator := styleInputPfx.Render(" / ")
		n := ""
		if len(m.searchResults) > 0 {
			n = styleCount.Render(fmt.Sprintf(" (%d)", len(m.searchResults)))
		}
		return indicator + styleInput.Render(m.inputBuf+"█") + n +
			styleFooter.Render("  ↑↓ navigate · enter jump · esc cancel")
	default:
		var flashStr string
		if m.flash != "" {
			if strings.Contains(m.flash, "fail") || strings.Contains(m.flash, "only") {
				flashStr = "  " + styleFlashWarn.Render(m.flash)
			} else {
				flashStr = "  " + styleFlash.Render(m.flash)
			}
		}
		hints := styleFooter.Render("[a]dd [d]el [m]ove [g]reedy [/]search [w]rite [c]ommit [q]uit")
		return hints + flashStr
	}
}

func (m model) viewBody() string {
	// Height: total - header(1) - footer(1)
	bodyH := m.height - 2
	if bodyH < 4 {
		bodyH = 4
	}

	switch m.state {
	case stateSearch:
		return m.viewSearch(bodyH)
	case stateAddSection:
		return m.viewSectionPicker("add › section:", m.addSecIdx, bodyH)
	case stateMove:
		return m.viewSectionPicker("move › section:", m.moveSecIdx, bodyH)
	default:
		return m.viewTwoPanes(bodyH)
	}
}

func (m model) viewTwoPanes(bodyH int) string {
	const leftInner = 22
	rightInner := m.width - leftInner - 4
	if rightInner < 10 {
		rightInner = 10
	}
	paneH := bodyH - 2 // border top + bottom
	if paneH < 1 {
		paneH = 1
	}

	left := m.viewLeft(leftInner, paneH)
	right := m.viewRight(rightInner, paneH)
	return lipgloss.JoinHorizontal(lipgloss.Top, left, right)
}

func (m model) viewLeft(inner, height int) string {
	var sb strings.Builder
	lines := 0

	start := 0
	if m.secIdx >= height {
		start = m.secIdx - height + 1
	}

	for i, sec := range m.bf.sections {
		if i < start || lines >= height {
			continue
		}
		badge := styleBadge.Render(fmt.Sprintf("(%d)", len(sec.entries)))
		nameW := inner - lipgloss.Width(badge) - 3
		if nameW < 1 {
			nameW = 1
		}
		name := truncate(sec.name, nameW)
		pad := strings.Repeat(" ", max(0, nameW-lipgloss.Width(name)))

		var line string
		if i == m.secIdx {
			pfx := "▸ "
			if m.leftFocus {
				line = styleCatActive.Render(pfx+name) + pad + styleCount.Render(badge)
			} else {
				line = styleCatNorm.Render(pfx+name) + pad + styleBadge.Render(badge)
			}
		} else {
			line = styleCatNorm.Render("  "+name) + pad + styleBadge.Render(badge)
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
	pane := stylePaneOff
	if !m.leftFocus {
		pane = stylePaneOn
	}

	sec := m.currentSection()
	if sec == nil || len(sec.entries) == 0 {
		return pane.Width(inner).Height(height).Render(styleDim.Render("empty section"))
	}

	// Show section full name as a dim header
	header := styleDim.Render(truncate(sec.fullName, inner))
	headerLines := 1
	pkgH := height - headerLines - 1
	if pkgH < 1 {
		pkgH = 1
	}

	start := 0
	if m.entIdx >= pkgH {
		start = m.entIdx - pkgH + 1
	}

	// Column widths: cursor(2) + name(nameW) + gap(2) + kind(4) + greedy(2) + gap(2) + desc(rest)
	const kindW = 4
	const greedyW = 2
	const fixedOverhead = 2 + 2 + kindW + greedyW + 2 // cursor + gap + kind + greedy + gap

	// Size name column to longest name in section, capped at 35
	maxNameLen := 0
	for _, e := range sec.entries {
		if l := len([]rune(e.name)); l > maxNameLen {
			maxNameLen = l
		}
	}
	nameW := min(maxNameLen, 35)
	descW := inner - nameW - fixedOverhead
	if descW < 0 {
		descW = 0
		nameW = inner - fixedOverhead
	}
	if nameW < 8 {
		nameW = 8
	}

	var sb strings.Builder
	written := 0
	for i, e := range sec.entries {
		if i < start || written >= pkgH {
			continue
		}

		isCursor := i == m.entIdx && !m.leftFocus

		name := truncate(e.name, nameW)
		name = padRight(name, nameW)

		kindBadge := styleDim.Render(padRight(e.kind.String(), kindW))
		greedyMark := "  "
		if e.greedy {
			greedyMark = styleGreedy.Render("◆ ")
		}

		desc := ""
		if descW > 0 {
			if d, ok := m.descCache[e.name]; ok {
				desc = "  " + styleDim.Render(truncate(d, descW))
			}
		}

		var line string
		if isCursor {
			line = styleEntCursor.Render("▸ ") +
				styleEntCursor.Render(name) + "  " +
				kindBadge + greedyMark + desc
		} else {
			line = "  " +
				styleEntNorm.Render(name) + "  " +
				kindBadge + greedyMark + desc
		}
		sb.WriteString(line + "\n")
		written++
	}

	content := header + "\n" + strings.TrimRight(sb.String(), "\n")
	return pane.Width(inner).Height(height).Render(content)
}

func (m model) viewSearch(bodyH int) string {
	paneH := bodyH - 2
	if paneH < 1 {
		paneH = 1
	}
	inner := m.width - 4
	if inner < 10 {
		inner = 10
	}

	var sb strings.Builder
	written := 0

	start := 0
	if m.searchIdx >= paneH {
		start = m.searchIdx - paneH + 1
	}

	if len(m.searchResults) == 0 {
		if m.searchQuery != "" {
			sb.WriteString(styleDim.Render("no matches"))
		}
	} else {
		nameW := inner - 20
		if nameW < 10 {
			nameW = 10
		}
		for i, r := range m.searchResults {
			if i < start || written >= paneH {
				continue
			}
			isCursor := i == m.searchIdx
			name := padRight(truncate(r.name, nameW), nameW)
			sec := truncate(r.sec, 16)
			kind := styleDim.Render(padRight(r.kind.String(), 4))

			var line string
			if isCursor {
				line = styleSearchHit.Render("▸ "+name) + "  " + kind + "  " + styleSearchSec.Render(sec)
			} else {
				line = "  " + styleEntNorm.Render(name) + "  " + kind + "  " + styleSearchSec.Render(sec)
			}
			sb.WriteString(line + "\n")
			written++
		}
	}

	content := strings.TrimRight(sb.String(), "\n")
	return stylePaneOn.Width(inner).Height(paneH).Render(content)
}

func (m model) viewSectionPicker(label string, cursor int, bodyH int) string {
	inner := m.width - 4
	paneH := bodyH - 2
	if paneH < 1 {
		paneH = 1
	}

	start := 0
	if cursor >= paneH {
		start = cursor - paneH + 1
	}

	var sb strings.Builder
	sb.WriteString(styleInputPfx.Render(" "+label) + "\n")
	written := 1

	for i, sec := range m.bf.sections {
		if i < start || written >= paneH {
			continue
		}
		badge := styleBadge.Render(fmt.Sprintf("(%d)", len(sec.entries)))
		nameW := inner - lipgloss.Width(badge) - 4
		name := truncate(sec.name, nameW)

		var line string
		if i == cursor {
			line = styleKindSel.Render("▸ "+name) + "  " + badge
		} else {
			line = "  " + styleKindNorm.Render(name) + "  " + badge
		}
		sb.WriteString(line + "\n")
		written++
	}

	content := strings.TrimRight(sb.String(), "\n")
	return stylePaneOn.Width(inner).Height(paneH).Render(content)
}

// ── Main ──────────────────────────────────────────────────────────────────

func defaultBrewfilePath() string {
	home, err := os.UserHomeDir()
	if err != nil {
		return "Brewfile"
	}
	return filepath.Join(home, "mrk", "Brewfile")
}

func main() {
	path := defaultBrewfilePath()
	if len(os.Args) > 1 {
		path = os.Args[1]
	}

	bf, err := loadBrewfile(path)
	if err != nil {
		fmt.Fprintf(os.Stderr, "bf: cannot load Brewfile: %v\n", err)
		os.Exit(1)
	}
	if len(bf.sections) == 0 {
		fmt.Fprintln(os.Stderr, "bf: no packages found in Brewfile")
		os.Exit(1)
	}

	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		fmt.Fprintf(os.Stderr, "bf: cannot open terminal: %v\n", err)
		os.Exit(1)
	}
	defer tty.Close()

	p := tea.NewProgram(
		newModel(bf),
		tea.WithAltScreen(),
		tea.WithInput(tty),
		tea.WithOutput(tty),
	)
	if _, err := p.Run(); err != nil {
		fmt.Fprintf(os.Stderr, "bf: %v\n", err)
		os.Exit(1)
	}
}
