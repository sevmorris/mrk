package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
	"mrk-theme"
)

type cmdType int

const (
	cmdBin cmdType = iota
	cmdMake
)

type item struct {
	name      string
	desc      string
	cmdType   cmdType
	target    string
	args      []string
	needsNuke bool
}

type category struct {
	name  string
	items []item
}

var categories = []category{
	{
		name: "Brewfile",
		items: []item{
			{"bf", "interactive Brewfile manager", cmdBin, "bf", nil, false},
			{"sync", "diff installed packages, add missing to Brewfile", cmdBin, "sync", nil, false},
			{"sync --prune", "remove Brewfile entries for uninstalled packages", cmdBin, "sync", []string{"--prune"}, false},
			{"sync --dry-run", "show what sync would do, no changes", cmdBin, "sync", []string{"--dry-run"}, false},
			{"snapshot", "export selected app prefs to assets/preferences/", cmdBin, "snapshot", nil, false},
		},
	},
	{
		name: "Login items",
		items: []item{
			{"sync-login-items", "diff and sync system login items", cmdBin, "sync-login-items", nil, false},
		},
	},
	{
		name: "Preferences",
		items: []item{
			{"snapshot-prefs", "export and push app prefs to mrk-prefs", cmdBin, "snapshot-prefs", nil, false},
			{"pull-prefs", "clone or update app prefs from mrk-prefs", cmdBin, "pull-prefs", nil, false},
		},
	},
	{
		name: "System state",
		items: []item{
			{"make defaults", "apply macOS defaults", cmdMake, "defaults", nil, false},
			{"make harden", "apply security hardening (Touch ID sudo, firewall)", cmdMake, "harden", nil, false},
			{"make trackpad", "apply defaults including trackpad", cmdMake, "trackpad", nil, false},
			{"make dotfiles", "relink dotfiles", cmdMake, "dotfiles", nil, false},
			{"make tools", "relink scripts and bin into ~/bin", cmdMake, "tools", nil, false},
		},
	},
	{
		name: "Diagnostics",
		items: []item{
			{"mrk-status", "health dashboard", cmdBin, "mrk-status", nil, false},
			{"make doctor", "check ~/bin is on PATH", cmdMake, "doctor", nil, false},
			{"make doctor ARGS=--fix", "also fix PATH if missing", cmdMake, "doctor", []string{"ARGS=--fix"}, false},
		},
	},
	{
		name: "Maintenance",
		items: []item{
			{"make update", "upgrade packages (topgrade or brew upgrade)", cmdMake, "update", nil, false},
			{"make updates", "run macOS software updates", cmdMake, "updates", nil, false},
			{"make tidy", "go mod tidy in all tool directories", cmdMake, "tidy", nil, false},
			{"make fix-exec", "make all scripts and bin files executable", cmdMake, "fix-exec", nil, false},
		},
	},
	{
		name: "Nuclear options",
		items: []item{
			{"nuke-mrk", "remove all mrk symlinks and undo setup", cmdBin, "nuke-mrk", nil, true},
		},
	},
}

type state int

const (
	stateFocusCat state = iota
	stateFocusItem
	stateNukeConfirm
	stateHelp
)

type model struct {
	state       state
	prevState   state
	cursorCat   int
	cursorItems []int

	nukeInput string
	flashMsg  string

	width  int
	height int
}

type execFinishedMsg struct {
	err  error
	item item
}

func initialModel() model {
	return model{
		state:       stateFocusCat,
		cursorItems: make([]int, len(categories)),
	}
}

func (m model) Init() tea.Cmd {
	return nil
}

func (m model) runCmd(i item) tea.Cmd {
	var cmd *exec.Cmd
	if i.cmdType == cmdBin {
		cmd = exec.Command(i.target, i.args...)
	} else {
		mrkRoot := os.Getenv("MRK_ROOT")
		if mrkRoot == "" {
			home, err := os.UserHomeDir()
			if err != nil {
				home = "~"
			}
			mrkRoot = filepath.Join(home, "mrk")
		}
		args := []string{"-C", mrkRoot, i.target}
		args = append(args, i.args...)
		cmd = exec.Command("make", args...)
	}

	return tea.ExecProcess(cmd, func(err error) tea.Msg {
		return execFinishedMsg{err: err, item: i}
	})
}

