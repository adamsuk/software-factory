#!/usr/bin/env bash
# Static checks for .github/workflows/metrics.yml (#340): triggers, job name,
# the three metric script calls, and pinned actions. Never calls gh or the network.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
wf=$here/../.github/workflows/metrics.yml
snap_dir=$here/../metrics

fail() { echo "FAIL: $*" >&2; exit 1; }
has() { grep -Eq -- "$1" "$wf" || fail "$2"; }

[[ -f "$wf" ]] || fail "missing $wf"
has '^  schedule:' "no schedule trigger"
has '^    - cron: "[^"]+"' "no cron entry"
has '^  workflow_dispatch:' "no workflow_dispatch trigger"
has '^  metrics:$' "no job with id metrics"
has '^    name: metrics$' "job is not named metrics"
for s in factory-delivery-metrics factory-pr-metrics factory-label-metrics; do
  has "scripts/$s\\.sh " "workflow does not call scripts/$s.sh"
  [[ -f "$here/$s.sh" ]] || fail "scripts/$s.sh does not exist"
done
has 'gh pr create' "workflow does not open a pull request"

# Every action is pinned by a full 40-hex commit SHA with a version comment.
while IFS= read -r line; do
  [[ "$line" =~ uses:\ [^@]+@[0-9a-f]{40}\ #\ v[0-9] ]] || fail "action not pinned by SHA with version comment: $line"
done < <(grep -E '^\s+- uses:' "$wf")

# A snapshot with a Baseline section exists.
grep -lq '^## Baseline$' "$snap_dir"/*.md || fail "no metrics snapshot has a '## Baseline' section"

echo "PASS: metrics workflow"
