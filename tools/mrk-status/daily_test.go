package main

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

// The daily panels read real git repositories, lib.sh's own functions, a stub
// brew and fixture plists, all under temporary directories. git runs with the
// global and system config cut off, so a signing key or a hook in the real
// config cannot take part.

func gitEnv(t *testing.T) {
	t.Helper()
	for k, v := range map[string]string{
		"GIT_CONFIG_GLOBAL": "/dev/null", "GIT_CONFIG_NOSYSTEM": "1",
		"GIT_AUTHOR_NAME": "test", "GIT_AUTHOR_EMAIL": "test@test.invalid",
		"GIT_COMMITTER_NAME": "test", "GIT_COMMITTER_EMAIL": "test@test.invalid",
	} {
		t.Setenv(k, v)
	}
}

func run(t *testing.T, dir, name string, args ...string) string {
	t.Helper()
	cmd := exec.Command(name, args...)
	cmd.Dir = dir
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("%s %s in %s: %v\n%s", name, strings.Join(args, " "), dir, err, out)
	}
	return string(out)
}

func write(t *testing.T, path, body string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
}

// newRepo makes a repository at dir with one commit on main, and, when origin
// is true, a bare origin elsewhere that it tracks and has pushed to, whose path
// it returns.
func newRepo(t *testing.T, dir string, origin bool) string {
	t.Helper()
	write(t, filepath.Join(dir, "README"), "x\n")
	run(t, dir, "git", "init", "-q", "-b", "main")
	run(t, dir, "git", "add", "-A")
	run(t, dir, "git", "commit", "-qm", "first")
	if !origin {
		return ""
	}
	bare := filepath.Join(t.TempDir(), "origin.git")
	run(t, dir, "git", "init", "-q", "--bare", "-b", "main", bare)
	run(t, dir, "git", "remote", "add", "origin", bare)
	run(t, dir, "git", "push", "-q", "-u", "origin", "main")
	run(t, dir, "git", "remote", "set-head", "origin", "main")
	return bare
}

// mrkRepo is a checkout holding the real scripts/lib.sh, committed and pushed.
func mrkRepo(t *testing.T) string {
	root, _ := mrkRepoWithOrigin(t)
	return root
}

func mrkRepoWithOrigin(t *testing.T) (root, origin string) {
	t.Helper()
	gitEnv(t)
	root = filepath.Join(t.TempDir(), "mrk")
	lib, err := os.ReadFile(filepath.Join("..", "..", "scripts", "lib.sh"))
	if err != nil {
		t.Fatal(err)
	}
	write(t, filepath.Join(root, "scripts", "lib.sh"), string(lib))
	return root, newRepo(t, root, true)
}

func line(g group, substr string) (statusLine, bool) {
	for _, l := range g.lines {
		if strings.Contains(l.text, substr) {
			return l, true
		}
	}
	return statusLine{}, false
}

// ── Unrecorded ──────────────────────────────────────────────────────────────

func TestUnrecordedBrewDrift(t *testing.T) {
	repo := mrkRepo(t)
	home := t.TempDir()

	g := checkUnrecorded(repo, home, drifts{brew: brewDrift{adds: []string{"jq", "firefox (cask)"}, prunes: []string{"wget"}}})
	add, ok := line(g, "installed but not in the Brewfile: jq, firefox (cask)")
	if !ok || add.sev != sevWarn || add.fix != fixSyncAdd {
		t.Errorf("an installed package the Brewfile lacks should warn with %q, got %+v:\n%s", fixSyncAdd, add, texts(g))
	}
	prune, ok := line(g, "in the Brewfile is not installed: wget")
	if !ok || prune.sev != sevWarn || prune.fix != "" {
		t.Errorf("a Brewfile entry not installed should warn with no fix — the repairs are opposites — got %+v:\n%s", prune, texts(g))
	}
	if _, ok := line(g, "removed on purpose: make sync ARGS=-p · not installed yet: make brew"); !ok {
		t.Errorf("the two repairs should both be named:\n%s", texts(g))
	}
	if g.fix != fixSyncAdd {
		t.Errorf("the panel's fix should be the first warning's, %q, got %q", fixSyncAdd, g.fix)
	}

	g = checkUnrecorded(repo, home, drifts{})
	if l, ok := line(g, "The Brewfile matches"); !ok || l.sev != sevOK {
		t.Errorf("no drift should read as matching:\n%s", texts(g))
	}
	if g.sev != sevOK {
		t.Errorf("a clean checkout with no drift and no projects should be OK, got %v:\n%s", g.sev, texts(g))
	}
}

func TestUnrecordedMrkCheckout(t *testing.T) {
	repo := mrkRepo(t)
	home := t.TempDir()

	if l, ok := line(checkUnrecorded(repo, home, drifts{}), "committed and pushed"); !ok || l.sev != sevOK {
		t.Fatalf("a pushed checkout should read as committed and pushed")
	}

	write(t, filepath.Join(repo, "README"), "changed\n")
	write(t, filepath.Join(repo, "new-file"), "untracked\n")
	g := checkUnrecorded(repo, home, drifts{})
	if l, ok := line(g, "1 uncommitted change"); !ok || l.sev != sevWarn || l.fix != fixMrkPush {
		t.Errorf("a tracked change should warn with %q:\n%s", fixMrkPush, texts(g))
	}
	if l, ok := line(g, "1 untracked file, which mrk-push commits only in the paths it stages: see mrk-push --help"); !ok || l.sev != sevInfo {
		t.Errorf("an untracked file should be named, as information:\n%s", texts(g))
	}

	run(t, repo, "git", "commit", "-qam", "local")
	g = checkUnrecorded(repo, home, drifts{})
	if l, ok := line(g, "1 commit not pushed"); !ok || l.sev != sevWarn || l.fix != fixMrkPush {
		t.Errorf("an unpushed commit should warn with %q:\n%s", fixMrkPush, texts(g))
	}

	run(t, repo, "git", "switch", "-q", "-c", "loose")
	g = checkUnrecorded(repo, home, drifts{})
	if l, ok := line(g, "no upstream, so nothing pushes it"); !ok || l.sev != sevWarn {
		t.Errorf("a branch with no upstream should warn:\n%s", texts(g))
	}
}

