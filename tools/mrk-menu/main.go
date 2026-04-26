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

var (
	styleHeader   = lipgloss.NewStyle().Bold(true).Foreground(theme.ColNormal).MarginBottom(1)
	styleSelected = lipgloss.NewStyle().Foreground(theme.ColAccent).Bold(true)
	styleNormal   = lipgloss.NewStyle().Foreground(theme.ColNormal)
	styleDesc     = lipgloss.NewStyle().Foreground(theme.ColSubtle)
	styleCmd      = lipgloss.NewStyle().Foreground(theme.ColDim)
	styleWarning  = lipgloss.NewStyle().Foreground(theme.ColAmber)
	styleHelp     = lipgloss.NewStyle().Foreground(theme.ColSubtle).MarginTop(1)

	stylePaneCatActive   = lipgloss.NewStyle().Width(25).Height(15).PaddingRight(2).BorderRight(true).BorderStyle(lipgloss.NormalBorder()).BorderForeground(theme.ColAccent)
	stylePaneCatInactive = lipgloss.NewStyle().Width(25).Height(15).PaddingRight(2).BorderRight(true).BorderStyle(lipgloss.NormalBorder()).BorderForeground(theme.ColSubtle)

	stylePaneItemActive   = lipgloss.NewStyle().PaddingLeft(2).Width(48).Height(15)
	stylePaneItemInactive = lipgloss.NewStyle().PaddingLeft(2).Width(48).Height(15)

	styleWindow = lipgloss.NewStyle().
		Border(lipgloss.RoundedBorder()).
		BorderForeground(theme.ColSubtle).
		Padding(1, 2).
		Width(80).
		Height(21)
)

func (m model) View() string {
	var s strings.Builder

	if m.state == stateFocusCat || m.state == stateFocusItem {
		s.WriteString(styleHeader.Render("mrk-menu") + "\n")
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
			nameStr := theme.Truncate(it.name, 47)

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

			descStr := theme.Truncate(it.desc, 45)
			cmdStr = theme.Truncate(cmdStr, 45)

			rightPane.WriteString(styleDesc.Render("    "+descStr) + "\n")
			if i < len(cat.items)-1 {
				rightPane.WriteString(styleCmd.Render("    $ "+cmdStr) + "\n")
			} else {
				rightPane.WriteString(styleCmd.Render("    $ "+cmdStr))
			}
		}

		var leftRendered, rightRendered string
		if m.state == stateFocusCat {
			leftRendered = stylePaneCatActive.Render(leftPane.String())
			rightRendered = stylePaneItemInactive.Render(rightPane.String())
			s.WriteString(lipgloss.JoinHorizontal(lipgloss.Top, leftRendered, rightRendered) + "\n\n")
			s.WriteString(styleHelp.Render("[j/k] navigate  [enter/→] select  [q/ctrl-c] quit  [?] help"))
		} else {
			leftRendered = stylePaneCatInactive.Render(leftPane.String())
			rightRendered = stylePaneItemActive.Render(rightPane.String())
			s.WriteString(lipgloss.JoinHorizontal(lipgloss.Top, leftRendered, rightRendered) + "\n\n")
			s.WriteString(styleHelp.Render("[j/k] navigate  [enter/→] launch  [esc/←] back  [q/ctrl-c] quit  [?] help"))
		}

	} else if m.state == stateNukeConfirm {
		cat := categories[m.cursorCat]
		s.WriteString(styleHeader.Render(fmt.Sprintf("mrk-menu / %s", cat.name)) + "\n")
		s.WriteString(styleWarning.Render("WARNING: This will remove all mrk symlinks and undo setup.") + "\n")
		s.WriteString("Type 'nuke' to proceed, esc to cancel.\n\n")
		s.WriteString("> " + m.nukeInput + "\n")

	} else if m.state == stateHelp {
		s.WriteString(styleHeader.Render("mrk-menu Help") + "\n")
		s.WriteString("j, k, up, down  : navigate\n")
		s.WriteString("enter, right, l : select / launch\n")
		s.WriteString("esc, left, h    : back\n")
		s.WriteString("q, ctrl-c       : quit\n")
		s.WriteString(styleHelp.Render("Press esc to return"))
	}

	renderedBox := styleWindow.Render(s.String())
	
	if m.width > 0 && m.height > 0 {
		return lipgloss.Place(m.width, m.height, lipgloss.Center, lipgloss.Center, renderedBox)
	}
	
	return renderedBox
}

func main() {
	p := tea.NewProgram(initialModel(), tea.WithAltScreen())
	if _, err := p.Run(); err != nil {
		fmt.Printf("Error running program: %v\n", err)
		os.Exit(1)
	}
}
