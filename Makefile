SHELL := /bin/bash
REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPTS   := $(REPO_ROOT)/scripts
BIN_DIR   := $(REPO_ROOT)/bin

.PHONY: all install fix-exec setup brew post-install tools dotfiles defaults trackpad uninstall update updates harden status doctor picker sync snapshot-prefs pull-prefs manual help

help: ## Show available make commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}' \
		| sort

all: setup brew post-install ## Full install: setup + brew + post-install

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

picker: ## Build the mrk-picker TUI binary
	@if ! command -v go >/dev/null 2>&1; then \
		echo "error: Go is not installed. Install it with: brew install go"; \
		exit 1; \
	fi
	@echo "Building mrk-picker…"
	@cd "$(REPO_ROOT)/tools/picker" && go mod tidy -e && go build -o "$(BIN_DIR)/mrk-picker" .
	@echo "Built: $(BIN_DIR)/mrk-picker"
	@chmod +x "$(BIN_DIR)/mrk-picker"

sync: ## Sync installed Homebrew packages into the Brewfile
	@"$(SCRIPTS)/sync"

snapshot-prefs: ## Export app preferences to ~/.mrk/preferences/ and push to mrk-prefs
	@"$(SCRIPTS)/snapshot-prefs"

pull-prefs: ## Clone or pull app preferences from mrk-prefs into ~/.mrk/preferences/
	@"$(SCRIPTS)/pull-prefs"

manual: ## Regenerate docs/index.html from docs/manual.md (requires pandoc)
	@if ! command -v pandoc >/dev/null 2>&1; then \
		echo "error: pandoc is not installed. Install it with: brew install pandoc"; \
		exit 1; \
	fi
	@echo "Generating docs/index.html..."
	@pandoc "$(REPO_ROOT)/docs/manual.md" \
		--standalone \
		--embed-resources \
		--resource-path "$(REPO_ROOT)/docs" \
		--toc \
		--toc-depth=2 \
		--css "$(REPO_ROOT)/docs/assets/manual.css" \
		--highlight-style=zenburn \
		--output "$(REPO_ROOT)/docs/index.html" 2>/dev/null
	@# Wrap nav#TOC in <details> for collapsible behaviour
	@python3 -c "\
f = open('$(REPO_ROOT)/docs/index.html', 'r+'); \
s = f.read(); \
s = s.replace('<nav id=\"TOC\" role=\"doc-toc\">', '<details id=\"toc-details\"><summary class=\"toc-summary\">Table of Contents</summary><nav id=\"TOC\" role=\"doc-toc\">', 1); \
s = s.replace('</nav>', '</nav></details>', 1); \
f.seek(0); f.write(s); f.truncate(); f.close()"
	@echo "Generated: docs/index.html"
