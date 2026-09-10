package main

import (
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

// The picker opens /dev/tty through tea.WithInput, so the running program cannot
// be driven from a pipe — piping keys into it just hangs. But the model is an
// ordinary value with an Update method, so the key handling can be exercised
// directly, with no terminal involved.
//
// This covers the half of the q/esc/ctrl+c contract that emitLines cannot see.
// emitLines proves what a given (cats, cancelled) pair renders; these prove the
// keys set that pair correctly. Until this existed, the wiring from "q" to
// `cancelled` was verified by reading the source and nothing else.

// A fixture with no flags preset. The emitLines fixture deliberately starts
// with ignored/selected already true, which is right for testing rendering and
// wrong here: `i` and space toggle, so pressing them on a pre-marked package
// clears the mark instead of setting it.
func cleanFixture() []category {
	return []category{{
		name: "Casks",
		pkgs: []*pkg{
			{name: "alpha", kind: cask},
			{name: "beta", kind: cask},
			{name: "gamma", kind: cask},
		},
	}}
}

func key(s string) tea.KeyMsg {
	switch s {
	case "ctrl+c":
		return tea.KeyMsg{Type: tea.KeyCtrlC}
	case "esc":
		return tea.KeyMsg{Type: tea.KeyEsc}
	case "enter":
		return tea.KeyMsg{Type: tea.KeyEnter}
	case "tab":
		return tea.KeyMsg{Type: tea.KeyTab}
	case " ":
		return tea.KeyMsg{Type: tea.KeySpace, Runes: []rune{' '}}
	default:
		return tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(s)}
	}
}

// press replays a sequence of keys and hands back the resulting model.
// It starts with one "tab", because newModel focuses the left pane and the
// mark keys only act on the right one.
func press(t *testing.T, keys ...string) model {
	t.Helper()
	var m tea.Model = newModel(cleanFixture())
	for _, k := range append([]string{"tab"}, keys...) {
		m, _ = m.Update(key(k))
	}
	got, ok := m.(model)
	if !ok {
		t.Fatalf("Update returned %T, not model", m)
	}
	return got
}

func TestQuitKeepsIgnoreMarks(t *testing.T) {
	m := press(t, "i", "q")
	if !m.cancelled {
		t.Error("q should set cancelled")
	}
	if m.aborted {
		t.Error("q is not a hard abort — aborted must stay false, or main exits before emitting")
	}
	lines := emitLines(m.cats, m.cancelled)
	if len(lines) != 1 || lines[0] != "ignore-cask:alpha" {
		t.Errorf("the ignore mark must survive q; got %v", lines)
	}
}

func TestEscFromRightPaneReturnsFocusBeforeQuitting(t *testing.T) {
	// esc is overloaded: from the right pane it moves focus left, and only a
	// second esc quits. A test that sent one esc and asserted "quit" would pass
	// for the wrong reason.
	m := press(t, "esc")
	if m.cancelled {
		t.Error("the first esc should return focus to the left pane, not quit")
	}
	m2 := press(t, "esc", "esc")
	if !m2.cancelled {
		t.Error("a second esc should quit")
	}
	if m2.aborted {
		t.Error("esc is not a hard abort")
	}
}

func TestCtrlCDiscardsEverything(t *testing.T) {
	m := press(t, "i", "ctrl+c")
	if !m.aborted {
		t.Error("ctrl+c must set aborted — that is what makes main exit 1 and emit nothing")
	}
	if !m.cancelled {
		t.Error("ctrl+c should also set cancelled")
	}
}

func TestSpaceSelectsAndQuitDropsIt(t *testing.T) {
	m := press(t, " ", "q")
	lines := emitLines(m.cats, m.cancelled)
	for _, l := range lines {
		if l == "cask:alpha" {
			t.Error("quitting must drop pending additions")
		}
	}
}

func TestEnterCommitsSelection(t *testing.T) {
	m := press(t, " ", "enter")
	if !m.confirmed {
		t.Error("enter should set confirmed")
	}
	if m.cancelled {
		t.Error("enter is not a cancel")
	}
	lines := emitLines(m.cats, m.cancelled)
	if len(lines) == 0 {
		t.Fatal("enter should commit the selection")
	}
}

func TestSpaceAndIgnoreAreMutuallyExclusive(t *testing.T) {
	// Marking a package for the ignore list must clear a pending selection:
	// "add this" and "never offer this again" are opposite answers. Both keys
	// advance the cursor after marking, so pressing them twice acts on two
	// different packages — press "i" on the same one by stepping back with "k".
	m := press(t, " ", "k", "i")
	p := m.cats[0].pkgs[0]
	if p.selected {
		t.Error("i should clear a pending selection on the same package")
	}
	if !p.ignored {
		t.Error("i should set ignored")
	}
}
