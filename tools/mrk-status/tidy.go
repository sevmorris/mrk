package main

// Clutter in the clones, for Upkeep: what tidy-projects --check finds under
// ~/Projects and in ~/mrk. Until 2026-11-05 nothing on the dashboard read
// tidy-projects, so Dipstick never showed a merged branch or a finished
// worktree, and the owner had to remember to run it.
//
// The survey asks GitHub about each clone: whether a branch's pull request
// merged, and how many Pages deployments a site has. On the Mac this was
// written on it took 7.4 seconds for 17 clones, twice as long as the rest of
// mrk-status, and Dipstick runs mrk-status every 30 minutes and whenever its
// menu opens on an old report. So mrk-status keeps the survey's lines for
// tidyMaxAge and reads them again until then, and checks each item against
// its clone, which needs no network: an item that a cleanup took since, by
// tidy-projects --apply, by hand, or by the app that made a worktree, leaves
// the panel at once. A new item waits for the next survey. A survey of the
// local clones alone would not do: without GitHub, only a branch whose tip is
// in the default branch counts as merged, and a squash merge never is.

import (
	"bytes"
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// tidyMaxAge is how long a survey's lines stand in for a new survey: a branch
// that a merge leaves behind shows within about two hours, and a survey runs
// at most once in four of Dipstick's runs.
const tidyMaxAge = 2 * time.Hour

// tidyTimeout bounds a survey, which waits on the network. A variable so the
// tests can make it short.
var tidyTimeout = 60 * time.Second

// tidyCache is where mrk-status keeps the last survey's lines. The file's date
// is the survey's.
func tidyCache(home string) string {
	return filepath.Join(home, "Library", "Caches", "mrk", "tidy-projects-check")
}

// The cleanups of tidy-projects --check, the words of its first field.
// lossless are the ones that lose no work, which fixTidy runs: the set
// mrk-menu offers. deploys deletes what cannot come back, and build takes a
// rebuild, so neither is ever on a button.
var (
	tidyCleanups = []string{"ff", "refs", "worktrees", "branches", "deploys", "build"}
	tidyLossless = []string{"ff", "refs", "worktrees", "branches"}
)

// tidyItem is one line of tidy-projects --check: a cleanup, the clone's name
// and folder, what the cleanup takes there, and a build folder's size.
type tidyItem struct {
	cleanup, repo, path, item string
	kb                        int64
}

type tidyReading struct {
	items   []tidyItem
	unknown int       // lines passed over: a word this binary does not know
	at      time.Time // when the survey ran
	err     error
}

// readTidy is the last survey while it is younger than tidyMaxAge, with the
// items that are gone since left out, or else a new one, which it keeps.
func readTidy(repoRoot, home string) tidyReading {
	cache := tidyCache(home)
	if fi, err := os.Stat(cache); err == nil {
		if age := now().Sub(fi.ModTime()); age >= 0 && age < tidyMaxAge {
			if out, err := os.ReadFile(cache); err == nil {
				if r := parseTidy(out); r.err == nil {
					r.at = fi.ModTime()
					r.items = slices.DeleteFunc(r.items, gone(map[string]string{}))
					return r
				}
			}
		}
	}
	out, err := runTidyCheck(repoRoot)
	if err != nil {
		return tidyReading{err: err}
	}
	r := parseTidy(out)
	r.at = now()
	if r.err == nil {
		saveTidy(cache, out)
	}
	return r
}

// runTidyCheck runs the checkout's bin/tidy-projects --check. It surveys six
// clones at a time in the background, so on a timeout the whole process group
// is stopped.
func runTidyCheck(repoRoot string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), tidyTimeout)
	defer cancel()
	cmd := exec.CommandContext(ctx, filepath.Join(repoRoot, "bin", "tidy-projects"), "--check")
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.Cancel = func() error { return syscall.Kill(-cmd.Process.Pid, syscall.SIGTERM) }
	cmd.WaitDelay = 5 * time.Second
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	switch {
	case errors.Is(ctx.Err(), context.DeadlineExceeded):
		return nil, fmt.Errorf("tidy-projects --check did not finish in %s", tidyTimeout)
	case err != nil:
		return nil, fmt.Errorf("tidy-projects --check failed: %s", failReason(stderr.String(), err))
	}
	return out, nil
}

func parseTidy(out []byte) tidyReading {
	rows, unknown, err := parseCheckLines("tidy-projects --check", out, 5, func(f []string) bool {
		return slices.Contains(tidyCleanups, f[0])
	})
	if err != nil {
		return tidyReading{err: err}
	}
	r := tidyReading{unknown: unknown}
	for _, f := range rows {
		kb, _ := strconv.ParseInt(f[4], 10, 64)
		r.items = append(r.items, tidyItem{cleanup: f[0], repo: f[1], path: f[2], item: f[3], kb: kb})
	}
	return r
}

// saveTidy keeps a survey's lines, through a file beside the cache and a
// rename, so a run that reads the cache meanwhile never sees half of it. A
// survey that cannot be kept is run again next time.
func saveTidy(path string, out []byte) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return
	}
	f, err := os.CreateTemp(filepath.Dir(path), ".tidy-projects-check-*")
	if err != nil {
		return
	}
	_, werr := f.Write(out)
	if cerr := f.Close(); werr != nil || cerr != nil || os.Rename(f.Name(), path) != nil {
		os.Remove(f.Name())
	}
}

