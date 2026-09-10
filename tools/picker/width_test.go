package main

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// Same contract as the other two TUIs: theme.Truncate returns "…" — one column
// wider than asked — when given zero or less, and this file computes nameW and
// descW from the terminal width before calling it.
func TestRendersWithinTerminalWidth(t *testing.T) {
	for _, w := range []int{0, 1, 2, 5, 10, 20, 40, 79, 80, 100, 200} {
		for _, h := range []int{0, 1, 5, 22, 24, 60} {
			var tm tea.Model = newModel(cleanFixture())
			tm, _ = tm.Update(tea.WindowSizeMsg{Width: w, Height: h})
			var out string
			func() {
				defer func() {
					if r := recover(); r != nil {
						t.Fatalf("PANIC at %dx%d: %v", w, h, r)
					}
				}()
				out = tm.(model).View()
			}()
			if w < 40 || h < 10 {
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