func (m model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width = msg.Width
		m.height = msg.Height

	case tea.KeyMsg:
		switch m.state {
		case stateFocusCat:
			switch msg.String() {
			case "q", "ctrl+c":
				return m, tea.Quit
			case "j", "down":
				m.cursorCat++
				if m.cursorCat >= len(categories) {
					m.cursorCat = len(categories) - 1
				}
				m.flashMsg = ""
			case "k", "up":
				m.cursorCat--
				if m.cursorCat < 0 {
					m.cursorCat = 0
				}
				m.flashMsg = ""
			case "enter", "right", "l":
				m.state = stateFocusItem
				m.flashMsg = ""
			case "?":
				m.prevState = m.state
				m.state = stateHelp
				m.flashMsg = ""
			}

		case stateFocusItem:
			switch msg.String() {
			case "q", "ctrl+c":
				return m, tea.Quit
			case "esc", "left", "h":
				m.state = stateFocusCat
				m.flashMsg = ""
				return m, tea.ClearScreen
			case "j", "down":
				m.cursorItems[m.cursorCat]++
				max := len(categories[m.cursorCat].items) - 1
				if m.cursorItems[m.cursorCat] > max {
					m.cursorItems[m.cursorCat] = max
				}
				m.flashMsg = ""
			case "k", "up":
				m.cursorItems[m.cursorCat]--
				if m.cursorItems[m.cursorCat] < 0 {
					m.cursorItems[m.cursorCat] = 0
				}
				m.flashMsg = ""
			case "enter", "right", "l":
				item := categories[m.cursorCat].items[m.cursorItems[m.cursorCat]]
				if item.needsNuke {
					m.state = stateNukeConfirm
					m.nukeInput = ""
					m.flashMsg = ""
				} else {
					return m, m.runCmd(item)
				}
			case "?":
				m.prevState = m.state
				m.state = stateHelp
				m.flashMsg = ""
			}

		case stateNukeConfirm:
			m.flashMsg = ""
			switch msg.Type {
			case tea.KeyCtrlC, tea.KeyEsc:
				m.state = stateFocusItem
				m.nukeInput = ""
				m.flashMsg = "Canceled nuke operation."
			case tea.KeyEnter:
				if m.nukeInput == "nuke" {
					item := categories[m.cursorCat].items[m.cursorItems[m.cursorCat]]
					m.state = stateFocusItem
					m.nukeInput = ""
					return m, m.runCmd(item)
				} else {
					m.state = stateFocusItem
					m.nukeInput = ""
					m.flashMsg = "Canceled nuke operation (incorrect input)."
				}
			case tea.KeyBackspace, tea.KeyDelete:
				if len(m.nukeInput) > 0 {
					m.nukeInput = m.nukeInput[:len(m.nukeInput)-1]
				}
			case tea.KeyRunes:
				m.nukeInput += string(msg.Runes)
			}

		case stateHelp:
			switch msg.String() {
			case "q", "ctrl+c":
				return m, tea.Quit
			case "esc", "enter":
				m.state = m.prevState
				return m, tea.ClearScreen
			}
		}

	case execFinishedMsg:
		if msg.err != nil {
			var exitErr *exec.ExitError
			if errors.As(msg.err, &exitErr) {
				m.flashMsg = fmt.Sprintf("%s exited with status %d", msg.item.name, exitErr.ExitCode())
			} else {
				m.flashMsg = fmt.Sprintf("%s failed to launch: %v", msg.item.name, msg.err)
			}
		} else {
			m.flashMsg = ""
		}
		return m, tea.ClearScreen
	}

	return m, nil
}