func TestUnrecordedProjectsAndManifest(t *testing.T) {
	repo := mrkRepo(t)
	home := t.TempDir()
	projects := filepath.Join(home, "Projects")
	newRepo(t, filepath.Join(projects, "clean"), true)
	newRepo(t, filepath.Join(projects, "dirty"), true)
	write(t, filepath.Join(projects, "dirty", "README"), "changed\n")
	newRepo(t, filepath.Join(projects, "ahead"), true)
	write(t, filepath.Join(projects, "ahead", "README"), "more\n")
	run(t, filepath.Join(projects, "ahead"), "git", "commit", "-qam", "local")
	newRepo(t, filepath.Join(projects, "Group", "nested"), true) // one level down, as project_repos finds it
	newRepo(t, filepath.Join(projects, "lonely"), false)         // no origin

	g := checkUnrecorded(repo, home, drifts{})
	if l, ok := line(g, "with uncommitted changes: dirty"); !ok || l.fix != fixPushall {
		t.Errorf("a project with tracked changes should warn with %q:\n%s", fixPushall, texts(g))
	}
	if l, ok := line(g, "with commits not pushed: ahead"); !ok || l.fix != fixPushall {
		t.Errorf("a project with unpushed commits should warn with %q:\n%s", fixPushall, texts(g))
	}
	if l, ok := line(g, "No origin remote, so nothing records or pushes them: lonely"); !ok || l.sev != sevWarn {
		t.Errorf("a project with no origin should warn:\n%s", texts(g))
	}
	if l, ok := line(g, "No repository manifest"); !ok || l.fix != fixSnapshot {
		t.Errorf("with no repos.tsv, the missing manifest should warn with %q:\n%s", fixSnapshot, texts(g))
	}

	write(t, filepath.Join(home, ".mrk", "preferences", "repos.tsv"),
		"# Generated by snapshot-prefs. One repository per line.\n# name\tremote\tpath-under-HOME\tkind\n"+
			"clean\tx\tProjects/clean\twork\ndirty\tx\tProjects/dirty\twork\n")
	g = checkUnrecorded(repo, home, drifts{})
	l, ok := line(g, "missing from the manifest")
	if !ok || l.fix != fixSnapshot || !strings.Contains(l.text, "ahead") || !strings.Contains(l.text, "Group/nested") {
		t.Errorf("repositories the manifest lacks, nested ones by their path, should warn with %q:\n%s", fixSnapshot, texts(g))
	}
	if strings.Contains(l.text, "lonely") {
		t.Errorf("a repository with no origin cannot be recorded, and should not be listed as missing: %q", l.text)
	}
}

// snapshot-prefs --check and sync-login-items --check, read through stubs that
// refuse any other argument, as the sync stub does in main_test.go.

func TestPrefsDriftReadsSnapshotPrefsCheck(t *testing.T) {
	repo := mrkRepo(t)
	writeScript(t, filepath.Join(repo, "scripts", "snapshot-prefs"), "#!/bin/sh\n[ \"$*\" = --check ] || exit 9\n"+
		"echo '  ▸ Dry run: exporting into a scratch copy' >&2\n"+
		"printf 'sevmorris-apps/io.github.sevmorris.ClipHack.plist\\tClipHackSettings\\tchanged\\n'\n"+
		"printf 'fonts/Some Font.ttf\\t\\tadded\\n'\n"+
		// A key with a tab in it, escaped, and a field a later version adds.
		`printf 'Foo.plist\tWin\\tFrame\tchanged\tlater\n'`+"\n"+
		"printf 'a line of another shape\\n'\n")
	d := readPrefsDrift(repo)
	if d.err != nil {
		t.Fatal(d.err)
	}
	if got := strings.Join(d.changes, ","); got != "io.github.sevmorris.ClipHack ClipHackSettings,Some Font.ttf (added),Foo Win Frame" {
		t.Errorf("changes = %q", got)
	}

	// On 2026-10-22 this one change was all there was, and the panel said all
	// clear. How much it counts is TestUnrecordedPrefsChangeWarnsWhenStale's.
	g := checkUnrecorded(repo, t.TempDir(), drifts{prefs: prefsDrift{changes: d.changes[:1]}})
	l, ok := line(g, "io.github.sevmorris.ClipHack ClipHackSettings")
	if !ok || !strings.HasPrefix(l.text, "1 app preference change not snapshotted") || l.fix != fixSnapshot {
		t.Errorf("a preference not snapshotted should be named with %q:\n%s", fixSnapshot, texts(g))
	}

	if l, ok := line(checkUnrecorded(repo, t.TempDir(), drifts{}), "App preferences: nothing new to snapshot"); !ok || l.sev != sevOK {
		t.Errorf("no change should read as nothing new")
	}
}

// A file snapshot-prefs could not read is not "nothing new": until 2026-10-28
// --check showed no line for it, and the panel said all clear for an app it
// had not seen (audit 22, Z-1).
func TestPrefsDriftUnread(t *testing.T) {
	repo := mrkRepo(t)
	writeScript(t, filepath.Join(repo, "scripts", "snapshot-prefs"), "#!/bin/sh\n[ \"$*\" = --check ] || exit 9\n"+
		"printf 'Keka.plist\\t\\tunread\\n'\n")
	d := readPrefsDrift(repo)
	if d.err != nil {
		t.Fatal(d.err)
	}
	if len(d.changes) != 0 || strings.Join(d.unread, ",") != "Keka.plist" {
		t.Fatalf("changes = %q, unread = %q", d.changes, d.unread)
	}
	g := checkUnrecorded(repo, t.TempDir(), drifts{prefs: d})
	if _, ok := line(g, "App preferences: nothing new to snapshot"); ok {
		t.Errorf("a file not read should not read as nothing new:\n%s", texts(g))
	}
	l, ok := line(g, "App preferences not read, so their changes are not known: Keka.plist")
	if !ok || l.sev != sevWarn || l.fix != "" {
		t.Errorf("a file not read should be a warning with no fix:\n%s", texts(g))
	}
}

