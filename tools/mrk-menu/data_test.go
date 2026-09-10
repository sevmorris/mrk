package main

import (
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// mrk-menu is a launcher: every row here runs something. Its sibling
// mrk-status carried a fix command — "hardening.sh" — that resolved nowhere and
// had therefore never worked, because a command stored as a string is only a
// string until somebody presses the key. These gates close the same class here.
//
// Deliberately repo-relative, never PATH-relative. CI runs scripts/ci-check on
// a fresh macos-latest runner with no `make setup`, so ~/bin holds no mrk
// symlinks; a LookPath check would fail there for the wrong reason. Every
// cmdBin target is a literal filename under bin/ or scripts/, so the repo is
// both the CI-safe question and the more correct one: does this command ship
// with mrk?

func allItems() []item {
	var out []item
	for _, c := range categories {
		out = append(out, c.items...)
	}
	return out
}

func TestMenuHasItems(t *testing.T) {
	// Guards every other test in this file against passing vacuously.
	if n := len(allItems()); n < 10 {
		t.Fatalf("only %d menu items — the other gates here would prove nothing", n)
	}
}

func TestEveryCmdBinTargetShipsWithMrk(t *testing.T) {
	for _, it := range allItems() {
		if it.cmdType != cmdBin {
			continue
		}
		bin := filepath.Join("..", "..", "bin", it.target)
		script := filepath.Join("..", "..", "scripts", it.target)
		if !exists(bin) && !exists(script) {
			t.Errorf("item %q runs %q, which is neither bin/%s nor scripts/%s",
				it.name, it.target, it.target, it.target)
		}
	}
}

var makeTargetLine = regexp.MustCompile(`(?m)^([a-zA-Z][a-zA-Z0-9_-]*):`)

func TestEveryCmdMakeTargetExists(t *testing.T) {
	b, err := os.ReadFile(filepath.Join("..", "..", "Makefile"))
	if err != nil {
		t.Fatalf("cannot read Makefile: %v", err)
	}
	targets := map[string]bool{}
	for _, m := range makeTargetLine.FindAllStringSubmatch(string(b), -1) {
		targets[m[1]] = true
	}
	if len(targets) == 0 {
		t.Fatal("parsed no Make targets — this gate would pass vacuously")
	}
	for _, it := range allItems() {
		if it.cmdType != cmdMake {
			continue
		}
		if !targets[it.target] {
			t.Errorf("item %q runs `make %s`, which the Makefile does not define",
				it.name, it.target)
		}
	}
}

// A launcher that shows one command and runs another is the worst failure this
// file can have, and it is invisible to every other test: the row still works,
// it just does something else. Every label is currently the literal command.
func TestLabelIsTheCommandItRuns(t *testing.T) {
	for _, it := range allItems() {
		var b strings.Builder
		if it.cmdType == cmdMake {
			b.WriteString("make ")
		}
		b.WriteString(it.target)
		for _, a := range it.args {
			b.WriteString(" ")
			b.WriteString(a)
		}
		if got := b.String(); got != it.name {
			t.Errorf("label %q does not match what it runs (%q)", it.name, got)
		}
	}
}

// nuke-mrk is the one item behind the typed-confirmation gate. If a second
// destructive command is ever added, this fails and whoever added it has to
// decide, deliberately, whether it belongs behind the same gate.
func TestOnlyNukeMrkIsGated(t *testing.T) {
	var gated []string
	for _, it := range allItems() {
		if it.needsNuke {
			gated = append(gated, it.target)
		}
	}
	if len(gated) != 1 || gated[0] != "nuke-mrk" {
		t.Errorf("items behind the nuke confirmation = %v; want exactly [nuke-mrk]", gated)
	}
}

func exists(p string) bool { _, err := os.Stat(p); return err == nil }
