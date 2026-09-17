#!/usr/bin/env bash
# report.sh — the read-only survey behind a Brewfile cleanup in mrk.
#
# Compares the Brewfile with what Homebrew has installed, runs the picker
# description gate, lists dependency pins and formulae nothing seems to use,
# and finds app paths, cache folders, bundle IDs and document counts that have
# gone stale. It changes nothing: every finding is a question for the person
# doing the cleanup, and some are for the owner of the Mac.
#
# Usage: report.sh [--descriptions] [REPO]
#   REPO            the mrk checkout (default: $MRK_ROOT, then ~/mrk)
#   --descriptions  also print each picker description beside Homebrew's

set -uo pipefail

SHOW_DESC=0
REPO=""
for arg in "$@"; do
  case "$arg" in
    --descriptions) SHOW_DESC=1 ;;
    -h|--help)      sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)             echo "report.sh: unknown option: $arg" >&2; exit 2 ;;
    *)              REPO=$arg ;;
  esac
done
REPO=${REPO:-${MRK_ROOT:-$HOME/mrk}}
PROJECTS=${PROJECTS:-$HOME/Projects}
SEVMAC=${SEVMAC:-$PROJECTS/sevmac}
BREWFILE="$REPO/Brewfile"
PICKER="$REPO/tools/picker/main.go"
GREP=/usr/bin/grep   # not a shell function or alias, whatever the caller has

[[ -f "$BREWFILE" ]] || { echo "report.sh: no Brewfile at $BREWFILE" >&2; exit 1; }
command -v brew >/dev/null 2>&1 || { echo "report.sh: brew not found" >&2; exit 1; }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/brewfile-report.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

h()    { printf '\n== %s\n' "$*"; }
list() { if [[ -s "$1" ]]; then sed 's/^/  /' "$1"; else echo "  (none)"; fi; }

sed -nE 's/^brew "([^"]+)".*/\1/p' "$BREWFILE" | sort -u > "$TMP/bf-formulae"
sed -nE 's/^cask "([^"]+)".*/\1/p' "$BREWFILE" | sort -u > "$TMP/bf-casks"
brew list --formula -1 2>/dev/null | sort -u > "$TMP/formulae"
brew list --cask -1 2>/dev/null | sort -u > "$TMP/casks"
brew leaves --installed-on-request 2>/dev/null | sort -u > "$TMP/leaves"
: > "$TMP/ignore"
if [[ -f "$HOME/.mrk/sync-ignore" ]]; then
  sed -e 's/#.*//' -e 's/[[:space:]]//g' -e '/^$/d' "$HOME/.mrk/sync-ignore" | sort -u > "$TMP/ignore"
fi

h "Repository"
echo "  $REPO, branch $(git -C "$REPO" branch --show-current 2>/dev/null || echo '?')"
changes=$(git -C "$REPO" status --porcelain 2>/dev/null)
if [[ -n "$changes" ]]; then
  echo "  uncommitted changes (find out whose before you touch them):"
  printf '%s\n' "$changes" | sed 's/^/    /'
fi
echo "  Brewfile: $(wc -l < "$TMP/bf-formulae" | tr -d ' ') formulae," \
     "$(wc -l < "$TMP/bf-casks" | tr -d ' ') casks," \
     "$($GREP -c '^tap "' "$BREWFILE") taps"
[[ -s "$TMP/ignore" ]] && echo "  ~/.mrk/sync-ignore: $(wc -l < "$TMP/ignore" | tr -d ' ') names"

h "check-picker-desc"
"$REPO/scripts/check-picker-desc" 2>&1 | sed 's/^/  /'

h "Installed, not in the Brewfile (sync would offer these)"
comm -23 "$TMP/leaves" "$TMP/bf-formulae" | comm -23 - "$TMP/ignore" | sed 's/^/formula /' > "$TMP/new"
comm -23 "$TMP/casks" "$TMP/bf-casks" | comm -23 - "$TMP/ignore" | sed 's/^/cask    /' >> "$TMP/new"
list "$TMP/new"

h "In the Brewfile, not installed (removed by hand, or a name Homebrew lists differently)"
comm -13 "$TMP/formulae" "$TMP/bf-formulae" | sed 's/^/formula /' > "$TMP/missing"
comm -13 "$TMP/casks" "$TMP/bf-casks" | sed 's/^/cask    /' >> "$TMP/missing"
list "$TMP/missing"

