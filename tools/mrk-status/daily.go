package main

// The daily panels, first in the dashboard: what this Mac holds that the next
// one would not get (Unrecorded), what has fallen behind (Upkeep), and whether
// Time Machine is keeping a copy. Until 2026-09-30 the dashboard showed only
// the nine installation checks, which on a Mac set up months ago are green
// every day and answer nothing about the day's work; those are now folded
// into one Installation panel, last.
//
// Where another mrk command already decides a question, the panel asks that
// command rather than deciding it again: Brewfile drift is `sync --check`, the
// list of projects is lib.sh's project_repos, and build freshness is lib.sh's
// tool_freshness. scripts/status and this binary were twins until the same
// day, and each kept gaining fixes the other lacked.

import (
	"bufio"
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"
)

// The fixes the daily panels offer. Each runs as `cd <repoRoot> && <fix>`, so a
// path is relative to the checkout; TestEveryFixCommandResolves holds each one
// to resolving there.
const (
	fixSyncAdd     = "make sync ARGS=-c"
	fixMrkPush     = "bin/mrk-push"
	fixPushall     = "bin/pushall"
	fixSnapshot    = "make snapshot-prefs"
	fixPull        = "make pull"
	fixUpdate      = "make update"
	fixUpdates     = "make updates"
	fixBuildTools  = "make build-tools"
	fixBrewInstall = "make brew"
)

var dailyFixes = []string{fixSyncAdd, fixMrkPush, fixPushall, fixSnapshot, fixPull,
	fixUpdate, fixUpdates, fixBuildTools, fixBrewInstall}

// Paths the checks read, variables so the tests can point them at fixtures.
var (
	tmPlist         = "/Library/Preferences/com.apple.TimeMachine.plist"
	suPlist         = "/Library/Preferences/com.apple.SoftwareUpdate.plist"
	sysVersionPlist = "/System/Library/CoreServices/SystemVersion.plist"
	now             = time.Now
)

// slFix is a status line that carries its own fix.
func slFix(sev severity, text, fix string) statusLine {
	return statusLine{sev: sev, text: text, fix: fix}
}

// firstFix is the fix the f key runs for a panel: the first one on a line that
// warns or errs. A fix on an informational line is a suggestion, not a repair.
func firstFix(lines []statusLine) string {
	for _, l := range lines {
		if l.sev >= sevWarn && l.fix != "" {
			return l.fix
		}
	}
	return ""
}

// panelSev is a panel's severity: the worst of its lines that pass, warn or
// err, and information only when it holds nothing else. worst() ranks an
// information line above a pass, which is right for one check's lines and wrong
// for a panel: an aside, a major upgrade named and not counted, would turn a
// healthy panel grey.
func panelSev(sevs ...severity) severity {
	s, any := sevOK, false
	for _, v := range sevs {
		if v == sevInfo {
			continue
		}
		any = true
		if v > s {
			s = v
		}
	}
	if !any && len(sevs) > 0 {
		return sevInfo
	}
	return s
}

func linesSev(lines []statusLine) severity {
	sevs := make([]severity, len(lines))
	for i, l := range lines {
		sevs[i] = l.sev
	}
	return panelSev(sevs...)
}

// tilde shortens a path under home to ~/….
func tilde(home, p string) string {
	if home != "" && (p == home || strings.HasPrefix(p, home+"/")) {
		return "~" + strings.TrimPrefix(p, home)
	}
	return p
}

// names lists up to five names, then how many more.
func names(ns []string) string {
	if len(ns) <= 5 {
		return strings.Join(ns, ", ")
	}
	return strings.Join(ns[:5], ", ") + fmt.Sprintf(" and %d more", len(ns)-5)
}

func plural(n int, one, many string) string {
	if n == 1 {
		return "1 " + one
	}
	return fmt.Sprintf("%d %s", n, many)
}

func ago(d time.Duration) string {
	switch {
	case d < time.Minute:
		return "just now"
	case d < time.Hour:
		return plural(int(d/time.Minute), "minute", "minutes") + " ago"
	case d < 48*time.Hour:
		return plural(int(d/time.Hour), "hour", "hours") + " ago"
	default:
		return plural(int(d/(24*time.Hour)), "day", "days") + " ago"
	}
}

