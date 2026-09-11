package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// The dashboard's job is to tell the truth about the machine, so the failure
// that matters most is a wrong severity: a false green hides a broken install,
// and a false red sends you chasing nothing. Six of the checks take their paths
// as arguments, which makes them exercisable against a constructed directory
// rather than against whatever this machine happens to look like.
//
// checkHomebrew and the live half of checkBrewfile are not covered here — they
// read the real system by design. So does checkShell, but its remediation
// branch is driven at the end of this file with a fake zsh first on PATH.

func texts(g group) string {
	var b strings.Builder
	for _, l := range g.lines {
		b.WriteString(l.text)
		b.WriteString("\n")
	}
	return b.String()
}

// ── Dotfiles ────────────────────────────────────────────────────────────────

// dotfileRepo builds a repo with one dotfile, plus the three kinds of file the
// check is supposed to ignore.
func dotfileRepo(t *testing.T) (repoRoot, home string) {
	t.Helper()
	repoRoot, home = t.TempDir(), t.TempDir()
	dots := filepath.Join(repoRoot, "dotfiles")
	if err := os.MkdirAll(dots, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, n := range []string{".zshrc", "README.md", "sample.example", "notes.md"} {
		if err := os.WriteFile(filepath.Join(dots, n), []byte("x"), 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return repoRoot, home
}

func TestCheckDotfilesLinkedIsOK(t *testing.T) {
	repo, home := dotfileRepo(t)
	if err := os.Symlink(filepath.Join(repo, "dotfiles", ".zshrc"), filepath.Join(home, ".zshrc")); err != nil {
		t.Fatal(err)
	}
	g := checkDotfiles(repo, home)
	if g.sev != sevOK {
		t.Errorf("a correctly linked dotfile should be OK, got sev=%v:\n%s", g.sev, texts(g))
	}
	// README.md, sample.example and notes.md must not be counted as unlinked.
	for _, skipped := range []string{"README", "sample.example", "notes.md"} {
		if strings.Contains(texts(g), skipped) {
			t.Errorf("%s should be skipped, not reported", skipped)
		}
	}
}

func TestCheckDotfilesRealFileIsNotMistakenForALink(t *testing.T) {
	// The false-green case: a real file sitting where the symlink belongs means
	// edits are going somewhere mrk does not track.
	repo, home := dotfileRepo(t)
	if err := os.WriteFile(filepath.Join(home, ".zshrc"), []byte("hand-written"), 0o644); err != nil {
		t.Fatal(err)
	}
	g := checkDotfiles(repo, home)
	if g.sev == sevOK {
		t.Errorf("a real file where a symlink belongs must not read as OK:\n%s", texts(g))
	}
}

func TestCheckDotfilesSymlinkToTheWrongTargetIsNotOK(t *testing.T) {
	repo, home := dotfileRepo(t)
	other := filepath.Join(t.TempDir(), "elsewhere")
	if err := os.WriteFile(other, []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(other, filepath.Join(home, ".zshrc")); err != nil {
		t.Fatal(err)
	}
	g := checkDotfiles(repo, home)
	if g.sev == sevOK {
		t.Errorf("a symlink pointing outside the repo must not read as OK:\n%s", texts(g))
	}
}

func TestCheckDotfilesMissingDirWarns(t *testing.T) {
	g := checkDotfiles(t.TempDir(), t.TempDir())
	if g.sev != sevWarn {
		t.Errorf("a missing dotfiles/ should warn, got sev=%v", g.sev)
	}
}

// ── Rollback-backed checks ──────────────────────────────────────────────────

// An empty rollback script is the interesting case for both of these: the file
// exists, so a naive check reports "Applied" when nothing was ever recorded.
func TestCheckDefaultsDistinguishesEmptyFromApplied(t *testing.T) {
	dir := t.TempDir()
	if g := checkDefaults(dir); g.sev != sevInfo || !strings.Contains(texts(g), "Not applied") {
		t.Errorf("no rollback should read as not applied, got sev=%v:\n%s", g.sev, texts(g))
	}

	path := filepath.Join(dir, "defaults-rollback.sh")
	if err := os.WriteFile(path, []byte("#!/usr/bin/env bash\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	g := checkDefaults(dir)
	if g.sev == sevOK {
		t.Errorf("an empty rollback must not read as Applied:\n%s", texts(g))
	}

	if err := os.WriteFile(path, []byte("#!/usr/bin/env bash\ndefaults write com.example Key -bool true\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	if g := checkDefaults(dir); g.sev != sevOK || !strings.Contains(texts(g), "1 change") {
		t.Errorf("one recorded change should read as Applied with a count of 1:\n%s", texts(g))
	}
}

func TestCheckHardeningDistinguishesEmptyFromApplied(t *testing.T) {
	dir := t.TempDir()
	if g := checkHardening(dir); g.sev != sevInfo {
		t.Errorf("no rollback should read as not applied, got sev=%v", g.sev)
	}

	path := filepath.Join(dir, "hardening-rollback.sh")
	if err := os.WriteFile(path, []byte("#!/usr/bin/env bash\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	if g := checkHardening(dir); g.sev == sevOK {
		t.Errorf("an empty rollback must not read as Applied:\n%s", texts(g))
	}

	body := "#!/usr/bin/env bash\nsudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate off\n"
	if err := os.WriteFile(path, []byte(body), 0o755); err != nil {
		t.Fatal(err)
	}
	if g := checkHardening(dir); g.sev != sevOK {
		t.Errorf("a recorded sudo change should read as Applied:\n%s", texts(g))
	}
}

// ── PATH ────────────────────────────────────────────────────────────────────

func TestCheckPATH(t *testing.T) {
	binDir := t.TempDir()
	t.Setenv("PATH", strings.Join([]string{"/usr/bin", binDir, "/bin"}, string(os.PathListSeparator)))
	if g := checkPATH(binDir); g.sev != sevOK {
		t.Errorf("binDir on PATH should be OK, got sev=%v", g.sev)
	}

	t.Setenv("PATH", "/usr/bin:/bin")
	if g := checkPATH(binDir); g.sev != sevWarn {
		t.Errorf("binDir absent from PATH should warn, got sev=%v", g.sev)
	}

	// A prefix must not count as a match: /opt/bin is not /opt/bin-extra.
	t.Setenv("PATH", binDir+"-extra")
	if g := checkPATH(binDir); g.sev != sevWarn {
		t.Errorf("a PATH entry that merely starts with binDir must not count as present")
	}
}

// ── Shell ───────────────────────────────────────────────────────────────────

// checkShell reads the real login shell, so this puts a zsh that cannot be it
// first on PATH to drive the check into its remediation branch. chsh refuses a
// shell /etc/shells does not list, and a new Mac is in exactly that state after
// make all: setup runs before brew installs the zsh it would have registered.
// Until 2026-09-11 the fix was that chsh regardless.
func TestCheckShellOffersChshOnlyForAListedShell(t *testing.T) {
	dir := t.TempDir()
	zsh := filepath.Join(dir, "zsh")
	if err := os.Symlink("/bin/zsh", zsh); err != nil {
		t.Fatal(err)
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	shells := filepath.Join(t.TempDir(), "shells")
	old := shellsFile
	t.Cleanup(func() { shellsFile = old })
	shellsFile = shells

	// A "-beta" sibling must not count as the shell itself.
	if err := os.WriteFile(shells, []byte("/bin/bash\n/bin/zsh\n"+zsh+"-beta\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	g := checkShell()
	if g.sev != sevWarn || !strings.Contains(g.lines[0].text, "expected: "+zsh) {
		t.Skipf("the check never reached its remediation branch here: %s", texts(g))
	}
	if want := `make setup ARGS="--only shell"`; g.fix != want {
		t.Errorf("unlisted shell: fix = %q, want %q — chsh would refuse it", g.fix, want)
	}
	if !strings.Contains(texts(g), "not listed in /etc/shells") {
		t.Errorf("unlisted shell: the panel should say why chsh is not offered:\n%s", texts(g))
	}

	if err := os.WriteFile(shells, []byte("/bin/zsh\n  "+zsh+"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if g := checkShell(); g.fix != "chsh -s "+zsh {
		t.Errorf("listed shell: fix = %q, want %q", g.fix, "chsh -s "+zsh)
	}
}
