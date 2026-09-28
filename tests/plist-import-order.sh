#!/usr/bin/env bash
# plist-import-order.sh — prove that post-install imports every saved app plist
# on a fresh Mac, and still leaves an app that is already configured alone.
#
# import_plist imports only into an empty domain. Until 2026-09-27 post-install
# ran its app-defaults scripts first, and they wrote keys into six of the
# domains it imports afterwards: rogue-amoeba-updates.sh wrote two Sparkle keys
# into Loopback, SoundSource, Audio Hijack, Farrago and Piezo, and the Audio
# Hijack and Helium scripts wrote their own. Each of the six imports then found
# its domain holding something and logged "exists — skipping import". The
# 2026-09-15 migration imported none of them. Audit 19, W-2.
#
# post-install runs whole, from a copy of the repository, under a throwaway
# HOME and an empty environment. `defaults` is a stub first on PATH that keeps
# each domain as a plist file in the scratch directory and hands /usr/bin/defaults
# that path: cfprefsd writes the real user's preferences whatever $HOME says,
# and given a path, defaults reads and writes that file instead. The stub
# refuses any other shape of call. Every "/Applications/" in the copies points
# at a scratch folder of empty .app directories, so no real app is seen. ssh,
# sudo, osascript, launchctl and open are stubs that run nothing, nvm is a stub
# with a default already set, and scripts/install-apps is replaced by a no-op:
# it writes no preferences. Nothing reaches the network, System Events, launchd
# or the apps' real settings.
#
# A fifth machine is the one Phase 2 has just run on: Homebrew installed, and
# not on the PATH make all started with. Until 2026-09-27 post-install logged
# topgrade, pyenv and pinentry-mac as not installed there, and skipped them
# (audit 19, W-31). It lives here because this is the one harness that runs
# post-install whole. Homebrew is a scratch prefix named by MRK_BREW, holding
# stubs, and the copy's lib.sh is pointed away from this Mac's Homebrew too, so
# no real pyenv or topgrade can reach PATH.
#
# The run goes under /bin/bash and under the bash running this file, because
# post-install carries no bash-4 guard and a new Mac runs it with bash 3.2.
# ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ "${1:-}" != --inner ]]; then
  run_under() {
    # shellcheck disable=SC2016  # expanded by the inner bash, not this one
    printf '  under bash %s\n' "$("$1" -c 'echo "${BASH_VERSION%%(*}"')"
    "$1" "${BASH_SOURCE[0]}" --inner "$1"
  }
  rc=0
  run_under /bin/bash || rc=1
  if [[ ! "$BASH" -ef /bin/bash ]]; then run_under "$BASH" || rc=1; fi
  exit "$rc"
fi
BASH_UNDER_TEST="$2"

# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

[[ -x /usr/bin/defaults ]] || { fail "/usr/bin/defaults not found"; exit 1; }

W=$(mrk_mktemp_d) || exit 1
W=$(cd "$W" && pwd -P)
trap 'rm -rf "$W"' EXIT
R="$W/repo"
APPS="$W/Applications"
STUBS="$W/stubs"
mkdir -p "$R/scripts" "$R/assets/preferences" "$R/assets/browsers" "$APPS" "$STUBS"

# ── The repository copy ──────────────────────────────────────────────────────

cp -p "$REPO_ROOT/scripts/post-install" "$REPO_ROOT/scripts/lib.sh" "$R/scripts/"
cp -p "$REPO_ROOT"/assets/preferences/*.sh "$R/assets/preferences/"
cp -p "$REPO_ROOT"/assets/browsers/*.sh "$R/assets/browsers/"
cp -p "$REPO_ROOT/assets/topgrade.toml" "$R/assets/"
cp -p "$REPO_ROOT/.python-version" "$R/"
cat > "$R/scripts/install-apps" <<'EOF'
#!/usr/bin/env bash
install_companion_apps() { COMPANION_FAILED=0; }
EOF

for f in "$R/scripts/post-install" "$R"/assets/*/*.sh; do
  sed "s#/Applications/#$APPS/#g" "$f" > "$W/rewrite" && cat "$W/rewrite" > "$f"
done
if grep -n '/Applications/' "$R/scripts/post-install" "$R"/assets/*/*.sh | grep -vF "$APPS/"; then
  fail "a real /Applications path survived the rewrite — refusing to run"
  exit 1
fi
if grep -n '/usr/bin/defaults' "$R/scripts/post-install" "$R"/assets/*/*.sh; then
  fail "a script names /usr/bin/defaults, which the stub cannot intercept — refusing to run"
  exit 1
fi

# run_pi sets MRK_BREW to the scratch Homebrew. lib.sh's own Homebrew paths are
# pointed into the scratch directory as well, so a post-install that stopped
# honouring MRK_BREW would find no Homebrew, rather than this Mac's.
sed -e "s#/opt/homebrew/bin/brew#$W/refused/bin/brew#g" -e "s#/usr/local/bin/brew#$W/refused/bin/brew#g" \
  "$R/scripts/lib.sh" > "$W/rewrite" && cat "$W/rewrite" > "$R/scripts/lib.sh"
if grep -nE '/(opt/homebrew|usr/local)/bin/brew' "$R/scripts/post-install" "$R/scripts/lib.sh"; then
  fail "a real Homebrew path survived the rewrite — refusing to run"
  exit 1
fi

# ── Stubs ────────────────────────────────────────────────────────────────────

cat > "$STUBS/defaults" <<'EOF'
#!/bin/bash
# Every domain is a plist file under $STORE; nothing reaches the user's own.
printf '%s\n' "$*" >> "$DEFAULTS_LOG"
refuse() { printf 'REFUSED %s\n' "$*" >> "$DEFAULTS_LOG"; echo "defaults stub: refused: $*" >&2; exit 2; }
case "${1:-}" in read|write|delete|import|export) ;; *) refuse "$@" ;; esac
case "${2:-}" in
  "" | -*)      refuse "$@" ;;
  "$SCRATCH"/*) domain="$2" ;;
  /*)           refuse "$@" ;;
  *)            domain="$STORE/$2" ;;
esac
if [[ "$1" == import || "$1" == export ]]; then
  case "${3:-}" in "$SCRATCH"/* | -) ;; *) refuse "$@" ;; esac
fi
verb="$1"
shift 2
exec /usr/bin/defaults "$verb" "$domain" "$@"
EOF
cat > "$STUBS/ssh" <<'EOF'
#!/bin/bash
echo "git@github.com: Permission denied (publickey)." >&2
exit 255
EOF
for tool in sudo osascript launchctl open; do
  cat > "$STUBS/$tool" <<EOF
#!/bin/bash
printf '%s %s\n' $tool "\$*" >> "\$CALLS"
EOF
done
chmod +x "$STUBS"/*
ln -s "$BASH_UNDER_TEST" "$STUBS/bash"

# ── What post-install imports ────────────────────────────────────────────────

# One line per import_plist call: app path, bundle id, plist file name, name.
ENTRIES="$W/entries"
grep -E '^[[:space:]]*import_plist "' "$R/scripts/post-install" > "$W/calls.sh"
# shellcheck disable=SC2016  # expanded by the inner bash, not this one
LOCAL_PREFS_DIR=@ bash -c \
  'import_plist() { printf "%s\t%s\t%s\t%s\n" "$1" "$2" "${3##*/}" "$4"; }; failed=0; source "$1"' \
  _ "$W/calls.sh" > "$ENTRIES"
