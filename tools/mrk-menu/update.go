package main

import (
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"unicode/utf8"

	tea "github.com/charmbracelet/bubbletea"
)

type execFinishedMsg struct {
	err  error
	item item
}

func (m model) Init() tea.Cmd {
	return nil
}

// commandFor builds the command an item runs. A cmdBin item runs from ~/bin,
// where setup links mrk's tools, and not by name through PATH: "sync" is also
// /bin/sync, so wherever /bin came first on PATH, choosing sync ran the
// system's, which flushes the disks and exits 0, and the menu reported "sync
// ok". Only .zshrc puts ~/bin on PATH, so a login shell that is not
// interactive has it last or not at all (audit 19, W-22). A tool that is not
// in ~/bin is an error, rather than whatever PATH finds under its name.
func commandFor(i item) (*exec.Cmd, error) {
	if i.cmdType == cmdBin {
		home, err := os.UserHomeDir()
		if err != nil {
			return nil, err
		}
		path := filepath.Join(home, "bin", i.target)
		if info, err := os.Stat(path); err != nil || info.IsDir() || info.Mode()&0o111 == 0 {
			return nil, fmt.Errorf("%s is not in ~/bin — make tools links the scripts, make build-tools the TUIs", i.target)
		}
		return exec.Command(path, i.args...), nil
	}
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
	return exec.Command("make", args...), nil
}

func (m model) runCmd(i item) tea.Cmd {
	cmd, err := commandFor(i)
	if err != nil {
		return func() tea.Msg { return execFinishedMsg{err: err, item: i} }
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
		// lastIdx, not max, which shadowed the builtin (audit 19, W-22)
		lastIdx := len(categories[m.cursorCat].items) - 1
		switch msg.String() {
		case "q", "ctrl+c":
			return m, tea.Quit
		case "esc", "left", "h":
			m.state = stateFocusCat
			m.flashMsg = ""
			return m, tea.ClearScreen
		case "j", "down":
			if m.cursorItems[m.cursorCat] < lastIdx {
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
			if d, ok := digitJump(msg.String(), lastIdx+1); ok {
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
			if m.filterInput != "" {
				_, size := utf8.DecodeLastRuneInString(m.filterInput)
				m.filterInput = m.filterInput[:len(m.filterInput)-size]
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
			if m.nukeInput != "" {
				_, size := utf8.DecodeLastRuneInString(m.nukeInput)
				m.nukeInput = m.nukeInput[:len(m.nukeInput)-size]
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
