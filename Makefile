SHELL := /bin/bash
REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPTS   := $(REPO_ROOT)/scripts
BIN_DIR   := $(REPO_ROOT)/bin

.PHONY: all adventure install fix-exec setup setup-dry brew post-install tools dotfiles defaults trackpad uninstall update updates harden status doctor picker bf mrk-status build-tools sync sync-login-items snapshot-prefs pull-prefs syncall dock help

# Build a Go tool: $(call go-build,<binary>,<tool-dir>)
define go-build
	@if ! command -v go >/dev/null 2>&1; then \
		echo "error: Go is not installed. Install it with: brew install go"; \
		exit 1; \
	fi
	@printf '  \033[36m▸\033[0m Building $(1)…\n'
	@cd "$(REPO_ROOT)/tools/$(2)" && go mod tidy && go build -o "$(BIN_DIR)/$(1)" .
	@chmod +x "$(BIN_DIR)/$(1)"
endef

help: ## Show available make commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' \
		| sort

all: fix-exec setup brew post-install build-tools ## Full install: setup + brew + post-install + TUI binaries
	@printf '\n'
	@if printf '%s' '$(ARGS)' | grep -q -- '--adventure'; then \
		printf '              \033[1m*** YOU HAVE WON ***\033[0m\n\n'; \
		printf '  Your Mac has been configured. Your dotfiles live in ~/.\n'; \
		printf '  Your tools are in ~/bin. The grue has been avoided.\n'; \
	else \
		printf '\033[1;32m  ✔  mrk installed successfully.\033[0m\n'; \
	fi
	@printf '\n'
	@printf '  Run \033[43;1;30m exec zsh \033[0m to reload your shell, or open a new terminal.\n'
	@if [ ! -d "$(HOME)/.mrk/preferences" ]; then \
		printf '\n'; \
		printf '  Preferences not restored — add your SSH key to GitHub, then run \033[43;1;30m make pull-prefs \033[0m\n'; \
		printf '  \033[2mhttps://github.com/settings/keys\033[0m\n'; \
	fi
	@printf '\n'
	@printf '  \033[2mManual: \033[4mhttps://sevmorris.github.io/mrk\033[0m\n'
	@printf '\n'

adventure: ## Full install in narrative adventure mode
	@"$(SCRIPTS)/adventure-prologue" && $(MAKE) --no-print-directory all ARGS=--adventure-end

build-tools: ## Build all Go TUI binaries (requires Go)
	@printf '\n\033[1;34m══ Phase 4: TUI Tools\033[0m\n\n'
	@$(MAKE) --no-print-directory picker bf mrk-status

fix-exec: ## Make scripts and bin files executable
	@if find $(SCRIPTS) -type f -maxdepth 1 -not -name "*.md" -exec chmod +x {} + 2>/dev/null && \
	    find $(BIN_DIR) -type f -maxdepth 1 -not -name "*.md" -exec chmod +x {} + 2>/dev/null; then \
	  printf '  \033[32m✓\033[0m Made scripts executable\n'; \
	else \
	  printf '  \033[31m✗\033[0m Failed to make some scripts executable\n'; \
	fi

install: setup ## Run Phase 1 setup
setup: ## Phase 1: shell, dotfiles, macOS defaults
	@"$(SCRIPTS)/setup" $(ARGS)

setup-dry: ## Preview Phase 1 changes without applying them
	@"$(SCRIPTS)/setup" --dry-run

brew: ## Phase 2: install Homebrew packages and casks
	@"$(SCRIPTS)/brew" $(ARGS)

post-install: ## Phase 3: configure apps and login items
	@"$(SCRIPTS)/post-install" $(ARGS)

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
	$(call go-build,bf,bf)
	@ln -sf "$(BIN_DIR)/bf" "$(HOME)/bin/bf"
	@printf '  \033[32m✓\033[0m bf → ~/bin/bf\n'

picker: ## Build the mrk-picker TUI binary
	$(call go-build,mrk-picker,picker)
	@ln -sf "$(BIN_DIR)/mrk-picker" "$(HOME)/bin/mrk-picker"
	@printf '  \033[32m✓\033[0m mrk-picker → ~/bin/mrk-picker\n'

mrk-status: ## Build the mrk-status TUI health dashboard binary
	$(call go-build,mrk-status,mrk-status)
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

syncall: ## Auto-commit and push all GitHub repos under $HOME  (pass ARGS=-n for dry run)
	@"$(SCRIPTS)/syncall" $(ARGS)

dock: ## Populate the Dock with preferred apps (requires dockutil)
	@"$(SCRIPTS)/dock-setup"