// Each change of a mode or a sort order made the menu bar icon warn, most of
// the day. A change is information while the last snapshot is recent, and
// warns once the snapshot is older than prefsStaleAge, or there is none. The
// line keeps its fix in each case.
func TestUnrecordedPrefsChangeWarnsWhenStale(t *testing.T) {
	repo := mrkRepo(t)
	at := time.Date(2026, 10, 27, 18, 0, 0, 0, time.Local)
	defer func(old func() time.Time) { now = old }(now)
	now = func() time.Time { return at }

	found := drifts{prefs: prefsDrift{changes: []string{"io.github.sevmorris.WaxOnWaxOff lastMode"}}}
	for _, c := range []struct {
		name string
		last time.Time
		sev  severity
		text string
	}{
		{"a snapshot this morning", at.Add(-5 * time.Hour), sevInfo,
			"1 app preference change not snapshotted: io.github.sevmorris.WaxOnWaxOff lastMode"},
		{"a snapshot six days ago", at.Add(-6 * 24 * time.Hour), sevInfo,
			"1 app preference change not snapshotted: io.github.sevmorris.WaxOnWaxOff lastMode"},
		{"a snapshot nine days ago", at.Add(-9 * 24 * time.Hour), sevWarn,
			"1 app preference change not snapshotted, last snapshot 9 days ago: io.github.sevmorris.WaxOnWaxOff lastMode"},
		{"no snapshot", time.Time{}, sevWarn,
			"1 app preference change not snapshotted, and no snapshot yet: io.github.sevmorris.WaxOnWaxOff lastMode"},
	} {
		g := unrecordedPanel(repo, t.TempDir(), found, repoReading{prefsLast: c.last})
		l, ok := line(g, "app preference change")
		if !ok || l.text != c.text || l.sev != c.sev || l.fix != fixSnapshot {
			t.Errorf("%s: got %q (sev %v, fix %q), want %q (sev %v):\n%s", c.name, l.text, l.sev, l.fix, c.text, c.sev, texts(g))
		}
		if c.sev == sevInfo && g.sev != sevOK {
			t.Errorf("%s: a recent snapshot's change should leave the panel at ok, got %v:\n%s", c.name, g.sev, texts(g))
		}
		if c.sev == sevWarn && (g.sev != sevWarn || g.fix != fixSnapshot) {
			t.Errorf("%s: a stale snapshot's change should warn with %q:\n%s", c.name, fixSnapshot, texts(g))
		}
	}
}

func TestReadPrefsLast(t *testing.T) {
	home := t.TempDir()
	prefs := filepath.Join(home, ".mrk", "preferences")
	if got := readPrefsLast(prefs); !got.IsZero() {
		t.Errorf("no ~/.mrk/preferences: got %v, want zero", got)
	}
	run(t, home, "git", "init", "-q", "-b", "main", prefs)
	if got := readPrefsLast(prefs); !got.IsZero() {
		t.Errorf("a repository with no commit: got %v, want zero", got)
	}
	os.RemoveAll(prefs)
	newRepo(t, prefs, false)
	if got := readPrefsLast(prefs); time.Since(got) > time.Minute || time.Since(got) < -time.Minute {
		t.Errorf("a commit made now: got %v", got)
	}
}

// unpushedCount runs snapshot-prefs' own unpushed_count, cut from the script.
func unpushedCount(t *testing.T, dir string) int {
	t.Helper()
	out := run(t, ".", "bash", "-c", `eval "$(sed -n '/^unpushed_count() {/,/^}/p' "$1")"; unpushed_count "$2"`,
		"bash", filepath.Join("..", "..", "scripts", "snapshot-prefs"), dir)
	n, err := strconv.Atoi(strings.TrimSpace(out))
	if err != nil {
		t.Fatalf("unpushed_count printed %q", out)
	}
	return n
}

// On 2026-10-22 snapshot-prefs --check printed no line for a commit that an
// earlier run made and did not push, and the panel said there was nothing new
// to snapshot. The next run pushes that commit; until then the next Mac does
// not get it.
func TestUnrecordedPrefsCommitsNotPushed(t *testing.T) {
	repo := mrkRepo(t)
	home := t.TempDir()
	prefs := filepath.Join(home, ".mrk", "preferences")

	count := func(want int, state string) {
		t.Helper()
		if got, script := readPrefsUnpushed(prefs), unpushedCount(t, prefs); got != want || script != want {
			t.Errorf("%s: readPrefsUnpushed = %d, snapshot-prefs' unpushed_count = %d, want %d", state, got, script, want)
		}
	}
	count(0, "no ~/.mrk/preferences")
	run(t, home, "git", "init", "-q", "-b", "main", prefs)
	count(0, "a repository with no commit")
	os.RemoveAll(prefs)
	newRepo(t, prefs, true)
	count(0, "everything pushed")
	if l, ok := line(checkUnrecorded(repo, home, drifts{}), "App preferences: nothing new to snapshot"); !ok || l.sev != sevOK {
		t.Errorf("a pushed ~/.mrk/preferences with no change should read as nothing new")
	}

	write(t, filepath.Join(prefs, "README"), "a snapshot whose push failed\n")
	run(t, prefs, "git", "commit", "-qam", "snapshot")
	count(1, "one commit ahead of its upstream")
	g := checkUnrecorded(repo, home, drifts{})
	l, ok := line(g, "~/.mrk/preferences: 1 commit not pushed to mrk-prefs")
	if !ok || l.sev != sevWarn || l.fix != fixSnapshot || g.fix != fixSnapshot {
		t.Errorf("a snapshot commit not pushed should warn with %q:\n%s", fixSnapshot, texts(g))
	}
	if _, ok := line(g, "nothing new to snapshot"); ok {
		t.Errorf("a commit not pushed must not read as nothing new:\n%s", texts(g))
	}

	g = checkUnrecorded(repo, home, drifts{prefs: prefsDrift{changes: []string{"Foo Bar"}}})
	if _, ok := line(g, "1 app preference change not snapshotted: Foo Bar"); !ok {
		t.Errorf("a change to commit should still be named:\n%s", texts(g))
	}
	if _, ok := line(g, "1 commit not pushed to mrk-prefs"); !ok {
		t.Errorf("a commit not pushed should be named beside a change to commit:\n%s", texts(g))
	}

	// snapshot-prefs pushes with -u, so a branch with no upstream sends every
	// commit it holds.
	run(t, prefs, "git", "switch", "-q", "-c", "loose")
	count(2, "a branch with no upstream")
	if _, ok := line(checkUnrecorded(repo, home, drifts{}), "~/.mrk/preferences: 2 commits not pushed to mrk-prefs"); !ok {
		t.Errorf("a branch with no upstream should count every commit:\n%s", texts(checkUnrecorded(repo, home, drifts{})))
	}
}