func git(dir string, args ...string) (string, error) {
	out, err := exec.Command("git", append([]string{"-C", dir}, args...)...).Output()
	return strings.TrimSpace(string(out)), err
}

func countNonEmpty(s string) int {
	n := 0
	for _, l := range strings.Split(s, "\n") {
		if strings.TrimSpace(l) != "" {
			n++
		}
	}
	return n
}

// bashLib runs a lib.sh function from the checkout, its output on stdout.
func bashLib(repoRoot, script string, args ...string) (string, error) {
	full := `source "$1/scripts/lib.sh" || exit 1; shift; ` + script
	cmd := exec.Command("bash", append([]string{"-c", full, "bash", repoRoot}, args...)...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil && stderr.Len() > 0 {
		err = fmt.Errorf("%v: %s", err, strings.TrimSpace(stderr.String()))
	}
	return string(out), err
}

// ── Homebrew drift ────────────────────────────────────────────────────────

// brewDrift is `sync --check`: what sync -c would add to the Brewfile and what
// sync -p would remove, by sync's own rules, sync-ignore included.
type brewDrift struct {
	adds, prunes []string // "name", casks as "name (cask)"
	noBrew       bool
	err          error
}

// brewPaths are where sync, and lib.sh's BREW_PATHS, look for Homebrew when
// PATH does not have it. A variable so the tests can say there is none.
var brewPaths = []string{"/opt/homebrew/bin/brew", "/usr/local/bin/brew"}

// brewBin is the brew to run, or "" when there is no Homebrew.
func brewBin() string {
	if p, err := exec.LookPath("brew"); err == nil {
		return p
	}
	for _, p := range brewPaths {
		if fi, err := os.Stat(p); err == nil && !fi.IsDir() {
			return p
		}
	}
	return ""
}

func readBrewDrift(repoRoot string) brewDrift {
	if brewBin() == "" {
		return brewDrift{noBrew: true}
	}
	cmd := exec.Command(filepath.Join(repoRoot, "scripts", "sync"), "--check")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		msg := strings.TrimSpace(stderr.String())
		if i := strings.LastIndex(msg, "\n"); i >= 0 {
			msg = strings.TrimSpace(msg[i+1:])
		}
		if msg == "" {
			msg = err.Error()
		}
		return brewDrift{err: fmt.Errorf("sync --check failed: %s", msg)}
	}
	var d brewDrift
	for _, line := range strings.Split(string(out), "\n") {
		f := strings.Split(line, "\t")
		if len(f) != 3 {
			continue
		}
		name := f[2]
		if f[1] == "cask" {
			name += " (cask)"
		}
		switch f[0] {
		case "add":
			d.adds = append(d.adds, name)
		case "prune":
			d.prunes = append(d.prunes, name)
		}
	}
	return d
}

// ── Repositories ──────────────────────────────────────────────────────────

// repoState is what mrk-push and pushall look at in one repository: tracked
// changes, which `git add -u` stages; untracked files, which neither commits;
// and commits its upstream lacks.
type repoState struct {
	uncommitted, untracked, unpushed int
	noUpstream                       bool
	err                              error
}

func readRepoState(dir string) repoState {
	var s repoState
	out, err := git(dir, "status", "--porcelain", "--untracked-files=no")
	if err != nil {
		return repoState{err: err}
	}
	s.uncommitted = countNonEmpty(out)
	if out, err := git(dir, "ls-files", "--others", "--exclude-standard"); err == nil {
		s.untracked = countNonEmpty(out)
	}
	if out, err := git(dir, "rev-list", "--count", "@{upstream}..HEAD"); err != nil {
		s.noUpstream = true
	} else {
		s.unpushed, _ = strconv.Atoi(out)
	}
	return s
}

// project is a repository mrk sweeps: rel is its path under ~/Projects.
type project struct {
	rel, origin string
	bare        bool
	state       repoState
}

