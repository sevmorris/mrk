package main

type cmdType int

// Where an item's command is. The menu runs a tool of bin/ or scripts/ from
// ~/bin, where setup links both (commandFor). --json names the tool by its
// path in the checkout, so a program that runs it from there needs to know
// which.
const (
	cmdBin    cmdType = iota // a tool in bin/, or one make builds there
	cmdScript                // a tool in scripts/
	cmdMake
)

// nukeWord is what nuke-mrk's confirmation wants typed: the menu's prompt,
// and --json's type_to_confirm for a program that asks the same.
const nukeWord = "nuke"

// terminalTools are the targets whose items must run in a terminal of their
// own: --json's "terminal", for a program that runs this list where it cannot
// draw a full screen, as Dipstick's console cannot.
//   - sync and sync-login-items can start mrk-picker and gum choose.
//     tests/mrk-contract.sh holds this to their scripts, as it holds the
//     Makefile's terminal targets.
//   - update-full quits every running application but the one it runs in,
//     which it can tell only for a terminal it knows, and offers a reboot.
//   - nuke-mrk moves ~/mrk itself to the Trash, the checkout such a program
//     runs commands in, and asks before each step.
var terminalTools = map[string]bool{
	"sync":             true,
	"sync-login-items": true,
	"update-full":      true,
	"nuke-mrk":         true,
}

type item struct {
	name      string
	desc      string
	cmdType   cmdType
	target    string
	args      []string
	needsNuke bool
}

type category struct {
	name  string
	items []item
}