func TestPrefsDriftFailureIsAWarning(t *testing.T) {
	repo := mrkRepo(t)
	writeScript(t, filepath.Join(repo, "scripts", "snapshot-prefs"), "#!/bin/sh\n"+
		"echo '  ✗ Not one app, in config/app-prefs.tsv (it has 3 fields): x' >&2\n"+
		"echo '    and more on a later line' >&2\nexit 1\n")
	g := checkUnrecorded(repo, t.TempDir(), drifts{prefs: readPrefsDrift(repo)})
	l, ok := line(g, "App preferences: snapshot-prefs --check failed: Not one app, in config/app-prefs.tsv")
	if !ok || l.sev != sevWarn || l.fix != "" {
		t.Errorf("a check that could not run should warn with the reason it gave, and no fix:\n%s", texts(g))
	}
	if _, ok := line(g, "nothing new"); ok {
		t.Errorf("a check that could not run must not read as nothing new:\n%s", texts(g))
	}
}

func withSystemEvents(t *testing.T, ok bool) {
	t.Helper()
	old := askSystemEvents
	askSystemEvents = func() bool { return ok }
	t.Cleanup(func() { askSystemEvents = old })
}

func TestLoginDriftReadsSyncLoginItemsCheck(t *testing.T) {
	withSystemEvents(t, true)
	repo := mrkRepo(t)
	writeScript(t, filepath.Join(repo, "scripts", "sync-login-items"), "#!/bin/sh\n[ \"$*\" = --check ] || exit 9\n"+
		"echo '  ▸ Reading system login items...' >&2\n"+
		"printf 'add\\tStats\\t/Applications/Stats.app\\tnew\\n'\n"+
		"printf 'add\\tRectangle\\t/Applications/Rectangle.app\\tnew\\n'\n"+
		"printf 'remove\\tOld App\\t/Applications/Old App.app\\tstale\\n'\n"+
		"printf 'remove\\tNoisy\\t/Applications/Noisy.app\\tignored\\n'\n"+
		"printf 'remove\\tOdd\\t/Applications/Odd.app\\tunknown\\n'\n"+
		// A backslash in a name, escaped, and a field a later version adds.
		`printf 'add\tA\\\\B\t/Applications/A.app\tnew\tlater\n'`+"\n")
	d := readLoginDrift(repo)
	if d.err != nil || d.skipped {
		t.Fatalf("a successful check should be read, got %+v", d)
	}
	if strings.Join(d.adds, ",") != `Stats,Rectangle,A\B` || strings.Join(d.stale, ",") != "Old App" || strings.Join(d.ignored, ",") != "Noisy" {
		t.Errorf("drift = %+v", d)
	}

	g := checkUnrecorded(repo, t.TempDir(), drifts{login: d})
	if l, ok := line(g, `3 login items not in config/login-items.txt: Stats, Rectangle, A\B`); !ok || l.sev != sevWarn || l.fix != fixLoginItems {
		t.Errorf("an untracked login item should warn with %q:\n%s", fixLoginItems, texts(g))
	}
	if l, ok := line(g, "1 login item tracked and also ignored: Noisy"); !ok || l.sev != sevWarn || l.fix != fixLoginItems {
		t.Errorf("a tracked item that is also ignored should warn with %q:\n%s", fixLoginItems, texts(g))
	}
	if l, ok := line(g, "1 tracked login item is not a login item here: Old App"); !ok || l.sev != sevWarn || l.fix != "" {
		t.Errorf("a stale item should warn with no fix — the repairs are opposites:\n%s", texts(g))
	}
	if _, ok := line(g, "removed on purpose: "+fixLoginItems+" · not added yet: make post-install"); !ok {
		t.Errorf("the two repairs should both be named:\n%s", texts(g))
	}
	if g.fix != fixLoginItems {
		t.Errorf("the panel's fix should be the first warning's, %q, got %q", fixLoginItems, g.fix)
	}
	// sync-login-items -c commits to ~/mrk, so its lines come before ~/mrk's.
	if i, j := lineIndex(g, "login item"), lineIndex(g, "committed and pushed"); i < 0 || j < 0 || i > j {
		t.Errorf("the login items should come before ~/mrk:\n%s", texts(g))
	}

	if l, ok := line(checkUnrecorded(repo, t.TempDir(), drifts{}), "config/login-items.txt tracks every login item"); !ok || l.sev != sevOK {
		t.Errorf("no offer should read as every login item tracked")
	}
}

