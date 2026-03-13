SHELL := /bin/bash
REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPTS   := $(REPO_ROOT)/scripts
BIN_DIR   := $(REPO_ROOT)/bin

.PHONY: all install fix-exec setup brew post-install tools dotfiles defaults trackpad uninstall update updates harden status doctor picker bf mrk-status build-tools barkeep sync sync-login-items snapshot-prefs pull-prefs manual help

help: ## Show available make commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' \
		| sort

all: setup brew post-install build-tools ## Full install: setup + brew + post-install + TUI binaries
	@echo ""
	@echo "  Run \`exec zsh\` to reload your shell, or open a new terminal."
	@echo "  Manual: https://sevmorris.github.io/mrk"
	@echo ""

build-tools: picker bf mrk-status ## Build all Go TUI binaries (requires Go)

fix-exec: ## Make scripts and bin files executable
	@echo "Making scripts and bin executables..."
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
	@echo "Building bf…"
	@cd "$(REPO_ROOT)/tools/bf" && go mod tidy -e && go build -o "$(BIN_DIR)/bf" .
	@chmod +x "$(BIN_DIR)/bf"
	@ln -sf "$(BIN_DIR)/bf" "$(HOME)/bin/bf"
	@echo "Built and linked: ~/bin/bf"

picker: ## Build the mrk-picker TUI binary
	@if ! command -v go >/dev/null 2>&1; then \
		echo "error: Go is not installed. Install it with: brew install go"; \
		exit 1; \
	fi
	@echo "Building mrk-picker…"
	@cd "$(REPO_ROOT)/tools/picker" && go mod tidy -e && go build -o "$(BIN_DIR)/mrk-picker" .
	@chmod +x "$(BIN_DIR)/mrk-picker"
	@ln -sf "$(BIN_DIR)/mrk-picker" "$(HOME)/bin/mrk-picker"
	@echo "Built and linked: ~/bin/mrk-picker"

mrk-status: ## Build the mrk-status TUI health dashboard binary
	@if ! command -v go >/dev/null 2>&1; then \
		echo "error: Go is not installed. Install it with: brew install go"; \
		exit 1; \
	fi
	@echo "Building mrk-status…"
	@cd "$(REPO_ROOT)/tools/mrk-status" && go mod tidy -e && go build -o "$(BIN_DIR)/mrk-status" .
	@chmod +x "$(BIN_DIR)/mrk-status"
	@ln -sf "$(BIN_DIR)/mrk-status" "$(HOME)/bin/mrk-status"
	@ln -sf "$(BIN_DIR)/mrk-status" "$(HOME)/bin/status"
	@echo "Built and linked: ~/bin/mrk-status and ~/bin/status"

barkeep: ## Build and install Barkeep.app to /Applications (requires xcodegen)
	@if ! command -v xcodegen >/dev/null 2>&1; then \
		echo "error: xcodegen is not installed. Install it with: brew install xcodegen"; \
		exit 1; \
	fi
	@echo "Building Barkeep…"
	@cd "$(REPO_ROOT)/tools/Barkeep" && xcodegen generate --quiet
	@xcodebuild \
		-project "$(REPO_ROOT)/tools/Barkeep/Barkeep.xcodeproj" \
		-scheme Barkeep \
		-configuration Release \
		-derivedDataPath /tmp/barkeep_build \
		-quiet
	@cp -Rf /tmp/barkeep_build/Build/Products/Release/Barkeep.app /Applications/
	@rm -rf /tmp/barkeep_build
	@echo "Installed: /Applications/Barkeep.app"

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