n_entries=$(wc -l < "$ENTRIES" | tr -d ' ')

# The six W-2 names. Each checks a key its defaults script writes, holding the
# opposite value in the saved plist, so the result shows which write came last.
W2_CHECKS="$W/w2"
cat > "$W2_CHECKS" <<'EOF'
com.rogueamoeba.Loopback	SUAutomaticallyUpdate	1	0
com.rogueamoeba.soundsource	SUAutomaticallyUpdate	1	0
com.rogueamoeba.audiohijack	applicationTheme	0	2
com.rogueamoeba.farrago	SUAutomaticallyUpdate	1	0
com.rogueamoeba.Piezo	SUAllowsAutomaticUpdates	1	0
net.imput.helium	SUAutomaticallyUpdate	0	1
EOF
missing=""
while IFS=$'\t' read -r id _; do
  cut -f2 "$ENTRIES" | grep -qxF "$id" || missing="$missing $id"
done < "$W2_CHECKS"
if [[ -z "$missing" ]] && (( n_entries >= 6 )); then
  pass "post-install imports $n_entries plists, the six W-2 names among them"
else
  fail "post-install no longer imports:$missing"
  exit 1
fi
W2_IDS=$(cut -f1 "$W2_CHECKS")
OWN_ID="io.github.sevmorris.ImportOrderProbe"

