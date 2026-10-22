#!/usr/bin/env bash
# check-defaults-desc.sh — prove that check-defaults-desc holds
# docs/defaults/descriptions.tsv to config/defaults.tsv, and refuses a line of
# it that is not one description.
#
# MRK-1 reads both files when it loads, and other programs read the
# descriptions too, so a line in the wrong shape is a fault even where the page
# would pass over it. Each case runs check-defaults-desc on a copy of the two
# files, under macOS's bash 3.2 as well as the bash running this file. It
# changes nothing in the repository. ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

W="$(mktemp -d "${TMPDIR:-/tmp}/check-defaults-desc.XXXXXX")"
trap 'rm -rf "$W"' EXIT

DESC="$REPO_ROOT/docs/defaults/descriptions.tsv"
TAB=$'\t'

# mkcopy NAME — a copy of what check-defaults-desc reads, in $W/NAME
mkcopy() {
  local d="$W/$1"
  mkdir -p "$d/scripts" "$d/config" "$d/docs/defaults"
  cp -p "$REPO_ROOT/scripts/check-defaults-desc" "$REPO_ROOT/scripts/lib.sh" "$d/scripts/"
  cp -p "$REPO_ROOT/config/defaults.tsv" "$d/config/"
  cp -p "$DESC" "$d/docs/defaults/"
}

# check NAME BASH — run the copy's check-defaults-desc under BASH. stdout and
# stderr in $OUT, the exit status in RC.
check() {
  OUT=$("$2" "$W/$1/scripts/check-defaults-desc" 2>&1)
  RC=$?
}

BASHES=(/bin/bash)
[[ "$BASH" -ef /bin/bash ]] || BASHES+=("$BASH")

# The number of settings: the lines of config/defaults.tsv, less those whose
# section, key, type and value repeat an earlier line's.
defaults_table "$REPO_ROOT/config/defaults.tsv" || { fail "config/defaults.tsv does not parse"; exit 1; }
settings=$'\n' n_settings=0
for i in "${!DT_DOMAIN[@]}"; do
  s="${DT_SECTION[i]}$TAB${DT_KEY[i]}$TAB${DT_TYPE[i]}$TAB${DT_VALUE[i]}"
  case "$settings" in *$'\n'"$s"$'\n'*) continue ;; esac
  settings+="$s"$'\n'; n_settings=$((n_settings + 1))
done

# A mirrored setting: the first line whose section, key, type and value repeat
# an earlier line's. Its domain needs no description.
mirror=""
seen=$'\n'
for i in "${!DT_DOMAIN[@]}"; do
  s="${DT_SECTION[i]}$TAB${DT_KEY[i]}$TAB${DT_TYPE[i]}$TAB${DT_VALUE[i]}"
  case "$seen" in *$'\n'"$s"$'\n'*) mirror="${DT_DOMAIN[i]}$TAB${DT_KEY[i]}"; break ;; esac
  seen+="$s"$'\n'
done
[[ -n "$mirror" ]] || { fail "config/defaults.tsv has no mirrored setting to test with"; exit 1; }

first=$(grep -v '^#' "$DESC" | grep -v '^[[:space:]]*$' | head -1)
first_id="${first%%"$TAB"*} $(cut -f2 <<<"$first")"

# ── The page reads the file, and holds no copy ───────────────────────────────

if grep -qF "docs/defaults/descriptions.tsv" "$REPO_ROOT/docs/defaults/script.js" \
   && ! grep -qE 'DEFAULT_DESCRIPTIONS|systemDefault:[[:space:]]*'"'" "$REPO_ROOT/docs/defaults/script.js"; then
  pass "MRK-1 reads docs/defaults/descriptions.tsv and holds no description of its own"
else
  fail "docs/defaults/script.js does not read descriptions.tsv, or holds descriptions of its own"
fi

