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
pass_args=()
title=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --role) role="$2"; shift 2;;
    --prompt) prompt_file="$2"; shift 2;;
    --work-order) work_order="$2"; shift 2;;
    --issue) issue="$2"; shift 2;;
    --repo) repo_ctx="$2"; shift 2;;
    --title) title="$2"; shift 2;;
    *) pass_args+=("$1"); shift;;
  esac
done

[[ -n "$role" && -n "$prompt_file" && -f "$prompt_file" ]] || die 2 "missing role or prompt"

prompt_content=$(cat "$prompt_file")
[[ -n "$title" ]] || title="factory:$role${issue:+#$issue}"

# Check if opencode CLI exists
if command -v opencode >/dev/null 2>&1; then
  if opencode --help 2>&1 | grep -q " run"; then
    # Try to pass prompt content via stdin or supported flag
    if opencode run --help 2>&1 | grep -q "\-\-prompt"; then
      printf '%s' "$prompt_content" | exec opencode run --prompt - --title "$title" "${pass_args[@]}"
    elif opencode run --help 2>&1 | grep -q "stdin"; then
      printf '%s' "$prompt_content" | exec opencode run --title "$title" "${pass_args[@]}"
    else
      # Fallback: write to temp file and pass via stdin
      tmp_prompt="$(mktemp /tmp/opencode-prompt-XXXXXX.md)"
      printf '%s' "$prompt_content" > "$tmp_prompt"
      trap 'rm -f "$tmp_prompt"' EXIT
      printf '%s' "$(cat "$tmp_prompt")" | exec opencode run --title "$title" "${pass_args[@]}"
    fi
  else
    tmp_prompt="$(mktemp /tmp/opencode-prompt-XXXXXX.md)"
    printf '%s' "$prompt_content" > "$tmp_prompt"
    trap 'rm -f "$tmp_prompt"' EXIT
    printf '%s' "$(cat "$tmp_prompt")" | exec opencode "${pass_args[@]}"
  fi
else
  die 2 "opencode CLI not found in PATH"
fi
