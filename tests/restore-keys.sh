#!/usr/bin/env bash
# restore-keys.sh — prove that scripts/restore-keys leaves ~/.gnupg holding
# exactly what the archive holds.
#
# On 2026-09-15 restore-keys moved ~/.gnupg aside and then ran gpg to decrypt
# the archive. gpg found no home directory and created one, and GnuPG 2.4.1 and
# later write `use-keyboxd` into the common.conf of a home directory they
# create. tar then extracted the archive into it. Homebrew's gpg read its keys
# from keyboxd from then on, and never from the pubring.kbx the archive had
# restored; GPG Suite's gpg 2.2 read nothing else. The Mac had two keyrings, and
# they drifted. restore-keys now runs gpg against a scratch home directory.
#
# Everything here happens under throwaway HOMEs in $TMPDIR, kept short because
# gpg-agent puts its sockets in the home directory and a socket path is limited
# to 104 bytes. A real gpg builds the keyring and the archive; a gpg first on
# PATH supplies the passphrase. The real ~/.gnupg and its agent are not touched.
#
# It also has snapshot-keys build an archive holding project credentials, and
# proves restore-keys puts those only into a checkout that exists: on a new
# machine it runs before restore-repos, and a file written into
# ~/Projects/DoublEnder first would stop restore-repos from cloning it.
#
# Runs restore-keys under /bin/bash as well as the bash running it. ci-check
# runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

SCRIPT="$REPO_ROOT/scripts/restore-keys"
# Made up per run, so the secret scan has no literal to flag.
PASSPHRASE="test-$$-$RANDOM"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

REAL_GPG="$(command -v gpg || true)"
if [[ -z "$REAL_GPG" ]]; then
  fail "gpg not found — install it with: brew install gnupg"
  exit 1
