#!/usr/bin/env bash
# OpenCode adapter - translates canonical station prompts to OpenCode
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

die() { echo "opencode-adapter: $2" >&2; exit "$1"; }

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

[[ -n "$role" && -n "$prompt_file" && -f "$prompt_file" ]] || die 2 "missing role or prompt"

# Check if opencode CLI exists
if command -v opencode >/dev/null 2>&1; then
  # Use OpenCode CLI - could use 'run' or pass as agent
  # Try to use opencode run with the prompt
  if opencode --help 2>&1 | grep -q "run"; then
    # Pass prompt file or content
    exec opencode run --prompt-file "$prompt_file" ${issue:+--title "factory:$role#$issue"} "$@"
  else
    # Fallback: just pass prompt
    exec opencode "$prompt_file" "$@"
  fi
else
  die 2 "opencode CLI not found in PATH"
fi
