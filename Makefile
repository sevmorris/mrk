SHELL := /bin/bash
REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPTS   := $(REPO_ROOT)/scripts
BIN_DIR   := $(REPO_ROOT)/bin

.PHONY: all install fix-exec setup brew post-install tools dotfiles defaults trackpad uninstall update updates harden status doctor picker sync

all: setup brew post-install

fix-exec:
	@echo "Making scripts and bin executables..."
	@find $(SCRIPTS) -type f -maxdepth 1 -not -name "*.md" -exec chmod +x {} + 2>/dev/null || true
	@find $(BIN_DIR) -type f -maxdepth 1 -not -name "*.md" -exec chmod +x {} + 2>/dev/null || true

install: setup
setup: fix-exec
	@"$(SCRIPTS)/setup"

brew: fix-exec
	@"$(SCRIPTS)/brew"

post-install: fix-exec
	@"$(SCRIPTS)/post-install"

tools:
	@"$(SCRIPTS)/setup" --only tools

dotfiles:
	@"$(SCRIPTS)/setup" --only dotfiles

defaults:
	@"$(SCRIPTS)/defaults.sh"

trackpad:
	@"$(SCRIPTS)/defaults.sh" --with-trackpad

uninstall:
	@"$(SCRIPTS)/uninstall"

update:
	@if command -v topgrade >/dev/null 2>&1; then topgrade; else brew update && brew upgrade; fi

updates:
	@softwareupdate -ia || true

harden:
	@"$(SCRIPTS)/hardening.sh"

status:
	@"$(SCRIPTS)/status"

doctor:
	@"$(SCRIPTS)/doctor"

picker:
	@if ! command -v go >/dev/null 2>&1; then \
		echo "error: Go is not installed. Install it with: brew install go"; \
		exit 1; \
	fi
	@echo "Building mrk-picker…"
	@cd "$(REPO_ROOT)/tools/picker" && go mod tidy -e && go build -o "$(BIN_DIR)/mrk-picker" .
	@echo "Built: $(BIN_DIR)/mrk-picker"
	@chmod +x "$(BIN_DIR)/mrk-picker"

sync:
	@"$(SCRIPTS)/sync"

