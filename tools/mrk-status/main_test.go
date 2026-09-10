package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// checkBrewfile used to swallow a failed `brew list` and leave its lookup map
// empty, so every tracked package missed and the whole Brewfile rendered as
// "(missing)" — a screen of fabricated failures with nothing saying the check
// had not run. brew being *absent* was already handled; brew present and
// *failing* was not. These tests pin both halves of that distinction.
//
// The stub shadows brew on PATH rather than mocking exec, because the bug was
// in how the exit status was read, and only a real failing process exercises it.

func withStubBrew(t *testing.T, script string) string {
	t.Helper()
	dir := t.TempDir()
	stub := filepath.Join(dir, "brew")
	if err := os.WriteFile(stub, []byte(script), 0o755); err != nil {
		t.Fatalf("writing stub: %v", err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	return dir
}

// repoWithBrewfile writes a Brewfile holding one formula and one cask.
func repoWithBrewfile(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	body := "brew \"jq\"\ncask \"firefox\"\n"
	if err := os.WriteFile(filepath.Join(root, "Brewfile"), []byte(body), 0o644); err != nil {
		t.Fatalf("writing Brewfile: %v", err)
	}
	return root
}

func TestCheckBrewfileReportsFailedListAsCheckFailure(t *testing.T) {
	withStubBrew(t, "#!/bin/sh\n[ \"$1\" = list ] && exit 2\nexit 0\n")
	g := checkBrewfile(repoWithBrewfile(t))

	if g.sev != sevWarn {
		t.Errorf("a failed `brew list` should surface as sevWarn, got sev=%v", g.sev)
	}
	for _, l := range g.lines {
		if strings.Contains(l.text, "missing") {
			t.Errorf("a failed check must not report packages as missing; got %q", l.text)
		}
	}
	joined := ""
	for _, l := range g.lines {
		joined += l.text + "\n"
	}
	if !strings.Contains(joined, "cannot check what is installed") {
		t.Errorf("the failure should say the check could not run; got:\n%s", joined)
	}
}

func TestCheckBrewfileStillFlagsGenuinelyMissingPackages(t *testing.T) {
	// brew works and reports nothing installed — here "missing" is the truth,
	// and suppressing it would trade one wrong answer for another.
	withStubBrew(t, "#!/bin/sh\nexit 0\n")
	g := checkBrewfile(repoWithBrewfile(t))

	// Count per-package rows only. The group also carries an sevInfo summary
	// ("0/2 installed, 2 missing"), which counting raw substrings would include.
	got := 0
	for _, l := range g.lines {
		if l.sev == sevErr && strings.Contains(l.text, "missing") {
			got++
		}
	}
	if got != 2 {
		t.Errorf("both tracked packages should read as missing when brew succeeds and lists nothing, got %d", got)
	}
}
