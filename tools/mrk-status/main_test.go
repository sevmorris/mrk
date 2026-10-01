package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Brewfile drift is sync's own answer, `sync --check`, read here. The lesson
// the checkBrewfile these replace was written around still holds: a check that
// could not run must say so, and never render as a screen of missing
// packages. Until 2026-09-09 a failed `brew list` was swallowed and every
// tracked package read as "(missing)".

// withStubBrew puts a brew running script first on PATH, and leaves no other
// Homebrew for brewBin to find.
func withStubBrew(t *testing.T, script string) string {
	t.Helper()
	dir := t.TempDir()
	stub := filepath.Join(dir, "brew")
	if err := os.WriteFile(stub, []byte(script), 0o755); err != nil {
		t.Fatalf("writing stub: %v", err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	noOtherBrew(t)
	return dir
}

// noOtherBrew stops brewBin finding the real Homebrew at its fixed paths.
func noOtherBrew(t *testing.T) {
	t.Helper()
	old := brewPaths
	brewPaths = []string{filepath.Join(t.TempDir(), "no-brew")}
	t.Cleanup(func() { brewPaths = old })
}

// repoWithSync makes a checkout whose scripts/sync is script.
func repoWithSync(t *testing.T, script string) string {
	t.Helper()
	root := t.TempDir()
	if err := os.MkdirAll(filepath.Join(root, "scripts"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(root, "scripts", "sync"), []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return root
}

func TestBrewDriftReadsSyncCheck(t *testing.T) {
	withStubBrew(t, "#!/bin/sh\nexit 0\n")
	repo := repoWithSync(t, "#!/bin/sh\n[ \"$1\" = --check ] || exit 9\n"+
		"printf 'add\\tformula\\tjq\\nadd\\tcask\\tfirefox\\nprune\\tformula\\twget\\nnoise line\\n'\n"+
		"echo '  ▸ Scanning installed Homebrew packages...' >&2\n")
	d := readBrewDrift(repo)
	if d.err != nil || d.noBrew {
		t.Fatalf("a successful sync --check should be read, got err=%v noBrew=%v", d.err, d.noBrew)
	}
	if got := strings.Join(d.adds, ","); got != "jq,firefox (cask)" {
		t.Errorf("adds = %q, want jq,firefox (cask)", got)
	}
	if got := strings.Join(d.prunes, ","); got != "wget" {
		t.Errorf("prunes = %q, want wget", got)
	}
}

func TestBrewDriftFailureIsAFailureNotMissingPackages(t *testing.T) {
	withStubBrew(t, "#!/bin/sh\nexit 0\n")
	repo := repoWithSync(t, "#!/bin/sh\necho '  ▸ Scanning installed Homebrew packages...' >&2\n"+
		"echo '  ✗ brew list --formula failed — cannot determine installed formulae' >&2\nexit 1\n")
	d := readBrewDrift(repo)
	if d.err == nil || !strings.Contains(d.err.Error(), "brew list --formula failed") {
		t.Fatalf("a failed sync --check should be an error naming sync's last word, got %v", d.err)
	}
	un := checkUnrecorded(repo, t.TempDir(), d)
	for _, l := range un.lines {
		if strings.Contains(l.text, "not installed") {
			t.Errorf("a check that could not run reported packages as not installed: %q", l.text)
		}
	}
	if !strings.Contains(texts(un), "sync --check failed") {
		t.Errorf("Unrecorded should say the comparison failed:\n%s", texts(un))
	}
	if g := brewfileSummary(writeBrewfile(t), d); g.sev != sevWarn {
		t.Errorf("Installation's Brewfile line should warn when the comparison failed, got sev=%v", g.sev)
	}
}

func TestBrewDriftWithNoHomebrew(t *testing.T) {
	t.Setenv("PATH", t.TempDir())
	noOtherBrew(t)
	repo := repoWithSync(t, "#!/bin/sh\necho 'must not run' >&2\nexit 1\n")
	d := readBrewDrift(repo)
	if !d.noBrew || d.err != nil {
		t.Fatalf("with no Homebrew anywhere, drift should be noBrew without running sync, got %+v", d)
	}
}

func writeBrewfile(t *testing.T) string {
	t.Helper()
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "Brewfile"), []byte("brew \"jq\"\ncask \"firefox\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	return root
}