// Layout sizing:
//   - Anything smaller than (minTermW × minTermH) shows a "resize" message.
//   - The window box width is capped at preferredW and shrinks to fit smaller terminals.
//   - The window box height is content-driven (lipgloss expands to fit) but the
//     panes inside are sized to leave room for the chrome on small terminals.
//   - The left pane is fixed at leftPaneW; the right pane gets the rest.
const (
	minTermW   = 80
	minTermH   = 22
	preferredW = 100
	leftPaneW  = 30
	// chromeLines is the number of vertical lines outside the panes:
	// window border (2) + window padding (2) + header (1) + header margin (1) +
	// flash row (1) + spacer (1) + spacer-after-panes (1) + help margin (1) + help (1).
	chromeLines = 11
	maxPaneH    = 24
	minPaneH    = 6
)

var (
	styleHeader     = lipgloss.NewStyle().Bold(true).Foreground(theme.ColNormal).MarginBottom(1)
	styleSelected   = lipgloss.NewStyle().Foreground(theme.ColAccent).Bold(true)
	styleNormal     = lipgloss.NewStyle().Foreground(theme.ColNormal)
	styleDesc       = lipgloss.NewStyle().Foreground(theme.ColSubtle)
	styleCmd        = lipgloss.NewStyle().Foreground(theme.ColDim)
	styleWarning    = lipgloss.NewStyle().Foreground(theme.ColAmber)
	styleHelp       = lipgloss.NewStyle().Foreground(theme.ColSubtle).MarginTop(1)
	styleHelpKey    = lipgloss.NewStyle().Foreground(theme.ColAccent).Bold(true)
	styleNukePrompt = lipgloss.NewStyle().Foreground(theme.ColAccent).Bold(true)
)

func paneCatStyle(focused bool, w, h int) lipgloss.Style {
	border := theme.ColSubtle
	if focused {
		border = theme.ColAccent
	}
	return lipgloss.NewStyle().
		Width(w).Height(h).
		PaddingRight(2).
		BorderRight(true).
		BorderStyle(lipgloss.NormalBorder()).
		BorderForeground(border)
}

func paneItemStyle(w, h int) lipgloss.Style {
	return lipgloss.NewStyle().PaddingLeft(2).Width(w).Height(h)
}

func windowStyle(w int) lipgloss.Style {
	return lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(theme.ColSubtle).
		Padding(1, 2).
		Width(w)
}

