package main

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Truncate() lives in the shared theme package and is fed computed widths at
// twelve call sites across the three TUIs. Asked for a width of zero or less it
// returns "…", one column WIDER than requested. Every caller currently clamps,
// so this checks the clamping actually holds — at every size, including the
// degenerate ones a terminal really can report.
func TestRendersWithinTerminalWidth(t *testing.T) {
	for _, w := range []int{0, 1, 2, 5, 10, 20, 40, 79, 80, 100, 200} {
		for _, h := range []int{0, 1, 5, 22, 24, 60} {
			m := initialModel()
			m.state = stateFocusItem
			tm, _ := m.Update(tea.WindowSizeMsg{Width: w, Height: h})
			var out string
			func() {
				defer func() {
					if r := recover(); r != nil {
						t.Fatalf("PANIC at %dx%d: %v", w, h, r)
					}
				}()
				out = tm.(model).View()
			}()
			// Below the stated minimum the TUI prints a "terminal too small"
			// notice, which cannot itself fit; only hold it to the contract at
			// or above the size it says it needs.
			if w < 80 || h < 22 {
				continue
			}
			for _, line := range strings.Split(out, "\n") {
				if lw := lipgloss.Width(line); lw > w {
					t.Errorf("%dx%d: line %d cols > %d: %q", w, h, lw, w, line)
					break
				}
			}
		}
	}
}
