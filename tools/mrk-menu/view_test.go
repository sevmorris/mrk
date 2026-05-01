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
		{"big terminal cat focus", 200, 60, stateFocusCat, "Brewfile"},
		{"big terminal item focus", 200, 60, stateFocusItem, "bf"},
		{"exact preferred", 100, 30, stateFocusCat, "Brewfile"},
		{"min size", 80, 22, stateFocusCat, "Brewfile"},
		{"too small width", 60, 30, stateFocusCat, "Terminal too small"},
		{"too small height", 100, 10, stateFocusCat, "Terminal too small"},
		{"zero size", 0, 0, stateFocusCat, ""},
		{"help screen", 100, 30, stateHelp, "Help"},
		{"nuke confirm", 100, 30, stateNukeConfirm, "nuke"},
		{"splash", 100, 30, stateSplash, "Mac Rebuild Kit"},
		{"filter", 100, 30, stateFilter, "Filter"},
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

// TestViewDoesNotOverflowHeight asserts that the rendered output respects the
// terminal height — a regression test for the right-pane wrapping bug we fixed.
func TestViewDoesNotOverflowHeight(t *testing.T) {
	cases := []struct {
		name  string
		w, h  int
		state state
	}{
		{"min focus item", 80, 22, stateFocusItem},
		{"preferred focus item", 100, 30, stateFocusItem},
		{"min focus cat", 80, 22, stateFocusCat},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			m := initialModel()
			m.width = tc.w
			m.height = tc.h
			m.state = tc.state
			out := m.View()
			lines := strings.Split(out, "\n")
			if len(lines) > tc.h {
				t.Errorf("size %d×%d: output has %d lines, exceeds height",
					tc.w, tc.h, len(lines))
			}
		})
	}
}

// TestDigitJump exercises the number-hotkey helper.
func TestDigitJump(t *testing.T) {
	cases := []struct {
		s     string
		count int
		idx   int
		ok    bool
	}{
		{"1", 5, 0, true},
		{"5", 5, 4, true},
		{"6", 5, 0, false},
		{"0", 5, 0, false},
		{"a", 5, 0, false},
		{"", 5, 0, false},
		{"12", 5, 0, false},
	}
	for _, tc := range cases {
		idx, ok := digitJump(tc.s, tc.count)
		if ok != tc.ok || idx != tc.idx {
			t.Errorf("digitJump(%q, %d) = (%d, %v), want (%d, %v)",
				tc.s, tc.count, idx, ok, tc.idx, tc.ok)
		}
	}
}

// TestApplyFilter exercises the substring filter.
func TestApplyFilter(t *testing.T) {
	m := initialModel()
	m.filterInput = "brew"
	m.applyFilter()
	if len(m.filterResults) == 0 {
		t.Errorf("expected at least one match for 'brew'")
	}
	for _, fi := range m.filterResults {
		hay := strings.ToLower(fi.item.name + " " + fi.item.desc + " " + categories[fi.cat].name)
		if !strings.Contains(hay, "brew") {
			t.Errorf("result %q does not match 'brew'", fi.item.name)
		}
	}

	m.filterInput = ""
	m.applyFilter()
	total := 0
	for _, c := range categories {
		total += len(c.items)
	}
	if len(m.filterResults) != total {
		t.Errorf("empty filter should return all %d items, got %d", total, len(m.filterResults))
	}

	m.filterInput = "zzzzzzzzzzz-no-match"
	m.applyFilter()
	if len(m.filterResults) != 0 {
		t.Errorf("expected zero matches, got %d", len(m.filterResults))
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
