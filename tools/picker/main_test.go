package main

import (
	"reflect"
	"testing"
)

// The picker opens /dev/tty directly (tea.WithInput), so its key handling
// cannot be driven from a pipe and the exit paths are not reachable from a
// test. emitLines is the decision those paths feed into, and it is where the
// bug lived: every exit but enter discarded the ignore marks, so marking
// packages with `i` and then quitting — the natural move when you are adding
// nothing — silently threw them away, and the same packages came back on the
// next run.
func fixture() []category {
	return []category{{
		name: "Casks",
		pkgs: []*pkg{
			{name: "example-ignored", kind: cask, ignored: true},
			{name: "example-added", kind: cask, selected: true},
			{name: "untouched", kind: cask},
		},
	}}
}

func TestEmitLinesConfirmed(t *testing.T) {
	got := emitLines(fixture(), false)
	want := []string{"ignore-cask:example-ignored", "cask:example-added"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("enter should commit both answers\n got: %v\nwant: %v", got, want)
	}
}

func TestEmitLinesQuitKeepsIgnores(t *testing.T) {
	got := emitLines(fixture(), true)
	want := []string{"ignore-cask:example-ignored"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("quitting must keep ignore marks and drop pending additions\n got: %v\nwant: %v", got, want)
	}
}

func TestEmitLinesUntouchedNeverEmitted(t *testing.T) {
	for _, cancelled := range []bool{false, true} {
		for _, line := range emitLines(fixture(), cancelled) {
			if line == "cask:untouched" || line == "ignore-cask:untouched" {
				t.Errorf("cancelled=%v: a package with no mark must produce no line, got %q",
					cancelled, line)
			}
		}
	}
}
