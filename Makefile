SHELL := /bin/bash
REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPTS   := $(REPO_ROOT)/scripts
BIN_DIR   := $(REPO_ROOT)/bin

.PHONY: all install fix-exec setup brew post-install tools dotfiles defaults trackpad uninstall update updates harden status doctor snapshot

all: fix-exec
	@MRK_PHASE=all "$(SCRIPTS)/setup"
	@MRK_PHASE=all "$(SCRIPTS)/brew"
	@MRK_PHASE=all "$(SCRIPTS)/post-install"
	@printf "\n  \033[2mRun\033[0m \033[36mexec zsh\033[0m \033[2mto reload your shell, or open a new terminal.\033[0m\n\n"

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
	@brew doctor

snapshot:
	@"$(SCRIPTS)/snapshot"