// readProjects lists the repositories pushall sweeps and snapshot-prefs
// records, by project_repos in lib.sh, plus the bare *.git directly in
// ~/Projects that snapshot-prefs records too.
func readProjects(repoRoot, projectsDir string) ([]project, error) {
	out, err := bashLib(repoRoot,
		`project_repos "$1" r o || exit 1; for x in ${r[@]+"${r[@]}"}; do printf '%s\n' "$x"; done`,
		projectsDir)
	if err != nil {
		return nil, fmt.Errorf("project_repos failed: %w", err)
	}
	var ps []project
	for _, rel := range strings.Split(strings.TrimSpace(out), "\n") {
		if rel == "" {
			continue
		}
		dir := filepath.Join(projectsDir, rel)
		origin, _ := git(dir, "remote", "get-url", "origin")
		ps = append(ps, project{rel: rel, origin: origin, state: readRepoState(dir)})
	}
	bares, _ := filepath.Glob(filepath.Join(projectsDir, "*.git"))
	for _, b := range bares {
		if fi, err := os.Stat(filepath.Join(b, "objects")); err != nil || !fi.IsDir() {
			continue
		}
		origin, _ := exec.Command("git", "--git-dir="+b, "remote", "get-url", "origin").Output()
		ps = append(ps, project{rel: filepath.Base(b), origin: strings.TrimSpace(string(origin)), bare: true})
	}
	return ps, nil
}

// readManifest is the set of paths repos.tsv records, as "Projects/<rel>".
func readManifest(prefsDir string) (map[string]bool, error) {
	f, err := os.Open(filepath.Join(prefsDir, "repos.tsv"))
	if err != nil {
		return nil, err
	}
	defer f.Close()
	m := map[string]bool{}
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		l := sc.Text()
		if strings.HasPrefix(l, "#") {
			continue
		}
		if f := strings.Split(l, "\t"); len(f) >= 3 {
			m[f[2]] = true
		}
	}
	return m, sc.Err()
}

// ── Unrecorded ────────────────────────────────────────────────────────────

