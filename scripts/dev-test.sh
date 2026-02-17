#!/usr/bin/env bash
# dev-test.sh — Rebuild mrk as a clean user install from the GitHub repo.

set -e
REPO_URL="https://github.com/sevmorris/mrk.git"
TARGET_DIR="$HOME/mrk"

echo "🧹 Cleaning up old mrk install…"
if [ -d "$TARGET_DIR" ]; then
  cd "$TARGET_DIR" || exit 1
  if make uninstall >/dev/null 2>&1; then
    echo "✓ Uninstalled previous mrk."
  else
    echo "⚠️ No uninstall target or cleanup incomplete."
  fi
  cd ~ && rm -rf "$TARGET_DIR"
fi

echo "⬇️ Cloning fresh copy from GitHub…"
git clone "$REPO_URL" "$TARGET_DIR"

cd "$TARGET_DIR"
echo "🔧 Fixing permissions…"
make fix-exec

echo "🚀 Installing mrk…"
make install

echo "🩺 Running doctor…"
make doctor || true

echo "✅ Dev test complete. Fresh mrk installed from GitHub."
