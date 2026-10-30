#!/usr/bin/env bash
# Contract tests for agents/roles/research.md (Research Scout files issues, #106).
# Each requirement is asserted against the real brief, then proven non-vacuous:
# a copy of the brief with that requirement removed must make the check fail.
# Backticks below are literal brief text, not command substitution.
# shellcheck disable=SC2016
set -euo pipefail
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
brief="$here/../agents/roles/research.md"
fail() { echo "FAIL: $*" >&2; exit 1; }
[[ -f "$brief" ]] || fail "brief not found: $brief"

# Whole file on one line, whitespace collapsed, so wrapped sentences still match.
flat() { tr '\n' ' ' < "$1" | tr -s ' '; }

# Each check takes a brief path; returns 0 when the requirement holds.
has() { flat "$1" | grep -qE -- "$2"; }
check_target_repo()  { has "$1" 'a `Target repo: owner/repo` line'; }
check_labels()       { has "$1" 'labels `factory` and `factory:triage`'; }
check_cap()          { has "$1" 'at most 3 issues per repo per run'; }
check_no_duplicate() { has "$1" "don't duplicate an open issue"; }
check_no_prs()       { has "$1" 'opens no pull requests and merges nothing'; }
check_no_merge_line() { ! has "$1" "merge unless"; }

checks=(target_repo labels cap no_duplicate no_prs no_merge_line)

for c in "${checks[@]}"; do
  "check_$c" "$brief" || fail "real brief fails requirement: $c"
  echo "ok: brief satisfies $c"
done

# Non-vacuity: strip the wording each check looks for and expect failure.
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
mutate() { # name, sed expression applied to the flattened brief
  flat "$brief" | sed -E "$2" > "$scratch/$1.md"
}
mutate target_repo 's/a `Target repo: owner\/repo` line/a line/'
mutate labels 's/labels `factory` and `factory:triage`/labels/'
mutate cap 's/at most 3 issues per repo per run/issues/'
mutate no_duplicate "s/don't duplicate an open issue/ok/"
mutate no_prs 's/opens no pull requests and merges nothing/does things/'
{ flat "$brief"; echo "Don't merge unless section 6 allows it."; } > "$scratch/no_merge_line.md"

for c in "${checks[@]}"; do
  if "check_$c" "$scratch/$c.md"; then
    fail "check $c still passes on a brief without the requirement (vacuous)"
  fi
  echo "ok: check $c fails when the requirement is removed"
done
echo "all research brief contract tests passed"