h "Dependency pins: tracked formulae that are not leaves installed on request"
comm -12 "$TMP/formulae" "$TMP/bf-formulae" | comm -23 - "$TMP/leaves" > "$TMP/pins"
if [[ -s "$TMP/pins" ]]; then
  while IFS= read -r f; do
    users=$(brew uses --installed "$f" 2>/dev/null | tr '\n' ' ')
    last=$(git -C "$REPO" log -S"brew \"$f\"" -1 --format='%h %ad %s' --date=short -- Brewfile 2>/dev/null)
    printf '  %s\n    used by: %s\n    last Brewfile change: %s\n' "$f" "${users:-nothing (installed as a dependency, not on request)}" "${last:-?}"
  done < "$TMP/pins"
else
  echo "  (none)"
fi

h "Tracked formulae that no code names (a hint, not a verdict)"
# Each formula is searched for by its name and by the commands it installs
# (ripgrep as rg, openssh as ssh), as whole words, in ~/Projects and in mrk's
# code. A tool you only type by hand is listed too, so this is where to start
# asking, not a list to delete. A common word (tree, watch) always matches.
comm -12 "$TMP/leaves" "$TMP/bf-formulae" > "$TMP/tracked-leaves"
prefix=$(brew --prefix 2>/dev/null)
: > "$TMP/words"
while IFS= read -r f; do
  printf '%s\t%s\n' "$f" "$f" >> "$TMP/words"
  for exe in "$prefix/opt/$f/bin/"*; do
    [[ -e "$exe" ]] && printf '%s\t%s\n' "${exe##*/}" "$f" >> "$TMP/words"
  done
done < "$TMP/tracked-leaves"
cut -f1 "$TMP/words" | sort -u > "$TMP/patterns"
if [[ -s "$TMP/patterns" ]]; then
  {
    if [[ -d "$PROJECTS" ]]; then
      $GREP -rIohwF --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=build \
        --exclude-dir=DerivedData --exclude-dir=.build --exclude-dir=Vendor \
        -f "$TMP/patterns" "$PROJECTS" 2>/dev/null
    fi
    # mrk's own code, minus the one file that names every package by design
    git -C "$REPO" ls-files -z -- bin scripts dotfiles assets tools Makefile 2>/dev/null \
      | tr '\0' '\n' | $GREP -vxF 'tools/picker/main.go' \
      | while IFS= read -r f; do printf '%s\0' "$REPO/$f"; done \
      | xargs -0 $GREP -IohwF -f "$TMP/patterns" 2>/dev/null
  } | sort -u > "$TMP/named-words"
  awk -F'\t' 'NR == FNR { named[$1] = 1; next } ($1 in named) { print $2 }' \
    "$TMP/named-words" "$TMP/words" | sort -u > "$TMP/named"
  comm -23 "$TMP/tracked-leaves" "$TMP/named" > "$TMP/unnamed"
  brew services list 2>/dev/null | awk 'NR > 1 { print $1, $2 }' > "$TMP/services"
  if [[ -s "$TMP/unnamed" ]]; then
    while IFS= read -r f; do
      svc=$(awk -v f="$f" '$1 == f { print $2 }' "$TMP/services")
      last=$(git -C "$REPO" log -S"brew \"$f\"" -1 --format='%h %ad %s' --date=short -- Brewfile 2>/dev/null)
      printf '  %-20s %s%s\n' "$f" "${last:-?}" "${svc:+  [service: $svc]}"
    done < "$TMP/unnamed"
  else
    echo "  (none)"
  fi
fi

