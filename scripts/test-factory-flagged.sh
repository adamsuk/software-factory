#!/usr/bin/env bash
# Behaviour tests for scripts/factory-flagged.sh. ShellCheck covers this file.
# A fake gh serves canned issue JSON and records every call, so the test proves
# the script only reads.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
script="$here/factory-flagged.sh"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

BIN=$work/bin
mkdir -p "$BIN"
export MOCK_GH="$work"
# Pin the default repo so it never depends on the checkout's remote.
export FACTORY_HOME_REPO=acme/software-factory
unset FACTORY_REPOS GITHUB_REPOSITORY

tname="startup"
fail() { echo "FAIL ($tname): $*" >&2; exit 1; }
pass() { echo "ok: $tname"; }

cat > "$BIN/gh" << 'FAKE'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_GH/calls"
if [[ -f "$MOCK_GH/issues.json" ]]; then
  cat "$MOCK_GH/issues.json"
else
  echo '[]'
fi
FAKE
chmod +x "$BIN/gh"

run() { PATH="$BIN:$PATH" bash "$script" "$@" 2>&1; }

set_issues() { printf '%s' "$1" > "$work/issues.json"; }

tname="says so plainly when nothing is flagged"
set_issues '[]'
out=$(run)
[[ "$out" == *"Nothing flagged"* ]] || fail "expected the empty message, got [$out]"
PATH="$BIN:$PATH" bash "$script" > /dev/null 2>&1 || fail "empty case must exit 0"
pass

tname="orders P0 before P1 before P2 before P3"
set_issues '[
 {"number":30,"title":"a p3","labels":[{"name":"priority: next"},{"name":"priority: P3"}]},
 {"number":10,"title":"a p1","labels":[{"name":"priority: next"},{"name":"priority: P1"}]},
 {"number":20,"title":"a p0","labels":[{"name":"priority: next"},{"name":"priority: P0"}]},
 {"number":40,"title":"a p2","labels":[{"name":"priority: next"},{"name":"priority: P2"}]}
]'
out=$(run)
order=$(printf '%s\n' "$out" | grep -oE '#(10|20|30|40)' | tr -d '#' | tr '\n' ' ')
[[ "$order" == "20 10 40 30 " ]] || fail "expected '20 10 40 30 ', got '$order'"
pass

tname="unprioritised issues sort last"
set_issues '[
 {"number":5,"title":"no priority","labels":[{"name":"priority: next"}]},
 {"number":9,"title":"a p3","labels":[{"name":"priority: next"},{"name":"priority: P3"}]}
]'
order=$(run | grep -oE '#(5|9)' | tr -d '#' | tr '\n' ' ')
[[ "$order" == "9 5 " ]] || fail "expected '9 5 ', got '$order'"
pass

tname="equal priority sorts by issue number"
set_issues '[
 {"number":77,"title":"later","labels":[{"name":"priority: next"},{"name":"priority: P0"}]},
 {"number":12,"title":"earlier","labels":[{"name":"priority: next"},{"name":"priority: P0"}]}
]'
order=$(run | grep -oE '#(12|77)' | tr -d '#' | tr '\n' ' ')
[[ "$order" == "12 77 " ]] || fail "expected '12 77 ', got '$order'"
pass

tname="shows the factory status, or says there is none"
set_issues '[
 {"number":1,"title":"blocked one","labels":[{"name":"priority: next"},{"name":"factory:blocked"}]},
 {"number":2,"title":"statusless","labels":[{"name":"priority: next"}]}
]'
out=$(run)
[[ "$out" == *"[factory:blocked]"* ]] || fail "status not shown"
[[ "$out" == *"[(no status)]"* ]] || fail "missing status not reported"
pass

tname="priority: next is not reported as the priority"
set_issues '[{"number":3,"title":"t","labels":[{"name":"priority: next"},{"name":"priority: P1"}]}]'
out=$(run)
[[ "$out" == *" P1  #3"* ]] || fail "expected P1 in the priority column, got [$out]"
pass

tname="it only reads"
rm -f "$work/calls"
set_issues '[]'
run > /dev/null
while IFS= read -r c; do
  case "$c" in
    "issue list"*) ;;
    *) fail "unexpected gh call: $c" ;;
  esac
done < "$work/calls"
grep -q "issue list" "$work/calls" || fail "no gh issue list recorded"
pass

tname="a bad --repo is a usage error"
out=$(run --repo nonsense || true)
[[ "$out" == *"bad --repo"* ]] || fail "expected a usage error"
pass

tname="the default repo is FACTORY_HOME_REPO"
rm -f "$work/calls"
set_issues '[]'
FACTORY_HOME_REPO=acme/home run > /dev/null
grep -q -- "--repo acme/home " "$work/calls" || fail "default repo is not FACTORY_HOME_REPO: $(cat "$work/calls")"
pass

tname="FACTORY_REPOS wins over FACTORY_HOME_REPO"
rm -f "$work/calls"
FACTORY_REPOS="acme/first acme/second" run > /dev/null
grep -q -- "--repo acme/first " "$work/calls" || fail "default repo is not the first FACTORY_REPOS entry: $(cat "$work/calls")"
pass

tname="--repo wins over the defaults"
rm -f "$work/calls"
FACTORY_REPOS="acme/first" run --repo acme/explicit > /dev/null
grep -q -- "--repo acme/explicit " "$work/calls" || fail "--repo was not used: $(cat "$work/calls")"
pass

echo "all factory-flagged tests passed"