func checkUnrecorded(repoRoot, home string, drift brewDrift) group {
	var lines []statusLine

	// Homebrew, by sync's own reckoning.
	switch {
	case drift.noBrew:
		lines = append(lines, sl(sevInfo, "Homebrew is not installed: nothing to compare with the Brewfile"))
	case drift.err != nil:
		lines = append(lines, sl(sevWarn, "Brewfile: "+drift.err.Error()))
	default:
		if len(drift.adds) > 0 {
			lines = append(lines, slFix(sevWarn,
				plural(len(drift.adds), "package installed but not in the Brewfile", "packages installed but not in the Brewfile")+": "+names(drift.adds),
				fixSyncAdd))
		}
		if len(drift.prunes) > 0 {
			// No fix for the f key: on this Mac a missing package was most likely
			// removed, and on a new one it is not installed yet, and the two
			// repairs are opposites. sync -p offers each entry before removing it.
			lines = append(lines,
				sl(sevWarn, plural(len(drift.prunes), "package in the Brewfile is not installed", "packages in the Brewfile are not installed")+": "+names(drift.prunes)),
				sl(sevInfo, "  removed on purpose: make sync ARGS=-p · not installed yet: make brew"))
		}
		if len(drift.adds) == 0 && len(drift.prunes) == 0 {
			lines = append(lines, sl(sevOK, "The Brewfile matches what Homebrew has installed"))
		}
	}

	// ~/mrk, as mrk-push would commit and push it.
	mrk := tilde(home, repoRoot)
	if s := readRepoState(repoRoot); s.err != nil {
		lines = append(lines, sl(sevWarn, fmt.Sprintf("%s: cannot read its git state: %v", mrk, s.err)))
	} else {
		clean := true
		if s.uncommitted > 0 {
			clean = false
			lines = append(lines, slFix(sevWarn, mrk+": "+plural(s.uncommitted, "uncommitted change", "uncommitted changes"), fixMrkPush))
		}
		if s.unpushed > 0 {
			clean = false
			lines = append(lines, slFix(sevWarn, mrk+": "+plural(s.unpushed, "commit not pushed", "commits not pushed"), fixMrkPush))
		}
		if s.noUpstream {
			clean = false
			lines = append(lines, sl(sevWarn, mrk+": the branch has no upstream, so nothing pushes it"))
		}
		if clean {
			lines = append(lines, sl(sevOK, mrk+": committed and pushed"))
		}
		if s.untracked > 0 {
			lines = append(lines, sl(sevInfo, "  "+plural(s.untracked, "untracked file", "untracked files")+", which mrk-push never commits"))
		}
	}

	// ~/Projects, as pushall sweeps it and the manifest records it.
	projectsDir := filepath.Join(home, "Projects")
	ps, err := readProjects(repoRoot, projectsDir)
	if err != nil {
		lines = append(lines, sl(sevWarn, "~/Projects: "+err.Error()))
	} else {
		var dirty, unpushed, noUp, untracked, noOrigin, unlisted []string
		for _, p := range ps {
			if p.origin == "" {
				noOrigin = append(noOrigin, p.rel)
			}
			if p.bare {
				continue
			}
			switch {
			case p.state.err != nil:
				dirty = append(dirty, p.rel+" (unreadable)")
			default:
				if p.state.uncommitted > 0 {
					dirty = append(dirty, p.rel)
				}
				if p.state.unpushed > 0 {
					unpushed = append(unpushed, p.rel)
				}
				if p.state.noUpstream {
					noUp = append(noUp, p.rel)
				}
				if p.state.untracked > 0 {
					untracked = append(untracked, p.rel)
				}
			}
		}
		if len(dirty) > 0 {
			lines = append(lines, slFix(sevWarn, "~/Projects: "+plural(len(dirty), "repository with uncommitted changes", "repositories with uncommitted changes")+": "+names(dirty), fixPushall))
		}
		if len(unpushed) > 0 {
			lines = append(lines, slFix(sevWarn, "~/Projects: "+plural(len(unpushed), "repository with commits not pushed", "repositories with commits not pushed")+": "+names(unpushed), fixPushall))
		}
		if len(dirty) == 0 && len(unpushed) == 0 {
			lines = append(lines, sl(sevOK, fmt.Sprintf("~/Projects: %s, committed and pushed", plural(len(ps), "repository", "repositories"))))
		}
		if len(noUp) > 0 {
			lines = append(lines, sl(sevInfo, "  no upstream, so pushall skips them: "+names(noUp)))
		}
		if len(untracked) > 0 {
			lines = append(lines, sl(sevInfo, "  untracked files, which pushall never commits: "+names(untracked)))
		}

		prefsDir := filepath.Join(home, ".mrk", "preferences")
		manifest, merr := readManifest(prefsDir)
		for _, p := range ps {
			if p.origin != "" && !manifest["Projects/"+p.rel] {
				unlisted = append(unlisted, p.rel)
			}
		}
		switch {
		case merr != nil && len(ps) > 0:
			lines = append(lines, slFix(sevWarn, "No repository manifest at "+tilde(home, filepath.Join(prefsDir, "repos.tsv")), fixSnapshot))
		case len(unlisted) > 0:
			lines = append(lines, slFix(sevWarn, plural(len(unlisted), "repository missing from the manifest", "repositories missing from the manifest")+": "+names(unlisted), fixSnapshot))
		case len(ps) > 0:
			lines = append(lines, sl(sevOK, "The manifest records every repository in ~/Projects"))
		}
		if len(noOrigin) > 0 {
			lines = append(lines, sl(sevWarn, "No origin remote, so nothing records or pushes them: "+names(noOrigin)))
		}
	}

	return group{"Unrecorded", linesSev(lines), lines, firstFix(lines)}
}

// ── Upkeep ────────────────────────────────────────────────────────────────

