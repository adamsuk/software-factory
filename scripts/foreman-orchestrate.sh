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
  --issue <n>       Issue number. Required for review.
  --repo <owner/repo>  Repository. Required for review.
  --pr <n>          Pull request number. Required for review.
  --sha <sha>       Pull request head. Required for review.
EOF
  exit 2
}

dry_run=false
action=""
issue=""
repo_arg=""
pr=""
sha=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --provider)
      [[ $# -ge 2 ]] || die 2 "missing value for --provider"
      provider="$2"; shift 2 ;;
    --issue)
      [[ $# -ge 2 ]] || die 2 "missing value for --issue"
      issue="$2"; shift 2 ;;
    --repo)
      [[ $# -ge 2 ]] || die 2 "missing value for --repo"
      repo_arg="$2"; shift 2 ;;
    --pr)
      [[ $# -ge 2 ]] || die 2 "missing value for --pr"
      pr="$2"; shift 2 ;;
    --sha)
      [[ $# -ge 2 ]] || die 2 "missing value for --sha"
      sha="$2"; shift 2 ;;
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
  local ctx=$2
  local -a args=(--provider "$provider")
  if [[ -n "$issue" ]]; then
    args+=(--issue "$issue")
  fi
  if [[ -n "$repo_arg" ]]; then
    args+=(--repo "$repo_arg")
  fi
  if $dry_run; then
    args+=(--dry-run)
  fi
  "$here/scripts/station-run.sh" "${args[@]}" "$role" "$ctx"
}

case "$action" in
  pick)
    echo "Foreman: picking next factory:ready issue (provider: $provider)"
    echo "The agent must post with scripts/station-post.sh. This does not pick an issue by itself."
    run_role foreman /dev/null
    ;;
  gate)
    echo "Foreman: processing gate (provider: $provider)"
    echo "Run scripts/gate-issue.sh for the label move. The agent only reads."
    run_role foreman /dev/null
    ;;
  review)
    [[ "$issue" =~ ^[0-9]+$ ]] || die 2 "review requires --issue"
    [[ "$repo_arg" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || die 2 "review requires --repo"
    [[ "$pr" =~ ^[0-9]+$ ]] || die 2 "review requires --pr"
    [[ "$sha" =~ ^[0-9a-fA-F]{7,40}$ ]] || die 2 "review requires --sha"
    echo "Reviewer: verdict on ${repo_arg}#${pr} (provider: $provider)"
    echo "Post it with scripts/station-post.sh verdict. Do not merge."
    ctx=$(mktemp)
    trap 'rm -f "$ctx"' EXIT
    cat > "$ctx" << EOF
Pull request: ${repo_arg}#${pr}
Issue: ${issue}
Head: ${sha}
Post the verdict with scripts/station-post.sh verdict --repo ${repo_arg} --pr ${pr} --issue ${issue} --sha ${sha}. Do not merge.
EOF
    run_role reviewer "$ctx"
    ;;
esac