// sync-login-items asks System Events, which asks the user whether the app
// that runs it may. Dipstick runs mrk-status --json with no terminal.
func TestLoginDriftIsNotAskedForWithoutATerminal(t *testing.T) {
	withSystemEvents(t, false)
	repo := mrkRepo(t)
	ran := filepath.Join(t.TempDir(), "ran")
	writeScript(t, filepath.Join(repo, "scripts", "sync-login-items"), "#!/bin/sh\ntouch '"+ran+"'\n")
	d := readLoginDrift(repo)
	if !d.skipped || d.err != nil {
		t.Errorf("with no terminal the check should be skipped, got %+v", d)
	}
	if _, err := os.Stat(ran); err == nil {
		t.Errorf("with no terminal sync-login-items must not run")
	}
	g := checkUnrecorded(repo, t.TempDir(), drifts{login: d})
	if l, ok := line(g, "Login items: not checked without a terminal"); !ok || l.sev != sevInfo {
		t.Errorf("a skipped check should say so, as information:\n%s", texts(g))
	}
	if g.sev != sevOK {
		t.Errorf("a skipped check should not change the panel's severity, got %v:\n%s", g.sev, texts(g))
	}
}

func TestLoginDriftFailureIsAWarning(t *testing.T) {
	withSystemEvents(t, true)
	repo := mrkRepo(t)
	writeScript(t, filepath.Join(repo, "scripts", "sync-login-items"), "#!/bin/sh\n"+
		"echo '  ✗ Could not read system login items — osascript exited 1.' >&2\n"+
		"echo '    (System Settings → Privacy & Security → Automation).' >&2\nexit 1\n")
	g := checkUnrecorded(repo, t.TempDir(), drifts{login: readLoginDrift(repo)})
	l, ok := line(g, "Login items: sync-login-items --check failed: Could not read system login items — osascript exited 1.")
	if !ok || l.sev != sevWarn {
		t.Errorf("a check that could not run should warn with the reason it gave:\n%s", texts(g))
	}
	if _, ok := line(g, "tracks every login item"); ok {
		t.Errorf("a check that could not run must not read as every login item tracked:\n%s", texts(g))
	}
}