func checkUpkeep(repoRoot, home, binDir string) group {
	var lines []statusLine
	mrk := tilde(home, repoRoot)

	// ~/mrk against origin, as of the last fetch. check-updates fetches in the
	// background once a day; nothing here waits for the network.
	def, _ := git(repoRoot, "symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD")
	def = strings.TrimPrefix(def, "origin/")
	if def == "" {
		def = "main"
	}
	branch, _ := git(repoRoot, "symbolic-ref", "--quiet", "--short", "HEAD")
	fetched := ""
	if p, err := git(repoRoot, "rev-parse", "--git-path", "FETCH_HEAD"); err == nil {
		if !filepath.IsAbs(p) {
			p = filepath.Join(repoRoot, p)
		}
		if fi, err := os.Stat(p); err == nil {
			fetched = ", fetched " + ago(now().Sub(fi.ModTime()))
		}
	}
	switch behind, err := git(repoRoot, "rev-list", "--count", "HEAD..origin/"+def); {
	case err != nil:
		lines = append(lines, sl(sevInfo, fmt.Sprintf("%s: no origin/%s to compare with", mrk, def)))
	case branch != def:
		lines = append(lines, sl(sevInfo, fmt.Sprintf("%s is on %s, not %s: make pull and check-updates wait for %s", mrk, orDetached(branch), def, def)))
	case behind != "0":
		n, _ := strconv.Atoi(behind)
		lines = append(lines, slFix(sevWarn, fmt.Sprintf("%s is %s behind origin/%s%s", mrk, plural(n, "commit", "commits"), def, fetched), fixPull))
	default:
		lines = append(lines, sl(sevOK, fmt.Sprintf("%s is level with origin/%s%s", mrk, def, fetched)))
	}

	// The Go tools against their source, as maintain checks them.
	if out, err := bashLib(repoRoot, `tool_freshness "$1" "$2"`, repoRoot, binDir); err != nil {
		lines = append(lines, sl(sevWarn, "Go tools: cannot check their builds: "+err.Error()))
	} else {
		var stale, missing []string
		for _, l := range strings.Split(strings.TrimSpace(out), "\n") {
			f := strings.Split(l, "\t")
			if len(f) != 2 {
				continue
			}
			switch f[1] {
			case "stale":
				stale = append(stale, f[0])
			case "missing":
				missing = append(missing, f[0])
			}
		}
		if len(stale) > 0 {
			lines = append(lines, slFix(sevWarn, "Older than their source: "+names(stale), fixBuildTools))
		}
		if len(missing) > 0 {
			lines = append(lines, slFix(sevWarn, "Not built: "+names(missing), fixBuildTools))
		}
		if len(stale) == 0 && len(missing) == 0 {
			lines = append(lines, sl(sevOK, "Go tools built from the current source"))
		}
	}

	// Homebrew. HOMEBREW_NO_AUTO_UPDATE: outdated reads what the last update
	// fetched, and must not start one.
	if brew := brewBin(); brew == "" {
		lines = append(lines, sl(sevInfo, "Homebrew is not installed"))
	} else {
		cmd := exec.Command(brew, "outdated", "--quiet")
		cmd.Env = append(os.Environ(), "HOMEBREW_NO_AUTO_UPDATE=1")
		if out, err := cmd.Output(); err != nil {
			lines = append(lines, sl(sevWarn, fmt.Sprintf("brew outdated failed: %v", err)))
		} else if pkgs := strings.Fields(string(out)); len(pkgs) > 0 {
			sort.Strings(pkgs)
			lines = append(lines, slFix(sevWarn, plural(len(pkgs), "Homebrew package outdated", "Homebrew packages outdated")+": "+names(pkgs), fixUpdate))
		} else {
			lines = append(lines, sl(sevOK, "Homebrew packages up to date"))
		}
	}

	lines = append(lines, macOSUpdateLines()...)
	return group{"Upkeep", linesSev(lines), lines, firstFix(lines)}
}

func orDetached(branch string) string {
	if branch == "" {
		return "a detached HEAD"
	}
	return branch
}

