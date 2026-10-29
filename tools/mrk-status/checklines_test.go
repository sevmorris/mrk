package main

import (
	"bytes"
	"encoding/json"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// tests/fixtures/check-lines.json is the line contract of the five --check
// modes as data: for each case, the fields and the line mrk_check_line writes
// for them. The tests here hold lib.sh's encoder and this package's decoder to
// it. Dipstick and Barkeep keep a copy, byte for byte, and hold their own
// decoders to the same lines. Until 2026-10-29 each app tested its decoder
// against lines it wrote by hand, and both decoders passed over lines that mrk
// writes (audit 22, Z-4, Z-5 and O-1).
//
// The fields are written by hand. The lines are mrk_check_line's: with
// MRK_UPDATE_FIXTURES=1, TestCheckLinesFixtureIsTheEncoders writes them again.

const checkLinesPath = "../../tests/fixtures/check-lines.json"

const checkLinesAbout = "The line contract of mrk's five --check modes, as data. " +
	"For each case: the fields, and the line that mrk_check_line in scripts/lib.sh writes for them, without its newline. " +
	"A reader that undoes the escapes gets the fields back from the line. " +
	"It splits an output into lines only at a newline, and each line into fields only at a tab. " +
	"sevmorris/mrk keeps this file at tests/fixtures/check-lines.json and writes its lines with MRK_UPDATE_FIXTURES=1 go test in tools/mrk-status. " +
	"Dipstick and Barkeep keep a copy, byte for byte, which mrk's tests compare. Do not edit a line by hand."

// checkLinesCopies are the copies in the apps, by repository under ~/Projects.
var checkLinesCopies = map[string]string{
	"Dipstick": "Tests/DipstickTests/Fixtures/check-lines.json",
	"Barkeep":  "BarkeepTests/Fixtures/check-lines.json",
}

type checkLinesFixture struct {
	About string           `json:"about"`
	Cases []checkLinesCase `json:"cases"`
}

type checkLinesCase struct {
	Why    string   `json:"why"`
	Fields []string `json:"fields"`
	Line   string   `json:"line"`
}

func readCheckLines(t *testing.T) checkLinesFixture {
	t.Helper()
	data, err := os.ReadFile(checkLinesPath)
	if err != nil {
		t.Fatal(err)
	}
	var fx checkLinesFixture
	if err := json.Unmarshal(data, &fx); err != nil {
		t.Fatalf("%s: %v", checkLinesPath, err)
	}
	if len(fx.Cases) == 0 {
		t.Fatalf("%s has no cases", checkLinesPath)
	}
	return fx
}

// Each line in the fixture is what mrk_check_line writes for its fields, under
// the bash on PATH and under macOS's bash 3.2.
func TestCheckLinesFixtureIsTheEncoders(t *testing.T) {
	root, err := filepath.Abs(filepath.Join("..", ".."))
	if err != nil {
		t.Fatal(err)
	}
	fx := readCheckLines(t)
	update := os.Getenv("MRK_UPDATE_FIXTURES") == "1"
	script := `source "$1/scripts/lib.sh" || exit 1; shift; mrk_check_line "$@"`
	for i, c := range fx.Cases {
		for _, sh := range []string{"bash", "/bin/bash"} {
			out, err := exec.Command(sh, append([]string{"-c", script, "bash", root}, c.Fields...)...).Output()
			if err != nil {
				t.Fatalf("%s: case %d: %v", sh, i+1, err)
			}
			line, ok := strings.CutSuffix(string(out), "\n")
			if !ok || strings.Contains(line, "\n") {
				t.Fatalf("%s: case %d: mrk_check_line did not write one line: %q", sh, i+1, out)
			}
			if update && sh == "bash" {
				fx.Cases[i].Line = line
				continue
			}
			if line != fx.Cases[i].Line {
				t.Errorf("%s: case %d (%s): mrk_check_line wrote %q, and the fixture has %q", sh, i+1, c.Why, line, fx.Cases[i].Line)
			}
		}
	}
	if !update {
		if fx.About != checkLinesAbout {
			t.Errorf("%s: its about text is not the one this test writes; run MRK_UPDATE_FIXTURES=1 go test", checkLinesPath)
		}
		return
	}
	fx.About = checkLinesAbout
	var b bytes.Buffer
	enc := json.NewEncoder(&b)
	enc.SetEscapeHTML(false)
	enc.SetIndent("", "  ")
	if err := enc.Encode(fx); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(checkLinesPath, b.Bytes(), 0o644); err != nil {
		t.Fatal(err)
	}
	t.Logf("wrote %d lines to %s", len(fx.Cases), checkLinesPath)
}

// checkLines' split and unescapeField give back the fields of each line. Then
// the lines are joined as one output, as a --check prints them, and the split
// at each newline gives back each line.
func TestCheckLinesFixtureDecodes(t *testing.T) {
	fx := readCheckLines(t)
	var out strings.Builder
	for i, c := range fx.Cases {
		f := strings.Split(c.Line, "\t")
		if len(f) != len(c.Fields) {
			t.Errorf("case %d (%s): %d fields, want %d", i+1, c.Why, len(f), len(c.Fields))
			continue
		}
		for j, want := range c.Fields {
			if got := unescapeField(f[j]); got != want {
				t.Errorf("case %d (%s): field %d came back as %q, want %q", i+1, c.Why, j+1, got, want)
			}
		}
		out.WriteString(c.Line + "\n")
	}
	lines := strings.Split(strings.TrimSuffix(out.String(), "\n"), "\n")
	if len(lines) != len(fx.Cases) {
		t.Fatalf("the joined output split into %d lines, want %d", len(lines), len(fx.Cases))
	}
	for i, c := range fx.Cases {
		if lines[i] != c.Line {
			t.Errorf("line %d of the joined output is %q, want %q", i+1, lines[i], c.Line)
		}
	}
}

// The apps' copies are this file, byte for byte. An app that is not checked
// out under ~/Projects is passed over, as in CI; an app that is checked out
// and has no copy, or an older one, fails.
func TestCheckLinesFixtureCopies(t *testing.T) {
	want, err := os.ReadFile(checkLinesPath)
	if err != nil {
		t.Fatal(err)
	}
	home, err := os.UserHomeDir()
	if err != nil {
		t.Skip("no HOME, so no ~/Projects to compare")
	}
	for app, rel := range checkLinesCopies {
		repo := filepath.Join(home, "Projects", app)
		if _, err := os.Stat(filepath.Join(repo, ".git")); err != nil {
			t.Logf("%s is not checked out at %s: not compared", app, repo)
			continue
		}
		got, err := os.ReadFile(filepath.Join(repo, rel))
		if err != nil {
			t.Errorf("%s has no copy of %s at %s: %v", app, checkLinesPath, rel, err)
			continue
		}
		if !bytes.Equal(got, want) {
			t.Errorf("%s's %s is not tests/fixtures/check-lines.json; copy it again", app, rel)
		}
	}
}
