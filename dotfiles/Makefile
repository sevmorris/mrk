MRK := $(HOME)/mrk

.PHONY: sync snapshot-prefs pull-prefs snapshot-keys restore-keys restore-repos picker help

help: ## Show available make commands
	@echo ""
	@echo "  \033[1mFrom ~/\033[0m"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| grep -v '^help:' \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' \
		| sort
	@echo ""
	@echo "  \033[1mFrom ~/mrk/\033[0m"
	@$(MAKE) -C $(MRK) help --no-print-directory 2>/dev/null
	@echo ""

sync: ## Sync installed Homebrew packages into the Brewfile  (pass ARGS=-c to commit, ARGS=-n for dry run)
	@$(MAKE) -C $(MRK) sync ARGS="$(ARGS)"

snapshot-prefs: ## Export app preferences and push to mrk-prefs
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

