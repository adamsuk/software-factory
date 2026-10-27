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
action=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      [[ $# -ge 2 ]] || die 2 "missing value for --provider"
      provider="$2"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    --help) usage ;;
    pick|gate|review)
      [[ -z "$action" ]] || die 2 "unexpected argument: $1"
      action="$1"; shift ;;
    *) die 2 "unknown argument: $1" ;;
  esac
done

[[ -n "$action" ]] || usage

run_role() {
  local role=$1
  if $dry_run; then
    "$here/scripts/station-run.sh" --provider "$provider" --dry-run "$role" /dev/null
  else
    "$here/scripts/station-run.sh" --provider "$provider" "$role" /dev/null
  fi
}

case "$action" in
  pick)
    echo "Foreman: picking next factory:ready issue (provider: $provider)"
    echo "The agent must post with scripts/station-post.sh. This does not pick an issue by itself."
    run_role foreman
    ;;
  gate)
    echo "Foreman: processing gate (provider: $provider)"
    echo "Run scripts/gate-issue.sh for the label move. The agent only reads."
    run_role foreman
    ;;
  review)
    echo "Reviewer: verdict on the open pull request (provider: $provider)"
    echo "Post it with scripts/station-post.sh verdict. Do not merge."
    run_role reviewer
    ;;
esac
