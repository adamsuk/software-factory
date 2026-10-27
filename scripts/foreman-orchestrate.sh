#!/usr/bin/env bash
# Provider-agnostic foreman orchestration using station-runner
# Wraps existing label/state machine logic with station delegation
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

die() { echo "foreman-orchestrate: $2" >&2; exit "$1"; }

provider="${FACTORY_PROVIDER:-opencode}"

usage() {
  cat >&2 << 'EOF'
Usage: scripts/foreman-orchestrate.sh [options] <action>
Actions:
  pick              Pick next factory:ready issue and start building
  gate              Process gate for issues in factory:gate state
  review            Hand off to reviewer
  help              Show this help
Options:
  --provider <name> Provider to use (default: $FACTORY_PROVIDER or opencode)
  --dry-run         Don't make changes
EOF
  exit 2
}

dry_run=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider) provider="$2"; shift 2;;
    --dry-run) dry_run=true; shift;;
    --help) usage;;
    *) break;;
  esac
done

[[ $# -ge 1 ]] || usage
action="$1"

case "$action" in
  pick)
    echo "Foreman: picking next factory:ready issue (provider: $provider)"
    # This would integrate with GitHub API to find issues
    # For now, delegate to foreman role via station-runner for planning
    if $dry_run; then
      "$here/scripts/station-run.sh" --provider "$provider" --dry-run foreman /dev/null
    else
      "$here/scripts/station-run.sh" --provider "$provider" foreman /dev/null
    fi
    ;;
  gate)
    echo "Foreman: processing gate (provider: $provider)"
    gate_issue="${FACTORY_GATE_ISSUE:-}"
    gate_work_order="${FACTORY_GATE_WORK_ORDER:-}"
    if $dry_run; then
      if [[ -n "$gate_work_order" ]]; then
        "$here/scripts/station-run.sh" --provider "$provider" --dry-run --work-order "$gate_work_order" ${gate_issue:+--issue "$gate_issue"} foreman /dev/null
      else
        "$here/scripts/station-run.sh" --provider "$provider" --dry-run foreman /dev/null
      fi
    else
      if [[ -n "$gate_work_order" ]]; then
        "$here/scripts/station-run.sh" --provider "$provider" --work-order "$gate_work_order" ${gate_issue:+--issue "$gate_issue"} foreman /dev/null
      else
        "$here/scripts/station-run.sh" --provider "$provider" foreman /dev/null
      fi
    fi
    ;;
  *)
    die 2 "unknown action: $action"
    ;;
esac