// macOSUpdateLines reads the updates macOS found at its last check, from its
// own record, which costs no network and no softwareupdate run. An update
// whose major version is not the running one is a major upgrade: named, never
// counted, as macos-updates treats it.
func macOSUpdateLines() []statusLine {
	v, err := readPlist(sysVersionPlist)
	current := pString(pDict(v)["ProductVersion"])
	if err != nil || current == "" {
		return []statusLine{sl(sevInfo, "macOS updates: cannot read the installed version")}
	}
	major := strings.SplitN(current, ".", 2)[0]
	su, err := readPlist(suPlist)
	if err != nil {
		return []statusLine{sl(sevInfo, "macOS has no record of an update check yet")}
	}
	as := ""
	if t, ok := pTime(pDict(su)["LastSuccessfulDate"]); ok {
		as = ", as of its check " + ago(now().Sub(t))
	}
	var minor, majors []string
	for _, u := range pArray(pDict(su)["RecommendedUpdates"]) {
		d := pDict(u)
		name, ver := pString(d["Display Name"]), pString(d["Display Version"])
		if name == "" {
			name = "macOS " + ver
		}
		if strings.SplitN(ver, ".", 2)[0] == major {
			minor = append(minor, name)
		} else {
			majors = append(majors, name)
		}
	}
	var lines []statusLine
	if len(minor) > 0 {
		lines = append(lines, slFix(sevWarn, plural(len(minor), "macOS update", "macOS updates")+" for macOS "+major+as+": "+names(minor), fixUpdates))
	} else {
		lines = append(lines, sl(sevOK, "No macOS update for macOS "+major+as))
	}
	if len(majors) > 0 {
		lines = append(lines, sl(sevInfo, "  offered, and never installed by mrk, being a major upgrade: "+names(majors)))
	}
	return lines
}

// ── Time Machine ──────────────────────────────────────────────────────────

const (
	tmWarnAge = 24 * time.Hour
	tmErrAge  = 7 * 24 * time.Hour
)

// checkTimeMachine reads Time Machine's own record: its destinations, whether
// it backs up on its own, and the dates of the backups each destination holds.
// The newest of those is the last backup.
func checkTimeMachine() group {
	const name = "Time Machine Backups"
	v, err := readPlist(tmPlist)
	if err != nil {
		return group{name, sevWarn, []statusLine{sl(sevWarn, "Cannot read Time Machine's settings: "+err.Error())}, ""}
	}
	root := pDict(v)
	dests := pArray(root["Destinations"])
	if len(dests) == 0 {
		return group{name, sevWarn, []statusLine{
			sl(sevWarn, "No destination: Time Machine is not backing up"),
			sl(sevInfo, "  set one up in System Settings → General → Time Machine"),
		}, ""}
	}
	var lines []statusLine
	if auto, ok := pBool(root["AutoBackup"]); ok && !auto {
		lines = append(lines, sl(sevWarn, "Automatic backups are off: Time Machine backs up only when asked"))
	}
	var last time.Time
	for _, d := range dests {
		dd := pDict(d)
		for _, s := range pArray(dd["SnapshotDates"]) {
			if t, ok := pTime(s); ok && t.After(last) {
				last = t
			}
		}
		if t, ok := pTime(dd["ReferenceLocalSnapshotDate"]); ok && t.After(last) {
			last = t
		}
	}
	dest := plural(len(dests), "destination", "destinations")
	if last.IsZero() {
		lines = append(lines, sl(sevWarn, "No completed backup recorded, on "+dest))
		return group{name, linesSev(lines), lines, ""}
	}
	age := now().Sub(last)
	when := fmt.Sprintf("Last backup %s (%s), %s", ago(age), last.Local().Format("2006-01-02 15:04"), dest)
	switch {
	case age > tmErrAge:
		lines = append(lines, sl(sevErr, when))
	case age > tmWarnAge:
		lines = append(lines, sl(sevWarn, when))
	default:
		lines = append(lines, sl(sevOK, when))
	}
	return group{name, linesSev(lines), lines, ""}
}

// ── Installation ──────────────────────────────────────────────────────────

