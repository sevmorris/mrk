SHELL := /bin/bash
REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SCRIPTS   := $(REPO_ROOT)/scripts
BIN_DIR   := $(REPO_ROOT)/bin
INSTALL_BIN := $(HOME)/bin

# The checkout ~/bin serves. update-full, mrk-menu and mrk-status read MRK_ROOT
# the same way.
MRK_HOME := $(or $(MRK_ROOT),$(HOME)/mrk)

# Symlink a repo-built binary into ~/bin: $(call link-home-bin,<binary>,<link names>)
#
# Only from the checkout ~/bin serves, compared as resolved paths so a repo
# under a symlink still counts. Built anywhere else — a clone, a worktree, a
# scratch copy, a CI runner — the binary is built and not linked. Until
# 2026-09-16 every build linked, so a `make build-tools` run to test a scratch
# copy repointed mrk-status, mrk-picker, mrk-menu and status at that copy, to
# dangle once it was deleted.
define link-home-bin
	@if [ "$$(cd "$(MRK_HOME)" 2>/dev/null && pwd -P)" = "$$(cd "$(REPO_ROOT)" && pwd -P)" ]; then \
		mkdir -p "$(INSTALL_BIN)" && \
		for n in $(2); do ln -sf "$(BIN_DIR)/$(1)" "$(INSTALL_BIN)/$$n" || exit 1; done && \
		printf '  \033[32m✓\033[0m $(1) → $(patsubst %,~/bin/%,$(2))\n'; \
	else \
		printf '  \033[33m⚠\033[0m $(1) built, not linked: ~/bin serves $(MRK_HOME), not this checkout\n'; \
	fi
endef

.PHONY: trim-services all install fix-exec setup setup-dry brew post-install apps tools dotfiles defaults trackpad uninstall update pull updates harden status doctor picker mrk-status mrk-menu build-tools tidy sync sync-login-items snapshot snapshot-prefs pull-prefs snapshot-keys restore-keys restore-repos dock help check ci maintain

# Build a Go tool: $(call go-build,<binary>,<tool-dir>)
define go-build
	@if ! command -v go >/dev/null 2>&1; then \
		echo "error: Go is not installed. Install it with: brew install go"; \
		exit 1; \
	fi
	@printf '  \033[36m▸\033[0m Building $(1)…\n'
	@VERSION=$$(git -C "$(REPO_ROOT)" describe --tags --always --dirty 2>/dev/null || echo dev); \
	 SHA=$$(git -C "$(REPO_ROOT)" rev-parse --short HEAD 2>/dev/null || echo unknown); \
	 cd "$(REPO_ROOT)/tools/$(2)" && \
	 go build -ldflags "-X main.Version=$$VERSION -X main.GitSHA=$$SHA" -o "$(BIN_DIR)/$(1)" .
	@chmod +x "$(BIN_DIR)/$(1)"
endef

help: ## Show available make commands
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2}'

check: ## Run local CI checks (descriptions, secret scan, commit gates, cleanempties, defaults and harden undo, macOS updates, shellcheck, go test)
	@"$(SCRIPTS)/ci-check"

ci: check build-tools ## Full CI pipeline locally (check + build all TUIs)

all: fix-exec setup brew post-install build-tools ## Full install: setup + brew + post-install + TUI binaries
	@printf '\n'
	@printf '\033[1;32m  ✔  mrk installed successfully.\033[0m\n'
	@printf '\n'
	@printf '  Run \033[43;1;30m exec zsh \033[0m to reload your shell, or open a new terminal.\n'
	@if [ ! -d "$(HOME)/.mrk/preferences" ]; then \
		printf '\n'; \
		printf '  Preferences not restored — add your SSH key to GitHub, then run \033[43;1;30m make pull-prefs \033[0m\n'; \
		printf '  \033[2mhttps://github.com/settings/keys\033[0m\n'; \
	fi
	@printf '\n'
	@printf '  App Store apps are not installed by mrk — the list is docs/app-store-apps.md.\n'
	@printf '  Install them from App Store.app, then run \033[43;1;30m make post-install \033[0m again — it skipped the preferences and login items of apps not installed yet.\n'
	@printf '\n'
	@printf '  \033[2mManual: \033[4mhttps://sevmorris.github.io/mrk\033[0m\n'
	@printf '\n'

build-tools: ## Build all Go TUI binaries (requires Go)
	@printf '\n\033[1;34m══ Phase 4: TUI Tools\033[0m\n\n'
	@$(MAKE) --no-print-directory picker mrk-status mrk-menu

