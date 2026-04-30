package main

import (
	"strings"
	"testing"
)

func TestViewRendersAtVariousSizes(t *testing.T) {
	cases := []struct {
		name       string
		w, h       int
		state      state
		wantSubstr string
	}{
		{"big terminal cat focus", 200, 60, stateFocusCat, "mrk-menu"},
		{"big terminal item focus", 200, 60, stateFocusItem, "Brewfile"},
		{"exact preferred", 100, 30, stateFocusCat, "mrk-menu"},
		{"min size", 80, 22, stateFocusCat, "mrk-menu"},
		{"too small width", 60, 30, stateFocusCat, "Terminal too small"},
		{"too small height", 100, 10, stateFocusCat, "Terminal too small"},
		{"zero size", 0, 0, stateFocusCat, ""},
		{"help screen", 100, 30, stateHelp, "Help"},
		{"nuke confirm", 100, 30, stateNukeConfirm, "nuke"},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			m := initialModel()
			m.width = tc.w
			m.height = tc.h
			m.state = tc.state
			out := m.View()
			if tc.wantSubstr != "" && !strings.Contains(out, tc.wantSubstr) {
				t.Errorf("View() output missing %q.\n--- output ---\n%s\n--- end ---",
					tc.wantSubstr, out)
			}
			if tc.wantSubstr == "" && out != "" {
				t.Errorf("expected empty output, got %d bytes", len(out))
			}
		})
	}
}

func TestViewDoesNotOverflowWidth(t *testing.T) {
	cases := []struct{ w, h int }{
		{80, 22}, {100, 30}, {120, 40}, {200, 60},
	}
	for _, tc := range cases {
		m := initialModel()
		m.width = tc.w
		m.height = tc.h
		m.state = stateFocusItem
		out := m.View()
		// Each rendered line shouldn't exceed terminal width (allowing ANSI escapes,
		// so we strip them roughly with a visible-width approximation).
		for _, line := range strings.Split(out, "\n") {
			visible := stripANSI(line)
			runes := []rune(visible)
			if len(runes) > tc.w {
				t.Errorf("size %d×%d: line exceeds width: %d > %d: %q",
					tc.w, tc.h, len(runes), tc.w, visible)
				break
			}
		}
	}
}

// stripANSI removes ANSI escape sequences for width measurement.
func stripANSI(s string) string {
	var b strings.Builder
	inEsc := false
	for _, r := range s {
		switch {
		case inEsc:
			if r == 'm' || r == 'K' || r == 'H' || r == 'J' {
				inEsc = false
			}
		case r == 0x1b:
			inEsc = true
		default:
			b.WriteRune(r)
		}
	}
	return b.String()
}