// brewfileSummary is the Brewfile's part of Installation: how much it tracks,
// and how much of that is installed, from the same drift Unrecorded reports.
func brewfileSummary(repoRoot string, drift brewDrift) group {
	path := filepath.Join(repoRoot, "Brewfile")
	f, err := os.Open(path)
	if err != nil {
		return group{"Brewfile", sevWarn, []statusLine{sl(sevWarn, "Not found at "+path)}, ""}
	}
	defer f.Close()
	formulae, casks := 0, 0
	sc := bufio.NewScanner(f)
	for sc.Scan() {
		l := strings.TrimSpace(sc.Text())
		switch {
		case reBrewPkg.MatchString(l):
			formulae++
		case reCaskPkg.MatchString(l):
			casks++
		}
	}
	if err := sc.Err(); err != nil {
		return group{"Brewfile", sevWarn, []statusLine{sl(sevWarn, "Cannot read "+path+": "+err.Error())}, ""}
	}
	tracked := fmt.Sprintf("%d formulae and %d casks tracked", formulae, casks)
	switch {
	case drift.noBrew:
		return group{"Brewfile", sevInfo, []statusLine{sl(sevInfo, tracked+"; Homebrew is not installed")}, ""}
	case drift.err != nil:
		return group{"Brewfile", sevWarn, []statusLine{sl(sevWarn, tracked+"; "+drift.err.Error())}, ""}
	case len(drift.prunes) > 0:
		return group{"Brewfile", sevInfo, []statusLine{sl(sevInfo, fmt.Sprintf("%s, %d not installed: see Unrecorded", tracked, len(drift.prunes)))}, ""}
	}
	return group{"Brewfile", sevOK, []statusLine{sl(sevOK, tracked+", all installed")}, ""}
}

// fold makes one panel of several checks: a line for each, its severity and
// its first line, then each of its lines that warns or errs, indented. The
// panel's fix is the first fix among the checks that warn or err.
func fold(name string, parts []group) group {
	var lines []statusLine
	var sevs []severity
	fix := ""
	for _, p := range parts {
		sevs = append(sevs, p.sev)
		head := p.name
		if len(p.lines) > 0 {
			head += " — " + p.lines[0].text
		}
		partFix := ""
		if p.sev >= sevWarn {
			partFix = p.fix
			if fix == "" {
				fix = p.fix
			}
		}
		lines = append(lines, slFix(p.sev, head, partFix))
		for _, l := range p.lines[min(1, len(p.lines)):] {
			if l.sev >= sevWarn {
				lines = append(lines, sl(l.sev, "  "+l.text))
			}
		}
	}
	return group{name, panelSev(sevs...), lines, fix}
}

func checkInstallation(repoRoot, home, binDir string, drift brewDrift) group {
	stateDir := filepath.Join(home, ".mrk")
	parts := []group{
		checkDotfiles(repoRoot, home),
		checkTools(repoRoot, binDir),
		checkShell(),
		checkPATH(home, binDir),
		checkHomebrew(),
		brewfileSummary(repoRoot, drift),
		checkDefaults(stateDir),
		checkHardening(stateDir),
	}
	if g, ok := checkBackups(stateDir); ok {
		g.name = "Displaced files"
		parts = append(parts, g)
	}
	return fold("Installation", parts)
}

// ── All of it ─────────────────────────────────────────────────────────────

// collect runs every panel, the slow ones side by side: sync --check and brew
// outdated each take about a second.
func collect(repoRoot, home, binDir string) []group {
	var (
		wg    sync.WaitGroup
		drift brewDrift
		up    group
		tm    group
	)
	wg.Add(3)
	go func() { defer wg.Done(); drift = readBrewDrift(repoRoot) }()
	go func() { defer wg.Done(); up = checkUpkeep(repoRoot, home, binDir) }()
	go func() { defer wg.Done(); tm = checkTimeMachine() }()
	wg.Wait()
	var un, inst group
	wg.Add(2)
	go func() { defer wg.Done(); un = checkUnrecorded(repoRoot, home, drift) }()
	go func() { defer wg.Done(); inst = checkInstallation(repoRoot, home, binDir, drift) }()
	wg.Wait()
	return []group{un, up, tm, inst}
}
