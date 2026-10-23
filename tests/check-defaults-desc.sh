#!/usr/bin/env bash
# check-defaults-desc.sh — prove that check-defaults-desc holds
# docs/defaults/descriptions.tsv and docs/defaults/sections.tsv to
# config/defaults.tsv, and refuses a line of either that is not one
# description or one section. It refuses a line of config/defaults-skip.tsv
# that defaults.sh refuses, too.
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
SECT="$REPO_ROOT/docs/defaults/sections.tsv"
TAB=$'\t'

# mkcopy NAME — a copy of what check-defaults-desc reads, in $W/NAME
mkcopy() {
  local d="$W/$1"
  mkdir -p "$d/scripts" "$d/config" "$d/docs/defaults"
  cp -p "$REPO_ROOT/scripts/check-defaults-desc" "$REPO_ROOT/scripts/lib.sh" "$d/scripts/"
  cp -p "$REPO_ROOT/config/defaults.tsv" "$REPO_ROOT/config/defaults-skip.tsv" "$d/config/"
  cp -p "$DESC" "$SECT" "$d/docs/defaults/"
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

# The sections: their number, and the first line of sections.tsv.
n_sections=0 sections_seen=$'\n'
for s in "${DT_SECTION[@]}"; do
  case "$sections_seen" in *$'\n'"$s"$'\n'*) continue ;; esac
  sections_seen+="$s"$'\n'; n_sections=$((n_sections + 1))
done
first_sect=$(grep -v '^#' "$SECT" | grep -v '^[[:space:]]*$' | head -1)
first_sect_name=${first_sect%%"$TAB"*}

# ── The page reads the files, and holds no copy ──────────────────────────────

if grep -qF "docs/defaults/descriptions.tsv" "$REPO_ROOT/docs/defaults/script.js" \
   && ! grep -qE 'DEFAULT_DESCRIPTIONS|systemDefault:[[:space:]]*'"'" "$REPO_ROOT/docs/defaults/script.js"; then
  pass "MRK-1 reads docs/defaults/descriptions.tsv and holds no description of its own"
else
  fail "docs/defaults/script.js does not read descriptions.tsv, or holds descriptions of its own"
fi

# The section text was an object of 'name': 'text' pairs in script.js. No
# section name of config/defaults.tsv may be a quoted key there now.
held=""
while IFS= read -r s; do
  [[ -n "$s" ]] || continue
  grep -qF "'$s':" "$REPO_ROOT/docs/defaults/script.js" && held="$held '$s'"
done <<<"$sections_seen"
if grep -qF "docs/defaults/sections.tsv" "$REPO_ROOT/docs/defaults/script.js" && [[ -z "$held" ]]; then
  pass "MRK-1 reads docs/defaults/sections.tsv and holds no section text of its own"
else
  fail "docs/defaults/script.js does not read sections.tsv, or holds section text of its own:${held:- (none held)}"
fi

