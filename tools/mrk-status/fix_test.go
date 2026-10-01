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
	// An empty directory drives each installation check into its remediation
	// branch, which is where its fix lives. The daily panels' fixes are the
	// constants in dailyFixes, each of which a line can carry.
	tmp := t.TempDir()
	bin := filepath.Join(tmp, "bin")

	groups := []group{
		checkDotfiles(tmp, tmp),
		checkTools(tmp, bin),
		checkDefaults(tmp),
		checkHardening(tmp),
		checkPATH(tmp, bin),
		checkShell(),
		checkHomebrew(),
	}
	type fix struct{ from, cmd string }
	var fixes []fix
	for _, g := range groups {
		if g.fix != "" {
			fixes = append(fixes, fix{g.name, g.fix})
		}
		for _, l := range g.lines {
			if l.fix != "" {
				fixes = append(fixes, fix{g.name, l.fix})
			}
		}
	}
	for _, f := range dailyFixes {
		fixes = append(fixes, fix{"daily panels", f})
	}

	repo, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	targets := makeTargets(t)
	for _, f := range fixes {
		fields := strings.Fields(f.cmd)
		switch {
		case fields[0] == "make":
			if len(fields) < 2 {
				t.Errorf("%s: fix %q is a bare \"make\"", f.from, f.cmd)
			} else if !targets[fields[1]] {
				t.Errorf("%s: fix %q names Make target %q, which the Makefile does not define",
					f.from, f.cmd, fields[1])
			}
		case strings.Contains(fields[0], "/"):
			// A path runs from the repo root, after the f key's cd.
			p := filepath.Join(repo, fields[0])
			if fi, err := os.Stat(p); err != nil || fi.Mode()&0o111 == 0 {
				t.Errorf("%s: fix %q names %s, which is not an executable in the repository",
					f.from, f.cmd, fields[0])
			}
		default:
			if _, err := exec.LookPath(fields[0]); err != nil {
				t.Errorf("%s: fix %q starts with %q, which does not resolve on the PATH — "+
					"the f key would fail with \"command not found\"", f.from, f.cmd, fields[0])
			}
		}
	}
	if len(fixes) < len(dailyFixes)+3 {
		t.Fatalf("only %d fix commands were examined — the gate is passing on too little", len(fixes))
	}
	t.Logf("checked %d fix command(s)", len(fixes))
}

// Resolving is not the same as working. Until 2026-09-11 the Tools fix was
// "make setup": a real target, so the gate above passed, and one that leaves a
// dead link exactly where it was — setup links only scripts that exist, and a
// dead link points at one that does not. The dashboard then offered the same fix
// again. This runs the fix the check names, the way the f key does, against a
// sandbox HOME, and requires the check to come back clean.
func TestToolsFixRepairsADeadLink(t *testing.T) {
	repo, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	home := t.TempDir()
	bin := filepath.Join(home, "bin")
	if err := os.MkdirAll(bin, 0o755); err != nil {
		t.Fatal(err)
	}
	gone := filepath.Join(repo, "scripts", "a-script-that-was-removed")
	if _, err := os.Lstat(gone); err == nil {
		t.Fatalf("%s exists; the fixture needs a path that does not", gone)
	}
	if err := os.Symlink(gone, filepath.Join(bin, "a-script-that-was-removed")); err != nil {
		t.Fatal(err)
	}

	before := checkTools(repo, bin)
	if before.sev != sevWarn || before.fix == "" {
		t.Fatalf("a dead link should warn and carry a fix, got sev=%v fix=%q:\n%s", before.sev, before.fix, texts(before))
	}
	cmd := exec.Command("/bin/sh", "-c", "cd '"+repo+"' && "+before.fix)
	cmd.Env = append(os.Environ(), "HOME="+home)
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("fix %q failed: %v\n%s", before.fix, err, out)
	}
	if after := checkTools(repo, bin); after.sev != sevOK {
		t.Errorf("fix %q ran and the check still fails, sev=%v:\n%s", before.fix, after.sev, texts(after))
	}
}
