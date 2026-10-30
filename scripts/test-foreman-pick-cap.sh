#!/usr/bin/env bash
# Brief-shaped test: the foreman's pick cap lives in agents/roles/foreman.md,
# because foreman-orchestrate.sh pick leaves the decision to the agent. ShellCheck covers this file.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
brief="$here/../agents/roles/foreman.md"
reviewer="$here/../agents/roles/reviewer.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

# The Pick step is step 1, which runs until step 2.
pick=$(awk '/^1\. \*\*Pick\.\*\*/{on=1} /^2\. \*\*Resolve/{on=0} on' "$brief")
[[ -n "$pick" ]] || fail "Pick step not found"
grep -q 'Cap: 2 open agent PRs per repo' <<< "$pick" || fail "cap of 2 not stated under Pick"
grep -q "PR's own repo" <<< "$pick" || fail "cap does not say which repo it counts against"
grep -q 'new' <<< "$pick" || fail "cap does not say it applies to new issues"
echo "ok: foreman Pick states the cap of 2"

# It must appear once, not also elsewhere in the brief.
[[ $(grep -c 'Cap: 2 open agent PRs' "$brief") -eq 1 ]] || fail "cap stated more than once"
echo "ok: cap stated once"

grep -q 'station 05 Review' "$reviewer" || fail "reviewer brief lacks station header"
grep -q '\*\*Takes in\*\*' "$reviewer" || fail "reviewer lacks takes in"
grep -q '\*\*Hands on\*\*' "$reviewer" || fail "reviewer lacks hands on"
echo "ok: reviewer station header"
