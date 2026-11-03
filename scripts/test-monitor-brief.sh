#!/usr/bin/env bash
# Brief-shaped test: the weekly monitor procedure in agents/roles/monitor.md
# runs scripts/review-bot-metrics.sh and records its stdout. ShellCheck covers this file.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
brief="${MONITOR_BRIEF:-$here/../agents/roles/monitor.md}"

fail() { echo "FAIL: $*" >&2; exit 1; }

check() {
  local file=$1 measure record
  measure=$(awk '/^2\. \*\*Measure\.\*\*/{on=1} /^3\. \*\*Record/{on=0} on' "$file" | tr -s ' \n' '  ')
  record=$(awk '/^3\. \*\*Record\.\*\*/{on=1} /^4\. \*\*Stop/{on=0} on' "$file" | tr -s ' \n' '  ')
  [[ -n "$measure" ]] || { echo "Measure step not found"; return 1; }
  [[ -n "$record" ]] || { echo "Record step not found"; return 1; }
  grep -qF 'scripts/review-bot-metrics.sh --repo adamsuk/software-factory' <<< "$measure" || { echo "Measure does not run review-bot-metrics.sh for adamsuk/software-factory"; return 1; }
  grep -qF 'review-bot' <<< "$record" || { echo "Record does not append the review-bot stdout"; return 1; }
  grep -q 'stdout' <<< "$record" || { echo "Record does not mention stdout"; return 1; }
}

msg=$(check "$brief") || fail "$msg"
echo "ok: monitor Measure runs review-bot-metrics.sh and Record appends its stdout"

# Non-vacuous: a copy without the command must fail.
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
grep -vF 'review-bot' "$brief" | sed 's#scripts/review-bot-metrics.sh --repo adamsuk/software-factory##' > "$tmp"
if check "$tmp" >/dev/null; then fail "check passes against a copy with the review-bot lines removed"; fi
echo "ok: check fails against a mutated copy"