// Every --check line is written by lib.sh's mrk_check_line, which escapes a
// backslash, a tab and a newline in each field.
func TestUnescapeField(t *testing.T) {
	for in, want := range map[string]string{
		`plain`:  "plain",
		`a\\b`:   `a\b`,
		`a\tb`:   "a\tb",
		`a\nb`:   "a\nb",
		`a\\tb`:  `a\tb`,
		`a\xb`:   `a\xb`,
		`ends\`:  `ends\`,
		`\\\\\t`: "\\\\\t",
	} {
		if got := unescapeField(in); got != want {
			t.Errorf("unescapeField(%q) = %q, want %q", in, got, want)
		}
	}
}

func lineIndex(g group, substr string) int {
	for i, l := range g.lines {
		if strings.Contains(l.text, substr) {
			return i
		}
	}
	return -1
}

// ── Upkeep ──────────────────────────────────────────────────────────────────

// upkeepFixtures points the macOS update check at fixtures, and stubs brew.
func upkeepFixtures(t *testing.T, outdated string) {
	t.Helper()
	withStubBrew(t, "#!/bin/sh\n[ \"$1\" = outdated ] || exit 9\n"+
		"[ \"$HOMEBREW_NO_AUTO_UPDATE\" = 1 ] || { echo 'would auto-update' >&2; exit 3; }\n"+
		"printf '"+outdated+"'\n")
	dir := t.TempDir()
	oldV, oldS := sysVersionPlist, suPlist
	sysVersionPlist, suPlist = filepath.Join(dir, "SystemVersion.plist"), filepath.Join(dir, "su.plist")
	t.Cleanup(func() { sysVersionPlist, suPlist = oldV, oldS })
	write(t, sysVersionPlist, plistXML(`<dict><key>ProductVersion</key><string>26.0.1</string></dict>`))
}

func plistXML(body string) string {
	return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">` + body + `</plist>`
}

func TestUpkeepMrkAgainstOrigin(t *testing.T) {
	upkeepFixtures(t, "")
	repo, origin := mrkRepoWithOrigin(t)
	bin := t.TempDir()

	if l, ok := line(checkUpkeep(repo, t.TempDir(), bin), "level with origin/main"); !ok || l.sev != sevOK {
		t.Errorf("a checkout level with origin should be OK")
	}

	// Another clone pushes; this one fetches but does not pull.
	other := filepath.Join(t.TempDir(), "other")
	run(t, filepath.Dir(other), "git", "clone", "-q", origin, other)
	write(t, filepath.Join(other, "README"), "upstream\n")
	run(t, other, "git", "commit", "-qam", "upstream")
	run(t, other, "git", "push", "-q")
	run(t, repo, "git", "fetch", "-q")
	g := checkUpkeep(repo, t.TempDir(), bin)
	if l, ok := line(g, "1 commit behind origin/main, fetched"); !ok || l.sev != sevWarn || l.fix != fixPull {
		t.Errorf("a checkout behind origin should warn with %q:\n%s", fixPull, texts(g))
	}

	run(t, repo, "git", "switch", "-q", "-c", "work")
	if l, ok := line(checkUpkeep(repo, t.TempDir(), bin), "is on work, not main"); !ok || l.sev != sevInfo {
		t.Errorf("on another branch, the comparison should be information, not a warning")
	}
}

func TestUpkeepToolFreshness(t *testing.T) {
	upkeepFixtures(t, "")
	repo := mrkRepo(t)
	bin := t.TempDir()
	// Explicit times, a half hour apart, so the comparison never rests on
	// whether two files written in the same second differ.
	sources, built := time.Now().Add(-time.Hour), time.Now().Add(-30*time.Minute)
	for _, d := range []string{"picker", "mrk-status", "mrk-menu", "theme"} {
		src := filepath.Join(repo, "tools", d, "main.go")
		write(t, src, "package main\n")
		if err := os.Chtimes(src, sources, sources); err != nil {
			t.Fatal(err)
		}
	}
	for _, b := range []string{"mrk-picker", "mrk-status", "mrk-menu"} {
		write(t, filepath.Join(bin, b), "#!/bin/sh\n")
		if err := os.Chtimes(filepath.Join(bin, b), built, built); err != nil {
			t.Fatal(err)
		}
	}
	if l, ok := line(checkUpkeep(repo, t.TempDir(), bin), "Go tools built from the current source"); !ok || l.sev != sevOK {
		t.Errorf("binaries newer than every source should be OK:\n%s", texts(checkUpkeep(repo, t.TempDir(), bin)))
	}

	// Each tool is held to its own directory, and mrk-picker's is tools/picker.
	// A go.mod or a go.sum counts as a source: a dependency bump changes the
	// binary without touching a .go file. Until 2026-10-01 this test changed
	// only the shared theme, and held neither rule (audit 20, X-11). So does
	// the description table mrk-picker embeds, which sync and
	// check-picker-desc --fix change without touching a .go file either.
	for _, c := range []struct{ file, stale string }{
		{"picker/go.mod", "mrk-picker"},
		{"picker/descriptions.tsv", "mrk-picker"},
		{"mrk-menu/go.sum", "mrk-menu"},
		{"mrk-status/extra.go", "mrk-status"},
	} {
		changed := filepath.Join(repo, "tools", c.file)
		write(t, changed, "changed\n")
		g := checkUpkeep(repo, t.TempDir(), bin)
		want := "Older than their source: " + c.stale
		if l, ok := line(g, "Older than their source"); !ok || l.text != want || l.fix != fixBuildTools {
			t.Errorf("a newer tools/%s should make %s stale, and it alone:\n%s", c.file, c.stale, texts(g))
		}
		if err := os.Remove(changed); err != nil {
			t.Fatal(err)
		}
	}

	// A change to the shared theme makes every tool stale.
	write(t, filepath.Join(repo, "tools", "theme", "main.go"), "package main // changed\n")
	g := checkUpkeep(repo, t.TempDir(), bin)
	if l, ok := line(g, "Older than their source: mrk-picker, mrk-status, mrk-menu"); !ok || l.fix != fixBuildTools {
		t.Errorf("a theme change should make all three stale, with %q:\n%s", fixBuildTools, texts(g))
	}

	if err := os.Remove(filepath.Join(bin, "mrk-menu")); err != nil {
		t.Fatal(err)
	}
	if l, ok := line(checkUpkeep(repo, t.TempDir(), bin), "Not built: mrk-menu"); !ok || l.fix != fixBuildTools {
		t.Errorf("a missing binary should warn with %q", fixBuildTools)
	}
}

func TestUpkeepHomebrewOutdated(t *testing.T) {
	upkeepFixtures(t, `wget\njq\n`)
	repo := mrkRepo(t)
	g := checkUpkeep(repo, t.TempDir(), t.TempDir())
	if l, ok := line(g, "2 Homebrew packages outdated: jq, wget"); !ok || l.fix != fixUpdate {
		t.Errorf("outdated packages should warn with %q, sorted — and the stub refuses to run without HOMEBREW_NO_AUTO_UPDATE:\n%s", fixUpdate, texts(g))
	}
	upkeepFixtures(t, "")
	if l, ok := line(checkUpkeep(repo, t.TempDir(), t.TempDir()), "Homebrew packages up to date"); !ok || l.sev != sevOK {
		t.Errorf("nothing outdated should be OK")
	}
}

func TestUpkeepMacOSUpdates(t *testing.T) {
	upkeepFixtures(t, "")
	update := func(name, ver string) string {
		return `<dict><key>Display Name</key><string>` + name + `</string><key>Display Version</key><string>` + ver + `</string></dict>`
	}
	write(t, suPlist, plistXML(`<dict><key>LastSuccessfulDate</key><date>2026-09-30T08:00:00Z</date>
		<key>RecommendedUpdates</key><array>`+update("macOS Tahoe 26.0.2", "26.0.2")+update("macOS 27.0.1", "27.0.1")+`</array></dict>`))
	lines := macOSUpdateLines()
	g := group{"x", linesSev(lines), lines, ""}
	if l, ok := line(g, "1 macOS update for macOS 26"); !ok || l.fix != fixUpdates || !strings.Contains(l.text, "macOS Tahoe 26.0.2") {
		t.Errorf("an update for the installed major version should warn with %q:\n%s", fixUpdates, texts(g))
	}
	if l, ok := line(g, "being a major upgrade: macOS 27.0.1"); !ok || l.sev != sevInfo {
		t.Errorf("a major upgrade should be named, as information, and never counted:\n%s", texts(g))
	}

	write(t, suPlist, plistXML(`<dict><key>RecommendedUpdates</key><array>`+update("macOS 27.0.1", "27.0.1")+`</array></dict>`))
	lines = macOSUpdateLines()
	g = group{"x", linesSev(lines), lines, ""}
	if g.sev != sevOK {
		t.Errorf("only a major upgrade on offer should leave the check OK, got %v:\n%s", g.sev, texts(g))
	}

	if err := os.Remove(suPlist); err != nil {
		t.Fatal(err)
	}
	if lines := macOSUpdateLines(); len(lines) != 1 || lines[0].sev != sevInfo {
		t.Errorf("no record of a check should be one line of information, got %+v", lines)
	}
}

// Safari and the Command Line Tools carry versions ahead of the OS, and make
// updates installs them: macos-updates applies its version test to macOS
// alone. Until 2026-10-01 this panel applied it to every entry, said "No macOS
// update", and named both as major upgrades that mrk never installs (audit 20,
// X-3).
func TestUpkeepOnlyMacOSIsEverAMajorUpgrade(t *testing.T) {
	upkeepFixtures(t, "") // macOS 26.0.1 is installed
	entry := func(name, ver, id string) string {
		s := `<dict><key>Display Version</key><string>` + ver + `</string><key>Identifier</key><string>` + id + `</string>`
		if name != "" {
			s += `<key>Display Name</key><string>` + name + `</string>`
		}
		return s + `</dict>`
	}
	record := func(entries ...string) {
		t.Helper()
		write(t, suPlist, plistXML(`<dict><key>RecommendedUpdates</key><array>`+strings.Join(entries, "")+`</array></dict>`))
	}
	safari := entry("Safari", "27.0", "Safari27.0TahoeAuto-27.0")
	clt := entry("Command Line Tools for Xcode", "27.0", "Command Line Tools for Xcode-27.0")
	// The entry this Mac's record held on 2026-10-01.
	upgrade := entry("macOS 27.0.1", "27.0.1", "MSU_UPDATE_26A5434_full_27.0.1_major")

	record(safari, clt, upgrade)
	lines := macOSUpdateLines()
	g := group{"x", linesSev(lines), lines, ""}
	if l, ok := line(g, "2 macOS updates for macOS 26"); !ok || l.sev != sevWarn || l.fix != fixUpdates ||
		!strings.Contains(l.text, "Safari 27.0") || !strings.Contains(l.text, "Command Line Tools for Xcode 27.0") {
		t.Errorf("Safari and the Command Line Tools should be counted as updates, with %q:\n%s", fixUpdates, texts(g))
	}
	if l, ok := line(g, "being a major upgrade:"); !ok || l.text != "  offered, and never installed by mrk, being a major upgrade: macOS 27.0.1" {
		t.Errorf("only macOS 27.0.1 should be named as a major upgrade:\n%s", texts(g))
	}

	// Safari alone: an update, and no major upgrade to name.
	record(safari)
	lines = macOSUpdateLines()
	g = group{"x", linesSev(lines), lines, ""}
	if _, ok := line(g, "1 macOS update for macOS 26"); !ok || len(lines) != 1 {
		t.Errorf("Safari alone should be one update and nothing else:\n%s", texts(g))
	}

	// macOS is known by its identifier too, and an entry with no name is taken
	// for macOS: each is judged by its version.
	record(entry("Tahoe 27.0", "27.0", "macOS 27-26A428"), entry("", "27.1", "x"), entry("", "26.1", "y"))
	lines = macOSUpdateLines()
	g = group{"x", linesSev(lines), lines, ""}
	if l, ok := line(g, "1 macOS update for macOS 26"); !ok || !strings.HasSuffix(l.text, ": macOS 26.1") {
		t.Errorf("a nameless 26.1 should be the one update:\n%s", texts(g))
	}
	if l, ok := line(g, "being a major upgrade:"); !ok || !strings.HasSuffix(l.text, ": Tahoe 27.0, macOS 27.1") {
		t.Errorf("an entry whose identifier says macOS, and a nameless 27.1, should be the major upgrades:\n%s", texts(g))
	}
}

// ── Time Machine ────────────────────────────────────────────────────────────

func TestTimeMachine(t *testing.T) {
	dir := t.TempDir()
	old, oldNow := tmPlist, now
	tmPlist = filepath.Join(dir, "tm.plist")
	fixed := time.Date(2026, 9, 30, 12, 0, 0, 0, time.UTC)
	now = func() time.Time { return fixed }
	t.Cleanup(func() { tmPlist, now = old, oldNow })

	at := func(d time.Duration) string { return fixed.Add(-d).Format(time.RFC3339) }
	dest := func(inner string) string {
		return `<dict><key>AutoBackup</key><true/><key>Destinations</key><array><dict>` + inner + `</dict></array></dict>`
	}
	for _, tc := range []struct {
		name, plist, want string
		sev               severity
	}{
		{"no destination, as this Mac has", `<dict><key>PreferencesVersion</key><integer>6</integer></dict>`,
			"No destination: Time Machine is not backing up", sevWarn},
		{"a backup two hours old", dest(`<key>SnapshotDates</key><array><date>` + at(30*time.Hour) + `</date><date>` + at(2*time.Hour) + `</date></array>`),
			"Last backup 2 hours ago", sevOK},
		{"three days old", dest(`<key>SnapshotDates</key><array><date>` + at(72*time.Hour) + `</date></array>`),
			"Last backup 3 days ago", sevWarn},
		{"ten days old", dest(`<key>SnapshotDates</key><array><date>` + at(240*time.Hour) + `</date></array>`),
			"Last backup 10 days ago", sevErr},
		{"only the reference snapshot date", dest(`<key>ReferenceLocalSnapshotDate</key><date>` + at(time.Hour) + `</date>`),
			"Last backup 1 hour ago", sevOK},
		{"a destination with no backup yet", dest(`<key>DestinationID</key><string>X</string>`),
			"No completed backup recorded, on 1 destination", sevWarn},
		{"automatic backups off", `<dict><key>AutoBackup</key><false/><key>Destinations</key><array><dict><key>SnapshotDates</key><array><date>` + at(time.Hour) + `</date></array></dict></array></dict>`,
			"Automatic backups are off", sevWarn},
	} {
		t.Run(tc.name, func(t *testing.T) {
			write(t, tmPlist, plistXML(tc.plist))
			g := checkTimeMachine()
			if _, ok := line(g, tc.want); !ok || g.sev != tc.sev {
				t.Errorf("want %q at sev %v, got sev %v:\n%s", tc.want, tc.sev, g.sev, texts(g))
			}
		})
	}
}

// ── Installation ────────────────────────────────────────────────────────────

func TestFoldKeepsProblemsAndOffersOnlyARepair(t *testing.T) {
	parts := []group{
		{"Fine", sevOK, []statusLine{sl(sevOK, "all good"), sl(sevOK, "detail that should not show")}, ""},
		{"Optional", sevInfo, []statusLine{sl(sevInfo, "Not applied — run: make defaults")}, "make defaults"},
		{"Broken", sevWarn, []statusLine{sl(sevInfo, "3 linked, 1 broken"), sl(sevWarn, "x (broken)"), sl(sevInfo, "an aside")}, "make fix-exec"},
		{"Worse", sevErr, []statusLine{sl(sevErr, "gone")}, "make worse"},
	}
	g := fold("Installation", parts)
	if g.sev != sevErr {
		t.Errorf("the panel should take the worst severity, got %v", g.sev)
	}
	if g.fix != "make fix-exec" {
		t.Errorf("the panel's fix should be the first among checks that warn or err, got %q", g.fix)
	}
	got := texts(g)
	for _, want := range []string{"Fine — all good", "Optional — Not applied", "Broken — 3 linked, 1 broken", "  x (broken)", "Worse — gone"} {
		if !strings.Contains(got, want) {
			t.Errorf("missing %q:\n%s", want, got)
		}
	}
	for _, not := range []string{"detail that should not show", "an aside"} {
		if strings.Contains(got, not) {
			t.Errorf("a line that neither warns nor errs should not be folded in: %q", not)
		}
	}
	if l, _ := line(g, "Optional"); l.fix != "" {
		t.Errorf("an informational check's suggestion is not a repair, and should carry no fix, got %q", l.fix)
	}
}

// ── The whole dashboard ─────────────────────────────────────────────────────

func TestPanelsComeDailyFirst(t *testing.T) {
	upkeepFixtures(t, "")
	withSystemEvents(t, false)
	old := tmPlist
	tmPlist = filepath.Join(t.TempDir(), "tm.plist")
	t.Cleanup(func() { tmPlist = old })
	write(t, tmPlist, plistXML(`<dict/>`))
	repo := mrkRepo(t)
	write(t, filepath.Join(repo, "scripts", "sync"), "#!/bin/sh\nexit 0\n")
	if err := os.Chmod(filepath.Join(repo, "scripts", "sync"), 0o755); err != nil {
		t.Fatal(err)
	}
	var got []string
	for _, g := range collect(repo, t.TempDir(), t.TempDir()) {
		got = append(got, g.name)
	}
	if want := "Unrecorded,Upkeep,Time Machine Backups,Installation"; strings.Join(got, ",") != want {
		t.Errorf("panels = %s, want %s", strings.Join(got, ","), want)
	}
}

func TestPlainPrintsEveryPanelAndFix(t *testing.T) {
	groups := []group{
		{"Unrecorded", sevWarn, []statusLine{slFix(sevWarn, "1 package installed but not in the Brewfile: jq", fixSyncAdd), sl(sevOK, "~/mrk: committed and pushed")}, fixSyncAdd},
		{"Time Machine Backups", sevOK, []statusLine{sl(sevOK, "Last backup 1 hour ago")}, ""},
	}
	var b bytes.Buffer
	renderPlain(&b, groups)
	out := b.String()
	for _, want := range []string{"mrk-status  1 warning", "\n⚠ Unrecorded\n", "    ⚠ 1 package installed but not in the Brewfile: jq  → make sync ARGS=-c",
		"    ✓ ~/mrk: committed and pushed", "\n✓ Time Machine Backups\n"} {
		if !strings.Contains(out, want) {
			t.Errorf("missing %q in:\n%s", want, out)
		}
	}
	if strings.Contains(out, "\x1b[") {
		t.Errorf("output to something that is not a terminal should carry no colour codes:\n%q", out)
	}
}

// ── Property lists ──────────────────────────────────────────────────────────

func TestDecodePlistXML(t *testing.T) {
	v, err := decodePlistXML([]byte(plistXML(`<dict>
		<key>s</key><string>a &amp; b</string>
		<key>i</key><integer>-3</integer>
		<key>r</key><real>1.5</real>
		<key>t</key><true/><key>f</key><false/>
		<key>d</key><date>2026-09-30T08:00:00Z</date>
		<key>b</key><data>aGVs
		bG8=</data>
		<key>a</key><array><string>x</string><dict><key>k</key><string>v</string></dict></array>
		<key>empty</key><dict/>
	</dict>`)))
	if err != nil {
		t.Fatal(err)
	}
	m := pDict(v)
	if pString(m["s"]) != "a & b" || m["i"] != int64(-3) || m["r"] != 1.5 {
		t.Errorf("scalars: %#v", m)
	}
	if b, ok := pBool(m["t"]); !ok || !b {
		t.Errorf("<true/> = %#v", m["t"])
	}
	if b, ok := pBool(m["f"]); !ok || b {
		t.Errorf("<false/> = %#v", m["f"])
	}
	if d, ok := pTime(m["d"]); !ok || !d.Equal(time.Date(2026, 9, 30, 8, 0, 0, 0, time.UTC)) {
		t.Errorf("<date> = %#v", m["d"])
	}
	if string(m["b"].([]byte)) != "hello" {
		t.Errorf("<data> = %q", m["b"])
	}
	a := pArray(m["a"])
	if len(a) != 2 || pString(a[0]) != "x" || pString(pDict(a[1])["k"]) != "v" {
		t.Errorf("<array> = %#v", a)
	}
	if e := pDict(m["empty"]); e == nil || len(e) != 0 {
		t.Errorf("<dict/> = %#v", m["empty"])
	}
	for _, bad := range []string{"not xml", plistXML(`<dict><string>no key</string></dict>`), plistXML(`<integer>x</integer>`)} {
		if _, err := decodePlistXML([]byte(bad)); err == nil {
			t.Errorf("%q should not decode", bad)
		}
	}
}

func TestPanelSeverityIgnoresAsides(t *testing.T) {
	for _, tc := range []struct {
		in   []severity
		want severity
	}{
		{[]severity{sevOK, sevInfo}, sevOK},
		{[]severity{sevInfo, sevInfo}, sevInfo},
		{[]severity{sevInfo, sevWarn, sevOK}, sevWarn},
		{[]severity{sevErr, sevInfo}, sevErr},
		{nil, sevOK},
	} {
		if got := panelSev(tc.in...); got != tc.want {
			t.Errorf("panelSev(%v) = %v, want %v", tc.in, got, tc.want)
		}
	}
}
