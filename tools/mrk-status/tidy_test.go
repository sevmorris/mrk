package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Upkeep's Clones line reads tidy-projects --check, run here as a stub in a
// temporary checkout, and the survey it keeps in a temporary home. The items a
// kept survey names are checked against real git repositories.

// tidyStub writes the checkout's bin/tidy-projects: it refuses any argument
// but --check, writes a mark when it runs, and then runs body.
func tidyStub(t *testing.T, repo, body string) (ran string) {
	t.Helper()
	ran = filepath.Join(t.TempDir(), "ran")
	writeScript(t, filepath.Join(repo, "bin", "tidy-projects"),
		"#!/bin/sh\n[ \"$*\" = --check ] || exit 9\ntouch '"+ran+"'\n"+body)
	return ran
}

func exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// checkOut is --check lines, each FIELD... escaped as mrk_check_line does.
func checkOut(lines ...[]string) string {
	var b strings.Builder
	esc := strings.NewReplacer(`\`, `\\`, "\t", `\t`, "\n", `\n`)
	for _, f := range lines {
		for i := range f {
			f[i] = esc.Replace(f[i])
		}
		b.WriteString(strings.Join(f, "\t") + "\n")
	}
	return b.String()
}

func printf(s string) string {
	return "cat <<'EOF'\n" + s + "EOF\n"
}

func TestTidyReadsTheCheckLines(t *testing.T) {
	repo, home := t.TempDir(), t.TempDir()
	out := checkOut(
		[]string{"ff", "Alpha", "/p/Alpha", "main", ""},
		[]string{"refs", "Alpha", "/p/Alpha", "origin/a origin/b", ""},
		[]string{"worktrees", "Magic Backup Machine", "/p/Magic Backup Machine", "/p/Magic Backup Machine/.claude/worktrees/x", ""},
		[]string{"branches", "Alpha", "/p/Alpha", "claude/one", ""},
		[]string{"branches", "beta", "/p/beta", "claude/tab\there", ""},
		[]string{"deploys", "Alpha", "/p/Alpha", "owner/Alpha", ""},
		[]string{"build", "Alpha", "/p/Alpha", "/p/Alpha/build", "1024"},
		[]string{"build", "Xcode", "/dd", "/dd", "2048"},
		[]string{"newcleanup", "Alpha", "/p/Alpha", "x", "", "a later field"},
		[]string{"ff", "short"},
	)
	tidyStub(t, repo, printf(out))
	r := readTidy(repo, home)
	if r.err != nil {
		t.Fatal(r.err)
	}
	if len(r.items) != 8 || r.unknown != 2 {
		t.Fatalf("%d items and %d unknown, want 8 and 2: %+v", len(r.items), r.unknown, r.items)
	}
	if got := r.items[4].item; got != "claude/tab\there" {
		t.Errorf("an escaped field reads %q, want its tab back", got)
	}
	if kept, err := os.ReadFile(tidyCache(home)); err != nil || string(kept) != out {
		t.Errorf("the survey should be kept as it was printed (%v):\n%s", err, kept)
	}

	lines := tidyLines(r)
	want := "Clones: 2 merged branches, 1 finished worktree, stale refs in 1 clone and 1 default branch behind origin, " +
		"surveyed just now: Alpha, beta, Magic Backup Machine"
	if l := lines[0]; l.sev != sevWarn || l.text != want || l.fix != fixTidy {
		t.Errorf("first line = %v %q → %q,\nwant warn %q → %q", l.sev, l.text, l.fix, want, fixTidy)
	}
	aside := "  not on the button, as their cleanups delete what cannot come back: 1 Pages site past 10 deployments; " +
		"1 build folder and Xcode's DerivedData, 3.0 MB (tidy-projects lists them)"
	if l := lines[1]; l.sev != sevInfo || l.text != aside || l.fix != "" {
		t.Errorf("second line = %v %q → %q,\nwant info %q and no fix: deploys and build are never on a button", l.sev, l.text, l.fix, aside)
	}
	if l, ok := line(group{lines: lines}, "tidy-projects --check: 2 lines that this mrk-status cannot read"); !ok || l.fix != fixBuildTools {
		t.Errorf("the lines passed over should warn, with make build-tools:\n%v", lines)
	}
	for _, l := range lines {
		if strings.Contains(l.fix, "deploys") || strings.Contains(l.fix, "build,") || strings.HasSuffix(l.fix, ",build") {
			t.Errorf("a fix takes deploys or build: %q", l.fix)
		}
	}
}

func TestTidyNothingToTidy(t *testing.T) {
	for _, tc := range []struct {
		name, out string
		lines     int
	}{
		{"no cleanup at all", "", 1},
		{"only what is left to the owner", checkOut([]string{"deploys", "Alpha", "/p/Alpha", "owner/Alpha", ""}), 2},
	} {
		t.Run(tc.name, func(t *testing.T) {
			repo := t.TempDir()
			tidyStub(t, repo, printf(tc.out))
			lines := tidyLines(readTidy(repo, t.TempDir()))
			if len(lines) != tc.lines || lines[0].sev != sevOK || lines[0].text != "Clones: no merged branches, finished worktrees or stale refs, surveyed just now" || lines[0].fix != "" {
				t.Errorf("lines = %v", lines)
			}
		})
	}
}

// A kept survey is read again while it is young, without running
// tidy-projects, and an item that has left its clone since is not counted.
func TestTidyKeepsTheSurveyAndDropsWhatIsGone(t *testing.T) {
	gitEnv(t)
	repo, home := t.TempDir(), t.TempDir()
	ran := tidyStub(t, repo, "exit 1\n")

	// A clone one commit behind its origin, with a merged branch, a branch
	// deleted since, a worktree, a stale ref and a build folder.
	clone := filepath.Join(t.TempDir(), "Alpha")
	origin := newRepo(t, clone, true)
	other := filepath.Join(t.TempDir(), "other")
	run(t, "", "git", "clone", "-q", origin, other)
	write(t, filepath.Join(other, "two"), "2\n")
	run(t, other, "git", "add", "-A")
	run(t, other, "git", "commit", "-qm", "two")
	run(t, other, "git", "push", "-q")
	run(t, clone, "git", "fetch", "-q")
	run(t, clone, "git", "branch", "merged")
	run(t, clone, "git", "update-ref", "refs/remotes/origin/stale", "HEAD")
	wt := filepath.Join(t.TempDir(), "wt")
	run(t, clone, "git", "worktree", "add", "-q", "--detach", wt)
	wt, _ = filepath.EvalSymlinks(wt) // git lists a worktree by its real path
	if err := os.MkdirAll(filepath.Join(clone, "build"), 0o755); err != nil {
		t.Fatal(err)
	}
	// Level with its origin.
	level := filepath.Join(t.TempDir(), "Beta")
	newRepo(t, level, true)

	still := [][]string{
		{"ff", "Alpha", clone, "main", ""},
		{"refs", "Alpha", clone, "origin/gone origin/stale", ""},
		{"worktrees", "Alpha", clone, wt, ""},
		{"branches", "Alpha", clone, "merged", ""},
		{"deploys", "Alpha", clone, "owner/Alpha", ""},
		{"build", "Alpha", clone, filepath.Join(clone, "build"), "100"},
	}
	since := [][]string{
		{"ff", "Beta", level, "main", ""},
		{"refs", "Beta", level, "origin/gone", ""},
		{"worktrees", "Alpha", clone, filepath.Join(t.TempDir(), "removed"), ""},
		{"branches", "Alpha", clone, "deleted", ""},
		{"branches", "Gamma", filepath.Join(t.TempDir(), "no-such-clone"), "x", ""},
		{"build", "Alpha", clone, filepath.Join(clone, ".build"), "100"},
	}
	write(t, tidyCache(home), checkOut(append(append([][]string{}, still...), since...)...))
	at := time.Now().Add(-time.Hour).Truncate(time.Second)
	if err := os.Chtimes(tidyCache(home), at, at); err != nil {
		t.Fatal(err)
	}

	r := readTidy(repo, home)
	if exists(ran) {
		t.Error("tidy-projects ran, and the kept survey is an hour old")
	}
	if r.err != nil || !r.at.Equal(at) {
		t.Fatalf("err %v, surveyed at %v, want the file's date %v", r.err, r.at, at)
	}
	var got []string
	for _, it := range r.items {
		item := it.item
		if strings.HasPrefix(item, "/") {
			item = filepath.Base(item)
		}
		got = append(got, it.cleanup+" "+it.repo+" "+item)
	}
	want := "ff Alpha main,refs Alpha origin/gone origin/stale,worktrees Alpha wt,branches Alpha merged,deploys Alpha owner/Alpha,build Alpha build"
	if strings.Join(got, ",") != want {
		t.Errorf("items = %s\nwant    %s", strings.Join(got, ","), want)
	}
	if l := tidyLines(r)[0]; !strings.Contains(l.text, ", surveyed 1 hour ago: Alpha") {
		t.Errorf("the line should give the kept survey's age: %q", l.text)
	}
}

// A survey older than tidyMaxAge, or dated in the future, is run again, and
// the new one is kept.
func TestTidySurveysAgainWhenTheKeptOneIsOld(t *testing.T) {
	for _, age := range []time.Duration{tidyMaxAge + time.Minute, -time.Hour} {
		repo, home := t.TempDir(), t.TempDir()
		out := checkOut([]string{"branches", "Alpha", "/p/Alpha", "claude/new", ""})
		ran := tidyStub(t, repo, printf(out))
		write(t, tidyCache(home), checkOut([]string{"branches", "Alpha", "/p/Alpha", "claude/old", ""}))
		at := time.Now().Add(-age)
		if err := os.Chtimes(tidyCache(home), at, at); err != nil {
			t.Fatal(err)
		}
		r := readTidy(repo, home)
		if !exists(ran) || len(r.items) != 1 || r.items[0].item != "claude/new" {
			t.Errorf("a survey %v old: ran %v, items %+v", age, exists(ran), r.items)
		}
		if kept, _ := os.ReadFile(tidyCache(home)); string(kept) != out {
			t.Errorf("a survey %v old: the new one should be kept, got:\n%s", age, kept)
		}
		if time.Since(r.at) > time.Minute {
			t.Errorf("a survey %v old: surveyed at %v, want now", age, r.at)
		}
	}
}

func TestTidyFailureIsAWarning(t *testing.T) {
	repo, home := t.TempDir(), t.TempDir()
	tidyStub(t, repo, "echo 'Surveying 0 clones…' >&2\necho '  ✗ No git clones under /nowhere' >&2\necho 'Usage: …' >&2\nexit 1\n")
	lines := tidyLines(readTidy(repo, home))
	want := "Clones: tidy-projects --check failed: No git clones under /nowhere"
	if len(lines) != 1 || lines[0].sev != sevWarn || lines[0].text != want || lines[0].fix != "" {
		t.Errorf("lines = %v, want one warning %q with no fix", lines, want)
	}
	if exists(tidyCache(home)) {
		t.Error("a failed survey should keep nothing")
	}

	// Lines and none of them readable: an error, never all clear.
	repo = t.TempDir()
	tidyStub(t, repo, printf(checkOut([]string{"frob", "Alpha", "/p", "x", ""})))
	lines = tidyLines(readTidy(repo, home))
	if len(lines) != 1 || lines[0].sev != sevWarn || !strings.Contains(lines[0].text, "printed 1 line that this mrk-status cannot read") {
		t.Errorf("lines = %v", lines)
	}
	if exists(tidyCache(home)) {
		t.Error("a survey this binary cannot read should not be kept")
	}
}

// The survey waits on the network, and runs its clones in the background. A
// timeout stops all of it, not tidy-projects alone, which would leave the
// pipe open until its children finished.
func TestTidyTimeoutStopsTheSurvey(t *testing.T) {
	old := tidyTimeout
	tidyTimeout = 300 * time.Millisecond
	t.Cleanup(func() { tidyTimeout = old })
	repo := t.TempDir()
	tidyStub(t, repo, "sleep 30 &\nsleep 30\n")
	start := time.Now()
	lines := tidyLines(readTidy(repo, t.TempDir()))
	if took := time.Since(start); took > 3*time.Second {
		t.Errorf("took %v: the survey's children kept it waiting", took)
	}
	if len(lines) != 1 || lines[0].sev != sevWarn || lines[0].text != "Clones: tidy-projects --check did not finish in 300ms" {
		t.Errorf("lines = %v", lines)
	}
}

func TestWithLinesTakesSeverityAndFixAgain(t *testing.T) {
	up := group{"Upkeep", sevOK, []statusLine{sl(sevOK, "Go tools built from the current source")}, ""}
	got := withLines(up, []statusLine{slFix(sevWarn, "Clones: 1 merged branch", fixTidy)})
	if got.sev != sevWarn || got.fix != fixTidy || len(got.lines) != 2 {
		t.Errorf("got %v %q with %d lines", got.sev, got.fix, len(got.lines))
	}
	up = group{"Upkeep", sevWarn, []statusLine{slFix(sevWarn, "~/mrk is 1 commit behind origin/main", fixPull)}, fixPull}
	if got := withLines(up, []statusLine{slFix(sevWarn, "Clones: 1 merged branch", fixTidy)}); got.fix != fixPull {
		t.Errorf("the panel's fix should stay its first: %q", got.fix)
	}
}

func TestSizeKB(t *testing.T) {
	for kb, want := range map[int64]string{0: "0.0 KB", 512: "512 KB", 1024: "1.0 MB", 335872: "328 MB", 3 << 20: "3.0 GB"} {
		if got := sizeKB(kb); got != want {
			t.Errorf("sizeKB(%d) = %q, want %q", kb, got, want)
		}
	}
	for ws, want := range map[string]string{"": "", "a": "a", "a|b": "a and b", "a|b|c": "a, b and c"} {
		var in []string
		if ws != "" {
			in = strings.Split(ws, "|")
		}
		if got := andList(in); got != want {
			t.Errorf("andList(%q) = %q, want %q", in, got, want)
		}
	}
}

// The line reaches --json in Upkeep, with its fix, and the schema stays 1: a
// new line is not a new schema.
func TestJSONCarriesTheClonesLine(t *testing.T) {
	upkeepFixtures(t, "")
	withSystemEvents(t, false)
	old := tmPlist
	tmPlist = filepath.Join(t.TempDir(), "tm.plist")
	t.Cleanup(func() { tmPlist = old })
	write(t, tmPlist, plistXML(`<dict/>`))
	repo := mrkRepo(t)
	writeScript(t, filepath.Join(repo, "scripts", "sync"), "#!/bin/sh\nexit 0\n")
	tidyStub(t, repo, printf(checkOut([]string{"branches", "Alpha", "/p/Alpha", "claude/done", ""})))
	var b bytes.Buffer
	if err := renderJSON(&b, collect(repo, t.TempDir(), t.TempDir())); err != nil {
		t.Fatal(err)
	}
	var r jsonReport
	decodeOne(t, b.Bytes(), &r)
	if r.Schema != 1 {
		t.Errorf("schema = %d, want 1", r.Schema)
	}
	for _, p := range r.Panels {
		for _, l := range p.Lines {
			if strings.HasPrefix(l.Text, "Clones: 1 merged branch, surveyed just now: Alpha") {
				if p.Name != "Upkeep" || l.Severity != "warn" || l.Fix != fixTidy {
					t.Errorf("in %s: %s %q → %q", p.Name, l.Severity, l.Text, l.Fix)
				}
				return
			}
		}
	}
	t.Errorf("no Clones line in:\n%s", b.String())
}