// The order is the point. Until 2026-09-30 the menu opened on Brewfile, with
// the commands of the day spread through Brewfile, Login items and
// Maintenance, and the setup phases and the migration steps in the middle.
// Daily comes first now: the three commands that record a change into mrk,
// the first column of SMAC-2's "After You Change Something". Setup and
// Migration, which a Mac runs once, come last, before Nuclear options.
var categories = []category{
	{
		name: "Daily",
		items: []item{
			{"sync --push", "add new Homebrew packages to the Brewfile, commit and push", cmdScript, "sync", []string{"--push"}, false},
			{"sync-login-items -c", "track new login items in config/login-items.txt, and commit", cmdScript, "sync-login-items", []string{"-c"}, false},
			{"mrk-push", "commit and push ~/mrk (asks for the message)", cmdBin, "mrk-push", nil, false},
		},
	},
	{
		name: "Brewfile",
		items: []item{
			{"sync", "diff installed packages, add missing to Brewfile", cmdScript, "sync", nil, false},
			{"sync --prune", "remove Brewfile entries for uninstalled packages", cmdScript, "sync", []string{"--prune"}, false},
			{"sync --dry-run", "show what sync would do, no changes", cmdScript, "sync", []string{"--dry-run"}, false},
		},
	},
	{
		name: "Login items",
		items: []item{
			{"sync-login-items", "diff and sync system login items", cmdScript, "sync-login-items", nil, false},
		},
	},
	{
		name: "Preferences",
		items: []item{
			{"snapshot-prefs", "export and push app prefs to mrk-prefs", cmdScript, "snapshot-prefs", nil, false},
			{"snapshot-prefs --dry-run", "show what snapshot-prefs would commit, push nothing", cmdScript, "snapshot-prefs", []string{"--dry-run"}, false},
		},
	},
	{
		name: "Diagnostics",
		items: []item{
			{"mrk-status", "daily dashboard", cmdBin, "mrk-status", nil, false},
			{"make doctor", "check ~/bin is on PATH", cmdMake, "doctor", nil, false},
			{"make doctor ARGS=--fix", "also fix PATH if missing", cmdMake, "doctor", []string{"ARGS=--fix"}, false},
		},
	},
	{
		name: "Maintenance",
		items: []item{
			{"make pull", "pull mrk, rebuild and relink what changed", cmdMake, "pull", nil, false},
			{"make update", "upgrade packages (topgrade or brew upgrade)", cmdMake, "update", nil, false},
			{"make updates", "install macOS updates, never a major upgrade", cmdMake, "updates", nil, false},
			{"make updates ARGS=-n", "list macOS updates, install nothing", cmdMake, "updates", []string{"ARGS=-n"}, false},
			{"make maintain", "prune deployments, fetch --prune, validate, check builds", cmdMake, "maintain", nil, false},
			{"make tidy", "go mod tidy in all tool directories", cmdMake, "tidy", nil, false},
			{"make fix-exec", "make all scripts and bin files executable", cmdMake, "fix-exec", nil, false},
			{"update-full", "full pass: quits apps, updates, rebuilds, offers reboot", cmdBin, "update-full", nil, false},
			{"pushall", "commit and push every repo in ~/Projects, and then mrk", cmdBin, "pushall", nil, false},
			{"pushall --dry-run", "scan and report; commit and push nothing", cmdBin, "pushall", []string{"--dry-run"}, false},
			{"clean-ds", "remove .DS_Store files from local volumes", cmdBin, "clean-ds", nil, false},
			{"clean-ds --dry-run", "list .DS_Store files, delete nothing", cmdBin, "clean-ds", []string{"--dry-run"}, false},
			{"tidy-projects", "survey the clones in ~/Projects and ~/mrk, change nothing", cmdBin, "tidy-projects", nil, false},
			{"tidy-projects --apply ff,refs,worktrees,branches", "fast-forward, prune refs, drop finished worktrees and merged branches", cmdBin, "tidy-projects", []string{"--apply", "ff,refs,worktrees,branches"}, false},
			{"prune-deployments --dry-run", "list old Pages deployments, delete nothing", cmdBin, "prune-deployments", []string{"--dry-run"}, false},
			{"prune-deployments", "delete old Pages deployments, keep the live one", cmdBin, "prune-deployments", nil, false},
		},
	},
	{
		name: "Setup",
		items: []item{
			{"make defaults", "apply macOS defaults", cmdMake, "defaults", nil, false},
			{"make harden", "apply security hardening (Touch ID sudo, firewall)", cmdMake, "harden", nil, false},
			{"make trackpad", "apply defaults including trackpad", cmdMake, "trackpad", nil, false},
			{"make dotfiles", "relink dotfiles", cmdMake, "dotfiles", nil, false},
			{"make tools", "relink scripts and bin into ~/bin", cmdMake, "tools", nil, false},
		},
	},
	{
		name: "Migration",
		// restore-keys is deliberately absent. It takes the archive path as a
		// required argument, and the menu runs a command with a fixed argument
		// list and no prompt, so the entry could only ever exit 1 on the usage
		// text. Run it as `make restore-keys ARGS=<archive>`.
		items: []item{
			{"snapshot-keys", "bundle ~/.ssh, ~/.gnupg and signing identities", cmdScript, "snapshot-keys", nil, false},
			{"snapshot-keys --dry-run", "show what would be bundled, write nothing", cmdScript, "snapshot-keys", []string{"--dry-run"}, false},
			{"pull-prefs", "clone or update app prefs from mrk-prefs", cmdScript, "pull-prefs", nil, false},
			{"restore-repos", "clone the repos listed in the mrk-prefs manifest", cmdScript, "restore-repos", nil, false},
			{"restore-repos --dry-run", "show which repos would be cloned", cmdScript, "restore-repos", []string{"--dry-run"}, false},
		},
	},
	{
		name: "Nuclear options",
		items: []item{
			{"nuke-mrk", "remove all mrk symlinks and undo setup", cmdBin, "nuke-mrk", nil, true},
		},
	},
}

func (i item) commandLine() string {
	cmd := i.target
	if i.cmdType == cmdMake {
		cmd = "make " + i.target
	}
	for _, a := range i.args {
		cmd += " " + a
	}
	return cmd
}

// shellLine is the item's command as a shell runs it in the checkout: the
// tool by its path there, or make, as mrk-status's fixes are written. --json
// gives it. No argument needs quoting (TestArgsNeedNoQuoting).
func (i item) shellLine() string {
	var cmd string
	switch i.cmdType {
	case cmdBin:
		cmd = "bin/" + i.target
	case cmdScript:
		cmd = "scripts/" + i.target
	default:
		cmd = "make " + i.target
	}
	for _, a := range i.args {
		cmd += " " + a
	}
	return cmd
}
