SHELL := /bin/bash
REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPTS   := $(REPO_ROOT)/scripts
BIN_DIR   := $(REPO_ROOT)/bin

.PHONY: all install fix-exec setup brew post-install tools dotfiles defaults trackpad uninstall update updates harden status doctor picker bf mrk-status build-tools sync sync-login-items snapshot-prefs pull-prefs manual help

help: ## Show available make commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' \
		| sort

all: setup brew post-install build-tools ## Full install: setup + brew + post-install + TUI binaries
	@printf '\n'
	@printf '\033[1;32m  ✔  mrk installed successfully.\033[0m\n'
	@printf '\n'
	@printf '  \033[1;33m→\033[0m  Run \033[1mexec zsh\033[0m to reload your shell, or open a new terminal.\n'
	@printf '  \033[1;34m→\033[0m  Manual: \033[4mhttps://sevmorris.github.io/mrk\033[0m\n'
	@printf '\n'

build-tools: ## Build all Go TUI binaries (requires Go)
	@printf '\n\033[1;34m══ Phase 4: TUI Tools\033[0m\n\n'
	@$(MAKE) --no-print-directory picker bf mrk-status

fix-exec: ## Make scripts and bin files executable
	@find $(SCRIPTS) -type f -maxdepth 1 -not -name "*.md" -exec chmod +x {} + 2>/dev/null || true
	@find $(BIN_DIR) -type f -maxdepth 1 -not -name "*.md" -exec chmod +x {} + 2>/dev/null || true

install: setup ## Run Phase 1 setup
setup: fix-exec ## Phase 1: shell, dotfiles, macOS defaults
	@"$(SCRIPTS)/setup"

brew: fix-exec ## Phase 2: install Homebrew packages and casks
	@"$(SCRIPTS)/brew"

post-install: fix-exec ## Phase 3: configure apps and login items
	@"$(SCRIPTS)/post-install"

tools: ## Install CLI tools only (skip dotfiles)
	@"$(SCRIPTS)/setup" --only tools

dotfiles: ## Link dotfiles only (skip tools)
	@"$(SCRIPTS)/setup" --only dotfiles

defaults: ## Apply macOS defaults
	@"$(SCRIPTS)/defaults.sh"

trackpad: ## Apply macOS defaults including trackpad settings
	@"$(SCRIPTS)/defaults.sh" --with-trackpad

uninstall: ## Remove symlinks and undo setup
	@"$(SCRIPTS)/uninstall"

update: ## Upgrade all packages (topgrade or brew)
	@if command -v topgrade >/dev/null 2>&1; then topgrade; else brew update && brew upgrade; fi

updates: ## Run macOS software updates
	@softwareupdate -ia || true

harden: ## Apply macOS security hardening
	@"$(SCRIPTS)/hardening.sh"

status: ## Show installation status
	@"$(SCRIPTS)/status"

doctor: ## Run diagnostics
	@"$(SCRIPTS)/doctor"

bf: ## Build the bf Brewfile manager TUI binary
	@if ! command -v go >/dev/null 2>&1; then \
		echo "error: Go is not installed. Install it with: brew install go"; \
		exit 1; \
	fi
	@printf '  \033[36m▸\033[0m Building bf…\n'
	@cd "$(REPO_ROOT)/tools/bf" && go mod tidy -e && go build -o "$(BIN_DIR)/bf" .
	@chmod +x "$(BIN_DIR)/bf"
	@ln -sf "$(BIN_DIR)/bf" "$(HOME)/bin/bf"
	@printf '  \033[32m✓\033[0m bf → ~/bin/bf\n'

picker: ## Build the mrk-picker TUI binary
	@if ! command -v go >/dev/null 2>&1; then \
		echo "error: Go is not installed. Install it with: brew install go"; \
		exit 1; \
	fi
	@printf '  \033[36m▸\033[0m Building mrk-picker…\n'
	@cd "$(REPO_ROOT)/tools/picker" && go mod tidy -e && go build -o "$(BIN_DIR)/mrk-picker" .
	@chmod +x "$(BIN_DIR)/mrk-picker"
	@ln -sf "$(BIN_DIR)/mrk-picker" "$(HOME)/bin/mrk-picker"
	@printf '  \033[32m✓\033[0m mrk-picker → ~/bin/mrk-picker\n'

mrk-status: ## Build the mrk-status TUI health dashboard binary
	@if ! command -v go >/dev/null 2>&1; then \
		echo "error: Go is not installed. Install it with: brew install go"; \
		exit 1; \
	fi
	@printf '  \033[36m▸\033[0m Building mrk-status…\n'
	@cd "$(REPO_ROOT)/tools/mrk-status" && go mod tidy -e && go build -o "$(BIN_DIR)/mrk-status" .
	@chmod +x "$(BIN_DIR)/mrk-status"
	@ln -sf "$(BIN_DIR)/mrk-status" "$(HOME)/bin/mrk-status"
	@ln -sf "$(BIN_DIR)/mrk-status" "$(HOME)/bin/status"
	@printf '  \033[32m✓\033[0m mrk-status → ~/bin/mrk-status, ~/bin/status\n'


sync: ## Sync installed Homebrew packages into the Brewfile  (pass ARGS=-c to commit, ARGS=-n for dry run)
	@"$(SCRIPTS)/sync" $(ARGS)

sync-login-items: ## Sync system login items into post-install and docs  (pass ARGS=-c to commit, ARGS=-n for dry run)
	@"$(SCRIPTS)/sync-login-items" $(ARGS)

snapshot-prefs: ## Export app preferences to ~/.mrk/preferences/ and push to mrk-prefs
	@"$(SCRIPTS)/snapshot-prefs"

pull-prefs: ## Clone or pull app preferences from mrk-prefs into ~/.mrk/preferences/
	@"$(SCRIPTS)/pull-prefs"

manual: ## Open docs/index.html for editing (hand-authored AFTO-style document)
	@echo "docs/index.html is a hand-authored document — edit it directly."
	@echo "  $$EDITOR $(REPO_ROOT)/docs/index.html"
