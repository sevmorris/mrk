#!/usr/bin/env bash
# tests/picard-settings.sh — snapshot-prefs keeps Picard's settings, not its credentials.
#
# Picard writes its settings and its MusicBrainz OAuth tokens into one INI,
# ~/.config/MusicBrainz/Picard.ini, so until 2026-09-24 snapshot-prefs left the
# file out entirely. It now keeps picard_settings' copy: the settings sections,
# each credential replaced with <redacted>. scan_for_secrets is no backstop for
# that filter — none of its patterns names fanart.tv's client_key — so this
# test holds the filter to it directly.
#
# The fixture is written at run time from variables. A literal token in this
# file would trip the secret scan on every push that staged it.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

failures=0
pass() { printf '  \033[32m✓\033[0m %s\n' "$1"; }
fail() { printf '  \033[31m✗\033[0m %s\n' "$1"; failures=$(( failures + 1 )); }

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/picard-settings.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

access="mebaFAKEaccess$RANDOM$RANDOM$RANDOM"
refresh="mebrFAKErefresh$RANDOM$RANDOM$RANDOM"
acoustid="FAKEacoustid$RANDOM"
fanart="fakefanart$RANDOM$RANDOM$RANDOM$RANDOM"
proxy="FAKEproxy$RANDOM$RANDOM"
plugin="FAKEplugin$RANDOM$RANDOM$RANDOM"
secrets=("$access" "$refresh" "$acoustid" "$fanart" "$proxy" "$plugin")

cat > "$ROOT/Picard.ini" <<EOF
[General]
AppleLocale=en_US

[application]
version=3.0.0.rc4

[com]
apple\\trackpad\\version=5

[persist]
oauth_access_token=$access
oauth_refresh_token=$refresh
oauth_username=someone
window_maximized=false

[plugin.d80f6f27-b141-438a-b644-fffb752e0ba2]
client_key=$plugin
use_cdart=noalbumart

[profiles]
user_profiles=@Invalid()

[setting]
acoustid_apikey=$acoustid
ca_providers=@Variant(\\0\\0\\0\\x7f), @Variant(\\0\\0\\0\\x7f)
cwp_key_tag=key
fanarttv_client_key=$fanart
fpcalc_threads=9
listenbrainz_token=
proxy_password=$proxy
EOF

out="$ROOT/settings.ini"
if ! picard_settings "$ROOT/Picard.ini" > "$out"; then
  fail "picard_settings failed on the fixture"
  exit 1
fi

leaked=0
for s in "${secrets[@]}"; do
  grep -qF -- "$s" "$out" && leaked=$(( leaked + 1 ))
done
if (( leaked == 0 )); then
  pass "no credential value survives (${#secrets[@]} checked)"
else
  fail "$leaked of ${#secrets[@]} credential values reached the output"
fi

for section in '[General]' '[com]' '[persist]'; do
  if grep -qxF -- "$section" "$out"; then fail "$section is kept"; else pass "$section is dropped"; fi
done
for section in '[application]' '[setting]' '[profiles]' '[plugin.d80f6f27-b141-438a-b644-fffb752e0ba2]'; do
  if grep -qxF -- "$section" "$out"; then pass "$section is kept"; else fail "$section is dropped"; fi
done

for key in acoustid_apikey fanarttv_client_key client_key proxy_password; do
  if grep -qxF -- "$key=<redacted>" "$out"; then
    pass "$key is redacted, so the diff still shows that it is set"
  else
    fail "$key is not redacted"
  fi
done

# Settings pass through byte for byte, a name ending in _key_tag included.
for line in 'listenbrainz_token=' 'cwp_key_tag=key' 'fpcalc_threads=9' \
            'version=3.0.0.rc4' 'use_cdart=noalbumart' \
            'ca_providers=@Variant(\0\0\0\x7f), @Variant(\0\0\0\x7f)'; do
  if grep -qxF -- "$line" "$out"; then pass "kept verbatim: $line"; else fail "not kept verbatim: $line"; fi
done

if scan_for_secrets "$out" 2>/dev/null; then
  pass "the output passes scan_for_secrets, so it cannot stall a snapshot-prefs push"
else
  fail "the output trips scan_for_secrets"
fi

# History, never a restore: a rewritten INI does not restore cleanly.
if grep -qE 'config/picard|"picard"' "$REPO_ROOT/scripts/post-install"; then
  fail "post-install reads config/picard — it is a record, not a restore"
else
  pass "post-install does not restore config/picard"
fi

if (( failures > 0 )); then
  printf '\n%d check(s) failed\n' "$failures"
  exit 1
fi
