package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
)

// Every check can carry a fix command, which the f key runs as
//
//	cd <repoRoot> && <fix>
//
// so a fix has to resolve from the repo root. checkHardening carried the bare
// string "hardening.sh", which resolves nowhere: it is installed on the PATH as
// "harden", and the file itself is in scripts/, not the repo root. Pressing f on
// Security Hardening therefore failed with "command not found" — a fix action
// that had never been run. Nothing caught it because a fix command is just a
// string until someone presses the key.
//
// This gate is the reason that class cannot come back.

var makeTargetRe = regexp.MustCompile(`(?m)^([a-zA-Z][a-zA-Z0-9_-]*):`)

func makeTargets(t *testing.T) map[string]bool {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("..", "..", "Makefile"))
	if err != nil {
		t.Fatalf("cannot read Makefile: %v", err)
	}
	targets := map[string]bool{}
	for _, m := range makeTargetRe.FindAllStringSubmatch(string(b), -1) {
		targets[m[1]] = true
	}
	if len(targets) == 0 {
		t.Fatal("parsed no targets from the Makefile — the gate would pass vacuously")
	}
	return targets
}

func TestEveryFixCommandResolves(t *testing.T) {
	// An empty directory drives each check into its remediation branch, which
	// is where the fix commands live.
	tmp := t.TempDir()
	bin := filepath.Join(tmp, "bin")

	groups := []group{
		checkDotfiles(tmp, tmp),
		checkTools(tmp, bin),
		checkDefaults(tmp),
		checkHardening(tmp),
		checkPATH(bin),
		checkBrewfile(tmp),
		checkShell(),
		checkHomebrew(),
	}

	targets := makeTargets(t)
	checked := 0
	for _, g := range groups {
		if g.fix == "" {
			continue
		}
		checked++
		fields := strings.Fields(g.fix)
		if fields[0] == "make" {
			if len(fields) < 2 {
				t.Errorf("%s: fix %q is a bare \"make\"", g.name, g.fix)
				continue
			}
			if !targets[fields[1]] {
				t.Errorf("%s: fix %q names Make target %q, which the Makefile does not define",
					g.name, g.fix, fields[1])
			}
			continue
		}
		if _, err := exec.LookPath(fields[0]); err != nil {
			t.Errorf("%s: fix %q starts with %q, which does not resolve on the PATH — "+
				"the f key would fail with \"command not found\"", g.name, g.fix, fields[0])
		}
	}
	if checked == 0 {
		t.Fatal("no fix commands were examined — the gate passed vacuously")
	}
	t.Logf("checked %d fix command(s)", checked)
}