h "/Applications paths that mrk's scripts name and this Mac does not have"
: > "$TMP/apps"
for f in scripts/post-install scripts/snapshot-prefs bin/snapshot scripts/dock-setup \
         assets/preferences/*.sh assets/browsers/*.sh; do
  [[ -f "$REPO/$f" ]] || continue
  $GREP -oE '"/Applications/[^"]+\.app"' "$REPO/$f" | tr -d '"' | sort -u | while IFS= read -r app; do
    [[ -d "$app" ]] || echo "$f: $app"
  done >> "$TMP/apps"
done
list "$TMP/apps"

h "Cache folders bin/clear-app-caches names that do not exist (app not installed, or never opened)"
: > "$TMP/caches"
if [[ -f "$REPO/bin/clear-app-caches" ]]; then
  # shellcheck disable=SC2016  # a literal $HOME in the file being read
  $GREP -oE '"\$HOME/Library/(Caches|Application Support)/[^"/]+' "$REPO/bin/clear-app-caches" \
    | sed -e 's/^"//' -e "s|^\\\$HOME|$HOME|" | sort -u | while IFS= read -r top; do
      [[ -e "$top" ]] || echo "$top"
    done > "$TMP/caches"
fi
list "$TMP/caches"

h "Bundle IDs that the app-settings scripts write, with no such app installed"
for app in /Applications/*.app /Applications/*/*.app /System/Applications/*.app; do
  [[ -f "$app/Contents/Info.plist" ]] || continue
  plutil -extract CFBundleIdentifier raw -o - "$app/Contents/Info.plist" 2>/dev/null
  echo
done | sed '/^$/d' | sort -u > "$TMP/bundle-ids"
: > "$TMP/ids"
for f in "$REPO"/assets/preferences/*.sh "$REPO"/assets/browsers/*.sh; do
  [[ -f "$f" ]] || continue
  $GREP -oE -- '-string "?(com|org|net|io|de|fr|jp|eu)\.[A-Za-z0-9._-]+"?' "$f" \
    | sed -E 's/^-string "?//; s/"$//' | sort -u | while IFS= read -r id; do
      $GREP -qxF "$id" "$TMP/bundle-ids" || echo "${f#"$REPO"/}: $id"
    done >> "$TMP/ids"
done
list "$TMP/ids"

h "App counts the docs give for snapshot-prefs and post-install"
# grep -c prints 0 and exits 1 on no match, so no `|| echo 0` here.
n=$($GREP -c '^snapshot_plist "' "$REPO/scripts/snapshot-prefs" 2>/dev/null); n=${n:-0}
m=$($GREP -c '^[[:space:]]*import_plist "' "$REPO/scripts/post-install" 2>/dev/null); m=${m:-0}
echo "  snapshot-prefs exports $n named domains; post-install imports $m"
count_re='exports [0-9]+ named plist domains|The [0-9]+ plist domains|plists for [0-9]+ named applications|exports the [0-9]+ app preference plists|Plist imports \([0-9]+ apps\)|imports preferences for [0-9]+ applications'
for doc in "$REPO/README.md" "$REPO/docs/manual.md" "$REPO/docs/bin/mrk-usage.html" "$SEVMAC/docs/index.html"; do
  [[ -f "$doc" ]] || continue
  $GREP -noE "$count_re" "$doc" | while IFS=: read -r line match; do
    num=$($GREP -oE '[0-9]+' <<< "$match" | head -1)
    [[ "$num" == "$n" ]] || echo "  $doc:$line says $num: $match"
  done
done

if (( SHOW_DESC )); then
  h "Picker descriptions beside Homebrew's"
  # shellcheck disable=SC2046  # one argument per package is the point
  brew info --json=v2 --formula $(cat "$TMP/bf-formulae") > "$TMP/f.json" 2>/dev/null || echo '{}' > "$TMP/f.json"
  # shellcheck disable=SC2046
  brew info --json=v2 --cask $(cat "$TMP/bf-casks") > "$TMP/c.json" 2>/dev/null || echo '{}' > "$TMP/c.json"
  python3 - "$TMP/f.json" "$TMP/c.json" "$PICKER" <<'PY'
import json, re, sys
hb = {}
for path, key, ident in ((sys.argv[1], 'formulae', 'name'), (sys.argv[2], 'casks', 'token')):
    try:
        data = json.load(open(path))
    except ValueError:
        data = {}
    for item in data.get(key, []):
        names = ', '.join(item.get('name') or []) if key == 'casks' else ''
        hb[item[ident]] = (item.get('desc') or '') + (f'  [{names}]' if names else '')
ours = dict(re.findall(r'^\t"([^"]+)":\s*"(.*)",$', open(sys.argv[3]).read(), re.M))
if not hb:
    print('  brew info failed; is a Brewfile name unknown to Homebrew?')
for name in sorted(set(hb) | set(ours), key=str.lower):
    print(f'  {name}\n    ours: {ours.get(name, "<none>")}\n    brew: {hb.get(name, "<not in the Brewfile>")}')
PY
fi