// gone says whether a kept item has left its clone since the survey, by one
// local git call for each. A deployment is only on GitHub, so it is never
// gone here. Whether an item that is still there is still safe to take is
// for tidy-projects --apply to say: it surveys again before it takes anything.
// worktrees holds each clone's worktree list, read once.
func gone(worktrees map[string]string) func(tidyItem) bool {
	return func(it tidyItem) bool {
		switch it.cleanup {
		case "ff":
			n, err := git(it.path, "rev-list", "--count", "HEAD..origin/"+it.item)
			return err != nil || n == "0"
		case "refs":
			args := []string{"for-each-ref", "--format=%(refname)"}
			for _, r := range strings.Fields(it.item) {
				args = append(args, "refs/remotes/"+r)
			}
			out, err := git(it.path, args...)
			return err != nil || out == ""
		case "worktrees":
			list, ok := worktrees[it.path]
			if !ok {
				list, _ = git(it.path, "worktree", "list", "--porcelain")
				worktrees[it.path] = list
			}
			return !slices.Contains(strings.Split(list, "\n"), "worktree "+it.item)
		case "branches":
			_, err := git(it.path, "show-ref", "--verify", "--quiet", "refs/heads/"+it.item)
			return err != nil
		case "build":
			_, err := os.Stat(it.item)
			return err != nil
		}
		return false
	}
}

// tidyLines are Upkeep's lines for the survey: a warning for the cleanups
// that lose no work, with fixTidy, and an aside for the two that are left to
// the owner.
func tidyLines(r tidyReading) []statusLine {
	if r.err != nil {
		return []statusLine{sl(sevWarn, "Clones: "+r.err.Error())}
	}
	n := map[string]int{}
	var repos []string // with a cleanup that loses no work
	var kb int64
	derived := false
	for _, it := range r.items {
		if it.cleanup == "build" && it.repo == "Xcode" {
			derived = true
		} else {
			n[it.cleanup]++
		}
		kb += it.kb
		if slices.Contains(tidyLossless, it.cleanup) && !slices.Contains(repos, it.repo) {
			repos = append(repos, it.repo)
		}
	}
	slices.SortFunc(repos, func(a, b string) int { return strings.Compare(strings.ToLower(a), strings.ToLower(b)) })
	surveyed := ", surveyed " + ago(now().Sub(r.at))

	var found []string
	if c := n["branches"]; c > 0 {
		found = append(found, plural(c, "merged branch", "merged branches"))
	}
	if c := n["worktrees"]; c > 0 {
		found = append(found, plural(c, "finished worktree", "finished worktrees"))
	}
	if c := n["refs"]; c > 0 {
		found = append(found, "stale refs in "+plural(c, "clone", "clones"))
	}
	if c := n["ff"]; c > 0 {
		found = append(found, plural(c, "default branch behind origin", "default branches behind origin"))
	}
	var lines []statusLine
	if len(found) > 0 {
		lines = append(lines, slFix(sevWarn, "Clones: "+andList(found)+surveyed+": "+names(repos), fixTidy))
	} else {
		lines = append(lines, sl(sevOK, "Clones: no merged branches, finished worktrees or stale refs"+surveyed))
	}

	var left []string
	if c := n["deploys"]; c > 0 {
		left = append(left, plural(c, "Pages site past 10 deployments", "Pages sites past 10 deployments"))
	}
	var build []string
	if c := n["build"]; c > 0 {
		build = append(build, plural(c, "build folder", "build folders"))
	}
	if derived {
		build = append(build, "Xcode's DerivedData")
	}
	if len(build) > 0 {
		left = append(left, andList(build)+", "+sizeKB(kb))
	}
	if len(left) > 0 {
		lines = append(lines, sl(sevInfo, "  not on the button, as their cleanups delete what cannot come back: "+
			strings.Join(left, "; ")+" (tidy-projects lists them)"))
	}
	return append(lines, unknownLines("tidy-projects", r.unknown)...)
}

// andList joins words as a sentence does: "a", "a and b", "a, b and c".
func andList(ws []string) string {
	if len(ws) < 2 {
		return strings.Join(ws, "")
	}
	return strings.Join(ws[:len(ws)-1], ", ") + " and " + ws[len(ws)-1]
}

// sizeKB is a size in kilobytes as a person reads it, in powers of 1024 as du
// and tidy-projects count: "1.0 MB", "328 MB".
func sizeKB(kb int64) string {
	v, units := float64(kb), []string{"KB", "MB", "GB", "TB"}
	i := 0
	for v >= 1024 && i < len(units)-1 {
		v /= 1024
		i++
	}
	if v < 10 {
		return fmt.Sprintf("%.1f %s", v, units[i])
	}
	return fmt.Sprintf("%.0f %s", v, units[i])
}

// withLines is g with more lines at the end, its severity and fix taken again.
func withLines(g group, more []statusLine) group {
	g.lines = append(g.lines, more...)
	g.sev = linesSev(g.lines)
	g.fix = firstFix(g.lines)
	return g
}
