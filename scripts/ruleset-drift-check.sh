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
# repo-specific ones, and write access can differ per ruleset). --paginate covers repos
# with more than one page of rulesets. source_type excludes an inherited org ruleset that
# happens to share the name -- without it, two matching IDs would break the lookup below.
# Same two filters gh-factory's own plan.py uses to find the repo's managed ruleset.
ruleset_id() {
  gh api --paginate "repos/$1/rulesets" \
    --jq '[.[] | select(.name == "factory-main" and (.source_type // "Repository") == "Repository")] | .[0].id // empty' \
    2> /dev/null
}
bypass_hidden() {
  local repo=$1 id
  id=$(ruleset_id "$repo") || return 0
  [[ -n "$id" ]] || return 1
  gh api "repos/$repo/rulesets/$id" --jq 'has("bypass_actors")' 2> /dev/null | grep -qx true && return 1
  return 0
}

# The contexts the live ruleset's required_status_checks rule lists, comma-separated, or
# ABSENT when the rule is not there. Fails when the live ruleset cannot be read. A plain
# read-only GET, like bypass_hidden above.
live_checks() {
  local id
  id=$(ruleset_id "$1") && [[ -n "$id" ]] || return 1
  gh api "repos/$1/rulesets/$id" --jq 'if any(.rules[]?; .type == "required_status_checks")
    then ([.rules[] | select(.type == "required_status_checks") | .parameters.required_status_checks[]?.context] | join(","))
    else "ABSENT" end' 2> /dev/null
}

# Names the checks behind a required_status_checks drift: $2 is the plan's desired
# contexts (comma-separated); for an update, the ones the live ruleset lacks, else all.
missing_checks() {
  local repo=$1 desired=$2 action=$3 live c out=""
  [[ -n "$desired" ]] || return 0
  if [[ "$action" == update ]] && live=$(live_checks "$repo") && [[ "$live" != ABSENT ]]; then
    for c in ${desired//,/ }; do
      [[ ",$live," == *",$c,"* ]] || out+="${out:+, }$c"
    done
    [[ -n "$out" ]] || { echo "all desired checks are present, other parameters differ"; return 0; }
  else
    out=${desired//,/, }
  fi
  echo "missing: $out"
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
    | ([$c.payload.body.rules[]? | select(.type == "required_status_checks")
        | .parameters.required_status_checks[]?.context] | join(",")) as $want
    | if .action == "create" then
        ("bypass_actors", "required_status_checks") as $k
        | "\($r.repo): \($k) differs (ruleset \($c.target) is missing)|\(if $k == "required_status_checks" then $want else "" end)|create"
      elif .action == "update" then
        ("bypass_actors", "required_status_checks") as $k
        | select($c.detail | test("differs:.*" + $k))
        | "\($r.repo): \($k) differs (ruleset \($c.target))|\(if $k == "required_status_checks" then $want else "" end)|update"
      else empty end' "$plan")
  hidden=0
  bypass_hidden "$repo" && hidden=1
  [[ $hidden -eq 1 ]] && unverified+="$repo: bypass_actors cannot be verified (the token cannot see bypass_actors; GitHub shows it only to write access)"$'\n'
  while IFS='|' read -r line want action; do
    [[ -n "$line" ]] || continue
    if [[ -n "$want" ]]; then
      detail=$(missing_checks "$repo" "$want" "$action")
      [[ -z "$detail" ]] || line="${line%)}; $detail)"
    fi
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