for B in "${BASHES[@]}"; do
  # shellcheck disable=SC2016  # expanded by the inner bash, not this one
  v=$("$B" -c 'echo "${BASH_VERSION%%(*}"')
  printf '  under bash %s\n' "$v"

  # ── The repository's own files ─────────────────────────────────────────────

  mkcopy "real-$v"
  check "real-$v" "$B"
  if (( RC == 0 )) && [[ "$OUT" == *"OK ($n_settings keys"* ]]; then
    pass "the repository's files: OK, $n_settings keys"
  else
    fail "the repository's files (exit $RC, want 0 and $n_settings keys): $OUT"
  fi

  # ── A key with no description, and a description with no key ───────────────

  mkcopy "missing-$v"
  grep -vxF "$first" "$DESC" > "$W/missing-$v/docs/defaults/descriptions.tsv"
  check "missing-$v" "$B"
  if (( RC == 1 )) && [[ "$OUT" == *"with no line in docs/defaults/descriptions.tsv (1)"* && "$OUT" == *"  $first_id"* ]]; then
    pass "a key with no line: named, exit 1"
  else
    fail "a key with no line (exit $RC, want 1, naming $first_id): $OUT"
  fi

  mkcopy "orphan-$v"
  printf 'com.example.gone\tGoneKey\tGone\tSecurity\t\tfalse\tDoes nothing now.\t\t\n' \
    >> "$W/orphan-$v/docs/defaults/descriptions.tsv"
  check "orphan-$v" "$B"
  if (( RC == 1 )) && [[ "$OUT" == *"not in config/defaults.tsv (1)"* && "$OUT" == *"  com.example.gone GoneKey"* ]]; then
    pass "a line with no key: named, exit 1"
  else
    fail "a line with no key (exit $RC, want 1, naming com.example.gone GoneKey): $OUT"
  fi

  # The second domain of a mirrored setting shares the first one's line. A
  # line of its own is a line with no key.
  mkcopy "mirror-$v"
  printf '%s\tTwin\tInput\t\tfalse\tThe same setting again.\t\t\n' "$mirror" \
    >> "$W/mirror-$v/docs/defaults/descriptions.tsv"
  check "mirror-$v" "$B"
  if (( RC == 1 )) && [[ "$OUT" == *"not in config/defaults.tsv (1)"* && "$OUT" == *"  ${mirror/$TAB/ }"* ]]; then
    pass "the second domain of a mirrored setting wants no line of its own"
  else
    fail "a line for a mirrored setting's second domain (${mirror/$TAB/ }; exit $RC, want 1): $OUT"
  fi

  # ── Lines that are not one description ─────────────────────────────────────

  # refused NAME WHY LINE — LINE in place of the first description: exit 1,
  # with the reason WHY, and the keys are not compared.
  refused() {
    local name=$1 why=$2 line=$3
    mkcopy "$name-$v"
    { grep -vxF "$first" "$DESC"; printf '%s\n' "$line"; } > "$W/$name-$v/docs/defaults/descriptions.tsv"
    check "$name-$v" "$B"
    if (( RC == 1 )) && [[ "$OUT" == *"Not one description"*"$why"* && "$OUT" != *"not in config/defaults.tsv"* ]]; then
      pass "refused: $name"
    else
      fail "$name (exit $RC, want 1 with \"$why\"): $OUT"
    fi
  }
  d=${first%%"$TAB"*}
  k=$(cut -f2 <<<"$first")
  refused "eight fields" "nine fields" "$d$TAB$k${TAB}Title${TAB}Security$TAB${TAB}false${TAB}Text.$TAB"
  refused "ten fields" "nine fields" "$first$TAB"
  refused "an empty title" "the title is empty" "$d$TAB$k$TAB${TAB}Security$TAB${TAB}false${TAB}Text.$TAB$TAB"
  refused "a blank description" "the description is empty" "$d$TAB$k${TAB}Title${TAB}Security$TAB${TAB}false$TAB   $TAB$TAB"
  refused "preference yes" "preference is not true or false" "$d$TAB$k${TAB}Title${TAB}Security$TAB${TAB}yes${TAB}Text.$TAB$TAB"
  refused "a bad escape" "a backslash is not one of" "$d$TAB$k${TAB}Title${TAB}Security$TAB${TAB}false${TAB}C:\\qtemp$TAB$TAB"
  refused "a domain with a space" "the domain is not" "com.example bad$TAB$k${TAB}Title${TAB}Security$TAB${TAB}false${TAB}Text.$TAB$TAB"
  refused "a newline in the title" "the title is empty, or holds a tab or a newline" "$d$TAB$k${TAB}Two\\nlines${TAB}Security$TAB${TAB}false${TAB}Text.$TAB$TAB"

  mkcopy "twice-$v"
  printf '%s\n' "$first" >> "$W/twice-$v/docs/defaults/descriptions.tsv"
  check "twice-$v" "$B"
  if (( RC == 1 )) && [[ "$OUT" == *"has $first_id on two lines"* ]]; then
    pass "refused: a domain and key on two lines"
  else
    fail "a domain and key on two lines (exit $RC, want 1): $OUT"
  fi

  # The escapes the file allows, in the prose fields.
  mkcopy "escapes-$v"
  { grep -vxF "$first" "$DESC"
    printf '%s\t%s\tTitle\tSecurity\t\ttrue\tOne line.\\nAnother.\tA tab\\there, a backslash \\\\.\t\n' "$d" "$k"
  } > "$W/escapes-$v/docs/defaults/descriptions.tsv"
  check "escapes-$v" "$B"
  if (( RC == 0 )); then
    pass "\\n, \\t and \\\\ in a prose field are taken"
  else
    fail "escapes in a prose field (exit $RC, want 0): $OUT"
  fi

  mkcopy "absent-$v"
  rm "$W/absent-$v/docs/defaults/descriptions.tsv"
  check "absent-$v" "$B"
  if (( RC == 1 )) && [[ "$OUT" == *"Cannot read"* ]]; then
    pass "no descriptions.tsv: exit 1"
  else
    fail "no descriptions.tsv (exit $RC, want 1): $OUT"
  fi
done

if (( fails )); then
  err "check-defaults-desc.sh: $fails failed"
  exit 1
fi
ok "check-defaults-desc.sh: all passed"
