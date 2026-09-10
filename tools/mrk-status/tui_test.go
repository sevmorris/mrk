package main

import (
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

// mrk-status opens /dev/tty through tea.WithInput, so the running program
// cannot be driven from a pipe. handleKey takes a model and returns one, so the
// navigation can be replayed directly with no terminal.
//
// The failure worth guarding is an out-of-range groupIdx: nothing stops the
// cursor at a boundary except the bounds checks in handleKey, and View indexes
// groups[groupIdx] on every frame, so an off-by-one there is a panic on a
// keypress rather than a wrong number on screen.

func statusModel() model {
	return model{
		groups: []group{
			{"One", sevOK, []statusLine{sl(sevOK, "a")}, ""},
			{"Two", sevWarn, []statusLine{sl(sevWarn, "b")}, ""},
			{"Three", sevErr, []statusLine{sl(sevErr, "c")}, ""},
		},
		// leftFocus matters: up/down only move between checks when the left
		// pane has focus, and scroll the detail pane otherwise. Leaving it at
		// the zero value made the first version of TestNavigationStopsAtTheTop
		// pass for the wrong reason — groupIdx stayed 0 because the keys were
		// never moving it at all.
		leftFocus: true,
		width:     100,
		height:    40,
	}
}

func send(m model, keys ...string) model {
	for _, k := range keys {
		var msg tea.KeyMsg
		switch k {
		case "tab":
			msg = tea.KeyMsg{Type: tea.KeyTab}
		case "up":
			msg = tea.KeyMsg{Type: tea.KeyUp}
		case "down":
			msg = tea.KeyMsg{Type: tea.KeyDown}
		default:
			msg = tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(k)}
		}
		m, _ = m.handleKey(msg)
	}
	return m
}

func TestNavigationStopsAtTheTop(t *testing.T) {
	// Walk to the bottom first, so going up genuinely has to travel and then
	// stop, rather than starting where the assertion already holds.
	m := send(statusModel(), "j", "j", "up", "up", "up", "up")
	if m.groupIdx != 0 {
		t.Errorf("groupIdx should stop at 0, got %d", m.groupIdx)
	}
	if m.groupIdx < 0 {
		t.Fatal("groupIdx went negative — View would panic")
	}
}

func TestNavigationStopsAtTheBottom(t *testing.T) {
	m := send(statusModel(), "j", "j", "j", "j", "j", "j")
	if m.groupIdx != len(m.groups)-1 {
		t.Errorf("groupIdx should stop at the last group (%d), got %d", len(m.groups)-1, m.groupIdx)
	}
	if m.groupIdx >= len(m.groups) {
		t.Fatal("groupIdx ran past the end — View would panic")
	}
}

func TestViewSurvivesBothBoundaries(t *testing.T) {
	// The bounds checks and View have to agree. Rendering at each end is the
	// assertion that actually matters, because a panic here is what the user
	// would see rather than a wrong severity.
	for _, keys := range [][]string{
		{"up", "up", "up"},
		{"j", "j", "j", "j", "j"},
		{},
	} {
		m := send(statusModel(), keys...)
		out := m.View()
		if strings.TrimSpace(out) == "" {
			t.Errorf("View rendered nothing after %v", keys)
		}
	}
}

func TestChangingGroupResetsTheDetailScroll(t *testing.T) {
	// Carrying a scroll offset from a long check into a short one would render
	// a detail pane scrolled past its own content.
	m := statusModel()
	m.detailScroll = 12
	m = send(m, "j")
	if m.detailScroll != 0 {
		t.Errorf("moving to another group should reset detailScroll, got %d", m.detailScroll)
	}
}

func TestTabTogglesFocus(t *testing.T) {
	m := statusModel()
	start := m.leftFocus
	m = send(m, "tab")
	if m.leftFocus == start {
		t.Error("tab should toggle which pane has focus")
	}
	m = send(m, "tab")
	if m.leftFocus != start {
		t.Error("a second tab should toggle it back")
	}
}

func TestEmptyGroupsDoNotPanic(t *testing.T) {
	// Every check can be skipped — checkBackups returns false when there is
	// nothing to report — so a model with no groups is reachable.
	m := model{groups: nil, width: 80, height: 24}
	m = send(m, "j", "k", "tab")
	_ = m.View()
}