# ── Helpers ──────────────────────────────────────────────────────────────────

# apps [all | none-of-w2] — the fake /Applications
apps() {
  local path id
  rm -rf "$APPS"; mkdir -p "$APPS"
  while IFS=$'\t' read -r path id _; do
    if [[ "$1" == all ]] || ! grep -qxF "$id" <<<"$W2_IDS"; then mkdir -p "$path"; fi
  done < "$ENTRIES"
}

# machine DIR — a new Mac: HOME with mrk-prefs cloned, and no domains yet
machine() {
  local d="$1" id file saved key savedv
  mkdir -p "$d/home/.mrk/preferences/sevmorris-apps" "$d/home/.nvm" "$d/domains" "$d/tmp"
  # shellcheck disable=SC2016  # for nvm.sh to expand, not this shell
  printf 'nvm() { [[ "$1" == version ]] && echo v24.0.0; }\n' > "$d/home/.nvm/nvm.sh"
  while IFS=$'\t' read -r _ id file _; do
    saved="$d/home/.mrk/preferences/${file%.plist}"
    /usr/bin/defaults write "$saved" mrkTestSaved -string "$id"
    if read -r _ key savedv _ < <(grep -F "$id"$'\t' "$W2_CHECKS"); then
      /usr/bin/defaults write "$saved" "$key" -int "$savedv"
    fi
  done < "$ENTRIES"
  /usr/bin/defaults write "$d/home/.mrk/preferences/sevmorris-apps/$OWN_ID" mrkTestSaved -string "$OWN_ID"
}

# run_pi DIR — post-install --yes on that machine; output in DIR/out
run_pi() {
  local d="$1"
  env -i HOME="$d/home" PATH="$STUBS:/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="$d/tmp" \
    STORE="$d/domains" SCRATCH="$W" DEFAULTS_LOG="$d/defaults.log" CALLS="$d/calls.log" \
    MRK_BREW="$W/homebrew/bin/brew" \
    "$STUBS/bash" "$R/scripts/post-install" --yes </dev/null > "$d/out" 2>&1
}

get()    { /usr/bin/defaults read "$1/domains/$2" "$3" 2>/dev/null; }  # get DIR DOMAIN KEY
exists() { /usr/bin/defaults read "$1/domains/$2" >/dev/null 2>&1; }  # exists DIR DOMAIN
rollback_deletes() { grep -cE '^defaults delete ' "$1/home/.mrk/defaults-rollback.sh"; }
show_out() { grep -E '✗|⚠|refused|plist \(' "$1/out" | sed 's/^/      /' >&2; }

# ── 1. A fresh Mac: every saved plist is imported ────────────────────────────

F="$W/fresh"
machine "$F"; apps all
if run_pi "$F"; then
  pass "fresh Mac: post-install exits 0"
else
  fail "fresh Mac: post-install exited non-zero"; show_out "$F"
fi

not_imported=""
while IFS=$'\t' read -r _ id _ name; do
  [[ "$(get "$F" "$id" mrkTestSaved)" == "$id" ]] || not_imported="$not_imported, $name"
done < "$ENTRIES"
if [[ -z "$not_imported" ]]; then
  pass "fresh Mac: all $n_entries saved plists imported"
else
  fail "fresh Mac: not imported: ${not_imported#, }"; show_out "$F"
fi

wrong=""
while IFS=$'\t' read -r id key _ want; do
  got=$(get "$F" "$id" "$key")
  [[ "$got" == "$want" ]] || wrong="$wrong, $id $key=${got:-absent} (want $want)"
