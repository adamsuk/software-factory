#!/usr/bin/env bash
# Behaviour tests for scripts/ruleset-drift-check.sh. ShellCheck covers this file.
# A fake gh writes canned `gh factory plan --json` output and records every call,
# so the test proves the script only runs the read-only plan.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script="$here/ruleset-drift-check.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

BIN=$work/bin
mkdir -p "$BIN"
export MOCK_GH="$work"

tname="startup"
fail() { echo "FAIL ($tname): $*" >&2; exit 1; }
pass() { echo "ok: $tname"; }

cat > "$BIN/gh" << 'FAKE'
#!/usr/bin/env bash
# `gh api` is the script's read-only probe for whether bypass_actors is visible; it is
# logged apart from the plan calls. A ruleset shows bypass_actors unless hide_bypass exists.
# The rulesets listing below has an unrelated ruleset first (id 5) and factory-main second
# (id 1): real jq runs against it here, so a selector that just grabbed the first entry
# would probe the wrong ruleset and fail this test, not pass it by coincidence.
# MOCK_GH/dup_inherited adds a same-named inherited (org-level) ruleset ahead of it, id 2.
if [[ "$1" == "api" ]]; then
  shift
  path="" jqf="" paginate=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --jq) jqf=$2; shift 2 ;;
      --paginate) paginate=1; shift ;;
      -*) shift ;;
      *) path=$1; shift ;;
    esac
  done
  printf '%s%s --jq %s\n' "$path" "$([[ $paginate -eq 1 ]] && echo ' --paginate')" "$jqf" >> "$MOCK_GH/api_calls"
  case "$path" in
    */rulesets)
      list='[{"id":5,"name":"other-ruleset"},{"id":1,"name":"factory-main"}]'
      [[ -e "$MOCK_GH/dup_inherited" ]] && list='[{"id":5,"name":"other-ruleset"},{"id":2,"name":"factory-main","source_type":"Organization"},{"id":1,"name":"factory-main"}]'
      printf '%s' "$list" | jq -r "$jqf"
      ;;
    */rulesets/1) [[ -e "$MOCK_GH/hide_bypass" ]] && echo false || echo true ;;
    # The inherited duplicate (id 2) always shows bypass_actors, unlike id 1 above, so
    # probing the wrong one is a detectably different (wrong) outcome, not a coincidence.
    */rulesets/2) echo true ;;
    *) exit 9 ;;
  esac
  exit 0
