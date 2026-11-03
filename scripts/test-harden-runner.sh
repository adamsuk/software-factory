#!/usr/bin/env bash
# Offline, read-only test: every job in lint.yml, line-audit.yml and ruleset-drift.yml
# starts with the pinned step-security/harden-runner step in audit mode, and
# changelog.yml (a bare reusable-workflow caller) still has no steps. ShellCheck covers
# this file. WORKFLOWS_DIR overrides the directory, to check another checkout.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dir=${WORKFLOWS_DIR:-$here/../.github/workflows}
pin='step-security/harden-runner@46b06cea07f9e64621fdf066ba77ac6915163d43'

tname="startup"
failed=0
fail() { echo "FAIL ($tname): $*" >&2; failed=1; }
pass() { echo "ok: $tname"; }

# Prints one line per job that has a steps list: "<job> <text of its first step>".
first_step_report() {
  awk '
    function flush() { if (job != "" && block != "") print job " " block; block = "" }
    /^jobs:/ { injobs = 1; next }
    !injobs { next }
    /^  [A-Za-z0-9_-]+:/ { flush(); job = $1; sub(/:$/, "", job); insteps = 0; seen = 0; collecting = 0; next }
    /^    steps:/ { insteps = 1; next }
    insteps && /^      - / {
      if (seen) { collecting = 0; next }
      seen = 1; collecting = 1; block = $0; next
    }
    collecting && /^        / { block = block " " $0; next }
    { collecting = 0 }
    END { flush() }
  ' "$1"
}

check_job() { # file job
  tname="$1 / $2"
  local report line
  report=$(first_step_report "$dir/$1")
  line=$(printf '%s\n' "$report" | grep -E "^$2 " || true)
  if [[ -z "$line" ]]; then fail "job $2 has no steps"; return; fi
  if [[ "$line" != *"uses: $pin"* ]]; then fail "first step is not $pin: $line"; return; fi
  if [[ "$line" != *"egress-policy: audit"* ]]; then fail "first step lacks egress-policy: audit: $line"; return; fi
  pass
}

check_job lint.yml shellcheck
check_job lint.yml test-assertions
check_job lint.yml tests
check_job line-audit.yml audit
check_job ruleset-drift.yml ruleset-drift

tname="changelog.yml has no steps"
if [[ -n "$(first_step_report "$dir/changelog.yml")" ]] || grep -qE '^    steps:' "$dir/changelog.yml"; then
  fail "changelog.yml gained a steps list; give it the Harden-Runner step and extend this test"
else
  pass
fi

exit "$failed"
