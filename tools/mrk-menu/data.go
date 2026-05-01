package main

type cmdType int

const (
	cmdBin cmdType = iota
	cmdMake
)

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

var categories = []category{
	{
		name: "Brewfile",
		items: []item{
			{"bf", "interactive Brewfile manager", cmdBin, "bf", nil, false},
			{"sync", "diff installed packages, add missing to Brewfile", cmdBin, "sync", nil, false},
			{"sync --prune", "remove Brewfile entries for uninstalled packages", cmdBin, "sync", []string{"--prune"}, false},
			{"sync --dry-run", "show what sync would do, no changes", cmdBin, "sync", []string{"--dry-run"}, false},
			{"snapshot", "export selected app prefs to assets/preferences/", cmdBin, "snapshot", nil, false},
		},
	},
	{
		name: "Login items",
		items: []item{
			{"sync-login-items", "diff and sync system login items", cmdBin, "sync-login-items", nil, false},
		},
	},
	{
		name: "Preferences",
		items: []item{
			{"snapshot-prefs", "export and push app prefs to mrk-prefs", cmdBin, "snapshot-prefs", nil, false},
			{"pull-prefs", "clone or update app prefs from mrk-prefs", cmdBin, "pull-prefs", nil, false},
		},
	},
	{
		name: "System state",
		items: []item{
			{"make defaults", "apply macOS defaults", cmdMake, "defaults", nil, false},
			{"make harden", "apply security hardening (Touch ID sudo, firewall)", cmdMake, "harden", nil, false},
			{"make trackpad", "apply defaults including trackpad", cmdMake, "trackpad", nil, false},
			{"make dotfiles", "relink dotfiles", cmdMake, "dotfiles", nil, false},
			{"make tools", "relink scripts and bin into ~/bin", cmdMake, "tools", nil, false},
		},
	},
	{
		name: "Diagnostics",
		items: []item{
			{"mrk-status", "health dashboard", cmdBin, "mrk-status", nil, false},
			{"make doctor", "check ~/bin is on PATH", cmdMake, "doctor", nil, false},
			{"make doctor ARGS=--fix", "also fix PATH if missing", cmdMake, "doctor", []string{"ARGS=--fix"}, false},
		},
	},
	{
		name: "Maintenance",
		items: []item{
			{"make update", "upgrade packages (topgrade or brew upgrade)", cmdMake, "update", nil, false},
			{"make updates", "run macOS software updates", cmdMake, "updates", nil, false},
			{"make tidy", "go mod tidy in all tool directories", cmdMake, "tidy", nil, false},
			{"make fix-exec", "make all scripts and bin files executable", cmdMake, "fix-exec", nil, false},
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
