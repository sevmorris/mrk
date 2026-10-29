#!/usr/bin/env bash
# mrk-contract.sh — prove that scripts/mrk-contract says what mrk's scripts
# take. Audit 22, O-2.
#
# Dipstick and Barkeep run scripts/mrk-contract once for each checkout, and
# give a script an option only when the contract lists it. Then an exit 2 means
# only that the command line is wrong. So a contract that lists an option that
# the script does not take sends a command line that fails, and one that leaves
# an option out makes an app say that this mrk is too old for it. The document
# is written by hand in the script, so this test holds it to the scripts:
# 1. it is JSON on stdout, with nothing on stderr and exit 0, from another
#    directory, through a symlink as ~/bin has it, and with a throwaway HOME
#    that it leaves empty. --help exits 0, and an unknown argument exits 2.
# 2. its shape: version 1, and every key present with its type
# 3. every script it names is an executable in scripts/, and every script in
#    scripts/ with a --check mode is in it, with that mode
# 4. each option it lists is one that the script's parser takes, with the
#    values it names: the script runs with the option, a placeholder for each
#    value, and --help after them, and shows its help. A parser stops at the
#    first argument it does not know, with exit 2, before it gets to --help.
#    The scripts run on a copy of scripts/, with stubs first on PATH for every
#    command that could change the Mac, and no stub may run.
# 5. the options it lists are the options of the script's --help, and its
#    equals options are the ones the help gives as --OPTION=VALUE
# 6. each word that a field can hold is in the script's --help
#
# The tests of the five --check scripts hold the lines that each one writes to
# the fields and words here, with tests/lib/contract-lines.
#
# Read-only, apart from the copy and the throwaway HOME. ci-check runs it.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../scripts/lib.sh
source "$REPO_ROOT/scripts/lib.sh"

fails=0
pass() { ok "$*"; }
fail() { err "$*"; fails=$((fails + 1)); }

command -v python3 >/dev/null 2>&1 || { fail "python3 not found"; exit 1; }

W=$(mrk_mktemp_d) || exit 1
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/home" "$W/tmp" "$W/bin" "$W/elsewhere"

# ── 1. The command ───────────────────────────────────────────────────────────

ln -s "$REPO_ROOT/scripts/mrk-contract" "$W/bin/mrk-contract"
(cd "$W/elsewhere" && env -i HOME="$W/home" TMPDIR="$W/tmp" PATH=/usr/bin:/bin \
  "$W/bin/mrk-contract" > "$W/contract.json" 2> "$W/contract.err")
rc=$?
if (( rc == 0 )) && [[ ! -s "$W/contract.err" ]] && [[ -z "$(ls -A "$W/home")$(ls -A "$W/tmp")" ]] \
   && python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$W/contract.json" 2>/dev/null; then
  pass "mrk-contract: JSON on stdout, exit 0, nothing on stderr, through a symlink from another directory, and nothing written"
else
  fail "mrk-contract: exit $rc"; sed 's/^/      /' "$W/contract.err" | head -5 >&2
  exit 1
fi
if "$REPO_ROOT/scripts/mrk-contract" --help > "$W/help" 2>&1 && head -1 "$W/help" | grep -q '^mrk-contract — '; then
  pass "--help shows the help and exits 0"
else
  fail "--help"; head -3 "$W/help" >&2
fi
"$REPO_ROOT/scripts/mrk-contract" --frob > "$W/out" 2> "$W/err"; rc=$?
if (( rc == 2 )) && [[ ! -s "$W/out" ]] && grep -q 'unknown argument: --frob' "$W/err"; then
  pass "an unknown argument exits 2, with no document on stdout"
else
  fail "an unknown argument: exit $rc"
fi

# ── 2. The shape, and 3. the scripts ─────────────────────────────────────────

