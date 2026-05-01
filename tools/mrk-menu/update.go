package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"

	tea "github.com/charmbracelet/bubbletea"
)

type execFinishedMsg struct {
	err  error
	item item
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
		return m.handleKey(msg)

	case execFinishedMsg:
		m.lastItemName = msg.item.name
		if msg.err != nil {
			var exitErr *exec.ExitError
			if errors.As(msg.err, &exitErr) {
				m.lastExitMsg = fmt.Sprintf("%s exited %d", msg.item.name, exitErr.ExitCode())
				m.lastExitOK = false
			} else {
				m.lastExitMsg = fmt.Sprintf("%s failed: %v", msg.item.name, msg.err)
				m.lastExitOK = false
			}
			m.flashMsg = m.lastExitMsg
		} else {
			m.lastExitMsg = fmt.Sprintf("%s ok", msg.item.name)
			m.lastExitOK = true
			m.flashMsg = ""
		}
		return m, tea.ClearScreen
	}

	return m, nil
}

func (m model) handleKey(msg tea.KeyMsg) (tea.Model, tea.Cmd) {
	switch m.state {
	case stateSplash:
		// Any key dismisses the splash.
		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		default:
			m.state = stateFocusCat
			return m, tea.ClearScreen
		}

	case stateFocusCat:
		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "j", "down":
			if m.cursorCat < len(categories)-1 {
				m.cursorCat++
			}
			m.flashMsg = ""
		case "k", "up":
			if m.cursorCat > 0 {
				m.cursorCat--
			}
			m.flashMsg = ""
		case "enter", "right", "l":
			m.state = stateFocusItem
			m.flashMsg = ""
		case "/":
			m.prevState = m.state
			m.state = stateFilter
			m.filterInput = ""
			m.filterCursor = 0
			m.applyFilter()
			m.flashMsg = ""
			return m, tea.ClearScreen
		case "?":
			m.prevState = m.state
			m.state = stateHelp
			m.flashMsg = ""
		default:
			if d, ok := digitJump(msg.String(), len(categories)); ok {
				m.cursorCat = d
				m.flashMsg = ""
			}
		}

	case stateFocusItem:
		max := len(categories[m.cursorCat].items) - 1
		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "esc", "left", "h":
			m.state = stateFocusCat
			m.flashMsg = ""
			return m, tea.ClearScreen
		case "j", "down":
			if m.cursorItems[m.cursorCat] < max {
				m.cursorItems[m.cursorCat]++
			}
			m.flashMsg = ""
		case "k", "up":
			if m.cursorItems[m.cursorCat] > 0 {
				m.cursorItems[m.cursorCat]--
			}
			m.flashMsg = ""
		case "enter", "right", "l":
			it := categories[m.cursorCat].items[m.cursorItems[m.cursorCat]]
			if it.needsNuke {
				m.state = stateNukeConfirm
				m.nukeInput = ""
				m.flashMsg = ""
			} else {
				return m, m.runCmd(it)
			}
		case "/":
			m.prevState = m.state
			m.state = stateFilter
			m.filterInput = ""
			m.filterCursor = 0
			m.applyFilter()
			m.flashMsg = ""
			return m, tea.ClearScreen
		case "?":
			m.prevState = m.state
			m.state = stateHelp
			m.flashMsg = ""
		default:
			if d, ok := digitJump(msg.String(), max+1); ok {
				m.cursorItems[m.cursorCat] = d
				m.flashMsg = ""
			}
		}

	case stateFilter:
		switch msg.Type {
		case tea.KeyCtrlC:
			return m, tea.Quit
		case tea.KeyEsc:
			m.state = m.prevState
			m.filterInput = ""
			m.filterResults = nil
			m.flashMsg = ""
			return m, tea.ClearScreen
		case tea.KeyDown, tea.KeyCtrlN:
			if m.filterCursor < len(m.filterResults)-1 {
				m.filterCursor++
			}
		case tea.KeyUp, tea.KeyCtrlP:
			if m.filterCursor > 0 {
				m.filterCursor--
			}
		case tea.KeyEnter:
			if m.filterCursor < 0 || m.filterCursor >= len(m.filterResults) {
				return m, nil
			}
			fi := m.filterResults[m.filterCursor]
			it := fi.item
			// Sync the regular cursors so the user lands on the same item if they exit filter.
			m.cursorCat = fi.cat
			m.cursorItems[fi.cat] = fi.idx
			if it.needsNuke {
				m.state = stateNukeConfirm
				m.nukeInput = ""
				m.flashMsg = ""
				return m, tea.ClearScreen
			}
			m.state = m.prevState
			m.filterInput = ""
			m.filterResults = nil
			return m, m.runCmd(it)
		case tea.KeyBackspace, tea.KeyDelete:
			if len(m.filterInput) > 0 {
				m.filterInput = m.filterInput[:len(m.filterInput)-1]
				m.applyFilter()
			}
		case tea.KeyRunes:
			m.filterInput += string(msg.Runes)
			m.applyFilter()
		case tea.KeySpace:
			m.filterInput += " "
			m.applyFilter()
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
				it := categories[m.cursorCat].items[m.cursorItems[m.cursorCat]]
				m.state = stateFocusItem
				m.nukeInput = ""
				return m, m.runCmd(it)
			}
			m.state = stateFocusItem
			m.nukeInput = ""
			m.flashMsg = "Canceled nuke operation (incorrect input)."
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
		case "esc", "enter", "?":
			m.state = m.prevState
			return m, tea.ClearScreen
		}
	}

	return m, nil
}

// digitJump returns (idx, true) if s is a digit "1"-"9" within bounds, else (0, false).
// "1" maps to index 0, "2" to index 1, etc.
func digitJump(s string, count int) (int, bool) {
	if len(s) != 1 {
		return 0, false
	}
	c := s[0]
	if c < '1' || c > '9' {
		return 0, false
	}
	idx := int(c - '1')
	if idx >= count {
		return 0, false
	}
	return idx, true
}
