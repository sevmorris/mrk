package main

import (
	"bytes"
	"os"
	"os/exec"
	"path/filepath"
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

	g := checkUnrecorded(repo, home, brewDrift{adds: []string{"jq", "firefox (cask)"}, prunes: []string{"wget"}})
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

	g = checkUnrecorded(repo, home, brewDrift{})
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

	if l, ok := line(checkUnrecorded(repo, home, brewDrift{}), "committed and pushed"); !ok || l.sev != sevOK {
		t.Fatalf("a pushed checkout should read as committed and pushed")
	}

	write(t, filepath.Join(repo, "README"), "changed\n")
	write(t, filepath.Join(repo, "new-file"), "untracked\n")
	g := checkUnrecorded(repo, home, brewDrift{})
	if l, ok := line(g, "1 uncommitted change"); !ok || l.sev != sevWarn || l.fix != fixMrkPush {
		t.Errorf("a tracked change should warn with %q:\n%s", fixMrkPush, texts(g))
	}
	if l, ok := line(g, "1 untracked file, which mrk-push never commits"); !ok || l.sev != sevInfo {
		t.Errorf("an untracked file should be named, as information:\n%s", texts(g))
	}

	run(t, repo, "git", "commit", "-qam", "local")
	g = checkUnrecorded(repo, home, brewDrift{})
	if l, ok := line(g, "1 commit not pushed"); !ok || l.sev != sevWarn || l.fix != fixMrkPush {
		t.Errorf("an unpushed commit should warn with %q:\n%s", fixMrkPush, texts(g))
	}

	run(t, repo, "git", "switch", "-q", "-c", "loose")
	g = checkUnrecorded(repo, home, brewDrift{})
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

	g := checkUnrecorded(repo, home, brewDrift{})
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
	g = checkUnrecorded(repo, home, brewDrift{})
	l, ok := line(g, "missing from the manifest")
	if !ok || l.fix != fixSnapshot || !strings.Contains(l.text, "ahead") || !strings.Contains(l.text, "Group/nested") {
		t.Errorf("repositories the manifest lacks, nested ones by their path, should warn with %q:\n%s", fixSnapshot, texts(g))
	}
	if strings.Contains(l.text, "lonely") {
		t.Errorf("a repository with no origin cannot be recorded, and should not be listed as missing: %q", l.text)
	}
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
