#!/usr/bin/env bash
# Fails when an enrolled repo's enforced ruleset has drifted from its factory.yml.
# Read-only: it runs `gh factory plan` (a dry run) and parses its JSON, so the
# comparison stays gh-factory's. Usage: ruleset-drift-check.sh [OWNER/REPO ...]
# (default: every enrolled repo). Env: PLAN_JSON=<file> reads a saved plan
# instead of calling gh (used by the tests).
# Exit: 0 no drift, 1 drift found, 2 the plan could not be read.
set -euo pipefail

command -v jq > /dev/null || { echo "ruleset-drift-check: jq not found" >&2; exit 2; }

plan=$(mktemp)
trap 'rm -f "$plan"' EXIT

if [[ -n "${PLAN_JSON:-}" ]]; then
  cp "$PLAN_JSON" "$plan"
else
  gh factory plan --json "$plan" "$@" > /dev/null || {
    echo "ruleset-drift-check: gh factory plan failed" >&2
    exit 2
  }
fi
jq -e 'type == "array"' "$plan" > /dev/null 2>&1 || {
  echo "ruleset-drift-check: unreadable plan JSON" >&2
  exit 2
}

# A ruleset change names its differing keys in `detail` as
# "(differs: bypass_actors, add rule required_status_checks)". Only the two keys
# this check owns are reported. A missing ruleset (action create) drifts on both.
report=$(jq -r '
  .[] | select(.enrolled) | . as $r
  | [ .changes[] | select(.item == "ruleset") ] as $rs
  | $rs[]
  | if .action == "create" then
      ("bypass_actors", "required_status_checks") as $k
      | "\($r.repo): \($k) differs (ruleset \(.target) is missing)"
    elif .action == "update" then
      . as $c
      | ("bypass_actors", "required_status_checks") as $k
      | select(.detail | test("differs:.*" + $k))
      | "\($r.repo): \($k) differs (ruleset \($c.target))"
    else empty end' "$plan")

if [[ -z "$report" ]]; then
  echo "No ruleset drift."
  exit 0
fi
echo "Ruleset drift (re-run gh factory apply, or fix factory.yml):"
printf '%s\n' "$report" | sed 's/^/- /'
exit 1
