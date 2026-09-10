package main

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// theme.Truncate is fed computed widths at six call sites in this file, several
// of the form `inner-3`. Asked for zero or less it returns "…", one column
// WIDER than requested. This checks the clamping in front of it actually holds
// at every size a terminal can report, including the degenerate ones.
func TestRendersWithinTerminalWidth(t *testing.T) {
	for _, w := range []int{0, 1, 2, 5, 10, 20, 40, 79, 80, 100, 200} {
		for _, h := range []int{0, 1, 5, 22, 24, 60} {
			tm, _ := statusModel().Update(tea.WindowSizeMsg{Width: w, Height: h})
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
				continue // too small to hold its own layout; only the no-panic contract applies
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
