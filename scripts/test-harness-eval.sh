#!/usr/bin/env bash
# Offline replay of one recorded work order. Fixture source:
# agents/work-orders/adamsuk_gh-factory-33.md
# scripts/fixtures/replay-work-order.md is a byte-for-byte copy of that file.
# Both renders call scripts/station-run.sh --dry-run --provider grok with role
# builder and context /dev/null. No gh, no grok, no network, and no provider.
# station-run.sh reads AGENTS.md and the role briefs from the latest v* tag
# (FACTORY_RELEASE_REF stays unset), so this checks the composer fences and
# the recorded work order.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
root=$(cd "$here/.." && pwd)
fixture_rel="scripts/fixtures/replay-work-order.md"
missing_rel="scripts/fixtures/no-such-replay-work-order.md"
goal='In README.md, section "Reusable changelog check", the example caller ends its'

fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
pass() { printf 'ok: %s\n' "$1"; }

[[ -f "$root/$fixture_rel" ]] || fail "fixture missing: $fixture_rel"
[[ ! -e "$root/$missing_rel" ]] || fail "proof path must not exist: $missing_rel"

# A leaked release pin or snapshot dir would not be this case.
unset FACTORY_RELEASE_REF FACTORY_SNAPSHOT_DIR FACTORY_REAL_ROOT FACTORY_SNAPSHOT_SUM

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
deny="$work/deny"
mkdir -p "$deny"
for cmd in gh grok curl wget; do
  cat > "$deny/$cmd" << EOF
#!/bin/sh
echo "refusing $cmd" >> "$work/denied"
echo "refusing $cmd" >&2
exit 99
EOF
  chmod +x "$deny/$cmd"
done
export PATH="$deny:$PATH"

cd "$root"

# stdout only. Snapshot notices stay on stderr.
render() {
  local out=$1
  local err=$2
  shift 2
  if ! bash scripts/station-run.sh --dry-run --provider grok "$@" builder /dev/null >"$out" 2>"$err"; then
    fail "dry-run exited non-zero ($(cat "$err"))"
  fi
}

# Each marker is a whole line, and each one must follow the one before it.
require_lines_in_order() {
  local file=$1
  shift
  [[ $# -gt 0 ]] || fail "no markers"
  local marker=$1
  local line
  local saw_last=0
  shift
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" == "$marker" ]]; then
      if [[ $# -eq 0 ]]; then
        saw_last=1
        break
      fi
      marker=$1
      shift
    fi
  done < "$file"
  if [[ "$saw_last" -ne 1 ]]; then
    fail "missing line in order: $marker"
  fi
}

count_goal() {
  local file=$1
  local count
  count=$(grep -o -F -- "$goal" "$file" | wc -l)
  printf '%s' "${count//[[:space:]]/}"
}

render "$work/with.out" "$work/with.err" --work-order "$fixture_rel"
require_lines_in_order "$work/with.out" \
  '=== DRY RUN ===' \
  '<system>' \
  '</system>' \
  '<context>' \
  '# Work Order' \
  "$goal" \
  '</context>'
[[ "$(count_goal "$work/with.out")" == "1" ]] || fail "goal line appears $(count_goal "$work/with.out") times, want 1"
pass "fixture render keeps the fences around the recorded work order"

render "$work/plain.out" "$work/plain.err"
grep -q -F -x -- '<system>' "$work/plain.out" || fail "plain render missing <system>"
grep -q -F -x -- '</context>' "$work/plain.out" || fail "plain render missing </context>"
if grep -q -F -- "$goal" "$work/plain.out"; then
  fail "goal line present without a work order"
fi
pass "render without a work order omits the recorded goal"

status=0
bash scripts/station-run.sh --dry-run --provider grok \
  --work-order "$missing_rel" builder /dev/null \
  >"$work/missing.out" 2>"$work/missing.err" || status=$?
[[ "$status" -ne 0 ]] || fail "missing work order exited 0"
grep -q -F 'work order not found' "$work/missing.err" \
  || fail "missing work order was not refused: $(cat "$work/missing.err")"
[[ -f "$root/$fixture_rel" ]] || fail "real fixture was removed"
pass "a missing fixture path is refused"

[[ ! -s "$work/denied" ]] || fail "suite called a forbidden command: $(cat "$work/denied")"
pass "no gh, grok, or network client ran"

echo "all harness eval tests passed"