done < "$W2_CHECKS"
if [[ -z "$wrong" ]]; then
  pass "fresh Mac: mrk's keys land over the six restored domains, not under them"
else
  fail "fresh Mac: ${wrong#, }"
fi

if [[ "$(get "$F" "$OWN_ID" mrkTestSaved)" == "$OWN_ID" ]]; then
  pass "fresh Mac: my own app's plist imported with no app installed"
else
  fail "fresh Mac: my own app's plist was not imported"
fi

no_line=""
while IFS=$'\t' read -r _ id _; do
  grep -qxF "defaults delete $id >/dev/null 2>&1 || true" "$F/home/.mrk/defaults-rollback.sh" \
    || no_line="$no_line, $id"
done < <(cut -f1-2 "$ENTRIES"; printf 'own\t%s\n' "$OWN_ID")  # a leading tab would be stripped
if [[ -z "$no_line" ]] && (( $(rollback_deletes "$F") == n_entries + 1 )); then
  pass "fresh Mac: one rollback line per import, each deleting a domain mrk created"
else
  fail "fresh Mac: $(rollback_deletes "$F") rollback deletes for $((n_entries + 1)) imports${no_line:+; none for ${no_line#, }}"
fi

# ── 2. The same Mac again: nothing is imported twice ─────────────────────────

/usr/bin/defaults write "$F/domains/com.rogueamoeba.Loopback" mrkTestSaved -string changed-by-use
cp -p "$F/home/.mrk/defaults-rollback.sh" "$W/rollback.after-first"
run_pi "$F"
if [[ "$(get "$F" com.rogueamoeba.Loopback mrkTestSaved)" == changed-by-use ]] \
   && cmp -s "$F/home/.mrk/defaults-rollback.sh" "$W/rollback.after-first" \
   && (( $(grep -c "exists — skipping import" "$F/out") == n_entries )); then
  pass "second run: all $n_entries skipped, a changed setting kept, no rollback line added"
else
  fail "second run imported again: $(grep -c "exists — skipping import" "$F/out") of $n_entries skipped"
  show_out "$F"
fi

# ── 3. A Mac where every app is already configured ───────────────────────────

# Each domain exists only as `defaults` reports it, never as
# ~/Library/Preferences/<id>.plist, which is how a sandboxed app such as Keka
# keeps it. A gate that tested for the file would import over all of them.
C="$W/configured"
machine "$C"; apps all
while IFS=$'\t' read -r _ id _; do
  /usr/bin/defaults write "$C/domains/$id" liveKey -string configured
done < "$ENTRIES"
/usr/bin/defaults write "$C/domains/$OWN_ID" liveKey -string configured
run_pi "$C"

overwritten=""
while IFS=$'\t' read -r _ id _ name; do
  if [[ -n "$(get "$C" "$id" mrkTestSaved)" || "$(get "$C" "$id" liveKey)" != configured ]]; then
    overwritten="$overwritten, $name"
  fi
done < "$ENTRIES"
[[ -n "$(get "$C" "$OWN_ID" mrkTestSaved)" ]] && overwritten="$overwritten, my own app"
if [[ -z "$overwritten" ]] && (( $(rollback_deletes "$C") == 0 )) \
   && [[ ! -d "$C/home/Library/Preferences" ]]; then
  pass "configured Mac: none of $n_entries imported over, my own app's neither, no rollback line"
else
  fail "configured Mac: imported over: ${overwritten#, } ($(rollback_deletes "$C") rollback deletes)"
fi

# ── 4. The six installed after the first run ─────────────────────────────────

L="$W/later"
machine "$L"; apps none-of-w2
run_pi "$L"
touched=""
while IFS= read -r id; do
  exists "$L" "$id" && touched="$touched, $id"
done <<<"$W2_IDS"
if [[ -z "$touched" ]]; then
  pass "apps not installed yet: their six domains are left empty, not given mrk's keys"
else
  fail "apps not installed yet, and their domains were written: ${touched#, }"
fi

