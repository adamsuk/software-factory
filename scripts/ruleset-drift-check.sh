#!/usr/bin/env bash
# Fails when an enrolled repo's enforced ruleset has drifted from its factory.yml.
# Read-only: it runs `gh factory plan` (a dry run) and parses its JSON, so the
# comparison stays gh-factory's. Usage: ruleset-drift-check.sh [--owner OWNER ...]
# (arguments go to `gh factory plan`; without --owner it searches the token's own
# account, so callers should pass owners). Env: PLAN_JSON=<file> reads a saved plan
# instead of calling gh (used by the tests).
# GitHub returns a ruleset's bypass_actors only to a token with write access to it,
# so with a read-only token that key cannot be checked. The script probes for the
# field (read-only GETs) and reports "cannot verify" instead of "matches".
# Exit: 0 nothing drifted (cannot-verify bypass_actors is reported, not failed),
# 1 drift found, 2 the plan could not be read or found no enrolled repos (nothing was
# checked), 3 a ruleset is unavailable (no drift confirmed, but not checked).
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

# Zero enrolled repos means nothing was checked (wrong --owner, token sees nothing).
jq -e '[.[] | select(.enrolled)] | length > 0' "$plan" > /dev/null || {
  echo "ruleset-drift-check: plan found no enrolled repos, so nothing was checked (check --owner and the token)" >&2
  exit 2
}

# Does a read-only token see bypass_actors? Probe the factory-managed ruleset by name
# (not the first in the list: `rulesets` also lists inherited org rulesets and any other
# repo-specific ones, and write access can differ per ruleset).
bypass_hidden() {
  local repo=$1 id
  id=$(gh api "repos/$repo/rulesets" --jq '.[] | select(.name == "factory-main") | .id' 2> /dev/null) || return 0
  [[ -n "$id" ]] || return 1
  gh api "repos/$repo/rulesets/$id" --jq 'has("bypass_actors")' 2> /dev/null | grep -qx true && return 1
  return 0
}

# A ruleset change names its differing keys in `detail` as
# "(differs: bypass_actors, add rule required_status_checks)". Only the two keys
# this check owns are reported. A missing ruleset (action create) drifts on both.
# An `unavailable` action means gh-factory could not read the ruleset at all.
drift=""
unverified=""
unavailable=$(jq -r '.[] | select(.enrolled) | . as $r | .changes[]
  | select(.item == "ruleset" and .action == "unavailable")
  | "\($r.repo): ruleset \(.target) could not be checked (\(.detail))"' "$plan")
while IFS= read -r repo; do
  [[ -n "$repo" ]] || continue
  lines=$(jq -r --arg repo "$repo" '
    .[] | select(.enrolled and .repo == $repo) | . as $r
    | .changes[] | select(.item == "ruleset") | . as $c
    | if .action == "create" then
        ("bypass_actors", "required_status_checks") as $k
        | "\($r.repo): \($k) differs (ruleset \($c.target) is missing)"
      elif .action == "update" then
        ("bypass_actors", "required_status_checks") as $k
        | select($c.detail | test("differs:.*" + $k))
        | "\($r.repo): \($k) differs (ruleset \($c.target))"
      else empty end' "$plan")
  hidden=0
  bypass_hidden "$repo" && hidden=1
  [[ $hidden -eq 1 ]] && unverified+="$repo: bypass_actors cannot be verified (the token cannot see bypass_actors; GitHub shows it only to write access)"$'\n'
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    if [[ $hidden -eq 1 && "$line" == *": bypass_actors differs"* ]]; then
      continue # a hidden field always looks different; already reported as unverifiable
    fi
    drift+="$line"$'\n'
  done <<< "$lines"
done < <(jq -r '.[] | select(.enrolled) | .repo' "$plan")

rc=0
if [[ -n "$drift" ]]; then
  echo "Ruleset drift (re-run gh factory apply, or fix factory.yml):"
  printf '%s' "$drift" | sed 's/^/- /'
  rc=1
fi
if [[ -n "$unavailable" ]]; then
  echo "Rulesets unavailable (not checked):"
  printf '%s\n' "$unavailable" | sed 's/^/- /'
  [[ $rc -eq 0 ]] && rc=3
fi
if [[ -n "$unverified" ]]; then
  echo "Cannot verify:"
  printf '%s' "$unverified" | sed 's/^/- /'
fi
[[ $rc -eq 0 && -z "$unverified" ]] && echo "No ruleset drift."
[[ $rc -eq 0 && -n "$unverified" ]] && echo "No confirmed ruleset drift (some checks could not be verified, see above)."
exit $rc