fi
printf '%s\n' "$*" >> "$MOCK_GH/calls"
[[ "$1 $2" == "factory plan" ]] || exit 9
out=""
while [[ $# -gt 0 ]]; do
  [[ "$1" == "--json" ]] && out=$2
  shift
done
cp "$MOCK_GH/plan.json" "$out"
FAKE
chmod +x "$BIN/gh"

run() { PATH="$BIN:$PATH" bash "$script" 2>&1; }
set_plan() { printf '%s' "$1" > "$work/plan.json"; }

tname="exits 0 when rulesets match"
set_plan '[{"repo":"o/a","enrolled":true,"changes":[{"item":"settings","action":"update","target":"s","detail":"x"}]}]'
out=$(run) || fail "clean plan must exit 0"
[[ "$out" == *"No ruleset drift"* ]] || fail "got [$out]"
pass

tname="names repo and key for bypass_actors drift"
set_plan '[{"repo":"o/a","enrolled":true,"changes":[{"item":"ruleset","action":"update","target":"factory-main","detail":"PR required (differs: bypass_actors)"}]}]'
rc=0; out=$(run) || rc=$?
[[ $rc -eq 1 ]] || fail "expected exit 1, got $rc"
[[ "$out" == *"o/a: bypass_actors differs"* ]] || fail "got [$out]"
[[ "$out" != *required_status_checks* ]] || fail "reported a key that did not differ"
pass

tname="names required_status_checks when the rule is missing"
set_plan '[{"repo":"o/b","enrolled":true,"changes":[{"item":"ruleset","action":"update","target":"factory-main","detail":"x (differs: add rule required_status_checks)"}]}]'
rc=0; out=$(run) || rc=$?
[[ $rc -eq 1 ]] || fail "expected exit 1, got $rc"
[[ "$out" == *"o/b: required_status_checks differs"* ]] || fail "got [$out]"
pass

tname="ignores other differing keys"
set_plan '[{"repo":"o/c","enrolled":true,"changes":[{"item":"ruleset","action":"update","target":"factory-main","detail":"x (differs: pull_request)"}]}]'
run > /dev/null || fail "unrelated key must not fail"
pass

tname="a missing ruleset drifts on both keys"
set_plan '[{"repo":"o/d","enrolled":true,"changes":[{"item":"ruleset","action":"create","target":"factory-main","detail":"x"}]}]'
rc=0; out=$(run) || rc=$?
[[ $rc -eq 1 && "$out" == *"o/d: bypass_actors"* && "$out" == *"o/d: required_status_checks"* ]] || fail "got [$out]"
pass

tname="only runs the read-only plan"
grep -qv '^factory plan ' "$work/calls" && fail "unexpected gh call: $(cat "$work/calls")"
pass

tname="exits 2 on unreadable plan"
set_plan 'not json'
rc=0; run > /dev/null || rc=$?
[[ $rc -eq 2 ]] || fail "expected exit 2, got $rc"
pass

tname="exits 2 when the plan finds no enrolled repos"
set_plan '[{"repo":"o/x","enrolled":false,"changes":[]}]'
rc=0; out=$(run) || rc=$?
[[ $rc -eq 2 && "$out" != *"No ruleset drift"* ]] || fail "rc=$rc got [$out]"
set_plan '[]'
rc=0; run > /dev/null || rc=$?
[[ $rc -eq 2 ]] || fail "empty plan: expected exit 2, got $rc"
pass

tname="reports an unavailable ruleset as its own outcome"
set_plan '[{"repo":"o/e","enrolled":true,"changes":[{"item":"ruleset","action":"unavailable","target":"factory-main","detail":"rulesets not available here (HTTP 403)"}]}]'
rc=0; out=$(run) || rc=$?
[[ $rc -eq 3 ]] || fail "expected exit 3, got $rc"
[[ "$out" == *"Rulesets unavailable"* && "$out" == *"o/e: ruleset factory-main could not be checked"* ]] || fail "got [$out]"
[[ "$out" != *"No ruleset drift"* && "$out" != *"Ruleset drift"* ]] || fail "collapsed into another outcome: [$out]"
pass

tname="reports hidden bypass_actors as cannot verify, not as a match"
touch "$work/hide_bypass"
set_plan '[{"repo":"o/f","enrolled":true,"changes":[]}]'
rc=0; out=$(run) || rc=$?
[[ $rc -eq 0 ]] || fail "expected exit 0, got $rc"
[[ "$out" == *"o/f: bypass_actors cannot be verified"* ]] || fail "got [$out]"
[[ "$out" != *"No ruleset drift."* ]] || fail "said clean though bypass_actors was not checked: [$out]"
pass

tname="hidden bypass_actors is not reported as confirmed drift"
set_plan '[{"repo":"o/g","enrolled":true,"changes":[{"item":"ruleset","action":"update","target":"factory-main","detail":"x (differs: bypass_actors, add rule required_status_checks)"}]}]'
rc=0; out=$(run) || rc=$?
[[ $rc -eq 1 ]] || fail "expected exit 1, got $rc"
[[ "$out" == *"o/g: required_status_checks differs"* && "$out" == *"o/g: bypass_actors cannot be verified"* ]] || fail "got [$out]"
[[ "$out" != *"o/g: bypass_actors differs"* ]] || fail "confirmed drift from a hidden field: [$out]"
rm -f "$work/hide_bypass"
pass

tname="the rulesets lookup paginates"
set_plan '[{"repo":"o/h","enrolled":true,"changes":[]}]'
run > /dev/null
grep -q -- '--paginate' "$work/api_calls" || fail "rulesets lookup did not paginate: $(cat "$work/api_calls")"
pass

tname="an inherited ruleset of the same name is excluded, not just the first match"
touch "$work/dup_inherited" "$work/hide_bypass"
set_plan '[{"repo":"o/i","enrolled":true,"changes":[]}]'
rc=0; out=$(run) || rc=$?
[[ $rc -eq 0 ]] || fail "expected exit 0, got $rc"
[[ "$out" == *"o/i: bypass_actors cannot be verified"* ]] \
  || fail "the inherited duplicate broke the probe instead of being excluded: [$out]"
rm -f "$work/dup_inherited" "$work/hide_bypass"
pass

tname="the probe only issues plain read-only api GETs"
[[ -s "$work/api_calls" ]] || fail "no probe ran"
grep -Eq -- ' (-X|--method|-f|-F|--field|--input)' "$work/api_calls" && fail "non-read api call: $(cat "$work/api_calls")"
pass
