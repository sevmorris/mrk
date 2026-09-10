package main

import (
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

// view_test.go covers rendering. This covers handleKey, which is the half that
// decides what actually runs — including the confirmation gate in front of
// nuke-mrk.
//
// Nothing here executes a command. runCmd builds its exec.Cmd with
// exec.Command, which only constructs, and hands it to tea.ExecProcess, which
// returns a tea.Cmd — a function bubbletea would call later. Asserting that the
// returned Cmd is non-nil proves the gate opened without running anything. The
// returned Cmd is never invoked, and must not be.

func k(s string) tea.KeyMsg {
	switch s {
	case "enter":
		return tea.KeyMsg{Type: tea.KeyEnter}
	case "esc":
		return tea.KeyMsg{Type: tea.KeyEsc}
	case "backspace":
		return tea.KeyMsg{Type: tea.KeyBackspace}
	case "ctrl+c":
		return tea.KeyMsg{Type: tea.KeyCtrlC}
	default:
		return tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(s)}
	}
}

func step(t *testing.T, m model, keys ...string) (model, tea.Cmd) {
	t.Helper()
	var cmd tea.Cmd
	var tm tea.Model = m
	for _, key := range keys {
		tm, cmd = tm.(model).handleKey(k(key))
	}
	got, ok := tm.(model)
	if !ok {
		t.Fatalf("handleKey returned %T, not model", tm)
	}
	return got, cmd
}

// typed drives the nuke prompt one rune at a time, the way a person would.
func typed(t *testing.T, s string) (model, tea.Cmd) {
	t.Helper()
	m := initialModel()
	m.state = stateNukeConfirm
	keys := make([]string, 0, len(s)+1)
	for _, r := range s {
		keys = append(keys, string(r))
	}
	return step(t, m, append(keys, "enter")...)
}

// ── The nuke confirmation gate ──────────────────────────────────────────────

func TestNukeGateOpensOnlyForTheExactWord(t *testing.T) {
	m, cmd := typed(t, "nuke")
	if cmd == nil {
		t.Fatal(`typing "nuke" then enter should produce a command`)
	}
	if m.state != stateFocusItem {
		t.Error("the prompt should close after a confirmed run")
	}
	if m.nukeInput != "" {
		t.Error("the typed input must be cleared, or it leaks into the next prompt")
	}
}

func TestNukeGateRefusesEverythingElse(t *testing.T) {
	// Case, whitespace and partial words must all fail. A gate that accepted
	// "NUKE" or "nuke " would be one keystroke from wiping the install.
	for _, in := range []string{"", "n", "nuk", "NUKE", "Nuke", "nuke ", " nuke", "nukee", "yes"} {
		m, cmd := typed(t, in)
		if cmd != nil {
			t.Errorf("input %q must NOT open the gate", in)
		}
		if m.state != stateFocusItem {
			t.Errorf("input %q should return to the item list, got state %v", in, m.state)
		}
		if m.nukeInput != "" {
			t.Errorf("input %q left nukeInput set to %q", in, m.nukeInput)
		}
	}
}

func TestNukeGateCancelKeys(t *testing.T) {
	for _, cancel := range []string{"esc", "ctrl+c"} {
		m := initialModel()
		m.state = stateNukeConfirm
		got, cmd := step(t, m, "n", "u", "k", "e", cancel)
		if cmd != nil {
			t.Errorf("%s must not run anything even with the word typed", cancel)
		}
		if got.state != stateFocusItem || got.nukeInput != "" {
			t.Errorf("%s should cancel and clear, got state=%v input=%q", cancel, got.state, got.nukeInput)
		}
	}
}

func TestNukeBackspaceIsRuneAware(t *testing.T) {
	m := initialModel()
	m.state = stateNukeConfirm
	// A multi-byte rune must be removed whole; slicing by byte would leave a
	// broken fragment behind and quietly change what the gate compares.
	got, _ := step(t, m, "é", "backspace")
	if got.nukeInput != "" {
		t.Errorf("backspace should remove the whole rune, left %q", got.nukeInput)
	}
}

// ── Navigation ──────────────────────────────────────────────────────────────

func TestSplashDismissesOnAnyKeyButQuitsOnQ(t *testing.T) {
	m, _ := step(t, initialModel(), "x")
	if m.state != stateFocusCat {
		t.Errorf("any key should dismiss the splash, got state %v", m.state)
	}
	q := initialModel()
	q.state = stateSplash
	got, cmd := step(t, q, "q")
	if cmd == nil {
		t.Error("q on the splash should quit")
	}
	if got.state != stateSplash {
		t.Error("quitting should not first advance the state")
	}
}

func TestCategoryCursorStaysInRange(t *testing.T) {
	m := initialModel()
	m.state = stateFocusCat
	up, _ := step(t, m, "k", "k", "k")
	if up.cursorCat != 0 {
		t.Errorf("cursorCat should stop at 0, got %d", up.cursorCat)
	}
	down, _ := step(t, m, "j", "j", "j", "j", "j", "j", "j", "j", "j", "j", "j", "j")
	if down.cursorCat >= len(categories) {
		t.Fatalf("cursorCat ran past the end (%d of %d) — View would panic",
			down.cursorCat, len(categories))
	}
	if down.cursorCat != len(categories)-1 {
		t.Errorf("cursorCat should stop at the last category, got %d", down.cursorCat)
	}
}

func TestFilterCursorClampsWhenResultsShrink(t *testing.T) {
	// applyFilter has to pull the cursor back when a longer query returns fewer
	// rows; otherwise the cursor points past the slice it indexes.
	m := initialModel()
	m.filterInput = ""
	m.applyFilter()
	if len(m.filterResults) == 0 {
		t.Skip("no items to filter")
	}
	m.filterCursor = len(m.filterResults) - 1
	m.filterInput = "zzzzzzzz-no-such-item"
	m.applyFilter()
	if m.filterCursor < 0 {
		t.Errorf("filterCursor went negative on an empty result set: %d", m.filterCursor)
	}
	if len(m.filterResults) > 0 && m.filterCursor >= len(m.filterResults) {
		t.Errorf("filterCursor %d is past the %d results", m.filterCursor, len(m.filterResults))
	}
}
