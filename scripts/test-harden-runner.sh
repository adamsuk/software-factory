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
    /^[ \t]*#/ { next }
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
if [[ ! -r "$dir/changelog.yml" ]]; then
  fail "changelog.yml not found or unreadable"
elif [[ -n "$(first_step_report "$dir/changelog.yml")" ]] || grep -qE '^    steps:' "$dir/changelog.yml"; then
  fail "changelog.yml gained a steps list; give it the Harden-Runner step and extend this test"
else
  pass
fi

# Self-test on temp fixtures: the checks above must fail on these. HARDEN_RUNNER_SELFTEST
# stops the nested runs from recursing.
if [[ -z "${HARDEN_RUNNER_SELFTEST:-}" ]]; then
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  good_job() { # job
    printf '  %s:\n    steps:\n      - uses: %s\n        with:\n          egress-policy: audit\n' "$1" "$pin"
  }
  mkfixture() { # name: a fully passing set of workflows
    local d="$tmp/$1"
    mkdir -p "$d"
    { echo 'jobs:'; good_job shellcheck; good_job test-assertions; good_job tests; } >"$d/lint.yml"
    { echo 'jobs:'; good_job audit; } >"$d/line-audit.yml"
    { echo 'jobs:'; good_job ruleset-drift; } >"$d/ruleset-drift.yml"
    printf 'jobs:\n  changelog:\n    uses: o/r/.github/workflows/c.yml@main\n' >"$d/changelog.yml"
  }
  expect_fail() { # name fixture-dir expected-text
    tname="selftest: $1"
    local out
    if out=$(HARDEN_RUNNER_SELFTEST=1 WORKFLOWS_DIR="$2" bash "${BASH_SOURCE[0]}" 2>&1); then
      fail "expected failure but the check passed"
    elif [[ "$out" != *"$3"* ]]; then
      fail "failed without \"$3\": $out"
    else
      pass
    fi
  }

  tname="selftest: baseline fixture passes"
  mkfixture good
  if HARDEN_RUNNER_SELFTEST=1 WORKFLOWS_DIR="$tmp/good" bash "${BASH_SOURCE[0]}" >/dev/null 2>&1; then pass; else fail "good fixture was rejected"; fi

  mkfixture commented
  printf 'jobs:\n  audit:\n    steps:\n      - name: other\n        run: echo hi\n        # uses: %s\n        # egress-policy: audit\n' "$pin" >"$tmp/commented/line-audit.yml"
  expect_fail "commented-out Harden-Runner is not a pass" "$tmp/commented" "line-audit.yml / audit"

  mkfixture nochangelog
  rm "$tmp/nochangelog/changelog.yml"
  expect_fail "missing changelog.yml fails" "$tmp/nochangelog" "changelog.yml not found or unreadable"
fi

exit "$failed"
