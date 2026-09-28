package main

import (
	"strings"
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

func TestNoIgnoreHidesTheIgnoreKey(t *testing.T) {
	// mrk brew runs the picker with --no-ignore: Phase 2 installs from the
	// Brewfile and keeps no ignore list, so an `i` mark there had nowhere to go
	// and was dropped (audit 19, W-17). The key must do nothing, the footer
	// must not offer it, and nothing may come out as "ignore-".
	var m tea.Model = newModel(cleanFixture())
	mm := m.(model)
	mm.noIgnore = true
	m = mm
	// With the key hidden, i neither marks nor moves the cursor, so the space
	// that follows selects the same package. With it live, i would mark alpha
	// and step to beta.
	for _, k := range []string{"tab", "i", " ", "q"} {
		m, _ = m.Update(key(k))
	}
	got := m.(model)
	for _, p := range got.cats[0].pkgs {
		if p.ignored {
			t.Errorf("%s was marked ignored with the key hidden", p.name)
		}
	}
	if !got.cats[0].pkgs[0].selected {
		t.Error("i should not move the cursor with the key hidden, so space selects alpha")
	}
	for _, line := range emitLines(got.cats, got.cancelled) {
		if strings.HasPrefix(line, "ignore-") {
			t.Errorf("emitted %q with the ignore key hidden", line)
		}
	}
	footer := got.viewFooter()
	for _, s := range []string{"i ignore", "ignores kept"} {
		if strings.Contains(footer, s) {
			t.Errorf("footer offers %q with the ignore key hidden: %q", s, footer)
		}
	}
	// And the default keeps the key, for sync.
	if !strings.Contains(newModel(cleanFixture()).viewFooter(), "i ignore") {
		t.Error("the default footer should still offer i ignore")
	}
}