# Each script that has a --check mode: its option parser takes --check.
check_scripts=$(cd "$REPO_ROOT" && grep -lE '^[[:space:]]*--check\)' scripts/* | sort)
if python3 - "$W/contract.json" "$REPO_ROOT" "$check_scripts" > "$W/shape" 2>&1 <<'PY'
import json, os, sys

doc = json.load(open(sys.argv[1]))
root, check_scripts = sys.argv[2], set(sys.argv[3].split())
problems = []

def keys(what, obj, want):
    if not isinstance(obj, dict) or set(obj) != set(want):
        problems.append(f"{what}: keys {sorted(obj) if isinstance(obj, dict) else type(obj).__name__}, not {sorted(want)}")
        return False
    return True

def strings(what, value):
    if not isinstance(value, list) or not all(isinstance(v, str) and v for v in value):
        problems.append(f"{what}: not a list of words")
        return []
    if len(set(value)) != len(value):
        problems.append(f"{what}: a word twice")
    return value

if keys("the document", doc, ["contract", "about", "scripts"]):
    # Raise this with the version, and with what Dipstick and Barkeep read:
    # a change that an older program would misread (scripts/mrk-contract).
    if doc["contract"] != 1 or isinstance(doc["contract"], bool):
        problems.append(f"contract is {doc['contract']!r}, not 1")
    for path, s in doc["scripts"].items():
        if not os.access(os.path.join(root, path), os.X_OK) or os.path.dirname(path) != "scripts":
            problems.append(f"{path}: not an executable in scripts/")
        if not keys(path, s, ["options", "equals", "decisions", "check"]):
            continue
        options = strings(f"{path} options", s["options"])
        for o in strings(f"{path} equals", s["equals"]):
            if o not in options:
                problems.append(f"{path}: equals names {o}, which options does not")
        for d in s["decisions"]:
            if keys(f"{path} decision", d, ["option", "values"]):
                if d["values"]:
                    strings(f"{path} {d['option']} values", d["values"])
                elif d["values"] != []:
                    problems.append(f"{path} {d['option']}: values is not a list")
                if d["option"] not in options:
                    problems.append(f"{path}: decision {d['option']} is not in options")
        if s["check"] is None:
            if path in check_scripts:
                problems.append(f"{path}: has a --check mode, and check is null")
            continue
        if not keys(f"{path} check", s["check"], ["options", "fields"]):
            continue
        copts = strings(f"{path} check options", s["check"]["options"])
        if not copts or copts[0] != "--check" or any(o not in options for o in copts):
            problems.append(f"{path}: check options {copts} do not start with --check, or are not all options")
        names = []
        for f in s["check"]["fields"]:
            if not keys(f"{path} field", f, ["field", "with", "words"]):
                continue
            names.append(f["field"])
            if f["with"] and f["with"] not in copts[1:]:
                problems.append(f"{path} {f['field']}: with {f['with']!r} is not a check option")
            if f["words"]:
                strings(f"{path} {f['field']} words", f["words"])
        if not names or len(set(names)) != len(names):
            problems.append(f"{path}: no field, or a field name twice")
        first_with = next((i for i, f in enumerate(s["check"]["fields"]) if f["with"]), None)
        if first_with is not None and any(not f["with"] for f in s["check"]["fields"][first_with:]):
            problems.append(f"{path}: a field on every line comes after one that an option adds")
    for path in sorted(check_scripts - set(doc["scripts"])):
        problems.append(f"{path}: has a --check mode, and the contract does not name it")
print("\n".join(problems))
sys.exit(1 if problems else 0)
PY
then
  pass "the shape: version 1, every key and type; each script in scripts/ with a --check mode is in it, and no other is missing"
else
  fail "the shape:"; sed 's/^/      /' "$W/shape" >&2
fi

# The contract as lines for the checks below: script, option, values, equals.
python3 - "$W/contract.json" > "$W/options.tsv" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
for path, s in doc["scripts"].items():
    values = {d["option"]: d["values"] for d in s["decisions"]}
    for o in s["options"]:
        print(f"{path}\t{o}\t{' '.join(values.get(o, []))}\t{'equals' if o in s['equals'] else ''}")
PY
scripts=$(cut -f1 "$W/options.tsv" | sort -u)

# ── 4. Each option is one the parser takes ───────────────────────────────────

# A copy of scripts/, and a stub for each command that could change the Mac or
# start a prompt. A parser that took --help as a value would run on, find no
# config/ and stop; a stub records any call it reaches first.
mkdir -p "$W/repo" "$W/stubs"
while IFS= read -r -d '' f; do
  mkdir -p "$W/repo/$(dirname "$f")"
  cp -p "$REPO_ROOT/$f" "$W/repo/$f"
done < <(git -C "$REPO_ROOT" ls-files -z scripts)
cp -p "$REPO_ROOT/scripts/mrk-contract" "$W/repo/scripts/"   # also when not committed yet
for c in defaults killall osascript dockutil brew gum git open launchctl sudo; do
  printf '#!/bin/bash\necho "%s $*" >> "%s/calls"\nexit 97\n' "$c" "$W" > "$W/stubs/$c"
  chmod +x "$W/stubs/$c"
done
# run_parser SCRIPT ARG... — SCRIPT from the copy, with the stubs first on PATH
run_parser() {
  local script=$1; shift
  (cd "$W/elsewhere" && env -i HOME="$W/home" TMPDIR="$W/tmp" USER="${USER:-$(id -un)}" \
    PATH="$W/stubs:$PATH" bash "$W/repo/$script" "$@" </dev/null > "$W/out" 2> "$W/err")
}
refused="" n_forms=0
for script in $scripts; do
  run_parser "$script" --help
  first=$(head -1 "$W/out")
  run_parser "$script" --frob-no-such-option --help
  [[ $? == 2 && "$(head -1 "$W/out")" != "$first" ]] \
    || refused="$refused; $script took --frob-no-such-option, so this check proves nothing for it"
  while IFS=$'\t' read -r path opt values equals; do
    [[ "$path" == "$script" ]] || continue
    # shellcheck disable=SC2206  # the value names, one word each
    vals=($values)
    args=("$opt" ${vals[@]+"${vals[@]/*/x}"})
    forms=("${args[*]}")
    run_parser "$script" "${args[@]}" --help
    [[ $? == 0 && "$(head -1 "$W/out")" == "$first" ]] || refused="$refused; $script ${args[*]}"
    if [[ -n "$equals" ]]; then
      forms+=("$opt=x")
      run_parser "$script" "$opt=x" --help
      [[ $? == 0 && "$(head -1 "$W/out")" == "$first" ]] || refused="$refused; $script $opt=x"
    fi
    n_forms=$((n_forms + ${#forms[@]}))
  done < "$W/options.tsv"
done
if (( n_forms >= 40 )) && [[ -z "$refused" && ! -e "$W/calls" ]]; then
  pass "each of the $n_forms options and forms the contract lists is one its script's parser takes, with the values it names; no stub ran"
else
  fail "options the parsers do not take as the contract has them ($n_forms forms): ${refused#; }"
  [[ -e "$W/calls" ]] && sed 's/^/      stub: /' "$W/calls" >&2
fi

# ── 5. The options are the options of --help ─────────────────────────────────

# The options of a help: the first column of each line that starts with spaces
# and a dash, as "  -n, --dry-run   Show ...". An option given as --OPTION=NAME
# there is an equals option. Every command takes --help and -h, and two helps
# do not list them.
drift=""
for script in $scripts; do
  bash "$REPO_ROOT/$script" --help 2>/dev/null | python3 -c '
import re, sys
for line in sys.stdin:
    if not re.match(r"^\s+-", line):
        continue
    column = re.split(r"\s{2,}", line.strip(), maxsplit=1)[0]
    for m in re.finditer(r"(?<![\w-])(--?[A-Za-z][A-Za-z-]*)(=?)", column):
        print(m.group(1) + "\t" + ("equals" if m.group(2) else ""))
' | sort -u > "$W/help-options"
  help_opts=$(cut -f1 "$W/help-options" | sort -u)
  help_eq=$(awk -F'\t' '$2 == "equals" { print $1 }' "$W/help-options" | sort -u)
  have_opts=$(awk -F'\t' -v s="$script" '$1 == s { print $2 }' "$W/options.tsv" | sort -u)
  have_eq=$(awk -F'\t' -v s="$script" '$1 == s && $4 == "equals" { print $2 }' "$W/options.tsv" | sort -u)
  only_help=$(comm -23 <(printf '%s\n' "$help_opts") <(printf '%s\n' "$have_opts") | tr '\n' ' ')
  only_contract=$(comm -13 <(printf '%s\n' "$help_opts" --help -h | sort -u) <(printf '%s\n' "$have_opts") | tr '\n' ' ')
  [[ -z "$help_opts" ]] && drift="$drift; $script: no option found in its --help"
  [[ -n "${only_help// }" ]] && drift="$drift; $script --help has, the contract lacks: $only_help"
  [[ -n "${only_contract// }" ]] && drift="$drift; the contract has, $script --help lacks: $only_contract"
  [[ "$help_eq" == "$have_eq" ]] || drift="$drift; $script equals: --help has '${help_eq//$'\n'/ }', the contract '${have_eq//$'\n'/ }'"
done
if [[ -z "$drift" ]]; then
  pass "the options of each script are the options of its --help, and the equals forms are the ones it gives"
else
  fail "options:${drift#;}"
fi

# ── 6. Each word is in the help ──────────────────────────────────────────────

python3 - "$W/contract.json" > "$W/words.tsv" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
for path, s in doc["scripts"].items():
    for f in (s["check"] or {}).get("fields", []):
        for w in f["words"]:
            print(f"{path}\t{f['field']}\t{w}")
PY
unnamed="" n_words=0
while IFS=$'\t' read -r script field word; do
  n_words=$((n_words + 1))
  bash "$REPO_ROOT/$script" --help 2>/dev/null | grep -qw -- "$word" || unnamed="$unnamed $script:$field:$word"
done < "$W/words.tsv"
if (( n_words >= 20 )) && [[ -z "$unnamed" ]]; then
  pass "each of the $n_words words a field can hold is in its script's --help"
else
  fail "words that a script's --help does not name ($n_words words):${unnamed:- none}"
fi

if (( fails )); then
  err "$fails mrk-contract check(s) failed"
  exit 1
fi
ok "mrk-contract checks passed"
