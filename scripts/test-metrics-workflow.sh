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

# App token and ledger wiring (#355): a SHA-pinned token action fed by the two
# secrets (names only), used for the push and gh pr create; the ledger limit is
# documented in the header and in the generated snapshot.
has 'FACTORY_GH_APP_ID' "workflow does not name FACTORY_GH_APP_ID"
has 'FACTORY_GH_APP_PRIVATE_KEY' "workflow does not name FACTORY_GH_APP_PRIVATE_KEY"
has 'uses: actions/create-github-app-token@[0-9a-f]{40} # v[0-9]' "no SHA-pinned create-github-app-token step"
has 'app-id: \$\{\{ secrets\.FACTORY_GH_APP_ID \}\}' "token step does not read FACTORY_GH_APP_ID"
has 'private-key: \$\{\{ secrets\.FACTORY_GH_APP_PRIVATE_KEY \}\}' "token step does not read FACTORY_GH_APP_PRIVATE_KEY"
awk '/- name: Open the pull request/{f=1} f' "$wf" | grep -Eq 'GH_TOKEN: \$\{\{ steps\.app-token\.outputs\.token \}\}' \
  || fail "the pull request step does not use the App token"
if grep -Eq 'GH_TOKEN: \$\{\{ secrets\.GITHUB_TOKEN \}\}' <(awk '/- name: Open the pull request/{f=1} f' "$wf"); then
  fail "the pull request step still uses GITHUB_TOKEN"
fi
has 'cost ledger lives on the factory host' "ledger limit is not documented"
has '^            echo "## Ledger"' "snapshot does not state the ledger limit"
# Rework rounds come from pull request data when the ledger is not readable (#392).
has '^ +--pr-rework \\$' "delivery metrics call does not pass --pr-rework"
if grep -Eq 'rework rounds per pr and cost per change usd are n/a' "$wf"; then
  fail "the ledger note still says rework rounds are n/a"
fi
if grep -Eq 'ghs_|-----BEGIN|private-key: [^$]' "$wf"; then fail "workflow contains a secret value"; fi

# A snapshot with a Baseline section exists.
grep -lq '^## Baseline$' "$snap_dir"/*.md || fail "no metrics snapshot has a '## Baseline' section"

echo "PASS: metrics workflow"
