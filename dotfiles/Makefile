MRK := $(HOME)/Projects/mrk-dev

.PHONY: sync snapshot-prefs pull-prefs picker manual help

help: ## Show available make commands
	@echo ""
	@echo "  \033[1mFrom ~/\033[0m"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| grep -v '^help:' \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' \
		| sort
	@echo ""
	@echo "  \033[1mFrom ~/Projects/mrk-dev/\033[0m"
	@$(MAKE) -C $(MRK) help --no-print-directory 2>/dev/null
	@echo ""

sync: ## Sync installed Homebrew packages into the Brewfile  (pass ARGS=-c to commit, ARGS=-n for dry run)
	@$(MAKE) -C $(MRK) sync ARGS="$(ARGS)"

snapshot-prefs: ## Export app preferences and push to mrk-prefs
	@$(MAKE) -C $(MRK) snapshot-prefs

pull-prefs: ## Clone or pull app preferences from mrk-prefs
	@$(MAKE) -C $(MRK) pull-prefs

picker: ## Build the mrk-picker TUI binary
	@$(MAKE) -C $(MRK) picker

manual: ## Regenerate docs/index.html from docs/manual.md
	@$(MAKE) -C $(MRK) manual