apps all
run_pi "$L"
not_imported=""
while IFS=$'\t' read -r id key _ want; do
  if [[ "$(get "$L" "$id" mrkTestSaved)" != "$id" || "$(get "$L" "$id" "$key")" != "$want" ]]; then
    not_imported="$not_imported, $id"
  fi
done < "$W2_CHECKS"
if [[ -z "$not_imported" ]]; then
  pass "installed later, post-install again: all six imported, mrk's keys over them"
else
  fail "installed later, post-install again: not imported: ${not_imported#, }"; show_out "$L"
fi

# ── 5. Right after Phase 2: Homebrew installed, and not on PATH ──────────────

# Machines 1 to 4 had no Homebrew: MRK_BREW named nothing. This one has a brew
# whose shellenv puts its bin on PATH, and stubs of topgrade, pyenv,
# pinentry-mac and gpgconf beside it. PATH is the same as before.
HB="$W/homebrew/bin"
mkdir -p "$HB"
cat > "$HB/brew" <<'EOF'
#!/bin/bash
printf 'brew %s\n' "$*" >> "$CALLS"
[[ "${1:-}" == shellenv ]] || exit 1
bin="$(cd "$(dirname "$0")" && pwd)"
printf 'export HOMEBREW_PREFIX=%q; export PATH=%q:"$PATH";\n' "${bin%/bin}" "$bin"
EOF
# pyenv keeps the versions it has "installed" in the machine's HOME
cat > "$HB/pyenv" <<'EOF'
#!/bin/bash
printf 'pyenv %s\n' "$*" >> "$CALLS"
case "${1:-}" in
  versions) cat "$HOME/.pyenv-stub" 2>/dev/null ;;
  install)  printf '%s\n' "${!#}" >> "$HOME/.pyenv-stub" ;;
esac
exit 0
EOF
for tool in topgrade pinentry-mac gpgconf; do
  cat > "$HB/$tool" <<EOF
#!/bin/bash
printf '%s %s\n' $tool "\$*" >> "\$CALLS"
EOF
done
chmod +x "$HB"/*

P2="$W/after-phase-2"
machine "$P2"; apps all
if run_pi "$P2"; then
  pass "after Phase 2, Homebrew not on PATH: post-install exits 0"
else
  fail "after Phase 2, Homebrew not on PATH: post-install exited non-zero"; show_out "$P2"
fi
want_py=$(tr -d '[:space:]' < "$R/.python-version")
skipped=$(grep -oE '(topgrade|pyenv|pinentry-mac) not installed' "$P2/out" | tr '\n' ' ')
if [[ "$(readlink "$P2/home/.config/topgrade.toml")" == "$R/assets/topgrade.toml" ]] \
   && grep -qxF "pinentry-program $HB/pinentry-mac" "$P2/home/.gnupg/gpg-agent.conf" 2>/dev/null \
   && grep -qxF "pyenv install -s $want_py" "$P2/calls.log" \
   && [[ -z "$skipped" ]]; then
  pass "after Phase 2: topgrade's config linked, pinentry-mac configured, Python $want_py installed"
else
  fail "after Phase 2: ${skipped:+logged as not installed: $skipped}"
  grep -E 'topgrade|pyenv|pinentry' "$P2/out" | sed 's/^/      /' >&2
fi
if (( $(grep -c '^brew shellenv$' "$P2/calls.log") == 1 )); then
  pass "after Phase 2: brew shellenv run once"
else
  fail "after Phase 2: brew shellenv run $(grep -c '^brew shellenv$' "$P2/calls.log") times"
fi

# ── Nothing escaped the stubs ────────────────────────────────────────────────

# The log, not the output: the import gate sends defaults' stderr to /dev/null.
if grep -q '^REFUSED' "$W"/*/defaults.log; then
  fail "the defaults stub refused a call: $(grep -h '^REFUSED' "$W"/*/defaults.log | head -3)"
elif [[ ! -s "$F/defaults.log" ]]; then
  fail "the defaults stub saw no call, so something else answered for defaults"
else
  pass "every defaults call went to the scratch store ($(cat "$W"/*/defaults.log | wc -l | tr -d ' ') calls)"
fi

(( fails == 0 ))