fi

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rkt.XXXXXX")"
ROOT="${ROOT//\/\//\/}"
cleanup() {
  local h
  for h in "$ROOT"/*/.gnupg "$ROOT"/enc; do
    [[ -d "$h" ]] && gpgconf --homedir "$h" --kill all >/dev/null 2>&1
  done
  rm -rf "$ROOT"
}
trap cleanup EXIT

# ── The old machine: a pubring.kbx keyring with no common.conf ─────────────────

SRC="$ROOT/src"
mkdir -m 700 "$SRC" "$SRC/.ssh" "$SRC/.gnupg"
printf 'not-a-real-key\n' > "$SRC/.ssh/id_test"
"$REAL_GPG" --homedir "$SRC/.gnupg" --batch --pinentry-mode loopback --passphrase '' \
  --quick-gen-key 'Restore Test <restore@test.invalid>' ed25519 sign never >/dev/null 2>&1
FPR=$("$REAL_GPG" --homedir "$SRC/.gnupg" --list-keys --with-colons 2>/dev/null \
  | awk -F: '$1 == "fpr" { print $10; exit }')
gpgconf --homedir "$SRC/.gnupg" --kill all >/dev/null 2>&1
if [[ -z "$FPR" || ! -f "$SRC/.gnupg/pubring.kbx" || -e "$SRC/.gnupg/common.conf" ]]; then
  fail "could not build a pubring.kbx keyring to archive"
  exit 1
fi

# The same pipeline snapshot-keys uses, with the passphrase given up front.
ARCHIVE="$ROOT/mrk-keys-test.asc"
mkdir -m 700 "$ROOT/enc"
tar -czf - -C "$SRC" --exclude='.gnupg/S.*' .ssh .gnupg 2>/dev/null \
  | "$REAL_GPG" --homedir "$ROOT/enc" --batch --pinentry-mode loopback \
      --passphrase "$PASSPHRASE" --symmetric --cipher-algo AES256 --armor -o "$ARCHIVE" 2>/dev/null
if [[ ! -s "$ARCHIVE" ]]; then
  fail "could not build the test archive"
  exit 1
fi

# A gpg first on PATH that answers the passphrase. Later options win, so the
# --pinentry-mode error that restore-keys passes to --list-packets still holds.
stub_dir() {
  local d="$ROOT/stub-$1"
  if [[ ! -x "$d/gpg" ]]; then
    mkdir -p "$d"
    printf '#!/bin/bash\nexec %q --batch --pinentry-mode loopback --passphrase %q "$@"\n' \
      "$REAL_GPG" "$1" > "$d/gpg"
    chmod +x "$d/gpg"
  fi
  printf '%s' "$d"
}

# scratch_dirs — the mrk.* directories in $TMPDIR, where mrk_mktemp_d puts them.
scratch_dirs() { find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'mrk.*' 2>/dev/null | sort; }

# restore BASH HOME PASSPHRASE ARGS... — run restore-keys in that HOME. Leaves
# the scratch directories it did not clean up in LEFTOVER.
LEFTOVER=""
restore() {
  local sh="$1" home="$2" pw="$3" before rc
  shift 3
  before=$(scratch_dirs)
  HOME="$home" GNUPGHOME="" PATH="$(stub_dir "$pw"):$PATH" \
    "$sh" "$SCRIPT" "$@" >"$home.log" 2>&1
  rc=$?
  LEFTOVER=$(comm -13 <(printf '%s\n' "$before") <(scratch_dirs))
  return "$rc"
}

# ── An archive from snapshot-keys, holding project credentials ─────────────────

# snapshot-keys builds this one itself, so the test covers what it bundles as
# well as how restore-keys puts it back. The contents are placeholders.
PSRC="$ROOT/psrc"
CLOUD="Projects/DoublEnder/DoublEnderCloud"
mkdir -m 700 "$PSRC" "$PSRC/.ssh"
mkdir -p "$PSRC/Projects/DoublEnder/.git" "$PSRC/$CLOUD"
printf 'not-a-real-key\n' > "$PSRC/.ssh/id_test"
printf 'placeholder json\n' > "$PSRC/$CLOUD/doublender-test.json"
printf 'placeholder env\n' > "$PSRC/$CLOUD/ingest.env"
printf 'tracked template\n' > "$PSRC/$CLOUD/ingest.env.example"
PARCHIVE="$ROOT/mrk-keys-projects.asc"
snap() {  # snap ARGS... — run snapshot-keys in PSRC
  HOME="$PSRC" GNUPGHOME="" PATH="$(stub_dir "$PASSPHRASE"):$PATH" \
    "$REPO_ROOT/scripts/snapshot-keys" --no-signing "$@"
}
if snap -n -o "$ROOT/dry-run.asc" >"$ROOT/snap-dry.log" 2>&1 && grep -q "$CLOUD/ingest.env" "$ROOT/snap-dry.log"; then
  pass "snapshot-keys -n lists the project credentials"
else
  fail "snapshot-keys -n did not list the project credentials; see $ROOT/snap-dry.log"
fi
if snap -o "$PARCHIVE" >"$ROOT/snap.log" 2>&1 && [[ -s "$PARCHIVE" ]]; then
  pass "snapshot-keys writes an archive"
else
  fail "snapshot-keys wrote no archive; see $ROOT/snap.log"
  exit 1
fi
listing=$("$REAL_GPG" --homedir "$ROOT/enc" --batch --pinentry-mode loopback --passphrase "$PASSPHRASE" \
  -d -q "$PARCHIVE" 2>/dev/null | tar -tf - 2>/dev/null)
if grep -qx "$CLOUD/doublender-test.json" <<<"$listing" && grep -qx "$CLOUD/ingest.env" <<<"$listing" \
   && grep -qx '.ssh/id_test' <<<"$listing"; then
  pass "the archive holds the keys and both project credentials, under Projects/"
else
  fail "the archive is missing a key or a project credential: $(tr '\n' ' ' <<<"$listing")"
fi
if grep -q 'ingest\.env\.example' <<<"$listing"; then
  fail "the archive holds ingest.env.example, which git already carries"
else
  pass "a tracked file beside them is left out"
fi

# placed HOME — do both project credentials sit in HOME, identical to the
# originals and mode 600?
placed() {
  local f
  for f in doublender-test.json ingest.env; do
    cmp -s "$1/$CLOUD/$f" "$PSRC/$CLOUD/$f" || return 1
    [[ -n "$(find "$1/$CLOUD/$f" -perm 600)" ]] || return 1
  done
}

# sees_key HOME — does gpg, run as it would be in that HOME, list the key?
sees_key() {
  HOME="$1" GNUPGHOME="" "$REAL_GPG" --list-keys --with-colons 2>/dev/null \
    | grep -q "^fpr:::::::::$FPR:"
}

cases() {
  local sh="$1" h rc tag
  # shellcheck disable=SC2016  # expanded by the inner bash, not this one
  tag="$(basename "$sh")-$("$sh" -c 'echo "${BASH_VERSINFO[0]}"')"

  # A ~/.gnupg already there, as GPG Suite's installer leaves one.
  h="$ROOT/$tag-existing"; mkdir -m 700 "$h" "$h/.gnupg"; : > "$h/.gnupg/pubring.kbx"
  if restore "$sh" "$h" "$PASSPHRASE" "$ARCHIVE"; then
    pass "restores over an existing ~/.gnupg"
  else
    fail "restore over an existing ~/.gnupg exited non-zero; see $h.log"
  fi
  if [[ -e "$h/.gnupg/common.conf" ]]; then
    fail ".gnupg/common.conf appeared, holding \"$(tr '\n' ' ' < "$h/.gnupg/common.conf")\": the archive has none"
  else
    pass "no common.conf the archive does not hold"
  fi
  if sees_key "$h"; then pass "gpg reads the restored keyring"; else fail "gpg does not see the restored key"; fi
  if [[ -z "$LEFTOVER" ]]; then pass "the scratch home is removed"; else fail "scratch home left behind: $LEFTOVER"; fi

  # No ~/.gnupg at all, as on a Mac with neither gnupg nor GPG Suite run yet.
  h="$ROOT/$tag-fresh"; mkdir -m 700 "$h"
  if restore "$sh" "$h" "$PASSPHRASE" "$ARCHIVE"; then
    pass "restores with no ~/.gnupg"
  else
    fail "restore with no ~/.gnupg exited non-zero; see $h.log"
  fi
  if [[ -e "$h/.gnupg/common.conf" ]]; then
    fail "with no ~/.gnupg to start, common.conf appeared anyway"
  else
    pass "with no ~/.gnupg to start, still no common.conf"
  fi
  if sees_key "$h"; then pass "gpg reads it there too"; else fail "gpg does not see the key there"; fi
  if compgen -G "$h/.gnupg.before-restore-*" >/dev/null; then
    fail "an archive check made a ~/.gnupg, which the restore then moved aside"
  else
    pass "no ~/.gnupg made by the checks, and none moved aside"
  fi

  # The wrong passphrase: the originals come back, and nothing is left over.
  h="$ROOT/$tag-wrong"; mkdir -m 700 "$h" "$h/.gnupg" "$h/.ssh"
  echo kept > "$h/.gnupg/marker"; echo kept > "$h/.ssh/marker"
  restore "$sh" "$h" "not-the-passphrase" "$ARCHIVE"; rc=$?
  if (( rc != 0 )); then pass "the wrong passphrase exits $rc"; else fail "the wrong passphrase exited 0"; fi
  if [[ -f "$h/.gnupg/marker" && -f "$h/.ssh/marker" ]]; then
    pass "the originals are put back"
  else
    fail "the original ~/.gnupg or ~/.ssh was not put back"
  fi
  if [[ -z "$LEFTOVER" ]]; then pass "the scratch home is removed after a failure"; else fail "scratch home left behind after a failure: $LEFTOVER"; fi

  # -l lists, restores nothing, and makes nothing.
  h="$ROOT/$tag-list"; mkdir -m 700 "$h"
  if restore "$sh" "$h" "$PASSPHRASE" -l "$ARCHIVE" && grep -q '\.gnupg/pubring\.kbx' "$h.log"; then
    pass "-l lists the archive"
  else
    fail "-l did not list the archive; see $h.log"
  fi
  if [[ -e "$h/.gnupg" || -e "$h/.ssh" ]]; then
    fail "-l created a ~/.gnupg or ~/.ssh"
  else
    pass "-l writes nothing to HOME"
  fi
  if [[ -z "$LEFTOVER" ]]; then pass "the scratch home is removed after -l"; else fail "scratch home left behind after -l: $LEFTOVER"; fi
}

project_cases() {
  local sh="$1" h rc tag
  # shellcheck disable=SC2016  # expanded by the inner bash, not this one
  tag="$(basename "$sh")-$("$sh" -c 'echo "${BASH_VERSINFO[0]}"')"

  # A new machine: the keys come back, and ~/Projects is left to restore-repos.
  h="$ROOT/$tag-pnew"; mkdir -m 700 "$h"
  if restore "$sh" "$h" "$PASSPHRASE" "$PARCHIVE" && [[ -f "$h/.ssh/id_test" ]]; then
    pass "restores the keys from an archive holding project credentials"
  else
    fail "the restore exited non-zero or left out ~/.ssh; see $h.log"
  fi
  if [[ -e "$h/Projects" ]]; then
    fail "a restore before restore-repos wrote into ~/Projects"
  else
    pass "nothing is written into ~/Projects before the project is cloned"
  fi
  if grep -q 'restore-keys --projects' "$h.log"; then
    pass "it says which credentials wait, and how to restore them"
  else
    fail "it did not say the project credentials are still to come; see $h.log"
  fi
  if [[ -z "$LEFTOVER" ]]; then pass "the scratch home is removed"; else fail "scratch home left behind: $LEFTOVER"; fi

  # --projects before the clone: nothing written, and a non-zero exit.
  restore "$sh" "$h" "$PASSPHRASE" --projects "$PARCHIVE"; rc=$?
  if (( rc != 0 )) && [[ ! -e "$h/Projects" ]]; then
    pass "--projects with the project not cloned exits $rc and writes nothing"
  else
    fail "--projects with the project not cloned exited $rc or wrote into ~/Projects"
  fi

  # After restore-repos: --projects puts them in place.
  mkdir -p "$h/Projects/DoublEnder/.git"
  if restore "$sh" "$h" "$PASSPHRASE" --projects "$PARCHIVE" && placed "$h"; then
    pass "--projects puts both credentials into the cloned project, mode 600"
  else
    fail "--projects did not place both credentials, identical and 600; see $h.log"
  fi

  # A different file already there is kept aside; an identical one is not.
  printf 'edited since\n' > "$h/$CLOUD/ingest.env"
  if restore "$sh" "$h" "$PASSPHRASE" --projects "$PARCHIVE" && placed "$h"; then
    pass "--projects restores over an existing credential"
  else
    fail "--projects over an existing credential failed; see $h.log"
  fi
  if grep -qx 'edited since' "$h/$CLOUD"/ingest.env.before-restore-* 2>/dev/null; then
    pass "the different one is kept, timestamped"
  else
    fail "the edited ingest.env was not kept aside"
  fi
  if compgen -G "$h/$CLOUD/doublender-test.json.before-restore-*" >/dev/null; then
    fail "an identical credential was kept aside as well"
  else
    pass "an identical one leaves no copy behind"
  fi

  # The wrong passphrase: the credentials already there are untouched.
  printf 'edited again\n' > "$h/$CLOUD/ingest.env"
  restore "$sh" "$h" "not-the-passphrase" --projects "$PARCHIVE"; rc=$?
  if (( rc != 0 )) && grep -qx 'edited again' "$h/$CLOUD/ingest.env"; then
    pass "--projects with the wrong passphrase exits $rc and changes nothing"
  else
    fail "--projects with the wrong passphrase exited $rc or changed ingest.env"
  fi

  # A full restore onto a machine where the project is already cloned places
  # them in the same run.
  h="$ROOT/$tag-pcloned"; mkdir -m 700 "$h"; mkdir -p "$h/Projects/DoublEnder/.git"
  if restore "$sh" "$h" "$PASSPHRASE" "$PARCHIVE" && placed "$h"; then
    pass "a full restore places them when the project is already cloned"
  else
    fail "a full restore with the project cloned did not place them; see $h.log"
  fi

  # An archive from before project credentials: --projects has nothing to do.
  h="$ROOT/$tag-pold"; mkdir -m 700 "$h"
  if restore "$sh" "$h" "$PASSPHRASE" --projects "$ARCHIVE" && grep -q 'holds no project credentials' "$h.log"; then
    pass "--projects on an archive without them says so and exits 0"
  else
    fail "--projects on an archive without project credentials failed; see $h.log"
  fi
}

# shellcheck disable=SC2016  # expanded by the inner bash, not this one
printf '  under bash %s\n' "$(/bin/bash -c 'echo "${BASH_VERSION%%(*}"')"
cases /bin/bash
project_cases /bin/bash
if [[ ! "$BASH" -ef /bin/bash ]]; then
  # shellcheck disable=SC2016  # expanded by the inner bash, not this one
  printf '  under bash %s\n' "$("$BASH" -c 'echo "${BASH_VERSION%%(*}"')"
  cases "$BASH"
  project_cases "$BASH"
fi

(( fails == 0 ))
