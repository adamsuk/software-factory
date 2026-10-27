#!/usr/bin/env bash
# Grok adapter - uses existing grok-build flow
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() { echo "grok-adapter: $2" >&2; exit "$1"; }

role=""
prompt_file=""
work_order=""
issue=""
repo_ctx=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) role="$2"; shift 2;;
    --prompt) prompt_file="$2"; shift 2;;
    --work-order) work_order="$2"; shift 2;;
    --issue) issue="$2"; shift 2;;
    --repo) repo_ctx="$2"; shift 2;;
    *) shift;;
  esac
done

# For builder role, use the existing run-work-order.sh flow
if [[ "$role" == "builder" && -n "$work_order" && -f "$work_order" ]]; then
  # Check for --push flag
  push_flag=""
  if [[ " $* " == *" --push "* ]]; then
    push_flag="--push"
  fi
  exec "$here/scripts/run-work-order.sh" $push_flag "$work_order"
fi

# For other roles, try to use grok CLI if available
if command -v grok >/dev/null 2>&1; then
  if grok --help 2>&1 | grep -q "prompt-file"; then
    exec grok --prompt-file "$prompt_file" --rules "$(cat "$here/AGENTS.md")" "$@"
  fi
fi

die 2 "grok adapter: role '$role' not supported or grok CLI not available"
