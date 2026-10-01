MRK := $(HOME)/mrk

# ~/Makefile, linked from ~/mrk/dotfiles: mrk's make targets from the home
# directory. The rules below are the ones `make help` lists under "From ~/";
# any other target goes to ~/mrk's Makefile by the .DEFAULT rule at the end,
# so every target there works from here. Until 2026-09-30 only these eleven
# did, and `make update` from ~ said "No rule to make target".

.PHONY: sync snapshot-prefs pull-prefs snapshot-keys restore-keys restore-repos picker mrk-status mrk-menu build-tools help

help: ## Show available make commands
	@echo ""
	@echo "  \033[1mFrom ~/\033[0m"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| grep -v '^help:' \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' \
		| sort
	@echo ""
	@echo "  \033[1mFrom ~/mrk/, and from ~/ as well\033[0m"
	@$(MAKE) -C $(MRK) help --no-print-directory 2>/dev/null
	@echo ""

sync: ## Sync installed Homebrew packages into the Brewfile  (pass ARGS=-c to commit, ARGS=-n for dry run)
	@$(MAKE) -C $(MRK) sync ARGS="$(ARGS)"

snapshot-prefs: ## Export app preferences and push to mrk-prefs  (ARGS=-n for dry run)
	@$(MAKE) -C $(MRK) snapshot-prefs

pull-prefs: ## Clone or pull app preferences from mrk-prefs
	@$(MAKE) -C $(MRK) pull-prefs

snapshot-keys: ## Bundle ~/.ssh, ~/.gnupg and signing identities into an encrypted archive
	@$(MAKE) -C $(MRK) snapshot-keys ARGS="$(ARGS)"

restore-keys: ## Restore ~/.ssh, ~/.gnupg and signing identities from an archive
	@$(MAKE) -C $(MRK) restore-keys ARGS="$(ARGS)"

restore-repos: ## Clone the repositories recorded in the mrk-prefs manifest
	@$(MAKE) -C $(MRK) restore-repos ARGS="$(ARGS)"

picker: ## Build the mrk-picker TUI binary
	@$(MAKE) -C $(MRK) picker

mrk-status: ## Build the mrk-status TUI binary
	@$(MAKE) -C $(MRK) mrk-status

mrk-menu: ## Build the mrk-menu TUI binary
	@$(MAKE) -C $(MRK) mrk-menu

build-tools: ## Build the three TUI binaries
	@$(MAKE) -C $(MRK) build-tools

# Every other target, to ~/mrk: `make update`, `make pull`, `make status` and
# the rest work from ~ as they do from ~/mrk. ARGS, like any variable given on
# the command line, reaches the inner make by itself; it is spelt out here as
# the rules above spell it. A target with no rule anywhere fails there, with
# ~/mrk's "No rule to make target".
.DEFAULT:
	@$(MAKE) -C $(MRK) $@ ARGS="$(ARGS)"