for B in "${BASHES[@]}"; do
  # shellcheck disable=SC2016  # expanded by the inner bash, not this one
  v=$("$B" -c 'echo "${BASH_VERSION%%(*}"')
  printf '  under bash %s\n' "$v"

  # ── The repository's own files ─────────────────────────────────────────────

  mkcopy "real-$v"
  check "real-$v" "$B"
  if (( RC == 0 )) && [[ "$OUT" == *"OK ($n_settings keys, $n_sections sections"* ]]; then
    pass "the repository's files: OK, $n_settings keys and $n_sections sections"
  else
    fail "the repository's files (exit $RC, want 0, $n_settings keys and $n_sections sections): $OUT"
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

  # ── The sections ───────────────────────────────────────────────────────────

  mkcopy "sect-missing-$v"
  grep -vxF "$first_sect" "$SECT" > "$W/sect-missing-$v/docs/defaults/sections.tsv"
  check "sect-missing-$v" "$B"
  if (( RC == 1 )) && [[ "$OUT" == *"with no line in docs/defaults/sections.tsv (1)"* && "$OUT" == *"  $first_sect_name"* ]]; then
    pass "a section with no line: named, exit 1"
  else
    fail "a section with no line (exit $RC, want 1, naming $first_sect_name): $OUT"
  fi

  mkcopy "sect-orphan-$v"
  printf 'Finish up\tRestarts the processes.\n' >> "$W/sect-orphan-$v/docs/defaults/sections.tsv"
  check "sect-orphan-$v" "$B"
  if (( RC == 1 )) && [[ "$OUT" == *"not a section of config/defaults.tsv (1)"* && "$OUT" == *"  Finish up"* ]]; then
    pass "a line with no section: named, exit 1"
  else
    fail "a line with no section (exit $RC, want 1, naming Finish up): $OUT"
  fi

  # The trackpad section is "Trackpad" in config/defaults.tsv. MRK-1 shows it
  # with "(opt-in: --with-trackpad)" after the name, and a line under that
  # name is a line with no section.
  mkcopy "sect-shown-$v"
  { grep -v "^Trackpad$TAB" "$SECT"; printf 'Trackpad (opt-in: --with-trackpad)\tGestures.\n'; } \
    > "$W/sect-shown-$v/docs/defaults/sections.tsv"
  check "sect-shown-$v" "$B"
  if (( RC == 1 )) && [[ "$OUT" == *"sections.tsv (1):"*"  Trackpad"* && "$OUT" == *"  Trackpad (opt-in: --with-trackpad)"* ]]; then
    pass "the trackpad section goes under its name in config/defaults.tsv, not the name MRK-1 shows"
  else
    fail "the trackpad section under the name MRK-1 shows (exit $RC, want 1): $OUT"
  fi

  # sect_refused NAME WHY LINE — LINE in place of the first section: exit 1,
  # with the reason WHY, and the sections are not compared.
  sect_refused() {
    local name=$1 why=$2 line=$3
    mkcopy "sect-$name-$v"
    { grep -vxF "$first_sect" "$SECT"; printf '%s\n' "$line"; } > "$W/sect-$name-$v/docs/defaults/sections.tsv"
    check "sect-$name-$v" "$B"
    if (( RC == 1 )) && [[ "$OUT" == *"Not one section"*"$why"* && "$OUT" != *"not a section of config/defaults.tsv"* ]]; then
      pass "refused, a section: $name"
    else
      fail "a section: $name (exit $RC, want 1 with \"$why\"): $OUT"
    fi
  }
  sect_refused "one field" "two fields" "$first_sect_name"
  sect_refused "three fields" "two fields" "$first_sect$TAB"
  sect_refused "a blank description" "the description is empty" "$first_sect_name$TAB   "
  sect_refused "an empty section" "the section is empty" "${TAB}Text."
  sect_refused "a newline in the section" "the section is empty, or holds a tab or a newline" "Two\\nlines${TAB}Text."
  sect_refused "a bad escape" "a backslash is not one of" "$first_sect_name${TAB}C:\\qtemp"

  mkcopy "sect-twice-$v"
  printf '%s\n' "$first_sect" >> "$W/sect-twice-$v/docs/defaults/sections.tsv"
  check "sect-twice-$v" "$B"
  if (( RC == 1 )) && [[ "$OUT" == *"has $first_sect_name on two lines"* ]]; then
    pass "refused: a section on two lines"
  else
    fail "a section on two lines (exit $RC, want 1): $OUT"
  fi

  # ── The keys to skip ───────────────────────────────────────────────────────

  # skip_case NAME WANT TEXT LINE... — the lines in config/defaults-skip.tsv:
  # exit WANT, and TEXT in what it says
  skip_case() {
    local name=$1 want=$2 text=$3; shift 3
    mkcopy "skip-$name-$v"
    printf '%s\n' "$@" >> "$W/skip-$name-$v/config/defaults-skip.tsv"
    check "skip-$name-$v" "$B"
    if (( RC == want )) && [[ "$OUT" == *"$text"* ]]; then
      pass "config/defaults-skip.tsv, $name: exit $want"
    else
      fail "config/defaults-skip.tsv, $name (exit $RC, want $want with \"$text\"): $OUT"
    fi
  }
  skip_case "two keys of the table" 0 "OK ($n_settings keys" \
    "com.apple.dock${TAB}tilesize" "NSGlobalDomain${TAB}AppleShowAllExtensions"
  skip_case "a key not in the table" 1 "skips com.example.gone GoneKey, which is not a key of config/defaults.tsv" \
    "com.example.gone${TAB}GoneKey"
  skip_case "one field" 1 "it does not have two fields" "com.apple.dock tilesize"
  skip_case "three fields" 1 "it does not have two fields" "com.apple.dock${TAB}tilesize${TAB}36"
  skip_case "a key on two lines" 1 "has com.apple.dock tilesize on two lines" \
    "com.apple.dock${TAB}tilesize" "com.apple.dock${TAB}tilesize"

  mkcopy "sect-absent-$v"
  rm "$W/sect-absent-$v/docs/defaults/sections.tsv"
  check "sect-absent-$v" "$B"
  if (( RC == 1 )) && [[ "$OUT" == *"Cannot read"*"sections.tsv"* ]]; then
    pass "no sections.tsv: exit 1"
  else
    fail "no sections.tsv (exit $RC, want 1): $OUT"
  fi
done

if (( fails )); then
  err "check-defaults-desc.sh: $fails failed"
  exit 1
fi
ok "check-defaults-desc.sh: all passed"