tidy: ## Run go mod tidy in all tool directories
	@for dir in picker mrk-status mrk-menu; do \
		printf '  \033[36m▸\033[0m go mod tidy: tools/$$dir\n'; \
		cd "$(REPO_ROOT)/tools/$$dir" && go mod tidy; \
	done

fix-exec: ## Make scripts and bin files executable
	@"$(SCRIPTS)/fix-exec"

install: setup ## Run Phase 1 setup
setup: ## Phase 1: shell, dotfiles, macOS defaults
	@"$(SCRIPTS)/setup" $(ARGS)

setup-dry: ## Preview Phase 1 changes without applying them
	@"$(SCRIPTS)/setup" --dry-run

brew: ## Phase 2: install Homebrew packages and casks
	@"$(SCRIPTS)/brew" $(ARGS)

post-install: ## Phase 3: configure apps and login items
	@"$(SCRIPTS)/post-install" $(ARGS)

apps: ## Install this Mac's own apps from their GitHub releases (skips any already installed)
	@"$(SCRIPTS)/install-apps" $(ARGS)

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

pull: ## Fast-forward the mrk repo to origin (git pull --ff-only)
	@git -C "$(REPO_ROOT)" pull --ff-only

update: ## Upgrade all packages (topgrade or brew)
	@if command -v topgrade >/dev/null 2>&1; then topgrade; else brew update && brew upgrade; fi

updates: ## Install macOS updates for the installed version, never a major upgrade  (ARGS=-n for dry run)
	@"$(BIN_DIR)/macos-updates" $(ARGS)

maintain: ## Housekeeping: prune Pages deployments, fetch --prune, validate, check builds
	@"$(BIN_DIR)/maintain" $(ARGS)

trim-services: ## Disable background launchd agents this Mac does not need  (ARGS=-n for dry run)
	@"$(SCRIPTS)/trim-services" $(ARGS)

harden: ## Apply macOS security hardening
	@"$(SCRIPTS)/hardening.sh" $(ARGS)

status: ## Show installation status
	@"$(SCRIPTS)/status"

doctor: ## Run diagnostics
	@"$(SCRIPTS)/doctor" $(ARGS)

picker: ## Build the mrk-picker TUI binary
	$(call go-build,mrk-picker,picker)
	$(call link-home-bin,mrk-picker,mrk-picker)

mrk-status: ## Build the mrk-status TUI health dashboard binary
	$(call go-build,mrk-status,mrk-status)
	$(call link-home-bin,mrk-status,mrk-status status)

mrk-menu: ## Build the mrk-menu TUI launcher binary
	$(call go-build,mrk-menu,mrk-menu)
	$(call link-home-bin,mrk-menu,mrk-menu)


# TODO: ARGS is word-split by Make before the shell sees it. For flags with
# embedded spaces, quote the script invocation directly. (audit Makefile-L1)

sync: ## Sync installed Homebrew packages into the Brewfile  (pass ARGS=-c to commit, ARGS=-n for dry run)
	@"$(SCRIPTS)/sync" $(ARGS)

sync-login-items: ## Sync system login items into post-install and docs  (pass ARGS=-c to commit, ARGS=-n for dry run)
	@"$(SCRIPTS)/sync-login-items" $(ARGS)

snapshot: ## Export selected app prefs to assets/preferences/ in repo (distinct from snapshot-prefs)
	@"$(BIN_DIR)/snapshot" $(ARGS)

snapshot-prefs: ## Export app preferences to ~/.mrk/preferences/ and push to mrk-prefs
	@"$(SCRIPTS)/snapshot-prefs"

pull-prefs: ## Clone or pull app preferences from mrk-prefs into ~/.mrk/preferences/
	@"$(SCRIPTS)/pull-prefs"

snapshot-keys: ## Bundle ~/.ssh, ~/.gnupg and signing identities into an encrypted archive  (ARGS="-o PATH" · ARGS=-n dry run · ARGS=--no-signing)
	@"$(SCRIPTS)/snapshot-keys" $(ARGS)

restore-keys: ## Restore ~/.ssh, ~/.gnupg and signing identities from an archive  (pass ARGS=<archive>)
	@"$(SCRIPTS)/restore-keys" $(ARGS)

restore-repos: ## Clone the repositories recorded in the mrk-prefs manifest  (ARGS=-n for dry run)
	@"$(SCRIPTS)/restore-repos" $(ARGS)

dock: ## Populate the Dock with preferred apps (requires dockutil)
	@"$(SCRIPTS)/dock-setup"
