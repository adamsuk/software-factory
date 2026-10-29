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