func (m model) View() string {
	if m.width == 0 || m.height == 0 {
		return ""
	}
	if m.width < minTermW || m.height < minTermH {
		msg := fmt.Sprintf("Terminal too small (%d×%d). Resize to at least %d×%d.",
			m.width, m.height, minTermW, minTermH)
		return lipgloss.Place(m.width, m.height, lipgloss.Center, lipgloss.Center,
			styleWarning.Render(msg))
	}

	// Target outer width on screen: cap at preferredW, shrink to fit smaller terminals.
	outerW := preferredW
	if outerW > m.width {
		outerW = m.width
	}
	// lipgloss Width(N) sets the rendered width *including padding but excluding
	// border*, so subtract 2 (border left + right) to get the Width value.
	winW := outerW - 2

	// Window height is content-driven (lipgloss expands as needed); we just size
	// the panes to leave room for the chrome.
	paneH := m.height - chromeLines
	if paneH < minPaneH {
		paneH = minPaneH
	}
	if paneH > maxPaneH {
		paneH = maxPaneH
	}

	// Inside the window box: subtract horizontal padding (4) from Width.
	innerW := winW - 4
	rightW := innerW - leftPaneW
	if rightW < 30 {
		rightW = 30
	}
	// Right-pane content has 4 spaces of indent; truncation budget is rightW - 4.
	descBudget := rightW - 4
	if descBudget < 10 {
		descBudget = 10
	}

	var s strings.Builder

	switch m.state {
	case stateFocusCat, stateFocusItem:
		title := "mrk-menu"
		if m.state == stateFocusItem {
			title = "mrk-menu / " + categories[m.cursorCat].name
		}
		s.WriteString(styleHeader.Render(title) + "\n")
		if m.flashMsg != "" {
			s.WriteString(styleWarning.Render(m.flashMsg) + "\n\n")
		} else {
			s.WriteString("\n\n")
		}

		var leftPane strings.Builder
		for i, cat := range categories {
			cursor := "  "
			if i == m.cursorCat {
				cursor = "> "
				if m.state == stateFocusCat {
					leftPane.WriteString(styleSelected.Render(cursor+cat.name) + "\n")
				} else {
					leftPane.WriteString(styleNormal.Render(cursor+cat.name) + "\n")
				}
			} else {
				leftPane.WriteString(styleNormal.Render(cursor+cat.name) + "\n")
			}
		}

		var rightPane strings.Builder
		cat := categories[m.cursorCat]
		for i, it := range cat.items {
			cursor := "  "
			nameStr := theme.Truncate(it.name, descBudget)

			if i == m.cursorItems[m.cursorCat] {
				cursor = "> "
				if m.state == stateFocusItem {
					nameStr = styleSelected.Render(cursor + nameStr)
				} else {
					nameStr = styleNormal.Render(cursor + nameStr)
				}
			} else {
				nameStr = styleNormal.Render(cursor + nameStr)
			}

			rightPane.WriteString(nameStr + "\n")

			cmdStr := it.target
			if it.cmdType == cmdMake {
				cmdStr = "make " + it.target
			}
			if len(it.args) > 0 {
				cmdStr += " " + strings.Join(it.args, " ")
			}

			descStr := theme.Truncate(it.desc, descBudget)
			cmdStr = theme.Truncate(cmdStr, descBudget)

			rightPane.WriteString(styleDesc.Render("    "+descStr) + "\n")
			if i < len(cat.items)-1 {
				rightPane.WriteString(styleCmd.Render("    $ "+cmdStr) + "\n")
			} else {
				rightPane.WriteString(styleCmd.Render("    $ "+cmdStr))
			}
		}

		leftRendered := paneCatStyle(m.state == stateFocusCat, leftPaneW, paneH).Render(leftPane.String())
		rightRendered := paneItemStyle(rightW, paneH).Render(rightPane.String())
		s.WriteString(lipgloss.JoinHorizontal(lipgloss.Top, leftRendered, rightRendered) + "\n\n")

		if m.state == stateFocusCat {
			s.WriteString(styleHelp.Render("[j/k] navigate  [enter/→] select  [q/ctrl-c] quit  [?] help"))
		} else {
			s.WriteString(styleHelp.Render("[j/k] navigate  [enter/→] launch  [esc/←] back  [q/ctrl-c] quit  [?] help"))
		}

	case stateNukeConfirm:
		cat := categories[m.cursorCat]
		s.WriteString(styleHeader.Render("mrk-menu / "+cat.name) + "\n")
		s.WriteString(styleWarning.Render("⚠ This will remove all mrk symlinks and undo setup.") + "\n\n")
		s.WriteString(styleNormal.Render("Type ") +
			styleNukePrompt.Render("nuke") +
			styleNormal.Render(" to proceed, ") +
			styleHelpKey.Render("esc") +
			styleNormal.Render(" to cancel.") + "\n\n")
		s.WriteString(styleNukePrompt.Render("> ") + styleNormal.Render(m.nukeInput))

	case stateHelp:
		s.WriteString(styleHeader.Render("mrk-menu / Help") + "\n\n")
		rows := []struct{ keys, desc string }{
			{"j  k  ↑  ↓", "navigate"},
			{"enter  →  l", "select / launch"},
			{"esc  ←  h", "back"},
			{"?", "toggle this help"},
			{"q  ctrl-c", "quit"},
		}
		for _, r := range rows {
			s.WriteString(styleHelpKey.Render(fmt.Sprintf("  %-14s", r.keys)) +
				styleNormal.Render("  "+r.desc) + "\n")
		}
		s.WriteString(styleHelp.Render("Press esc or enter to return"))
	}

	renderedBox := windowStyle(winW).Render(s.String())
	return lipgloss.Place(m.width, m.height, lipgloss.Center, lipgloss.Center, renderedBox)
}

func main() {
	p := tea.NewProgram(initialModel(), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Printf("Error running program: %v\n", err)
		os.Exit(1)
	}
}
