#!/usr/bin/env bash
# dev-test.sh — Rebuild mrk as a clean user install from the GitHub repo.

set -e
REPO_URL="https://github.com/sevmorris/mrk.git"
TARGET_DIR="$HOME/mrk"

echo "🧹 Cleaning up old mrk install…"
if [ -d "$TARGET_DIR" ]; then
  make -C "$TARGET_DIR" uninstall >/dev/null 2>&1 && echo "✓ Uninstalled previous mrk." \
    || echo "⚠️ No uninstall target or cleanup incomplete."
  rm -rf "$TARGET_DIR"
fi

echo "⬇️ Cloning fresh copy from GitHub…"
git clone "$REPO_URL" "$TARGET_DIR"

echo "🚀 Installing mrk…"
make -C "$TARGET_DIR" all

echo "🩺 Running doctor…"
make -C "$TARGET_DIR" doctor || true

echo "✅ Dev test complete. Fresh mrk installed from GitHub."
